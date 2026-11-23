import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';
import 'package:respawnd1/features/admin/donation/campaign_animal_needs.dart';
import 'package:respawnd1/features/donation/campaign_needs_view.dart';
import 'package:respawnd1/features/donation/models.dart';

DateTime _nov(int d) => DateTime(2026, 11, d);

Expense _e(String title, double amount, {List<int>? animals, int day = 1}) => Expense(
    id: title, caseId: 'c1', title: title, category: ExpenseCategory.procedure, amount: amount,
    animalIndexes: animals, incurredAt: _nov(day));

TreatmentLogEntry _log(String type, {List<int>? animals, int day = 1, String? condition, String? procedure}) =>
    TreatmentLogEntry(
        id: type, caseId: 'c1', type: type, notes: '', condition: condition, procedurePerformed: procedure,
        treatmentDate: _nov(day), animalIndexes: animals);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Same fixture as functions/campaign_needs_rules_test.js.
  final rescueCase = RescueCase.fromMap('c1', {
    'rescueType': 'Injury',
    'condition': 'Hit by a car',
    'animals': [
      {'name': 'Bantay', 'species': 'Dog', 'condition': 'Hind leg fractured'},
      {'name': 'Puti', 'species': 'Dog'},
      {'species': 'Dog'},
    ],
  });
  final expenses = [
    _e('Leg surgery', 8000, animals: [0], day: 3),
    _e('Clinic confinement', 1000, day: 2),
    _e('Puti vaccine', 500, animals: [1], day: 4),
  ];
  final logs = [
    _log('Procedure', animals: [0], day: 3, procedure: 'Femur pinning'),
    _log('Assessment', day: 2, condition: 'Stable'),
    _log('Medication', animals: [1], day: 4),
  ];

  test('the preview matches the server: own expenses, equal share of shared ones, total is the target', () {
    final n = previewAnimalNeeds(rescueCase: rescueCase, index: 0, expenses: expenses, logs: logs, intakeComplete: false);
    expect(n.expenses.map((e) => (e.title, e.amount, e.shared)), [
      ('Clinic confinement', 333.34, true),
      ('Leg surgery', 8000.0, false),
    ]);
    expect(n.expenseTotal, 8333.34);
    expect(n.rescueType, 'Injury');
    expect(n.reportedCondition, 'Hind leg fractured');
    expect(n.currentCondition, 'Stable');
    expect(n.treatmentLog.map((l) => l.type), ['Assessment', 'Procedure']);
    final shares = [0, 1, 2].map((i) => previewAnimalNeeds(
        rescueCase: rescueCase, index: i, expenses: expenses, logs: logs, intakeComplete: false)
        .expenses.firstWhere((e) => e.title == 'Clinic confinement').amount);
    expect((shares.fold<double>(0, (a, b) => a + b) * 100).round(), 100000);
  });

  test('options: animals after intake from records, animals in treatment from cases, each once', () {
    final record = AnimalRecord.fromMap('r1', {'name': 'Bantay', 'species': 'Dog', 'linkedCaseId': 'c1', 'sourceAnimalIndex': 0});
    final options = treatmentAnimalOptions(records: [record], inTreatmentOrIntake: [rescueCase]);
    expect(options.length, 3);
    final bantay = options.firstWhere((o) => o.key == 'c1#0');
    expect((bantay.recordId, bantay.intakeComplete), ('r1', true));
    expect(options.where((o) => !o.intakeComplete).length, 2);
  });

  test('the stored summary reads back', () {
    final n = CampaignAnimalNeeds.fromMap({
      'rescueType': 'Injury',
      'treatmentLog': [{'type': 'Procedure', 'procedure': 'Femur pinning', 'dateMs': Timestamp.fromDate(_nov(3)).millisecondsSinceEpoch}],
      'expenses': [{'title': 'Surgery', 'category': 'Procedure', 'amount': 8000, 'shared': false}],
      'expenseTotal': 8000,
      'intakeComplete': true,
    });
    expect(n.treatmentLog.single.details, 'Procedure: Femur pinning');
    expect(n.expenses.single.amount, 8000);
    expect(n.intakeComplete, isTrue);
  });

  testWidgets('the donor view renders at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final n = previewAnimalNeeds(rescueCase: rescueCase, index: 0, expenses: expenses, logs: logs, intakeComplete: true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(padding: const EdgeInsets.all(20), child: CampaignNeedsView(needs: n))),
    ));
    expect(find.text('Rescue Reason'), findsOneWidget);
    expect(find.text('Injury'), findsOneWidget);
    expect(find.text('Treatment Log'), findsOneWidget);
    expect(find.text('₱8,333.34'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
