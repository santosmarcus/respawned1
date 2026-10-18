import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/models/rescue/saved_clinic.dart';
import 'package:respawnd1/core/repos/clinic_search_repository.dart';
import 'package:respawnd1/core/repos/saved_clinics_repository.dart';
import 'package:respawnd1/core/utils/geo.dart';

/// Shared clinic picker — map, text search, Saved/Nearby sectioned results,
/// bookmark toggling, and the closed-clinic availability warning. Extracted
/// from select_clinic_sheet.dart so every place that needs to pick a clinic
/// (the live "currently treating" clinic on a case, or a Transfer
/// destination) uses the exact same search/selection experience instead of
/// each maintaining its own lookalike list.
///
/// This widget only *picks* a clinic — it never writes anything to
/// Firestore itself. [onConfirm] is called once a clinic is selected and
/// (if relevant) the closed-clinic warning has been cleared; it should
/// perform whatever the caller actually wants done with the pick (save it
/// onto a case's vetClinic* fields, stash it in a form, etc.) and pop the
/// sheet itself on success. Throwing from [onConfirm] keeps the sheet open
/// and shows the error inline, exactly like the old inline save-error
/// behavior.
class ClinicPickerBody extends StatefulWidget {
  final ClinicSearchRepository repository;
  final SavedClinicsRepository savedClinicsRepository;
  final String actorUid;
  final double? centerLat;
  final double? centerLng;
  final ClinicSearchResult? initialClinic;
  final String title;
  final String currentClinicBannerLabel;
  final String confirmLabel;
  final String errorPrefix;

  // A clinic to disable/mark as unselectable — used by Transfer to Clinic
  // so the animal's current/admitting clinic can't be picked as its own
  // transfer destination (spec §12). Matched by Place ID first when
  // available; falls back to normalized name + approximate coordinates
  // since clinic names aren't unique. Left null everywhere else (e.g. the
  // live "currently treating" clinic sheet), which never excludes anything.
  final String? excludeClinicPlaceId;
  final String? excludeClinicName;
  final double? excludeClinicLat;
  final double? excludeClinicLng;
  final String excludeClinicLabel;

  /// Called with the picked clinic and whether the closed-clinic warning
  /// was acknowledged for it. Implementations should pop the sheet on
  /// success and throw (with a user-readable message) on failure.
  final Future<void> Function(ClinicSearchResult clinic, bool closedWarningAcknowledged) onConfirm;

  const ClinicPickerBody({
    super.key,
    required this.repository,
    required this.savedClinicsRepository,
    required this.actorUid,
    this.centerLat,
    this.centerLng,
    this.initialClinic,
    required this.title,
    this.currentClinicBannerLabel = 'Currently saved',
    required this.confirmLabel,
    this.errorPrefix = 'Could not save clinic',
    this.excludeClinicPlaceId,
    this.excludeClinicName,
    this.excludeClinicLat,
    this.excludeClinicLng,
    this.excludeClinicLabel = 'Current clinic',
    required this.onConfirm,
  });

  @override
  State<ClinicPickerBody> createState() => _ClinicPickerBodyState();
}

class _ClinicPickerBodyState extends State<ClinicPickerBody> {
  final _searchController = TextEditingController();
  GoogleMapController? _mapController;

  List<ClinicSearchResult> _results = const [];
  ClinicSearchResult? _selected;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  String? _saveError;

  List<SavedClinic> _savedClinics = const [];
  final Set<String> _pendingBookmarkToggles = {};

  LatLng get _fallbackCenter => (widget.centerLat != null && widget.centerLng != null)
      ? LatLng(widget.centerLat!, widget.centerLng!)
      : const LatLng(14.5995, 120.9842); // Manila, matches rescue_page.dart's default

  @override
  void initState() {
    super.initState();
    _selected = widget.initialClinic;
    _loadNearby();
    _loadSavedClinics();
  }

  Future<void> _loadSavedClinics() async {
    try {
      final saved = await widget.savedClinicsRepository.fetchSavedClinics(widget.actorUid);
      if (mounted) setState(() => _savedClinics = saved);
    } catch (_) {
      // Bookmarks are a nice-to-have on top of search — a failure to load
      // them shouldn't block clinic search/selection at all.
    }
  }

  bool _isSaved(String placeId) => _savedClinics.any((s) => s.placeId == placeId);

  Future<void> _toggleBookmark(ClinicSearchResult clinic) async {
    if (_pendingBookmarkToggles.contains(clinic.placeId)) return;

    final wasSaved = _isSaved(clinic.placeId);
    setState(() {
      _pendingBookmarkToggles.add(clinic.placeId);
      if (wasSaved) {
        _savedClinics = _savedClinics.where((s) => s.placeId != clinic.placeId).toList();
      } else {
        _savedClinics = [SavedClinic.fromClinicSearchResult(clinic), ..._savedClinics];
      }
    });

    try {
      if (wasSaved) {
        await widget.savedClinicsRepository.unsaveClinic(widget.actorUid, clinic.placeId);
      } else {
        await widget.savedClinicsRepository.saveClinic(widget.actorUid, clinic);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          if (wasSaved) {
            _savedClinics = [SavedClinic.fromClinicSearchResult(clinic), ..._savedClinics];
          } else {
            _savedClinics = _savedClinics.where((s) => s.placeId != clinic.placeId).toList();
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update bookmark: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingBookmarkToggles.remove(clinic.placeId));
    }
  }

  double? _distanceKmTo(ClinicSearchResult clinic) {
    if (widget.centerLat == null || widget.centerLng == null) return null;
    return haversineDistanceKm(widget.centerLat!, widget.centerLng!, clinic.lat, clinic.lng);
  }

  int _byDistance(ClinicSearchResult a, ClinicSearchResult b) {
    final da = _distanceKmTo(a);
    final db = _distanceKmTo(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  List<ClinicSearchResult> get _savedSection {
    final resultsByPlaceId = {for (final r in _results) r.placeId: r};
    final seen = <String>{};
    final combined = <ClinicSearchResult>[];
    for (final saved in _savedClinics) {
      if (!seen.add(saved.placeId)) continue;
      final fromResults = resultsByPlaceId[saved.placeId];
      if (fromResults != null) {
        combined.add(fromResults);
      } else {
        final converted = saved.toClinicSearchResult();
        if (converted != null) combined.add(converted);
      }
    }
    combined.sort(_byDistance);
    return combined;
  }

  List<ClinicSearchResult> get _nearbySection {
    final savedPlaceIds = _savedClinics.map((s) => s.placeId).toSet();
    final seen = <String>{};
    final list =
        _results.where((r) => !savedPlaceIds.contains(r.placeId) && seen.add(r.placeId)).toList();
    list.sort(_byDistance);
    return list;
  }

  List<Widget> _buildSectionedList() {
    final saved = _savedSection;
    final nearby = _nearbySection;
    final widgets = <Widget>[];

    final selected = _selected;
    if (selected != null &&
        !saved.any((c) => c.placeId == selected.placeId) &&
        !nearby.any((c) => c.placeId == selected.placeId)) {
      widgets.add(_sectionHeader('Currently Selected'));
      widgets.add(_clinicTile(selected));
      widgets.add(const Divider(height: 1));
    }

    if (saved.isNotEmpty) {
      widgets.add(_sectionHeader('Saved Clinics'));
      for (final clinic in saved) {
        widgets.add(_clinicTile(clinic));
        widgets.add(const Divider(height: 1));
      }
    }
    if (nearby.isNotEmpty) {
      widgets.add(_sectionHeader('Other Nearby Clinics'));
      for (final clinic in nearby) {
        widgets.add(_clinicTile(clinic));
        widgets.add(const Divider(height: 1));
      }
    }
    return widgets;
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(title,
            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );

  /// Whether [clinic] is the clinic the caller wants disabled (Transfer to
  /// Clinic excluding the animal's current clinic). Place ID is the primary
  /// key when both sides have one; otherwise falls back to a normalized
  /// name + close-enough coordinate match, since clinic names alone can be
  /// duplicated across different real locations.
  bool _isExcluded(ClinicSearchResult clinic) {
    final excludePlaceId = widget.excludeClinicPlaceId;
    if (excludePlaceId != null && excludePlaceId.isNotEmpty) {
      return clinic.placeId == excludePlaceId;
    }
    final excludeName = widget.excludeClinicName?.trim().toLowerCase();
    final excludeLat = widget.excludeClinicLat;
    final excludeLng = widget.excludeClinicLng;
    if (excludeName == null || excludeName.isEmpty || excludeLat == null || excludeLng == null) {
      return false;
    }
    const coordTolerance = 0.0005; // ~50m — close enough to call it the same place
    return clinic.name.trim().toLowerCase() == excludeName &&
        (clinic.lat - excludeLat).abs() < coordTolerance &&
        (clinic.lng - excludeLng).abs() < coordTolerance;
  }

  Widget _clinicTile(ClinicSearchResult clinic) {
    final isSelected = clinic.placeId == _selected?.placeId;
    final isSaved = _isSaved(clinic.placeId);
    final isBookmarkPending = _pendingBookmarkToggles.contains(clinic.placeId);
    final distanceKm = _distanceKmTo(clinic);
    final isExcluded = _isExcluded(clinic);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !isExcluded,
      tileColor: isSelected ? AppColors.yellowrspwn.withValues(alpha: 0.15) : null,
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.local_hospital_outlined,
        color: isSelected ? AppColors.greenrspwn : (isExcluded ? AppColors.textSecondary : AppColors.textPrimary),
      ),
      title: Text(clinic.name, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(clinic.address, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Wrap(
            spacing: 8,
            children: [
              if (isExcluded)
                Text(widget.excludeClinicLabel,
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary))
              else
                Text(
                  distanceKm != null ? '${distanceKm.toStringAsFixed(1)} km away' : 'Distance unknown',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                ),
              if (clinic.openNow != null)
                Text(
                  clinic.openNow! ? 'Open now' : 'Closed now',
                  style: GoogleFonts.zain(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: clinic.openNow! ? AppColors.greenrspwn : const Color(0xFFE05353),
                  ),
                ),
            ],
          ),
        ],
      ),
      isThreeLine: true,
      onTap: isExcluded ? null : () => _selectResult(clinic),
      trailing: SizedBox(
        width: 88,
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Calling never selects the clinic (spec: keep selection and
            // calling separate) — this button has its own onPressed, never
            // routed through _selectResult/onTap. Disabled (not hidden, so
            // the row stays a consistent width) when Places returned no
            // phone number for this clinic — never launches an empty tel:.
            IconButton(
              icon: const Icon(Icons.call_outlined),
              color: (clinic.phone?.trim().isNotEmpty ?? false) ? AppColors.textPrimary : AppColors.slaterspwn,
              tooltip: (clinic.phone?.trim().isNotEmpty ?? false) ? 'Call ${clinic.name}' : 'Phone number unavailable',
              onPressed: (clinic.phone?.trim().isNotEmpty ?? false) ? () => _callClinic(context, clinic.phone!) : null,
            ),
            isBookmarkPending
                ? const Padding(padding: EdgeInsets.all(14), child: CircularProgressIndicator(strokeWidth: 2))
                : IconButton(
                    icon: Icon(
                      isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: isSaved ? AppColors.yellowrspwn : AppColors.textSecondary,
                    ),
                    tooltip: isSaved ? 'Remove bookmark' : 'Save clinic',
                    onPressed: () => _toggleBookmark(clinic),
                  ),
          ],
        ),
      ),
    );
  }

  // Reuses the exact tel: launch pattern already established in
  // transporter_details_card.dart's own _launchCall — not a second approach.
  Future<void> _callClinic(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone.trim());
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not start the call.')));
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _describeLoadError(Object e) {
    if (e is ClinicSearchConfigException) return 'Clinic search is misconfigured: ${e.message}';
    if (e is ClinicSearchNetworkException) return e.message;
    if (e is ClinicSearchUnexpectedException) return e.message;
    return 'Could not load clinics: $e';
  }

  Future<void> _loadNearby() async {
    if (widget.centerLat == null || widget.centerLng == null) {
      setState(() {
        _loading = false;
        _results = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await widget.repository.nearbySearch(lat: widget.centerLat!, lng: widget.centerLng!);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      _fitCameraToResults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = _describeLoadError(e);
        _loading = false;
      });
    }
  }

  void _fitCameraToResults() {
    if (_mapController == null) return;
    if (_results.isEmpty) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_fallbackCenter, 13));
      return;
    }
    final lats = _results.map((c) => c.lat).followedBy([_fallbackCenter.latitude]);
    final lngs = _results.map((c) => c.lng).followedBy([_fallbackCenter.longitude]);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      48,
    ));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      _loadNearby();
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await widget.repository.textSearch(query: query, lat: widget.centerLat, lng: widget.centerLng);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      _fitCameraToResults();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = _describeLoadError(e);
        _loading = false;
      });
    }
  }

  void _selectResult(ClinicSearchResult clinic) {
    // Belt-and-suspenders: the list tile already disables its own tap for
    // an excluded clinic, but the map marker doesn't have a separate
    // disabled state, so this is the one chokepoint both funnel through.
    if (_isExcluded(clinic)) return;
    setState(() {
      _selected = clinic;
      _saveError = null;
      _closedWarningAcknowledged = false;
    });
  }

  bool _closedWarningAcknowledged = false;

  Future<bool> _confirmAvailability(ClinicSearchResult clinic) async {
    if (clinic.openNow != false || _closedWarningAcknowledged) return true;
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('This clinic appears to be closed.'),
        content: const Text('You may continue, but confirm that the clinic can receive the animal.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
          OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'choose_another'), child: const Text('Choose Another Clinic')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'proceed'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE0A353), foregroundColor: Colors.white),
            child: const Text('Proceed Anyway'),
          ),
        ],
      ),
    );
    if (action == 'proceed') {
      setState(() => _closedWarningAcknowledged = true);
      return true;
    }
    return false;
  }

  Future<void> _confirm() async {
    final clinic = _selected;
    if (clinic == null || _saving) return;
    // Final guard in case a selection was made before this exclusion
    // existed (e.g. restored from initialClinic) — never trust the
    // disabled UI state alone.
    if (_isExcluded(clinic)) {
      setState(() => _saveError = 'Select a different clinic for the transfer.');
      return;
    }
    if (!await _confirmAvailability(clinic)) return;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.onConfirm(clinic, _closedWarningAcknowledged);
      // onConfirm is responsible for popping on success. If it returns
      // without popping (e.g. widget was already disposed), there's
      // nothing further to do here.
    } catch (e) {
      if (mounted) {
        setState(() {
          _saveError = '${widget.errorPrefix}: $e';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>{
      if (widget.centerLat != null && widget.centerLng != null)
        Marker(
          markerId: const MarkerId('rescue_location'),
          position: LatLng(widget.centerLat!, widget.centerLng!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Rescue location'),
        ),
      for (final c in _results)
        Marker(
          markerId: MarkerId(c.placeId),
          position: LatLng(c.lat, c.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
              c.placeId == _selected?.placeId ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(title: c.name, snippet: c.address),
          onTap: () => _selectResult(c),
        ),
    };

    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration:
                          BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(widget.title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                  if (widget.initialClinic != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.tearspwn.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.local_hospital, size: 16, color: AppColors.textPrimary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${widget.currentClinicBannerLabel}: ${widget.initialClinic!.name}',
                                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700)),
                                if (widget.initialClinic!.address.isNotEmpty)
                                  Text(widget.initialClinic!.address,
                                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onSubmitted: _search,
                    decoration: InputDecoration(
                      hintText: 'Search clinic name or location…',
                      hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        onPressed: () => _search(_searchController.text),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: AppColors.slaterspwn),
                      ),
                    ),
                    textInputAction: TextInputAction.search,
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: keyboardOpen ? 90 : 160,
                      child: GoogleMap(
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        },
                        onMapCreated: (ctrl) {
                          _mapController = ctrl;
                          _fitCameraToResults();
                        },
                        initialCameraPosition: CameraPosition(target: _fallbackCenter, zoom: 13),
                        markers: markers,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_loadError != null)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFE05353), size: 28),
                          const SizedBox(height: 8),
                          Text(_loadError!,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                          const SizedBox(height: 10),
                          OutlinedButton(onPressed: _loadNearby, child: const Text('Retry')),
                        ],
                      ),
                    )
                  else if (_savedSection.isEmpty && _nearbySection.isEmpty && _selected == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text('No clinics found. Try a different search.',
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ..._buildSectionedList(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: _bottomActionArea(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActionArea() {
    if (_selected == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.slaterspwn.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Center(
          child: Text('Select a clinic to continue',
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
      );
    }

    return Column(
      children: [
        if (_saveError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Text(_saveError!, style: GoogleFonts.zain(fontSize: 12, color: Colors.red.shade700)),
          ),
        ],
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : _confirm,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                : Text(widget.confirmLabel, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}

/// Opens [ClinicPickerBody] as a standalone modal that just returns the
/// picked [ClinicSearchResult] (or null if cancelled) — no case write of
/// any kind. Used by callers that need to capture a clinic pick as part of
/// a larger form (e.g. the Transfer Animal sheet's Clinic destination)
/// rather than immediately saving it onto a case's own vetClinic* fields
/// (see select_clinic_sheet.dart for that flow).
Future<ClinicSearchResult?> showClinicPickerSheet(
  BuildContext context, {
  required ClinicSearchRepository repository,
  required SavedClinicsRepository savedClinicsRepository,
  required String actorUid,
  double? centerLat,
  double? centerLng,
  ClinicSearchResult? initialClinic,
  required String title,
  required String confirmLabel,
  String? excludeClinicPlaceId,
  String? excludeClinicName,
  double? excludeClinicLat,
  double? excludeClinicLng,
  String excludeClinicLabel = 'Current clinic',
}) {
  return showModalBottomSheet<ClinicSearchResult>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ClinicPickerBody(
      repository: repository,
      savedClinicsRepository: savedClinicsRepository,
      actorUid: actorUid,
      centerLat: centerLat,
      centerLng: centerLng,
      initialClinic: initialClinic,
      title: title,
      currentClinicBannerLabel: 'Currently selected',
      confirmLabel: confirmLabel,
      errorPrefix: 'Could not select clinic',
      excludeClinicPlaceId: excludeClinicPlaceId,
      excludeClinicName: excludeClinicName,
      excludeClinicLat: excludeClinicLat,
      excludeClinicLng: excludeClinicLng,
      excludeClinicLabel: excludeClinicLabel,
      onConfirm: (clinic, _) async => Navigator.pop(context, clinic),
    ),
  );
}
