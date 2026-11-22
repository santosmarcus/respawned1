// Renders every Reports by area tab with fixture data at phone width, so a
// layout overflow or a crash in a card shows up here. The figures
// themselves are checked in the *_report_metrics_test.dart files.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/stock/stock_service.dart';
import 'package:respawnd1/features/adminhome/dashboard/area_reports.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

Timestamp _ago(int days) => Timestamp.fromDate(DateTime.now().subtract(Duration(days: days)));

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('every tab renders at phone width without layout errors', (tester) async {
    tester.view.physicalSize = const Size(360, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cases = [
      RescueCase.fromMap('a', {
        'status': 'in_treatment', 'urgency': 'Critical', 'rescueType': 'Injury', 'address': 'Brgy. San Roque, Marikina',
        'createdAt': _ago(5), 'acceptedAt': _ago(5), 'pickedUpAt': _ago(4), 'treatmentAcceptedAt': _ago(4),
        'animals': [{'species': 'Dog'}, {'species': 'Dog', 'dischargedAt': _ago(1), 'postTreatmentAction': 'intake'}],
      }),
      RescueCase.fromMap('b', {
        'status': 'referred', 'createdAt': _ago(3), 'urgency': 'Low',
        'referral': {'referredAt': _ago(2), 'type': 'anotherOrganization', 'referralReason': 'shelterAtCapacity'},
      }),
    ];
    final animals = [
      AnimalRecord.fromMap('x', {'name': 'Bantay', 'species': 'Dog', 'adoptionStatus': 'adoptable', 'createdAt': _ago(120),
        'readyForAdoptionAt': _ago(90)}),
      AnimalRecord.fromMap('y', {'name': 'Mingming', 'species': 'Cat', 'adoptionStatus': 'adopted', 'createdAt': _ago(40),
        'adoptedAt': _ago(2)}),
    ];

    await tester.pumpWidget(ProviderScope(
      overrides: [
        reportCasesProvider.overrideWith((ref) => Stream.value(cases)),
        reportAssignmentsProvider.overrideWith((ref) => Stream.value(const [])),
        reportOfferDocsProvider.overrideWith((ref) => Stream.value([
              {'caseId': 'a', 'riderId': 'r1', 'status': 'completed', 'offeredAt': _ago(5), 'acceptedAt': _ago(5),
                'completedAt': _ago(4), 'respondedAt': _ago(5)},
            ])),
        reportEngagementProvider.overrideWith((ref) => Stream.value([
              {'animalId': 'x', 'day': DateTime.now().subtract(const Duration(days: 3)).toIso8601String().substring(0, 10), 'views': 25, 'saves': 6},
            ])),
        reportFollowUpsProvider.overrideWith((ref) => Stream.value(const [])),
        reportStockMovementsProvider.overrideWith((ref) => Stream.value(const [])),
        volunteerReportProvider.overrideWith((ref) async => null),
        allAnimalRecordsProvider.overrideWith((ref) => Stream.value(animals)),
        allAdoptionsProvider.overrideWith((ref) => Stream.value(const [])),
        shelterOccupancyProvider.overrideWithValue(const AsyncValue.data(
            ShelterOccupancy(inShelter: 150, atVet: 6, isolation: 4, arriving: 2, capacity: 200, isolationCapacity: 10))),
        shelterSettingsProvider.overrideWith((ref) => Stream.value(const ShelterSettings(capacity: 200, isolationCapacity: 10, treatmentCapacity: 12))),
        transportSupplyProvider.overrideWithValue(
            const AsyncValue.data(TransportSupply(registered: 9, verified: 7, free: 3, onAssignment: 1))),
        dashboardRescueSnapshotProvider.overrideWithValue(const AsyncValue.loading()),
        canViewFinancesProvider.overrideWith((ref) => Stream.value(true)),
        allDonationsProvider.overrideWith((ref) => Stream.value(const [])),
        allCaseExpensesProvider.overrideWith((ref) => Stream.value(const [])),
        orgCampaignsProvider.overrideWith((ref) => Stream.value(const [])),
        orgAllocationsProvider.overrideWith((ref) => Stream.value(const [])),
        myGeneralExpensesProvider.overrideWith((ref) => Stream.value(const [])),
        stockItemsProvider.overrideWith((ref) => Stream.value(const <StockItem>[])),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(padding: EdgeInsets.all(16), child: AreaReportsCard())),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.text('Referral rate'), findsOneWidget);
    expect(find.text('Treatment capacity utilization'), findsOneWidget);
    expect(find.text('6 of 12 treatment spots, now'), findsOneWidget);
    expect(tester.takeException(), isNull);

    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Each tab with a heading that only appears once its data rendered.
    for (final (tab, shown) in [
      ('Adoptions', 'Adoption promotion funnel'),
      ('Donations', 'Fundraising target completion'),
      ('Shelter', 'Current occupancy'),
      ('Volunteers & transporters', 'Offer response rate'),
    ]) {
      await tester.tap(find.text(tab).first);
      await settle();
      expect(find.text(shown), findsOneWidget, reason: tab);
      expect(tester.takeException(), isNull, reason: tab);
      if (tab == 'Adoptions') {
        // Bantay: 25 views, 6 saves, no application, listed 90 days.
        expect(find.text('Viewed a lot, no applications'), findsOneWidget);
        expect(find.text('Not available'), findsOneWidget);
      }
      if (tab == 'Shelter') {
        // Housed animals (150 + 4 in isolation), not the 6 at the vet.
        expect(find.text('154'), findsOneWidget);
      }
    }
  });
}
