import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/org_referral_candidate.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

/// Transfer Animal — post-treatment handoff to another organization/
/// shelter. Deliberately not called "Refer": a referral happens before a
/// case is ever accepted; this happens after treatment, once the animal is
/// ready for its next step. Reuses the same organization-search UI as
/// "Refer to Another Organization" (refer_to_organization_sheet.dart) —
/// same search/card/selected-state pattern, transfer-specific wording and
/// a different, simplified write (RescueCaseRepository.transferAnimal).
///
/// TODO(transfer): this only records a one-way "handed off" state
/// (`transferStatus: 'pending'`). There is no receiving-organization
/// accept/decline workflow yet — see the repository method's own TODO.
Future<bool> showTransferAnimalSheet(BuildContext context, {required RescueCase rescueCase}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _TransferAnimalSheetBody(rescueCase: rescueCase),
  );
  return result ?? false;
}

class _TransferAnimalSheetBody extends ConsumerStatefulWidget {
  final RescueCase rescueCase;
  const _TransferAnimalSheetBody({required this.rescueCase});

  @override
  ConsumerState<_TransferAnimalSheetBody> createState() => _TransferAnimalSheetBodyState();
}

class _TransferAnimalSheetBodyState extends ConsumerState<_TransferAnimalSheetBody> {
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
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
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await ref.read(organizationDirectoryRepositoryProvider).search(
          nameQuery: query,
          species: widget.rescueCase.animalType,
        );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Transfer to ${_selected!.name}?',
      message: 'This records a simplified transfer — the receiving organization does not '
          'yet have an accept/decline workflow in this app.',
      confirmLabel: 'Confirm Transfer',
    );
    if (!confirmed || !mounted) return;

    setState(() => _sending = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).transferAnimal(
            caseId: widget.rescueCase.id,
            targetOrganizationId: _selected!.id,
            targetOrganizationName: _selected!.name,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            actorUid: 'admin',
            actorName: 'Admin Staff',
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not transfer animal: $e'), backgroundColor: Colors.redAccent),
        );
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.rescueCase;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
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
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Transfer Animal', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('#${source.shortCaseId} · ${source.speciesSummary}',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            if ((source.vetClinicName ?? '').isNotEmpty)
              Text('Current clinic: ${source.vetClinicName}',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
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
                              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
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
                                              style:
                                                  GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 18),
                                      ],
                                    ),
                                    if (distance != null)
                                      Text('${distance.toStringAsFixed(1)} km away',
                                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                                    if (org.acceptedSpecies.isNotEmpty)
                                      Text('Accepts: ${org.acceptedSpecies.join(', ')}',
                                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _notesController,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Transfer notes (optional)',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 6),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                focusedBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
              ),
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),

            const SizedBox(height: 6),
            Text(
              'Assign Transporter: not required for this simplified transfer — '
              'capture arrangements in the notes above for now.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selected == null || _sending) ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Confirm Transfer',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
