import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/animal_treatment_state.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/admin/animals/animal_records_flow_page.dart';
import 'package:respawnd1/features/admin/animals/create_animal_record_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// One intaked rescue animal that has arrived at the shelter but has no
/// animal record yet.
typedef IntakeWithoutRecord = ({RescueCase rescueCase, int index, Map<String, dynamic> animal});

/// Intaked animals (received at the shelter) with no record linked to them
/// yet, across the organization's intake cases — org-scoped queries only.
final intakesWithoutRecordProvider = Provider.autoDispose<AsyncValue<List<IntakeWithoutRecord>>>((ref) {
  final byStatus = ref.watch(casesByStatusesProvider(const [RescueStatus.intake]));
  final byStage = ref.watch(casesByActiveStageProvider('intake'));
  final records = ref.watch(allAnimalRecordsProvider);
  for (final v in [byStatus, byStage]) {
    if (v.hasError) return AsyncValue.error(v.error!, v.stackTrace ?? StackTrace.current);
  }
  if (records.hasError) return AsyncValue.error(records.error!, records.stackTrace ?? StackTrace.current);
  if (!byStatus.hasValue || !byStage.hasValue || !records.hasValue) return const AsyncValue.loading();

  final linked = <String>{
    for (final r in records.value!)
      if (r.linkedCaseId.isNotEmpty) '${r.linkedCaseId}#${r.sourceAnimalIndex ?? 0}',
  };
  final cases = <String, RescueCase>{
    for (final c in [...byStatus.value!, ...byStage.value!]) c.id: c,
  };
  final out = <IntakeWithoutRecord>[];
  for (final c in cases.values) {
    final animals = c.animals.isNotEmpty ? c.animals : [c.raw];
    for (var i = 0; i < animals.length; i++) {
      final a = Map<String, dynamic>.from(animals[i] as Map);
      if (c.animals.isNotEmpty && a['postTreatmentAction'] != null && a['postTreatmentAction'] != 'intake') continue;
      if (!animalIsReceived(c, i)) continue;
      if (linked.contains('${c.id}#$i')) continue;
      out.add((rescueCase: c, index: i, animal: a));
    }
  }
  out.sort((x, y) => (y.rescueCase.createdAt ?? DateTime(0)).compareTo(x.rescueCase.createdAt ?? DateTime(0)));
  return AsyncValue.data(out);
});

/// "Add animal" from Animal Records: pick an intaked rescue animal that
/// still needs its record (prefilled and linked to its case), or start a
/// blank record.
Future<void> openAddAnimalRecord(BuildContext context) async {
  final picked = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => const _LinkIntakeSheet(),
  );
  if (picked == null || !context.mounted) return;
  if (picked is IntakeWithoutRecord) {
    final animal = picked.animal;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAnimalRecordPage(
          prefillData: animalRecordPrefillFor(picked.rescueCase, animal),
          linkedCaseId: picked.rescueCase.id,
          sourceAnimalIndex: picked.index,
        ),
      ),
    );
  } else {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateAnimalRecordPage()));
  }
}

class _LinkIntakeSheet extends ConsumerWidget {
  const _LinkIntakeSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(intakesWithoutRecordProvider);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Text('Add animal record', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Pick a rescued animal already at the shelter to fill the record from its case, or start blank.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'blank'),
            icon: const Icon(Icons.add),
            label: Text('Start a blank record', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
            style: AppButtons.outline,
          ),
          const SizedBox(height: 16),
          Text('Intaked, no record yet',
              style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          ...async.when(
            loading: () => [
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
            ],
            error: (e, _) => [
              Text('Could not load intaked animals: $e',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.error)),
            ],
            data: (items) => items.isEmpty
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('Every intaked animal already has a record.',
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    ),
                  ]
                : [
                    for (final it in items)
                      Card(
                        color: Colors.white,
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: AppColors.slaterspwn),
                        ),
                        child: ListTile(
                          leading: _thumb(it.rescueCase),
                          title: Text(_title(it),
                              style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
                          subtitle: Text(
                            'Case #${shortCaseId(it.rescueCase.id)}'
                            '${it.rescueCase.animals.length > 1 ? ' · animal ${it.index + 1} of ${it.rescueCase.animals.length}' : ''}',
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.pop(context, it),
                        ),
                      ),
                  ],
          ),
        ],
      ),
    );
  }

  static String _title(IntakeWithoutRecord it) {
    final a = it.animal;
    final species = (a['species'] ?? a['animalType'] ?? it.rescueCase.animalType)?.toString() ?? 'Animal';
    final extra = [a['sex'], a['size'], a['colorMarkings']]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    return extra.isEmpty ? species : '$species · $extra';
  }

  static Widget _thumb(RescueCase c) {
    final url = c.photoUrls.isNotEmpty ? c.photoUrls.first : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: url == null
            ? Container(color: AppColors.tearspwn, child: const Icon(Icons.pets, color: AppColors.textPrimary))
            : Image.network(url, fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(color: AppColors.tearspwn, child: const Icon(Icons.pets))),
      ),
    );
  }
}
