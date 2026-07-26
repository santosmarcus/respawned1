import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/models/rescue/org_referral_candidate.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/clinic_picker_body.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/organization_picker_list.dart';

enum _TransferDestinationType { organization, clinic, volunteer }

extension on _TransferDestinationType {
  String get label => switch (this) {
        _TransferDestinationType.organization => 'Organization',
        _TransferDestinationType.clinic => 'Clinic',
        _TransferDestinationType.volunteer => 'Volunteer',
      };
  String get firestoreValue => switch (this) {
        _TransferDestinationType.organization => 'organization',
        _TransferDestinationType.clinic => 'clinic',
        _TransferDestinationType.volunteer => 'volunteer',
      };
}

/// Transfer Animal — post-treatment handoff to one of three destination
/// types (spec: never one untyped free-text destination). Deliberately not
/// called "Refer": a referral happens before a case is ever accepted; this
/// happens after treatment, once the animal is ready for its next step.
///
/// Organization branch reuses [OrganizationPickerList] — the exact same
/// search/result-card widget refer_to_organization_sheet.dart uses — so
/// this doesn't maintain a second organization-search implementation.
/// Clinic branch opens [showClinicPickerSheet], the same map/search/
/// Saved+Nearby/availability-warning picker select_clinic_sheet.dart uses,
/// via the shared [ClinicPickerBody] widget — just without that sheet's own
/// save step, since a transfer destination clinic must never overwrite the
/// case's own "currently treating" vetClinic* fields. Volunteer has no
/// queryable directory anywhere in this app (confirmed: no volunteers
/// collection/model exists — see Volunteers page investigation) — rather
/// than a manual-entry workaround, this shows a controlled empty state and
/// blocks submission entirely, never a fabricated volunteer list.
///
/// TODO(transfer): this only records a one-way "handed off" state
/// (`transferStatus: 'pending'`). There is no receiving-party accept/
/// decline workflow yet — see RescueCaseRepository.transferAnimal's own
/// TODO. Selecting a destination alone never marks the transfer complete —
/// that still requires the (not-yet-built) acknowledgement step.
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
  _TransferDestinationType _type = _TransferDestinationType.organization;

  // Organization branch
  OrgReferralCandidate? _selectedOrg;

  // Clinic branch
  ClinicSearchResult? _selectedClinic;

  // Common fields
  final _reasonController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _transferDate = DateTime.now();

  bool _sending = false;

  @override
  void dispose() {
    _reasonController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickClinic() async {
    final source = widget.rescueCase;
    final picked = await showClinicPickerSheet(
      context,
      repository: ref.read(clinicSearchRepositoryProvider),
      savedClinicsRepository: ref.read(savedClinicsRepositoryProvider),
      actorUid: 'admin',
      centerLat: source.lat,
      centerLng: source.lng,
      title: 'Select Transfer Clinic',
      confirmLabel: 'Select Clinic',
      initialClinic: _selectedClinic,
    );
    if (picked != null && mounted) setState(() => _selectedClinic = picked);
  }

  bool get _hasDestination => switch (_type) {
        _TransferDestinationType.organization => _selectedOrg != null,
        _TransferDestinationType.clinic => _selectedClinic != null,
        // No volunteer directory exists yet (spec §5) — never selectable,
        // so this destination type can never be submitted.
        _TransferDestinationType.volunteer => false,
      };

  String get _destinationName => switch (_type) {
        _TransferDestinationType.organization => _selectedOrg?.name ?? '',
        _TransferDestinationType.clinic => _selectedClinic?.name ?? '',
        _TransferDestinationType.volunteer => '',
      };

  bool get _canSubmit => _hasDestination && _reasonController.text.trim().isNotEmpty && !_sending;

  Future<void> _confirm() async {
    if (!_canSubmit) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Transfer to $_destinationName?',
      message: 'This records a simplified transfer — the receiving ${_type.label.toLowerCase()} does not '
          'yet have an accept/decline workflow in this app. This does not mark the transfer complete.',
      confirmLabel: 'Confirm Transfer',
    );
    if (!confirmed || !mounted) return;

    setState(() => _sending = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).transferAnimal(
            caseId: widget.rescueCase.id,
            targetType: _type.firestoreValue,
            targetName: _destinationName,
            targetContact: _selectedClinic?.phone,
            targetAddress: _type == _TransferDestinationType.clinic ? _selectedClinic?.address : null,
            targetOrganizationId: _type == _TransferDestinationType.organization ? _selectedOrg?.id : null,
            targetClinicPlaceId: _type == _TransferDestinationType.clinic ? _selectedClinic?.placeId : null,
            targetLat: _type == _TransferDestinationType.clinic ? _selectedClinic?.lat : null,
            targetLng: _type == _TransferDestinationType.clinic ? _selectedClinic?.lng : null,
            reason: _reasonController.text.trim(),
            transferDate: _transferDate,
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
      initialChildSize: 0.9,
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

            Text('Transfer Type', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _TransferDestinationType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _type == t,
                    selectedColor: AppColors.yellowrspwn,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    switch (_type) {
                      _TransferDestinationType.organization => _organizationBranch(source),
                      _TransferDestinationType.clinic => _clinicBranch(),
                      _TransferDestinationType.volunteer => _volunteerBranch(),
                    },
                    const SizedBox(height: 14),

                    Text('Reason for Transfer', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _reasonController,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(hintText: 'e.g. Ready for placement, needs specialized care'),
                    ),
                    const SizedBox(height: 12),

                    Text('Transfer Date', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _transferDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 30)),
                        );
                        if (picked != null) setState(() => _transferDate = picked);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${_transferDate.month}/${_transferDate.day}/${_transferDate.year}',
                                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                            const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textPrimary),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Text('Notes', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _notesController,
                      maxLines: 2,
                      decoration: const InputDecoration(hintText: 'Optional notes'),
                    ),

                    const SizedBox(height: 10),
                    Text(
                      'Assign Transporter: if transport is required, use the existing Assign Transporter flow '
                      'after this transfer is recorded — capture arrangements in the notes above for now.',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canSubmit ? _confirm : null,
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

  Widget _organizationBranch(RescueCase source) {
    return OrganizationPickerList(
      directory: ref.read(organizationDirectoryRepositoryProvider),
      sourceLat: source.lat,
      sourceLng: source.lng,
      species: source.animalType,
      selectedOrgId: _selectedOrg?.id,
      shrinkWrap: true,
      onSelect: (org) => setState(() => _selectedOrg = org),
    );
  }

  Widget _clinicBranch() {
    final clinic = _selectedClinic;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (clinic != null)
          _DestinationCard(
            title: clinic.name,
            subtitle: clinic.address,
            trailingBadge: clinic.openNow == false ? 'Closed' : null,
            selected: true,
            onTap: _pickClinic,
          ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _pickClinic,
            icon: const Icon(Icons.local_hospital_outlined, size: 18),
            label: Text(clinic == null ? 'Choose Clinic' : 'Change Clinic'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.slaterspwn),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _volunteerBranch() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        children: [
          const Icon(Icons.volunteer_activism_outlined, color: AppColors.textSecondary, size: 28),
          const SizedBox(height: 8),
          Text(
            'No eligible volunteers are available for transfer yet.',
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _DestinationCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? trailingBadge;
  final bool selected;
  final VoidCallback onTap;
  const _DestinationCard({
    required this.title,
    required this.subtitle,
    this.trailingBadge,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
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
                  child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                ),
                if (trailingBadge != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE05353), borderRadius: BorderRadius.circular(20)),
                    child: Text(trailingBadge!, style: GoogleFonts.zain(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                if (selected) const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 18),
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(subtitle, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
