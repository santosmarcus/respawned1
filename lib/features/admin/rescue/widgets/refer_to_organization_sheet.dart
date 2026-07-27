import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_referral_candidate.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

/// Refer to Another Organization modal: search organizations by name, see
/// distance/accepted species/service area/intake availability, add a note,
/// and send. Returns true if a referral was sent.
Future<bool> showReferToOrganizationSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required OrganizationDirectoryRepository directory,
  required RescueCaseRepository caseRepository,
  required String actorUid,
  required String actorName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReferToOrganizationSheetBody(
      rescueCase: rescueCase,
      directory: directory,
      caseRepository: caseRepository,
      actorUid: actorUid,
      actorName: actorName,
    ),
  );
  return result ?? false;
}

class _ReferToOrganizationSheetBody extends StatefulWidget {
  final RescueCase rescueCase;
  final OrganizationDirectoryRepository directory;
  final RescueCaseRepository caseRepository;
  final String actorUid;
  final String actorName;

  const _ReferToOrganizationSheetBody({
    required this.rescueCase,
    required this.directory,
    required this.caseRepository,
    required this.actorUid,
    required this.actorName,
  });

  @override
  State<_ReferToOrganizationSheetBody> createState() => _ReferToOrganizationSheetBodyState();
}

class _ReferToOrganizationSheetBodyState extends State<_ReferToOrganizationSheetBody> {
  final _searchController = TextEditingController();
  final _noteController = TextEditingController();
  List<OrgReferralCandidate> _results = const [];
  OrgReferralCandidate? _selected;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await widget.directory.search(
      nameQuery: query,
      species: widget.rescueCase.animalType,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _send() async {
    if (_selected == null) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Refer to ${_selected!.name}?',
      message: 'This case will be marked Referred and the receiving organization '
          'can accept or decline it.',
      confirmLabel: 'Send Referral',
    );
    if (!confirmed || !mounted) return;

    setState(() => _sending = true);
    try {
      await widget.caseRepository.referToOrganization(
        caseId: widget.rescueCase.id,
        targetOrgId: _selected!.id,
        targetOrgName: _selected!.name,
        note: _noteController.text.trim().isEmpty ? null : _noteController.text.trim(),
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send referral: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.rescueCase;
    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
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
            const SizedBox(height: 14),
            Text('Refer to Another Organization',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(
                          child: Text('No organizations found.',
                              style:
                                  GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _results.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final org = _results[i];
                            final isSelected = _selected?.id == org.id;
                            final distance = (source.lat != null && source.lng != null)
                                ? org.distanceKmFrom(source.lat!, source.lng!)
                                : null;
                            return GestureDetector(
                              onTap: () => setState(() => _selected = org),
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
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(org.name,
                                              style: GoogleFonts.tiltWarp(
                                                  fontSize: 14, color: AppColors.textPrimary)),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_circle,
                                              color: AppColors.greenrspwn, size: 18),
                                      ],
                                    ),
                                    if (distance != null)
                                      Text('${distance.toStringAsFixed(1)} km away',
                                          style: GoogleFonts.zain(
                                              fontSize: 11, color: AppColors.textSecondary)),
                                    if (org.serviceArea != null && org.serviceArea!.isNotEmpty)
                                      Text('Service area: ${org.serviceArea}',
                                          style: GoogleFonts.zain(
                                              fontSize: 11, color: AppColors.textSecondary)),
                                    if (org.acceptedSpecies.isNotEmpty)
                                      Text('Accepts: ${org.acceptedSpecies.join(', ')}',
                                          style: GoogleFonts.zain(
                                              fontSize: 11, color: AppColors.textSecondary)),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: org.intakeAvailable
                                            ? AppColors.greenrspwn
                                            : AppColors.slaterspwn,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        org.intakeAvailable ? 'Intake available' : 'At capacity',
                                        style: GoogleFonts.zain(
                                            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Referral note (optional)',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 6),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selected == null || _sending) ? null : _send,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Send Referral',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
