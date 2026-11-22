/// The module metrics as rows for the Analytics CSV export
/// (analytics_export.dart, `module_metrics.csv`): one row per figure, with
/// its fraction or count so a rate is never shown without what it was
/// measured on. No donor or reporter details.
library;

import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/adoption_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/finance_metrics.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/rescue_metrics.dart';

const kMetricRowsHeader = ['module', 'metric', 'value', 'measured_on'];

List<List<Object?>> moduleMetricRows(
  Period p, {
  required List<Map<String, dynamic>> cases,
  required List<Map<String, dynamic>> offers,
  required List<Map<String, dynamic>> adoptions,
  required List<Map<String, dynamic>> followUps,
  required DateTime now,
  List<DonationRow>? donations,
  List<Expense>? expenses,
}) {
  String rate(Fraction f) => f.whole == 0 ? 'none recorded' : (f.percent ?? 'too few for a rate');
  String med(MedianOf m, String unit) => m.isEmpty ? 'not recorded' : '${m.value!.toStringAsFixed(1)} $unit';

  final referrals = referralsIn(p, cases);
  final retrieved = retrievalsIn(p, cases, offers);
  final retrievedTotal = retrieved.values.fold(0, (a, b) => a + b);
  final offerStats = offerStatsIn(p, offers, cases);
  final exits = treatmentExitsIn(p, cases);
  final times = responseTimesIn(p, cases);
  final intake = intakeVolumeIn(p, cases);
  final checkIns = checkInsIn(p, followUps, now);
  final cohort = adoptionCohortIn(p, adoptions, now);
  final funnel = applicationFunnelIn(p, adoptions);

  final rows = <List<Object?>>[
    ['Rescue', 'Reports received', intake.received, null],
    ['Rescue', 'Reports finished', rate(intake.resolved), intake.resolved.text],
    ['Rescue', 'Referred or declined', rate(referrals.rate), referrals.rate.text],
    for (final k in ReferralKind.values) ['Rescue', '  ${k.label}', referrals.counts[k], null],
    ['Rescue', 'Because the shelter was full', rate(referrals.capacityShare), referrals.capacityShare.text],
    for (final k in RetrievedBy.values) ['Rescue', 'Retrieved by: ${k.label}', retrieved[k], null],
    ['Rescue', 'Retrieved by pet transporters', rate(Fraction(retrieved[RetrievedBy.transporter]!, retrievedTotal)),
     Fraction(retrieved[RetrievedBy.transporter]!, retrievedTotal).text],
    ['Rescue', 'Transport offers accepted', rate(offerStats.acceptance), offerStats.acceptance.text],
    ['Rescue', 'Median time to accept an offer', med(offerStats.minutesToAccept, 'min'), offerStats.minutesToAccept.count],
    ['Rescue', 'Cases no transporter took', offerStats.casesWithNoTaker, null],
    ['Rescue', 'Declined: no available riders', offerStats.declinedNoRiders, null],
    for (final k in TreatmentExit.values) ['Rescue', 'Left treatment: ${k.label}', exits.counts[k], null],
    ['Rescue', 'Recovered out of all leaving treatment', rate(exits.recoveredShare), exits.recoveredShare.text],
    ['Rescue', 'Median days in treatment', med(exits.days, 'days'), exits.days.count],
    ['Rescue', 'Median report to accepted', med(times.reportToAccepted, 'min'), times.reportToAccepted.count],
    ['Rescue', 'Median accepted to picked up', med(times.acceptedToPickup, 'min'), times.acceptedToPickup.count],
    ['Rescue', 'Median picked up to clinic', med(times.pickupToClinic, 'min'), times.pickupToClinic.count],
    ['Adoption', 'Applications submitted', funnel.applied, null],
    ['Adoption', 'Of those approved', funnel.approved, funnel.approvedShare.text],
    ['Adoption', 'Of those adopted', funnel.adopted, funnel.adoptedShare.text],
    ['Adoption', 'Check-ins answered', rate(checkIns.answered), checkIns.answered.text],
    ['Adoption', 'Check-ins answered on time', rate(checkIns.onTime), checkIns.onTime.text],
    ['Adoption', 'Check-ins overdue now', checkIns.overdueNow, null],
    ['Adoption', 'Stayed home past $kAdoptionSuccessWindowDays days', rate(cohort.success), cohort.success.text],
    ['Adoption', 'Returned within $kAdoptionSuccessWindowDays days', rate(cohort.returnRate), cohort.returnRate.text],
    for (final r in returnReasonsIn(p, adoptions)) ['Adoption', 'Return reason: ${r.reason} (${r.support})', r.count, null],
  ];

  if (donations != null && expenses != null) {
    final collected = fundsCollectedIn(p, donations);
    final spending = expensesIn(p, expenses);
    rows.addAll([
      ['Funds', 'Money received (PHP)', collected.total.toStringAsFixed(2), collected.count],
      for (final e in collected.byChannel.entries) ['Funds', '  ${e.key} (PHP)', e.value.amount.toStringAsFixed(2), e.value.count],
      ['Funds', 'Recorded automatically through PayMongo', rate(collected.automatic), collected.automatic.text],
      ['Funds', 'Expenses paid (PHP)', spending.paid.toStringAsFixed(2), null],
      ['Funds', 'Running bills, not paid yet (PHP)', spending.running.toStringAsFixed(2), null],
      for (final e in spending.byCategory.entries)
        ['Funds', '  ${e.key}: paid / running (PHP)', '${e.value.paid.toStringAsFixed(2)} / ${e.value.running.toStringAsFixed(2)}', null],
      for (final e in inKindReceivedIn(p, donations).entries)
        ['Funds', 'In-kind received: ${e.key} (quantity)', e.value.quantity, e.value.donations],
    ]);
  }
  return rows;
}
