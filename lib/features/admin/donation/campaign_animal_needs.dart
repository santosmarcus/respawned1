import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';
import 'package:respawnd1/features/donation/models.dart';

/// An animal a donation campaign can be made for: one of a rescue case's
/// animals that went through treatment. [recordId] is its animal record,
/// made at intake; without one the animal is still in treatment, and its
/// campaign can only be saved as a draft.
class TreatmentAnimalOption {
  const TreatmentAnimalOption({
    required this.caseId,
    required this.index,
    required this.name,
    this.recordId,
    this.intakeComplete = false,
  });

  final String caseId;
  final int index;
  final String name;
  final String? recordId;
  final bool intakeComplete;

  String get key => '$caseId#$index';
}

/// Animals after intake (records made from a rescue case) and animals still
/// in treatment or at intake (cases in those stages), each once.
List<TreatmentAnimalOption> treatmentAnimalOptions({
  required List<AnimalRecord> records,
  required List<RescueCase> inTreatmentOrIntake,
}) {
  final out = <String, TreatmentAnimalOption>{};
  for (final r in records) {
    final idx = r.sourceAnimalIndex ?? 0;
    if (r.linkedCaseId.isEmpty) continue;
    final o = TreatmentAnimalOption(
      caseId: r.linkedCaseId,
      index: idx,
      name: '${r.name}${r.species.isEmpty ? '' : ' · ${r.species}'}',
      recordId: r.id,
      intakeComplete: true,
    );
    out[o.key] = o;
  }
  for (final c in inTreatmentOrIntake) {
    final animals = c.animals.isEmpty ? [c.raw] : c.animals;
    for (var i = 0; i < animals.length; i++) {
      final key = '${c.id}#$i';
      if (out.containsKey(key)) continue;
      final a = animals[i];
      final name = (a['name'] as String?)?.trim() ?? '';
      final species = (a['species'] as String?)?.trim() ?? '';
      out[key] = TreatmentAnimalOption(
        caseId: c.id,
        index: i,
        name: '${name.isEmpty ? (species.isEmpty ? 'Animal ${i + 1}' : species) : '$name${species.isEmpty ? '' : ' · $species'}'}'
            ' · case #${c.shortCaseId}',
        intakeComplete: a['intakeCompletedAt'] != null,
      );
    }
  }
  return out.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

bool _appliesTo(List<int>? indexes, int index) => indexes == null || indexes.isEmpty || indexes.contains(index);

/// What the campaign will show donors, worked out in the form exactly as
/// functions/campaign_needs_rules.js does on save (the server's is the one
/// stored): this animal's expenses with an equal share of shared ones, its
/// treatment log, rescue reason and condition. The target is the total.
CampaignAnimalNeeds previewAnimalNeeds({
  required RescueCase rescueCase,
  required int index,
  required List<Expense> expenses,
  required List<TreatmentLogEntry> logs,
  required bool intakeComplete,
}) {
  final animals = rescueCase.animals.isEmpty ? [rescueCase.raw] : rescueCase.animals;
  final count = animals.length;
  final animal = index < animals.length ? animals[index] : const <String, dynamic>{};

  final items = <NeedsExpense>[];
  for (final e in expenses) {
    final amountC = (e.amount * 100).round();
    if (amountC <= 0 || !_appliesTo(e.animalIndexes, index)) continue;
    final shared = e.isSharedCaseExpense && count > 1;
    final shareC = shared ? amountC ~/ count + (index < amountC % count ? 1 : 0) : amountC;
    if (shareC <= 0) continue;
    items.add(NeedsExpense(
      title: e.title,
      category: e.category.label,
      amount: shareC / 100,
      shared: shared,
      fullAmount: amountC / 100,
      date: e.incurredAt ?? e.createdAt,
    ));
  }
  items.sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));

  final log = [
    for (final l in logs)
      if (_appliesTo(l.animalIndexes, index))
        NeedsLogEntry(
          date: l.treatmentDate ?? l.timestamp,
          type: l.type.trim().isEmpty ? 'Update' : l.type,
          condition: (l.finalCondition ?? '').trim().isNotEmpty ? l.finalCondition : l.condition,
          procedure: l.procedurePerformed,
          medication: l.medicationName,
          vaccine: l.vaccineName,
          notes: l.notes.trim().isEmpty ? null : l.notes.trim(),
        ),
  ]..sort((a, b) => (a.date ?? DateTime(0)).compareTo(b.date ?? DateTime(0)));
  final latest = log.reversed.where((l) => (l.condition ?? '').trim().isNotEmpty).firstOrNull;
  String? text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  return CampaignAnimalNeeds(
    animalName: text(animal['name']),
    species: text(animal['species']),
    rescueType: text(rescueCase.raw['rescueType']),
    reportedCondition: text(animal['condition']) ?? text(rescueCase.condition),
    currentCondition: latest?.condition,
    treatmentLog: log,
    expenses: items,
    expenseTotal: items.fold<int>(0, (s, e) => s + (e.amount * 100).round()) / 100,
    intakeComplete: intakeComplete,
  );
}
