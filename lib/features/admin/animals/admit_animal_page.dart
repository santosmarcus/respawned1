import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/medical_episode.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';

/// Animal Record -> Medical -> Admit Animal. For an animal already in the
/// organization's records (not a new rescue report) — collects why, then
/// goes straight into the existing clinic-selection/transporter-assignment
/// flow, never through Rescue Review/Accept/Possible-Duplicate/Community
/// Reports (those are rescue-report concepts that don't apply here). See
/// RescueCaseRepository.createAdmissionCase for how the underlying case
/// doc is created to make that skip possible.
class AdmitAnimalPage extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  const AdmitAnimalPage({super.key, required this.animal});

  @override
  ConsumerState<AdmitAnimalPage> createState() => _AdmitAnimalPageState();
}

class _AdmitAnimalPageState extends ConsumerState<AdmitAnimalPage> {
  AdmissionReason? _reason;
  final _notesController = TextEditingController();
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _submit() async {
    if (_isSubmitting || _reason == null) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      // Same shelter-location resolution Intake Details already uses
      // (org's saved shelter -> this account's own temporary saved
      // location) — reused as-is rather than a second lookup, since it's
      // exactly "where is this organization" either way.
      final uid = _actorUid;
      final membership = uid.isEmpty ? null : await ref.read(orgMembershipServiceProvider).getMembership(uid);
      final orgRepo = ref.read(organizationDirectoryRepositoryProvider);
      var destination = await orgRepo.resolveShelterLocation(membership?.organizationId);
      destination ??= uid.isEmpty ? null : await orgRepo.resolveUserShelterLocation(uid);

      if (destination == null || destination.lat == null || destination.lng == null) {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
            _error = 'No shelter location is set for this account yet. Set one from Intake Details first.';
          });
        }
        return;
      }

      final actorName = FirebaseAuth.instance.currentUser?.displayName?.trim();
      final caseId = await ref.read(animalRecordRepositoryProvider).admitAnimal(
            animal: widget.animal,
            reason: _reason!.name,
            notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            shelterLat: destination.lat!,
            shelterLng: destination.lng!,
            shelterAddress: destination.address ?? destination.name,
            actorUid: uid,
            actorName: (actorName != null && actorName.isNotEmpty) ? actorName : 'Admin Staff',
          );

      if (!mounted) return;
      setState(() => _isSubmitting = false);

      // Straight into the existing Select Clinic sheet — no rescue-review
      // detour. offerAssignRider carries the admin straight on to Assign
      // Transporter (also existing/reused) once a clinic is saved.
      final outcome = await showSelectClinicSheet(
        context,
        repository: ref.read(clinicSearchRepositoryProvider),
        caseRepository: ref.read(rescueCaseRepositoryProvider),
        savedClinicsRepository: ref.read(savedClinicsRepositoryProvider),
        caseId: caseId,
        actorUid: uid,
        actorName: (actorName != null && actorName.isNotEmpty) ? actorName : 'Admin Staff',
        centerLat: destination.lat,
        centerLng: destination.lng,
        offerAssignRider: true,
      );
      if (!mounted) return;

      switch (outcome.result) {
        case ClinicSheetResult.assignRider:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => AssignRiderPage(caseId: caseId, data: const {}),
            ),
          );
          break;
        case ClinicSheetResult.clinicSaved:
        case ClinicSheetResult.cancelled:
          // Either way, the admission case already exists (and the animal
          // record already points at it) — pop back to the Medical tab,
          // which reads its state live and offers the right resume action
          // (Select Clinic / Assign Transporter) either way.
          Navigator.pop(context);
          break;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _error = 'Could not start admission: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Admit Animal', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.animal.name.isNotEmpty ? widget.animal.name : widget.animal.species,
                style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('This starts a new medical episode for this animal — not a new rescue report.',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 20),

            Text('Reason for Admission',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AdmissionReason.values.map((r) {
                final selected = _reason == r;
                return ChoiceChip(
                  label: Text(r.label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                  selected: selected,
                  selectedColor: AppColors.yellowrspwn,
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: const BorderSide(color: AppColors.slaterspwn),
                  ),
                  onSelected: (_) => setState(() => _reason = r),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),

            Text('Notes',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Describe the concern (optional)',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                focusedBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),

            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ],

            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_reason == null || _isSubmitting) ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: AppColors.textSecondary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Continue to Select Clinic', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
