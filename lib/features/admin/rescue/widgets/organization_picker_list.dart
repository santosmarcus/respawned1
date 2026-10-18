import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_referral_candidate.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';

/// Shared organization search + result list — search field, distance/
/// service-area/accepted-species/intake-availability card, selection
/// highlighting. Extracted from refer_to_organization_sheet.dart so the
/// Refer flow and the post-treatment Transfer flow's Organization
/// destination search the exact same directory the exact same way instead
/// of maintaining two lookalike implementations.
///
/// Selection-only: no send/confirm button of its own — callers embed this
/// inside whatever form/action bar they need (Refer's note field + Send
/// Referral, Transfer's reason/date/notes + Confirm Transfer).
class OrganizationPickerList extends StatefulWidget {
  final OrganizationDirectoryRepository directory;
  final double? sourceLat;
  final double? sourceLng;
  // Every species the source case covers (RescueCase.allSpecies) — an org
  // matches if it accepts any one of them, not just the first animal.
  final List<String>? species;
  final String? selectedOrgId;
  final ValueChanged<OrgReferralCandidate> onSelect;
  final ScrollController? scrollController;
  final bool shrinkWrap;

  const OrganizationPickerList({
    super.key,
    required this.directory,
    this.sourceLat,
    this.sourceLng,
    this.species,
    this.selectedOrgId,
    required this.onSelect,
    this.scrollController,
    this.shrinkWrap = false,
  });

  @override
  State<OrganizationPickerList> createState() => OrganizationPickerListState();
}

class OrganizationPickerListState extends State<OrganizationPickerList> {
  final _searchController = TextEditingController();
  List<OrgReferralCandidate> _results = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await widget.directory.search(nameQuery: query, species: widget.species);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _searchController,
          onChanged: _search,
          decoration: InputDecoration(
            hintText: 'Search organizations…',
            hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
            prefixIcon: const Icon(Icons.search, size: 20),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: const BorderSide(color: AppColors.slaterspwn),
            ),
          ),
        ),
        const SizedBox(height: 10),
        widget.shrinkWrap ? _list() : Expanded(child: _list()),
      ],
    );
  }

  Widget _list() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('No organizations found.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }
    if (widget.shrinkWrap) {
      return Column(
        children: [
          for (final org in _results) ...[
            _OrgCard(
              org: org,
              distanceKm: (widget.sourceLat != null && widget.sourceLng != null)
                  ? org.distanceKmFrom(widget.sourceLat!, widget.sourceLng!)
                  : null,
              selected: widget.selectedOrgId == org.id,
              onTap: () => widget.onSelect(org),
            ),
            const SizedBox(height: 10),
          ],
        ],
      );
    }
    return ListView.separated(
      controller: widget.scrollController,
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final org = _results[i];
        return _OrgCard(
          org: org,
          distanceKm: (widget.sourceLat != null && widget.sourceLng != null)
              ? org.distanceKmFrom(widget.sourceLat!, widget.sourceLng!)
              : null,
          selected: widget.selectedOrgId == org.id,
          onTap: () => widget.onSelect(org),
        );
      },
    );
  }
}

class _OrgCard extends StatelessWidget {
  final OrgReferralCandidate org;
  final double? distanceKm;
  final bool selected;
  final VoidCallback onTap;
  const _OrgCard({required this.org, required this.distanceKm, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppColors.textPrimary : AppColors.slaterspwn,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(org.name, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                ),
                if (selected) const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 18),
              ],
            ),
            if (distanceKm != null)
              Text('${distanceKm!.toStringAsFixed(1)} km away',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            if (org.serviceArea != null && org.serviceArea!.isNotEmpty)
              Text('Service area: ${org.serviceArea}',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            if (org.acceptedSpecies.isNotEmpty)
              Text('Accepts: ${org.acceptedSpecies.join(', ')}',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: org.intakeAvailable ? AppColors.greenrspwn : AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                org.intakeAvailable ? 'Intake available' : 'At capacity',
                style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
