import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';

void main() {
  final now = DateTime(2026, 11, 18, 12);

  test('Closed tab covers cancelled, completed (incl. closed) and referred', () {
    expect(RescuePipelineTab.closed.statuses,
        containsAll([RescueStatus.cancelled, RescueStatus.completed, RescueStatus.referred]));
    final values = RescuePipelineTab.closed.statuses.expand((s) => s.queryValues);
    expect(values, containsAll(['cancelled', 'completed', 'closed', 'referred']));
    expect(kSecondaryStatuses, isNot(contains(RescueStatus.referred)));
  });

  group('closedCaseOutcomeNote', () {
    test('organization referral: target and how long it has waited', () {
      final c = RescueCase.fromMap('c1', {
        'status': 'referred',
        'referredToOrgId': 'orgB',
        'referral': {
          'targetOrgName': 'Paws B',
          'fromOrgName': 'Org A',
          'referredAt': Timestamp.fromDate(now.subtract(const Duration(hours: 5))),
        },
      });
      expect(closedCaseOutcomeNote(c, myOrgId: 'orgA', now: now), 'Referred to Paws B · waiting 5h');
      expect(closedCaseOutcomeNote(c, myOrgId: 'orgB', now: now), 'Referred to you by Org A · needs your answer');
    });

    test('LGU referral reads the barangay from the status line', () {
      final c = RescueCase.fromMap('c2', {
        'status': 'referred',
        'statusHistory': [
          {'status': 'Referred to the San Isidro LGU/barangay: Stray dog.', 'timestamp': Timestamp.fromDate(now.subtract(const Duration(days: 3)))},
        ],
      });
      expect(closedCaseOutcomeNote(c, now: now), 'Referred to San Isidro LGU · waiting 3d');
    });

    test('completed vs closed', () {
      expect(closedCaseOutcomeNote(RescueCase.fromMap('c3', {'status': 'completed'})), 'Intaked');
      expect(closedCaseOutcomeNote(RescueCase.fromMap('c4', {'status': 'closed'})), 'Closed · animal deceased');
    });
  });

  testWidgets('CaseActionBar: overflow fills the secondary slot when alone', (tester) async {
    var exported = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        bottomNavigationBar: CaseActionBar.maybe(overflow: [CaseAction('Export transfer details', () => exported = true)]),
      ),
    ));
    await tester.tap(find.text('Export transfer details'));
    expect(exported, isTrue);
    expect(CaseActionBar.maybe(), isNull);
  });
}
