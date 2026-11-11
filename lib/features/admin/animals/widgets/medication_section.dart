import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/medication.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/animal_medication_repository.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

// ---- Providers ---------------------------------------------------------------

final animalMedicationRepositoryProvider = Provider<AnimalMedicationRepository>(
  (ref) => AnimalMedicationRepository(),
);

final medicationPlansProvider = StreamProvider.autoDispose.family<List<MedicationPlan>, String>((ref, animalId) {
  return ref.watch(animalMedicationRepositoryProvider).watchPlans(animalId);
});

final medicationDosesProvider = StreamProvider.autoDispose.family<Map<String, MedicationDose>, String>((ref, animalId) {
  return ref.watch(animalMedicationRepositoryProvider).watchDoses(animalId);
});

/// Carers record doses only. Staff (and platform admins with an org) plan
/// medication and see missed doses.
final _medicationRoleProvider = Provider.autoDispose<({bool isCarer, bool canPlan})>((ref) {
  final membership = ref.watch(currentOrgMembershipProvider).asData?.value;
  final caps = ref.watch(currentOrganizationCapabilitiesProvider).asData?.value ?? OrganizationCapabilities.none;
  final isCarer = membership?.role == OrgRole.carer;
  return (isCarer: isCarer, canPlan: !isCarer && caps.canManageRecords);
});

// ---- Section -----------------------------------------------------------------

/// Medication orders for an animal, with today's dose slots and, for admins,
/// the count of missed doses over the past week.
class MedicationSection extends ConsumerWidget {
  const MedicationSection({super.key, required this.animal});

  final AnimalRecord animal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(_medicationRoleProvider);
    final plans = ref.watch(medicationPlansProvider(animal.id));
    final doses = ref.watch(medicationDosesProvider(animal.id));
    final now = DateTime.now();

    final activePlans = (plans.asData?.value ?? const <MedicationPlan>[])
        .where((p) => p.active)
        .toList();
    final doseMap = doses.asData?.value ?? const <String, MedicationDose>{};
    final missed = role.canPlan
        ? countMissedDoses(
            plans: activePlans,
            doses: doseMap,
            from: now.subtract(const Duration(days: 7)),
            to: now.subtract(const Duration(days: 1)),
            now: now,
          )
        : 0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Medication',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
              if (role.canPlan)
                TextButton.icon(
                  onPressed: () => _showAddPlanSheet(context, ref, animal),
                  icon: const Icon(Icons.add, size: 16, color: AppColors.textPrimary),
                  label: Text('Add',
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
            ],
          ),
          if (role.canPlan && missed > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('$missed missed dose${missed == 1 ? '' : 's'} in the past 7 days',
                  style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
            ),
          if (plans.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else if (activePlans.isEmpty)
            Text('No active medication orders.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
          else
            for (final plan in activePlans)
              _PlanTasks(
                animal: animal,
                plan: plan,
                doses: doseMap,
                now: now,
                canPlan: role.canPlan,
              ),
        ],
      ),
    );
  }
}

class _PlanTasks extends ConsumerWidget {
  const _PlanTasks({
    required this.animal,
    required this.plan,
    required this.doses,
    required this.now,
    required this.canPlan,
  });

  final AnimalRecord animal;
  final MedicationPlan plan;
  final Map<String, MedicationDose> doses;
  final DateTime now;
  final bool canPlan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = dayOnly(now);
    final scheduledToday = plan.isScheduledOn(today);

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('${plan.drug} · ${plan.dose}',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              if (canPlan)
                IconButton(
                  tooltip: 'End this order',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.stop_circle_outlined, size: 20, color: AppColors.textSecondary),
                  onPressed: () => _confirmEnd(context, ref),
                ),
            ],
          ),
          Text('${plan.timesPerDay}× a day · from ${_fmt(plan.startDate)}'
              '${plan.endDate == null ? '' : ' to ${_fmt(plan.endDate!)}'}',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          if (!scheduledToday)
            Text('Not scheduled today.',
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary))
          else
            for (var slot = 1; slot <= plan.timesPerDay; slot++)
              _SlotRow(
                animal: animal,
                plan: plan,
                slot: slot,
                status: doseStatusFor(
                  planId: plan.id,
                  day: today,
                  slot: slot,
                  doses: doses,
                  now: now,
                ),
                dose: doses[doseIdFor(plan.id, today, slot)],
              ),
        ],
      ),
    );
  }

  Future<void> _confirmEnd(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End this order?'),
        content: Text('${plan.drug} stops today. Dose history is kept.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End')),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(animalMedicationRepositoryProvider).endPlan(animalId: animal.id, planId: plan.id);
  }
}

class _SlotRow extends ConsumerStatefulWidget {
  const _SlotRow({
    required this.animal,
    required this.plan,
    required this.slot,
    required this.status,
    required this.dose,
  });

  final AnimalRecord animal;
  final MedicationPlan plan;
  final int slot;
  final DoseStatus status;
  final MedicationDose? dose;

  @override
  ConsumerState<_SlotRow> createState() => _SlotRowState();
}

class _SlotRowState extends ConsumerState<_SlotRow> {
  bool _saving = false;

  Future<void> _markGiven() async {
    if (_saving) return;
    // Doses can't be deleted, so confirm before recording one.
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Record dose ${widget.slot} of ${widget.plan.drug}?'),
        content: const Text('Add a photo as proof, or record it without one.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'plain'), child: const Text('Without photo')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'photo'), child: const Text('Add photo')),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _saving = true);
    try {
      final today = dayOnly(DateTime.now());
      final doseId = doseIdFor(widget.plan.id, today, widget.slot);

      final XFile? picked = choice == 'photo'
          ? await pickImageWithSource(context, ImagePicker(), imageQuality: 85)
          : null;
      // Asked for a photo, then backed out of the picker: record nothing.
      if (choice == 'photo' && picked == null) return;
      final mediaUrls = <String>[];
      if (picked != null) {
        final storageRef = FirebaseStorage.instance
            .ref('animalRecords/${widget.animal.id}/doseMedia/$doseId.${_ext(picked.path)}');
        await storageRef.putFile(File(picked.path));
        mediaUrls.add(await storageRef.getDownloadURL());
      }

      final user = FirebaseAuth.instance.currentUser;
      await ref.read(animalMedicationRepositoryProvider).logDose(
            animalId: widget.animal.id,
            planId: widget.plan.id,
            day: today,
            slot: widget.slot,
            givenBy: user?.uid ?? '',
            givenByName: user?.displayName ?? user?.email,
            mediaUrls: mediaUrls,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not record dose: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _ext(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? 'jpg' : path.substring(dot + 1).toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final color = switch (status) {
      DoseStatus.given => AppColors.success,
      DoseStatus.missed => AppColors.error,
      DoseStatus.due => AppColors.warning,
      DoseStatus.upcoming => AppColors.textSecondary,
    };
    final dose = widget.dose;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text('Dose ${widget.slot}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              status == DoseStatus.given && dose != null
                  ? 'Given by ${dose.givenByName ?? 'carer'}${dose.mediaUrls.isEmpty ? '' : ' · with photo'}'
                  : status.label,
              style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: color),
            ),
          ),
          if (status == DoseStatus.due || status == DoseStatus.missed)
            TextButton(
              onPressed: _saving ? null : _markGiven,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: _saving
                  ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(status == DoseStatus.missed ? 'Log late' : 'Mark given',
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
        ],
      ),
    );
  }
}

// ---- Add order sheet ---------------------------------------------------------

Future<void> _showAddPlanSheet(BuildContext context, WidgetRef ref, AnimalRecord animal) async {
  final drugCtrl = TextEditingController();
  final doseCtrl = TextEditingController();
  var timesPerDay = 1;
  var start = dayOnly(DateTime.now());
  DateTime? end;
  var saving = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => StatefulBuilder(
      builder: (ctx, setSheet) => Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New medication order',
                style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            TextField(
              controller: drugCtrl,
              decoration: const InputDecoration(labelText: 'Drug', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: doseCtrl,
              decoration: const InputDecoration(labelText: 'Dose (e.g. 250 mg)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Times a day', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                const Spacer(),
                for (final n in [1, 2, 3, 4])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text('$n'),
                      selected: timesPerDay == n,
                      selectedColor: AppColors.yellowrspwn,
                      onSelected: (_) => setSheet(() => timesPerDay = n),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: start,
                        firstDate: DateTime.now().subtract(const Duration(days: 30)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheet(() => start = dayOnly(picked));
                    },
                    child: Text('From ${_fmt(start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: end ?? start,
                        firstDate: start,
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setSheet(() => end = dayOnly(picked));
                    },
                    child: Text(end == null ? 'Until (open)' : 'Until ${_fmt(end!)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primary,
                onPressed: saving
                    ? null
                    : () async {
                        final drug = drugCtrl.text.trim();
                        final dose = doseCtrl.text.trim();
                        if (drug.isEmpty || dose.isEmpty) return;
                        setSheet(() => saving = true);
                        await ref.read(animalMedicationRepositoryProvider).addPlan(
                              animalId: animal.id,
                              drug: drug,
                              dose: dose,
                              timesPerDay: timesPerDay,
                              startDate: start,
                              endDate: end,
                              createdBy: FirebaseAuth.instance.currentUser?.uid,
                            );
                        if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                      },
                child: Text('Save order',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  drugCtrl.dispose();
  doseCtrl.dispose();
}

String _fmt(DateTime d) => formatDate(d);
