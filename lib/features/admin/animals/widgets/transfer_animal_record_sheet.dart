import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/org_referral_candidate.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

enum _TransferTargetType { organization, volunteer }

/// Transfer for an Animal Record — visually/behaviorally modeled on the
/// existing rescue-case Transfer Animal sheet (transfer_animal_sheet.dart),
/// reusing the SAME organization search (OrganizationDirectoryRepository)
/// rather than a second lookup; writes to the animal doc instead of a
/// `cases` doc, since a record-level transfer isn't a case action.
Future<bool> showTransferAnimalRecordSheet(BuildContext context, {required AnimalRecord animal}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _TransferAnimalRecordSheetBody(animal: animal),
  );
  return result ?? false;
}

class _TransferAnimalRecordSheetBody extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  const _TransferAnimalRecordSheetBody({required this.animal});

  @override
  ConsumerState<_TransferAnimalRecordSheetBody> createState() => _TransferAnimalRecordSheetBodyState();
}

class _TransferAnimalRecordSheetBodyState extends ConsumerState<_TransferAnimalRecordSheetBody> {
  _TransferTargetType _targetType = _TransferTargetType.organization;
  final _searchController = TextEditingController();
  final _volunteerNameController = TextEditingController();
  final _notesController = TextEditingController();
  List<OrgReferralCandidate> _results = const [];
  OrgReferralCandidate? _selected;
  bool _loading = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchController.dispose();
    _volunteerNameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await ref
        .read(organizationDirectoryRepositoryProvider)
        .search(nameQuery: query, species: widget.animal.species);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  bool get _canConfirm =>
      _targetType == _TransferTargetType.organization ? _selected != null : _volunteerNameController.text.trim().isNotEmpty;

  Future<void> _confirm() async {
    if (!_canConfirm) return;
    final targetName =
        _targetType == _TransferTargetType.organization ? _selected!.name : _volunteerNameController.text.trim();
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Transfer to $targetName?',
      message: 'This records a transfer for this animal — full profile and medical history are preserved either way.',
      confirmLabel: 'Confirm Transfer',
    );
    if (!confirmed || !mounted) return;

    setState(() => _sending = true);
    try {
      await ref.read(animalRecordRepositoryProvider).transferAnimal(
            animalId: widget.animal.id,
            targetType: _targetType.name,
            targetName: targetName,
            targetOrgId: _targetType == _TransferTargetType.organization ? _selected!.id : null,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
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
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
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
            Text(widget.animal.name.isNotEmpty ? widget.animal.name : widget.animal.species,
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Another Organization'),
                    selected: _targetType == _TransferTargetType.organization,
                    onSelected: (_) => setState(() => _targetType = _TransferTargetType.organization),
                    selectedColor: AppColors.yellowrspwn,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    label: const Text('Rescue Volunteer'),
                    selected: _targetType == _TransferTargetType.volunteer,
                    onSelected: (_) => setState(() => _targetType = _TransferTargetType.volunteer),
                    selectedColor: AppColors.yellowrspwn,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_targetType == _TransferTargetType.organization) ...[
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
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(org.name,
                                            style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                                      ),
                                      if (isSelected) const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 18),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ] else ...[
              TextField(
                controller: _volunteerNameController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Volunteer name / contact',
                  hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                  isDense: true,
                  contentPadding: const EdgeInsets.only(bottom: 8),
                  enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                  focusedBorder:
                      const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
                ),
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              ),
              const Spacer(),
            ],

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

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (!_canConfirm || _sending) ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: AppColors.textSecondary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _sending
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Confirm Transfer', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
