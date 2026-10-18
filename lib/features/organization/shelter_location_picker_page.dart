import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Searchable address/place picker for the organization's shelter/intake
/// location — reuses ClinicSearchRepository.searchPlaces (same Places
/// API (New) infra/key/error-handling already used for clinic search, just
/// without the veterinary bias) rather than a second search integration.
/// The map here is a small read-only preview of the selected result, not a
/// permanent fixture — this picker is the only place a map appears in the
/// shelter-location flow; Intake Details itself never shows one.
///
/// Returns `true` via Navigator.pop if a location was actually saved.
///
/// Exactly one of [organizationId] / [userId] should be provided:
/// [organizationId] saves onto that organization's shared shelter location
/// (`organizations/{orgId}.shelter*`); [userId] is the
/// no-organization-linked fallback (see IntakeDetailPage's TODO on why this
/// exists), saving onto that user's own `temporaryShelter*` fields instead
/// so the Intake flow can still be exercised without organization
/// membership set up yet.
class ShelterLocationPickerPage extends ConsumerStatefulWidget {
  final String? organizationId;
  final String? userId;
  // Whatever is already saved (organizations/{orgId}.shelter* or
  // users/{uid}.temporaryShelter*) — pre-selects it on open so reopening
  // the picker shows the current location on the map instead of a blank
  // search, matching select_clinic_sheet.dart's own restore-on-open
  // pattern.
  final String? initialName;
  final String? initialAddress;
  final String? initialPlaceId;
  final double? initialLat;
  final double? initialLng;
  const ShelterLocationPickerPage({
    super.key,
    this.organizationId,
    this.userId,
    this.initialName,
    this.initialAddress,
    this.initialPlaceId,
    this.initialLat,
    this.initialLng,
  }) : assert(organizationId != null || userId != null,
            'ShelterLocationPickerPage needs either an organizationId or a userId to save to.');

  @override
  ConsumerState<ShelterLocationPickerPage> createState() => _ShelterLocationPickerPageState();
}

class _ShelterLocationPickerPageState extends ConsumerState<ShelterLocationPickerPage> {
  final _searchController = TextEditingController();
  List<ClinicSearchResult> _results = const [];
  ClinicSearchResult? _selected;
  bool _searching = false;
  bool _saving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final name = widget.initialName;
    final placeId = widget.initialPlaceId;
    final lat = widget.initialLat;
    final lng = widget.initialLng;
    if (name != null && name.isNotEmpty && placeId != null && lat != null && lng != null) {
      _selected = ClinicSearchResult(
        placeId: placeId,
        name: name,
        address: widget.initialAddress ?? '',
        lat: lat,
        lng: lng,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _searching = true;
      _errorMessage = null;
    });
    try {
      final results = await ref.read(clinicSearchRepositoryProvider).searchPlaces(query: query.trim());
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _errorMessage = 'Search failed: $e';
        });
      }
    }
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null || _saving) return;
    setState(() => _saving = true);
    try {
      final repo = ref.read(organizationDirectoryRepositoryProvider);
      if (widget.organizationId != null) {
        await repo.saveShelterLocation(
          organizationId: widget.organizationId!,
          name: selected.name,
          address: selected.address,
          placeId: selected.placeId,
          lat: selected.lat,
          lng: selected.lng,
        );
      } else {
        await repo.saveUserShelterLocation(
          uid: widget.userId!,
          name: selected.name,
          address: selected.address,
          placeId: selected.placeId,
          lat: selected.lat,
          lng: selected.lng,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Could not save shelter location: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context, false),
        ),
        title: Text('Set Shelter Location', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search address or place…',
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
            ),
          ),

          if (selected != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                child: SizedBox(
                  height: 140,
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: LatLng(selected.lat, selected.lng), zoom: 15),
                    markers: {
                      Marker(markerId: const MarkerId('shelter'), position: LatLng(selected.lat, selected.lng)),
                    },
                    liteModeEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    scrollGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(_errorMessage!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ),

          Expanded(
            child: _searching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.trim().isEmpty
                              ? 'Search for your shelter\'s address.'
                              : 'No results found.',
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _results.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final r = _results[i];
                          final isSelected = selected?.placeId == r.placeId;
                          return GestureDetector(
                            onTap: () => setState(() => _selected = r),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSelected ? AppColors.textPrimary : AppColors.slaterspwn,
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(r.name,
                                            style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                                        if (r.address.isNotEmpty)
                                          Text(r.address,
                                              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                                      ],
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (selected == null || _saving) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Save Shelter Location',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
