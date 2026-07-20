import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/models/rescue/saved_clinic.dart';
import 'package:respawnd1/core/repos/clinic_search_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/repos/saved_clinics_repository.dart';
import 'package:respawnd1/core/utils/geo.dart';

/// What the Select Clinic sheet actually did, so callers never have to
/// guess what a bare `null`/non-null pop result means. Fixes a real bug:
/// dismissing the sheet (back button, tap-outside, swipe-down) used to be
/// indistinguishable from "continue to Assign Rider" at some call sites,
/// which sent admins to Assign Rider even when they'd cancelled.
enum ClinicSheetResult { cancelled, clinicSaved, assignRider }

class ClinicSheetOutcome {
  final ClinicSheetResult result;
  final ClinicSearchResult? clinic;
  const ClinicSheetOutcome._(this.result, this.clinic);
  const ClinicSheetOutcome.cancelled() : this._(ClinicSheetResult.cancelled, null);
  const ClinicSheetOutcome.clinicSaved(ClinicSearchResult clinic)
      : this._(ClinicSheetResult.clinicSaved, clinic);
  const ClinicSheetOutcome.assignRider(ClinicSearchResult clinic)
      : this._(ClinicSheetResult.assignRider, clinic);
}

/// Select Clinic modal — map/Places search, select a result, save it to
/// the case, and (when [offerAssignRider] is true) continue straight to
/// Assign Rider. The sheet performs the save itself and waits for it to
/// succeed before returning [ClinicSheetResult.clinicSaved] or
/// [ClinicSheetResult.assignRider] — a failed save keeps the sheet open
/// with an error instead of popping. Dismissing the sheet any other way
/// (back button, tap-outside, drag-to-close) always resolves to
/// [ClinicSheetResult.cancelled], never [ClinicSheetResult.assignRider].
///
/// [offerAssignRider] should be false when reassigning a clinic on a case
/// that already has a rider (e.g. from the Ongoing/In Treatment "Reassign
/// Clinic" action) — there, "continue to Assign Rider" doesn't apply, so
/// the primary action is just "Save Clinic".
///
/// [centerLat]/[centerLng] seed the initial nearby search and map camera —
/// normally the rescue case's own location. [currentClinicName] and the
/// rest of the `currentClinic*` fields describe whatever is already saved
/// on the case (if any) — passing the full set (not just name/address)
/// lets the sheet actually restore it as the *selected* clinic on open,
/// not just show it as an informational banner.
Future<ClinicSheetOutcome> showSelectClinicSheet(
  BuildContext context, {
  required ClinicSearchRepository repository,
  required RescueCaseRepository caseRepository,
  required SavedClinicsRepository savedClinicsRepository,
  required String caseId,
  required String actorUid,
  required String actorName,
  double? centerLat,
  double? centerLng,
  String? currentClinicName,
  String? currentClinicAddress,
  String? currentClinicPlaceId,
  double? currentClinicLat,
  double? currentClinicLng,
  String? currentClinicPhone,
  bool offerAssignRider = true,
}) async {
  final outcome = await showModalBottomSheet<ClinicSheetOutcome>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _SelectClinicSheetBody(
      repository: repository,
      caseRepository: caseRepository,
      savedClinicsRepository: savedClinicsRepository,
      caseId: caseId,
      actorUid: actorUid,
      actorName: actorName,
      centerLat: centerLat,
      centerLng: centerLng,
      currentClinicName: currentClinicName,
      currentClinicAddress: currentClinicAddress,
      currentClinicPlaceId: currentClinicPlaceId,
      currentClinicLat: currentClinicLat,
      currentClinicLng: currentClinicLng,
      currentClinicPhone: currentClinicPhone,
      offerAssignRider: offerAssignRider,
    ),
  );
  // showModalBottomSheet returns null for every dismissal path (back
  // button, tap-outside, swipe-down) — normalize that to an explicit
  // cancelled outcome so callers never branch on null.
  return outcome ?? const ClinicSheetOutcome.cancelled();
}

class _SelectClinicSheetBody extends StatefulWidget {
  final ClinicSearchRepository repository;
  final RescueCaseRepository caseRepository;
  final SavedClinicsRepository savedClinicsRepository;
  final String caseId;
  final String actorUid;
  final String actorName;
  final double? centerLat;
  final double? centerLng;
  final String? currentClinicName;
  final String? currentClinicAddress;
  final String? currentClinicPlaceId;
  final double? currentClinicLat;
  final double? currentClinicLng;
  final String? currentClinicPhone;
  final bool offerAssignRider;

  const _SelectClinicSheetBody({
    required this.repository,
    required this.caseRepository,
    required this.savedClinicsRepository,
    required this.caseId,
    required this.actorUid,
    required this.actorName,
    this.centerLat,
    this.centerLng,
    this.currentClinicName,
    this.currentClinicAddress,
    this.currentClinicPlaceId,
    this.currentClinicLat,
    this.currentClinicLng,
    this.currentClinicPhone,
    required this.offerAssignRider,
  });

  @override
  State<_SelectClinicSheetBody> createState() => _SelectClinicSheetBodyState();
}

class _SelectClinicSheetBodyState extends State<_SelectClinicSheetBody> {
  final _searchController = TextEditingController();
  GoogleMapController? _mapController;

  List<ClinicSearchResult> _results = const [];
  ClinicSearchResult? _selected;
  bool _loading = true;
  String? _loadError;
  bool _saving = false;
  String? _saveError;

  // Bookmarks — independent of clinic *selection* for this case. Loaded
  // once and then updated optimistically on toggle so the UI reflects a
  // save/unsave immediately without waiting on the round trip or requiring
  // the sheet to be reopened.
  List<SavedClinic> _savedClinics = const [];
  final Set<String> _pendingBookmarkToggles = {};

  LatLng get _fallbackCenter =>
      (widget.centerLat != null && widget.centerLng != null)
          ? LatLng(widget.centerLat!, widget.centerLng!)
          : const LatLng(14.5995, 120.9842); // Manila, matches rescue_page.dart's default

  @override
  void initState() {
    super.initState();
    // Restore whatever clinic is already saved on the case as the
    // *selected* one (not just an informational banner) — this is what
    // makes reopening the sheet on an accepted-with-clinic case show it as
    // genuinely selected, with the bottom action enabled immediately.
    final placeId = widget.currentClinicPlaceId;
    final lat = widget.currentClinicLat;
    final lng = widget.currentClinicLng;
    final name = widget.currentClinicName;
    if (placeId != null && placeId.isNotEmpty && lat != null && lng != null && name != null) {
      _selected = ClinicSearchResult(
        placeId: placeId,
        name: name,
        address: widget.currentClinicAddress ?? '',
        lat: lat,
        lng: lng,
        phone: widget.currentClinicPhone,
      );
    }
    _loadNearby();
    _loadSavedClinics();
  }

  Future<void> _loadSavedClinics() async {
    try {
      final saved = await widget.savedClinicsRepository.fetchSavedClinics(widget.actorUid);
      if (mounted) setState(() => _savedClinics = saved);
    } catch (_) {
      // Bookmarks are a nice-to-have on top of search — a failure to load
      // them shouldn't block clinic search/selection at all, just leaves
      // the Saved Clinics section empty for this open of the sheet.
    }
  }

  bool _isSaved(String placeId) => _savedClinics.any((s) => s.placeId == placeId);

  Future<void> _toggleBookmark(ClinicSearchResult clinic) async {
    // Rapid re-taps on the same clinic while a toggle is in flight are
    // ignored rather than queued — the in-flight request already reflects
    // the user's latest intent by the time it lands.
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
      // Revert the optimistic update and say why.
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

  /// Ascending distance from the case location; clinics without a
  /// calculable distance (case location unknown) sort after ones that
  /// have it, never mixed in ahead of real nearest-first ordering.
  int _byDistance(ClinicSearchResult a, ClinicSearchResult b) {
    final da = _distanceKmTo(a);
    final db = _distanceKmTo(b);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return da.compareTo(db);
  }

  /// Bookmarked clinics, merged from two sources: whichever of them appear
  /// in the current search results, plus every other bookmark regardless
  /// of whether it's part of this search (skipping any with no usable
  /// coordinates) — always sorted nearest-first. Never includes the same
  /// clinic twice (deduplicated by placeId).
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
        if (converted != null) combined.add(converted); // skip incomplete (no coords) bookmarks
      }
    }
    combined.sort(_byDistance);
    return combined;
  }

  /// Current search results, minus anything already shown in Saved
  /// Clinics — no clinic appears in both sections — sorted nearest-first
  /// rather than relying on whatever order Places returned them in.
  List<ClinicSearchResult> get _nearbySection {
    final savedPlaceIds = _savedClinics.map((s) => s.placeId).toSet();
    final seen = <String>{};
    final list = _results
        .where((r) => !savedPlaceIds.contains(r.placeId) && seen.add(r.placeId))
        .toList();
    list.sort(_byDistance);
    return list;
  }

  List<Widget> _buildSectionedList() {
    final saved = _savedSection;
    final nearby = _nearbySection;
    final widgets = <Widget>[];

    // The case's previously-selected clinic might not be bookmarked and
    // might not appear in this particular search (different query, moved
    // out of the default nearby radius, etc.) — if so, still surface it so
    // it's visibly selected instead of silently vanishing from the list.
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
            style: GoogleFonts.zain(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      );

  Widget _clinicTile(ClinicSearchResult clinic) {
    final isSelected = clinic.placeId == _selected?.placeId;
    final isSaved = _isSaved(clinic.placeId);
    final isBookmarkPending = _pendingBookmarkToggles.contains(clinic.placeId);
    final distanceKm = _distanceKmTo(clinic);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: isSelected ? AppColors.yellowrspwn.withValues(alpha: 0.15) : null,
      leading: Icon(
        isSelected ? Icons.check_circle : Icons.local_hospital_outlined,
        color: isSelected ? AppColors.greenrspwn : AppColors.textPrimary,
      ),
      title: Text(clinic.name, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(clinic.address, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Wrap(
            spacing: 8,
            children: [
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
      // Tapping the card selects the clinic for this rescue case; the
      // bookmark icon is a separate tap target with its own onPressed, so
      // it doesn't fall through to this onTap (IconButton establishes its
      // own hit-test region ahead of the ListTile's).
      onTap: () => _selectResult(clinic),
      trailing: SizedBox(
        width: 48,
        height: 48,
        child: isBookmarkPending
            ? const Padding(
                padding: EdgeInsets.all(14),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(
                  isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: isSaved ? AppColors.yellowrspwn : AppColors.textSecondary,
                ),
                tooltip: isSaved ? 'Remove bookmark' : 'Save clinic',
                onPressed: () => _toggleBookmark(clinic),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _describeLoadError(Object e) {
    if (e is ClinicSearchConfigException) {
      return 'Clinic search is misconfigured: ${e.message}';
    }
    if (e is ClinicSearchNetworkException) {
      return e.message;
    }
    if (e is ClinicSearchUnexpectedException) {
      return e.message;
    }
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
      final results = await widget.repository.nearbySearch(
        lat: widget.centerLat!,
        lng: widget.centerLng!,
      );
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
      final results = await widget.repository.textSearch(
        query: query,
        lat: widget.centerLat,
        lng: widget.centerLng,
      );
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
    setState(() {
      _selected = clinic;
      _saveError = null;
    });
  }

  Future<void> _confirm({required bool asAssignRider}) async {
    final clinic = _selected;
    if (clinic == null || _saving) return; // guards double-taps
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await widget.caseRepository.assignClinic(
        caseId: widget.caseId,
        clinicName: clinic.name,
        clinicAddress: clinic.address,
        clinicPlaceId: clinic.placeId,
        clinicLat: clinic.lat,
        clinicLng: clinic.lng,
        clinicPhone: clinic.phone,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) {
        Navigator.pop(
          context,
          asAssignRider ? ClinicSheetOutcome.assignRider(clinic) : ClinicSheetOutcome.clinicSaved(clinic),
        );
      }
    } catch (e) {
      // Save failed — stay open, show why, let them retry. Never pop here.
      if (mounted) {
        setState(() {
          _saveError = 'Could not save clinic: $e';
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

    // Keyboard-open fix: the whole scrollable middle section (drag handle
    // through results) lives in ONE ListView bound to the
    // DraggableScrollableSheet's own scrollController, instead of a fixed,
    // non-scrolling Column with only the results list independently
    // scrollable. Previously, opening the keyboard added bottom padding
    // (for viewInsets.bottom) to a Column whose other children were all
    // fixed-height — with nothing able to shrink to compensate, the total
    // required height exceeded the sheet's actual pixel height and
    // overflowed. Now the map shrinks a bit and everything above the
    // pinned bottom action bar can scroll to stay reachable instead.
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
                      decoration: BoxDecoration(
                        color: AppColors.slaterspwn,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Select Clinic',
                      style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                  if (widget.currentClinicName != null) ...[
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
                                Text('Currently saved: ${widget.currentClinicName}',
                                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700)),
                                if (widget.currentClinicAddress != null)
                                  Text(widget.currentClinicAddress!,
                                      style:
                                          GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
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
                          OutlinedButton(
                            onPressed: _loadNearby,
                            child: const Text('Retry'),
                          ),
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
            // Pinned footer — always reachable regardless of scroll
            // position or keyboard state.
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
              style: GoogleFonts.zain(
                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
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
            child: Text(_saveError!,
                style: GoogleFonts.zain(fontSize: 12, color: Colors.red.shade700)),
          ),
        ],
        // Only one continuation action now — no separate "save without
        // continuing" path. Saving and (when applicable) continuing to
        // Assign Rider happen together, or not at all.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _saving ? null : () => _confirm(asAssignRider: widget.offerAssignRider),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                : Text(widget.offerAssignRider ? 'Assign Transporter' : 'Save Clinic',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}
