import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/medical_episode.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/animals/admit_animal_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/add_care_record_sheet.dart';
import 'package:respawnd1/features/admin/animals/widgets/add_vaccine_record_sheet.dart';
import 'package:respawnd1/features/admin/animals/widgets/health_details_sheet.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/select_clinic_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/treatment_log_widgets.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/animals/widgets/care_updates_section.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';

const String _kNA = 'Not provided';

/// The animal's full health history — reuses the existing rescue Treatment
/// Details / treatment-log components wherever an episode's medical
/// content needs showing, rather than a second treatment interface. See
/// _EpisodeCard for how each episode's logs come straight from
/// treatmentLogsProvider, the same provider Treatment Details itself uses.
class AnimalMedicalTab extends ConsumerWidget {
  final AnimalRecord animal;
  const AnimalMedicalTab({super.key, required this.animal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MedicalProfileSection(animal: animal),
          if (animal.hasMeaningfulSpecialNeedsInfo) ...[
            const SizedBox(height: 20),
            SpecialNeedsSection(animal: animal),
          ],
          const SizedBox(height: 20),
          VaccineSection(animal: animal),
          const SizedBox(height: 20),
          PreventiveCareSection(animal: animal),
          const SizedBox(height: 20),
          MedicationSection(animal: animal),
          const SizedBox(height: 20),
          CareUpdatesSection(animal: animal),
          const SizedBox(height: 8),
          // Backfill for animals whose paper health list is out of date.
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => showPastHealthHistorySheet(context, animal: animal),
              icon: const Icon(Icons.history, size: 16, color: AppColors.textPrimary),
              label: Text('Add Past Health Records',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 12),
          _CurrentStatusSection(animal: animal),
          const SizedBox(height: 20),
          Text('Treatment Episodes', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          _EpisodesSection(animal: animal),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---- Medical Profile (was "Health") ------------------------------------
// Renamed visible terminology only — the underlying AnimalHealthDetails
// fields/Firestore keys (spayedNeutered/dewormed/allergies/
// chronicConditions/currentMedications/lastVetCheckup/weightKg/
// bodyCondition/microchipStatus) are unchanged. Shared by the admin
// Medical tab (editable, [readOnly]=false) and the user-facing Medical tab
// ([readOnly]=true, no Edit button, per spec section 8) so both stay in
// sync with one implementation.

/// Read-only value formatting shared by admin and user Medical Profile
/// display — "Not recorded" is the one consistent fallback for anything
/// empty/unknown (spec section 8), rather than admin's own "Unknown"/"Not
/// provided" wording.
String medicalProfileBoolLabel(bool? v, {bool userFacing = false}) =>
    v == null ? (userFacing ? 'Not recorded' : 'Unknown') : (v ? 'Yes' : 'No');
String medicalProfileOrFallback(String? v, {bool userFacing = false}) =>
    (v == null || v.isEmpty) ? (userFacing ? 'Not recorded' : _kNA) : v;

class MedicalProfileSection extends StatelessWidget {
  final AnimalRecord animal;
  /// True on the user-facing Medical tab: hides the Edit button and uses
  /// "Not recorded" instead of admin's "Unknown"/"Not provided" fallback.
  final bool readOnly;
  const MedicalProfileSection({super.key, required this.animal, this.readOnly = false});

  @override
  Widget build(BuildContext context) {
    final h = animal.health;
    String boolLabel(bool? v) => medicalProfileBoolLabel(v, userFacing: readOnly);
    String orNA(String? v) => medicalProfileOrFallback(v, userFacing: readOnly);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Medical Profile', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              if (!readOnly)
                TextButton(
                  onPressed: () => showHealthDetailsSheet(context, animal: animal),
                  child: Text('Edit Medical Profile', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
            ],
          ),
          _HealthRow('Spay/Neuter Status', boolLabel(h.sterilized)),
          _HealthRow('Deworming Status', boolLabel(h.dewormed)),
          _HealthRow('Known Allergies', orNA(h.allergies)),
          _HealthRow('Chronic Conditions', orNA(h.chronicConditions)),
          _HealthRow('Current Medications', orNA(h.currentMedications)),
          _HealthRow('Last Veterinary Checkup',
              h.lastVetCheckup != null ? formatDate(h.lastVetCheckup!) : (readOnly ? 'Not recorded' : _kNA)),
          _HealthRow('Weight', h.weightKg != null ? '${h.weightKg} kg' : (readOnly ? 'Not recorded' : _kNA)),
          _HealthRow('Body Condition', orNA(h.bodyCondition)),
          _HealthRow('Identification Tag Status', orNA(h.microchipStatus)),
        ],
      ),
    );
  }
}

/// The user-facing Medical tab: the yes/no health summary the public
/// profile (`publicAnimals/{id}`) carries. Details stay with staff.
class PublicHealthSummarySection extends StatelessWidget {
  final AnimalRecord animal;
  const PublicHealthSummarySection({super.key, required this.animal});

  @override
  Widget build(BuildContext context) {
    String label(bool? v) => medicalProfileBoolLabel(v, userFacing: true);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Health', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          _HealthRow('Vaccinated', label(animal.vaccinated)),
          _HealthRow('Spayed/Neutered', label(animal.health.sterilized)),
          _HealthRow('Dewormed', label(animal.health.dewormed)),
          _HealthRow('Special needs', animal.hasSpecialNeeds ? 'Yes' : 'No'),
          const SizedBox(height: 10),
          Text('Ask the shelter for vaccine dates and other medical details when you apply.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  final String label;
  final String value;
  const _HealthRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

// ---- Special Needs --------------------------------------------------------
// Only rendered when animal.hasMeaningfulSpecialNeedsInfo (see the guard in
// AnimalMedicalTab.build above) — never a bare "Special Needs / None" row.
// Distinct from MedicalProfileSection: this is the structured disability/
// impairment list, not sterilization/allergies/chronic conditions/etc.

class SpecialNeedsSection extends StatelessWidget {
  final AnimalRecord animal;
  const SpecialNeedsSection({super.key, required this.animal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Special Needs', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          if (animal.specialNeedsTypes.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final need in animal.specialNeedsTypes)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(20)),
                    child: Text(need, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
              ],
            ),
          if ((animal.specialNeedsNotes ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(animal.specialNeedsNotes!.trim(), style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}

// ---- Vaccines -----------------------------------------------------------

class VaccineSection extends ConsumerWidget {
  final AnimalRecord animal;
  /// True on the user-facing Medical tab: hides the "Add Vaccine Record"
  /// action and shows a user-facing empty-state message.
  final bool readOnly;
  const VaccineSection({super.key, required this.animal, this.readOnly = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(vaccinationsProvider(animal.id));
    final records = recordsAsync.asData?.value ?? const <VaccinationRecord>[];

    // Most recent record per vaccine name — older ones are reachable via
    // "View history", not shown in the main list.
    final byName = <String, VaccinationRecord>{};
    for (final r in records) {
      final existing = byName[r.vaccineName];
      if (existing == null || r.dateAdministered.isAfter(existing.dateAdministered)) {
        byName[r.vaccineName] = r;
      }
    }
    final latest = byName.values.toList()..sort((a, b) => a.vaccineName.compareTo(b.vaccineName));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Vaccines', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              if (!readOnly)
                TextButton(
                  onPressed: () => showAddVaccineRecordSheet(context, animal: animal),
                  child: Text('Add Vaccine Record',
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
            ],
          ),
          if (latest.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  readOnly ? 'No vaccine records available.' : 'No vaccination records yet.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            )
          else
            for (final r in latest) _VaccineTile(record: r, allForName: records.where((x) => x.vaccineName == r.vaccineName).toList()),
        ],
      ),
    );
  }
}

class _VaccineTile extends StatelessWidget {
  final VaccinationRecord record;
  final List<VaccinationRecord> allForName;
  const _VaccineTile({required this.record, required this.allForName});

  (Color, Color) _statusColors(VaccineStatus s) => switch (s) {
        VaccineStatus.upToDate => (AppColors.greenrspwn, AppColors.textPrimary),
        VaccineStatus.dueSoon => (AppColors.yellowrspwn, AppColors.textPrimary),
        VaccineStatus.overdue => (AppColors.error, Colors.white),
        VaccineStatus.noRecord => (AppColors.slaterspwn, AppColors.textSecondary),
      };

  void _showHistory(BuildContext context) {
    showInfoDialog(context, title: '${record.vaccineName} History', content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final r in allForName..sort((a, b) => b.dateAdministered.compareTo(a.dateAdministered)))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Given: ${formatDate(r.dateAdministered)}',
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                      Text('Valid for ${r.validityDurationDays} days · Next due ${formatDate(r.nextDueDate)}',
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      if ((r.clinicOrProvider ?? '').isNotEmpty)
                        Text(r.clinicOrProvider!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      if (r.attachments.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        MediaThumbStrip(media: r.attachments, size: 44),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = _statusColors(record.status);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => _showHistory(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.vaccineName, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(
                    'Given: ${formatDate(record.dateAdministered)} · '
                    'Valid ${record.validityDurationDays}d · Next due ${formatDate(record.nextDueDate)}',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (allForName.length > 1)
                    Text('View history (${allForName.length})',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.greenrspwn, decoration: TextDecoration.underline)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
              child: Text(record.status.label, style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: fg)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Preventive care (deworming, flea & tick, vet checkups) ----------------

/// Latest record per care type with its due status, like the vaccine list.
/// Recorded directly on the animal — no treatment episode needed for
/// routine care given in the shelter.
class PreventiveCareSection extends ConsumerWidget {
  final AnimalRecord animal;
  const PreventiveCareSection({super.key, required this.animal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(careRecordsProvider(animal.id)).asData?.value ?? const <CareRecord>[];
    final latest = CareRecord.latestByType(records);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Preventive Care', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              TextButton(
                onPressed: () => showAddCareRecordSheet(context, animal: animal),
                child: Text('Add Record',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
          for (final type in CareType.values)
            _CareTile(
              type: type,
              latest: latest[type],
              history: records.where((r) => r.type == type).toList(),
              onAdd: () => showAddCareRecordSheet(context, animal: animal, initialType: type),
            ),
        ],
      ),
    );
  }
}

class _CareTile extends StatelessWidget {
  final CareType type;
  final CareRecord? latest;
  final List<CareRecord> history;
  final VoidCallback onAdd;
  const _CareTile({required this.type, required this.latest, required this.history, required this.onAdd});

  static String _d(DateTime d) => formatDate(d);

  (Color, Color) _statusColors(VaccineStatus s) => switch (s) {
        VaccineStatus.upToDate => (AppColors.greenrspwn, AppColors.textPrimary),
        VaccineStatus.dueSoon => (AppColors.yellowrspwn, AppColors.textPrimary),
        VaccineStatus.overdue => (AppColors.error, Colors.white),
        VaccineStatus.noRecord => (AppColors.slaterspwn, AppColors.textSecondary),
      };

  void _showHistory(BuildContext context) {
    showInfoDialog(context, title: '${type.label} History', content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final r in history)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            _d(r.dateGiven),
                            if ((r.product ?? '').isNotEmpty) r.product!,
                            if ((r.provider ?? '').isNotEmpty) r.provider!,
                            if ((r.notes ?? '').isNotEmpty) r.notes!,
                          ].join(' · '),
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                        ),
                        if (r.attachments.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          MediaThumbStrip(media: r.attachments, size: 44),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ));
  }

  @override
  Widget build(BuildContext context) {
    final r = latest;
    final status = r?.status ?? VaccineStatus.noRecord;
    final (bg, fg) = _statusColors(status);
    final dueLabel = type == CareType.vetCheckup ? 'Next visit' : 'Next due';
    final statusLabel = r == null
        ? 'No record'
        : (r.nextDueDate == null ? 'Done' : (status == VaccineStatus.overdue && type == CareType.vetCheckup ? 'Visit overdue' : status.label));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: InkWell(
        onTap: r == null ? onAdd : () => _showHistory(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(
                    r == null
                        ? 'Not recorded yet — tap to add'
                        : '${type == CareType.vetCheckup ? 'Last visit' : 'Given'}: ${_d(r.dateGiven)}'
                            '${r.nextDueDate != null ? ' · $dueLabel ${_d(r.nextDueDate!)}' : ''}',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  ),
                  if (history.length > 1)
                    Text('View history (${history.length})',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.greenrspwn, decoration: TextDecoration.underline)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: r?.nextDueDate == null && r != null ? AppColors.greenrspwn : bg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel,
                  style: GoogleFonts.zain(
                      fontSize: 10, fontWeight: FontWeight.bold, color: r?.nextDueDate == null && r != null ? AppColors.textPrimary : fg)),
            ),
          ],
        ),
      ),
    );
  }
}

// ---- Current admission status -------------------------------------------

Future<void> _resumeClinicSelection(BuildContext context, WidgetRef ref, RescueCase c) async {
  final outcome = await showSelectClinicSheet(
    context,
    repository: ref.read(clinicSearchRepositoryProvider),
    caseRepository: ref.read(rescueCaseRepositoryProvider),
    savedClinicsRepository: ref.read(savedClinicsRepositoryProvider),
    caseId: c.id,
    actorUid: 'admin',
    actorName: 'Admin Staff',
    centerLat: c.lat,
    centerLng: c.lng,
    currentClinicName: c.vetClinicName,
    currentClinicAddress: c.vetClinicAddress,
    currentClinicPlaceId: c.vetClinicPlaceId,
    currentClinicLat: c.vetClinicLat,
    currentClinicLng: c.vetClinicLng,
    currentClinicPhone: c.vetClinicPhone,
    offerAssignRider: true,
  );
  if (outcome.result == ClinicSheetResult.assignRider && context.mounted) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw)));
  }
}

class _CurrentStatusSection extends ConsumerWidget {
  final AnimalRecord animal;
  const _CurrentStatusSection({required this.animal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentCaseId = animal.currentCaseId;
    if (currentCaseId == null || currentCaseId.isEmpty) {
      return _NotInTreatmentCard(animal: animal);
    }

    final c = ref.watch(caseDetailProvider(currentCaseId)).asData?.value;
    if (c == null || c.status.isTerminal) {
      return _NotInTreatmentCard(animal: animal);
    }

    if (!c.hasSavedClinic) {
      return _ResumeCard(
        title: 'Pending — Select Clinic',
        subtitle: 'A clinic still needs to be chosen for this admission.',
        buttonLabel: 'Select Clinic',
        onPressed: () => _resumeClinicSelection(context, ref, c),
      );
    }

    final assignment = ref.watch(currentAssignmentProvider(currentCaseId)).asData?.value;

    if (c.status == RescueStatus.treatment) {
      return _InTreatmentCard(rescueCase: c);
    }

    if (assignment == null || !assignment.isActive) {
      return _ResumeCard(
        title: 'Pending — Assign Transporter',
        subtitle: 'Clinic: ${c.vetClinicName ?? _kNA}',
        buttonLabel: 'Assign Transporter',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssignRiderPage(caseId: c.id, data: c.raw))),
      );
    }

    if (assignment.status == TransportAssignmentStatus.pending) {
      return _ResumeCard(
        title: 'Pending Transporter Response',
        subtitle: 'Waiting for ${assignment.riderName} to respond.',
        buttonLabel: 'View Pending',
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTrackCasePage(caseId: c.id, data: c.raw))),
      );
    }

    return _ResumeCard(
      title: 'Transport Ongoing',
      subtitle: 'Heading to ${c.vetClinicName ?? 'the clinic'}.',
      buttonLabel: 'View Transport Tracking',
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminTrackCasePage(caseId: c.id, data: c.raw))),
    );
  }
}

class _NotInTreatmentCard extends StatelessWidget {
  final AnimalRecord animal;
  const _NotInTreatmentCard({required this.animal});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Not in Treatment', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('This animal is not currently under active medical care.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdmitAnimalPage(animal: animal))),
              style: AppButtons.primary,
              child: Text('Admit Animal', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback onPressed;
  const _ResumeCard({required this.title, required this.subtitle, required this.buttonLabel, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.yellowrspwn.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.textPrimary,
                foregroundColor: AppColors.background,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text(buttonLabel, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.background)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InTreatmentCard extends ConsumerWidget {
  final RescueCase rescueCase;
  const _InTreatmentCard({required this.rescueCase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(treatmentLogsProvider(rescueCase.id));
    final logs = (logsAsync.asData?.value ?? const []).reversed.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('In Treatment', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _MiniInfo('Clinic', rescueCase.vetClinicName ?? _kNA)),
              Expanded(child: _MiniInfo('Days in Treatment', '${rescueCase.daysInTreatment}')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _MiniInfo('Condition', rescueCase.currentCondition ?? _kNA)),
              Expanded(
                child: _MiniInfo(
                    'Admitted',
                    rescueCase.dateAdmitted != null
                        ? formatDate(rescueCase.dateAdmitted!)
                        : _kNA),
              ),
            ],
          ),
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 4),
            for (final log in logs) TreatmentLogCard(log: log),
          ],
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => TreatmentDetailPage(caseId: rescueCase.id, data: rescueCase.raw))),
              style: AppButtons.outline,
              child: Text('Open Active Treatment', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniInfo extends StatelessWidget {
  final String label;
  final String value;
  const _MiniInfo(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      );
}

// ---- Consolidated treatment episodes -------------------------------------

class _EpisodeEntry {
  final String sourceCaseId;
  final String title;
  final String? notes;
  final DateTime? createdAt;
  const _EpisodeEntry({required this.sourceCaseId, required this.title, this.notes, this.createdAt});
}

class _EpisodesSection extends ConsumerWidget {
  final AnimalRecord animal;
  const _EpisodesSection({required this.animal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodesAsync = ref.watch(medicalEpisodesProvider(animal.id));
    final episodes = episodesAsync.asData?.value ?? const <MedicalEpisode>[];

    final entries = <_EpisodeEntry>[
      if (animal.hasSourceCase)
        _EpisodeEntry(sourceCaseId: animal.linkedCaseId, title: 'Rescue Treatment', createdAt: animal.createdAt),
      ...episodes.map((e) => _EpisodeEntry(sourceCaseId: e.sourceCaseId, title: e.reason.episodeTitle, notes: e.notes, createdAt: e.createdAt)),
    ];

    if (entries.isEmpty) {
      return Text('No treatment episodes yet.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
    }

    entries.sort((a, b) {
      final aCurrent = a.sourceCaseId == animal.currentCaseId;
      final bCurrent = b.sourceCaseId == animal.currentCaseId;
      if (aCurrent != bCurrent) return aCurrent ? -1 : 1;
      return (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0));
    });

    return Column(children: [for (final e in entries) _EpisodeCard(entry: e)]);
  }
}

class _EpisodeCard extends ConsumerStatefulWidget {
  final _EpisodeEntry entry;
  const _EpisodeCard({required this.entry});

  @override
  ConsumerState<_EpisodeCard> createState() => _EpisodeCardState();
}

class _EpisodeCardState extends ConsumerState<_EpisodeCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(caseDetailProvider(widget.entry.sourceCaseId)).asData?.value;
    final isActive = c != null && !c.status.isTerminal;
    final dateStr = c?.dateAdmitted != null ? formatDate(c!.dateAdmitted!) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.entry.title, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('#${shortCaseId(widget.entry.sourceCaseId)}${dateStr.isNotEmpty ? ' · $dateStr' : ''}',
                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      if (c?.vetClinicName != null)
                        Text(c!.vetClinicName!, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? AppColors.yellowrspwn : AppColors.slaterspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(isActive ? 'Active' : 'Completed',
                      style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                ),
                Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
              ],
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 20),
            if (c != null && c.currentCondition != null) _MiniInfo('Latest Condition', c.currentCondition!),
            if (widget.entry.notes != null && widget.entry.notes!.isNotEmpty) _MiniInfo('Reason Notes', widget.entry.notes!),
            _EpisodeLogs(caseId: widget.entry.sourceCaseId),
            _EpisodeExpenses(caseId: widget.entry.sourceCaseId),
          ],
        ],
      ),
    );
  }
}

class _EpisodeLogs extends ConsumerWidget {
  final String caseId;
  const _EpisodeLogs({required this.caseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(treatmentLogsProvider(caseId));
    final logs = (logsAsync.asData?.value ?? const []).reversed.toList();
    if (logs.isEmpty) {
      return Text('No treatment logs for this episode.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
    }
    return Column(children: [for (final log in logs) TreatmentLogCard(log: log)]);
  }
}

class _EpisodeExpenses extends ConsumerWidget {
  final String caseId;
  const _EpisodeExpenses({required this.caseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(expensesProvider(caseId));
    final expenses = expensesAsync.asData?.value ?? const [];
    if (expenses.isEmpty) return const SizedBox.shrink();
    final total = expenses.fold<double>(0, (sum, e) => sum + e.amount);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text('Expenses: ${formatPeso(total)}', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );
  }
}
