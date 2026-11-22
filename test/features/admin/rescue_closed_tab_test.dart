import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:respawnd1/features/admin/widgets/view_only.dart';
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

  testWidgets('other case actions are in the app bar menu', (tester) async {
    var exported = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [canEditProvider.overrideWith((ref, perm) => true)],
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [
            CaseOverflowMenu(actions: [CaseAction('Export transfer details', () => exported = true)]),
          ]),
          bottomNavigationBar: CaseActionBar.maybe(),
        ),
      ),
    ));
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export transfer details'));
    await tester.pumpAndSettle();
    expect(exported, isTrue);
    expect(CaseActionBar.maybe(), isNull);
  });

  testWidgets('view-only Staff get no case actions', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [canEditProvider.overrideWith((ref, perm) => false)],
      child: MaterialApp(
        home: Scaffold(
          appBar: AppBar(actions: [
            CaseOverflowMenu(actions: [CaseAction('Close Case', () {})]),
          ]),
          bottomNavigationBar: CaseActionBar(primary: CaseAction('Proceed', () {})),
        ),
      ),
    ));
    expect(find.byTooltip('More actions'), findsNothing);
    expect(find.text('Proceed'), findsNothing);
  });
}
