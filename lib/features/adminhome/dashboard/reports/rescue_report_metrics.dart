/// Rescue KPIs for Reports by area → Rescue. Pure functions over case
/// documents (`{...data, 'id': caseId}`) and transport offers
/// (`cases/{id}/transportAssignments`), tested in
/// test/features/adminhome/reports/rescue_report_metrics_test.dart.
///
/// Dates: cases record `acceptedAt` / `rejectedAt` (from Nov 2026),
/// `referral.referredAt`, `linkReferral.at`, `pickedUpAt` (from Nov 2026),
/// `treatmentAcceptedAt`, `dateAdmitted`, `transitCompletedAt`,
/// `shelterDeliveredAt`. Older cases have no acceptedAt / rejectedAt, so
/// those moments are read from the reporter timeline (`statusHistory`),
/// whose lines and times the app has always written.
library;

import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

typedef CaseDoc = Map<String, dynamic>;
typedef OfferDoc = Map<String, dynamic>;

/// Statuses of reports the organization never handles (Pet Surrender goes
/// straight to Community Adoption) or that were folded into another report.
const _notOrgStatuses = ['community_adoption', 'withdrawn', 'possible_duplicate', 'merged'];

bool isOrgCase(CaseDoc c) => !_notOrgStatuses.contains(c['status']) && c['isDemo'] != true;

/// The first reporter-timeline line starting with [prefix], and its time.
DateTime? _timelineAt(CaseDoc c, String prefix) {
  final h = c['statusHistory'];
  if (h is! List) return null;
  DateTime? best;
  for (final e in h) {
    if (e is! Map) continue;
    final text = '${e['status'] ?? ''}';
    final at = dateOf(e['timestamp']);
    if (at != null && text.startsWith(prefix) && (best == null || at.isBefore(best))) best = at;
  }
  return best;
}

DateTime? acceptedAtOf(CaseDoc c) => dateOf(c['acceptedAt']) ?? _timelineAt(c, 'Rescue case has been accepted');
DateTime? rejectedAtOf(CaseDoc c) => dateOf(c['rejectedAt']) ?? _timelineAt(c, 'Case rejected');
DateTime? referredAtOf(CaseDoc c) =>
    dateOf(mapOf(c['referral'])?['referredAt']) ?? dateOf(mapOf(c['linkReferral'])?['at']) ?? _timelineAt(c, 'Referred to ');

/// When the animals reached a clinic or the shelter: the rescue trip ended.
DateTime? deliveredAtOf(CaseDoc c) => earliestOf([
      dateOf(c['treatmentAcceptedAt']),
      dateOf(c['dateAdmitted']),
      dateOf(c['transitCompletedAt']),
      dateOf(c['shelterDeliveredAt']),
      dateOf(c['intakeReceivedAt']),
    ]);

/// Raw statuses reached only after the animal was picked up.
const _afterPickup = [
  'treatment', 'searching_clinic', 'dropoff', 'in_treatment', 'awaiting_adopter_pickup',
  'in_transit_shelter', 'intake', 'completed', 'closed',
];

/// The animal was physically retrieved (picked up and on its way, or
/// already at a clinic or the shelter).
bool wasRetrieved(CaseDoc c) =>
    c['pickedUpAt'] != null || deliveredAtOf(c) != null || _afterPickup.contains(c['status']);

bool _wentToTreatment(CaseDoc c) =>
    c['treatmentAcceptedAt'] != null ||
    c['dateAdmitted'] != null ||
    const ['dropoff', 'in_treatment', 'awaiting_adopter_pickup'].contains(c['status']) ||
    animalsOf(c).any((a) => a['dischargedAt'] != null || a['postTreatmentAction'] != null);

// ─── Referrals ─────────────────────────────────────────────────────────────

class ReferralStats {
  const ReferralStats({
    required this.reviewed,
    required this.accepted,
    required this.declined,
    required this.referred,
    required this.toOrganization,
    required this.toVolunteer,
    required this.toBarangay,
    required this.capacityReferred,
    required this.capacityDeclined,
  });

  /// Reports whose review ended in the period (accepted, declined or
  /// referred), each counted once.
  final int reviewed;
  final int accepted;
  final int declined;
  final int referred;
  final int toOrganization;
  final int toVolunteer;
  final int toBarangay;

  /// Referred because the shelter was full (reason recorded from Nov 2026).
  final int capacityReferred;

  /// Declined with the reason "No shelter space".
  final int capacityDeclined;

  Ratio get referralRate => Ratio(referred, reviewed);
  int get dueToCapacity => capacityReferred + capacityDeclined;
}

ReferralStats referralStatsIn(Period p, List<CaseDoc> cases) {
  var reviewed = 0, accepted = 0, declined = 0, referred = 0;
  var toOrg = 0, toVol = 0, toLgu = 0, capRef = 0, capDec = 0;
  for (final c in cases.where(isOrgCase)) {
    final acc = p.has(acceptedAtOf(c));
    final rej = p.has(rejectedAtOf(c));
    final ref = p.has(referredAtOf(c));
    if (!acc && !rej && !ref) continue;
    reviewed++;
    if (acc) accepted++;
    if (rej) {
      declined++;
      if (c['rejectionReason'] == RejectionReason.noShelterSpace.name) capDec++;
    }
    if (ref) {
      referred++;
      final referral = mapOf(c['referral']);
      if (referral == null && c['linkReferral'] != null) {
        toLgu++;
      } else if (referral?['type'] == ReferralType.rescueVolunteer.name) {
        toVol++;
      } else {
        toOrg++;
      }
      if (referral?['referralReason'] == OrgReferralReason.shelterAtCapacity.name) capRef++;
    }
  }
  return ReferralStats(
    reviewed: reviewed,
    accepted: accepted,
    declined: declined,
    referred: referred,
    toOrganization: toOrg,
    toVolunteer: toVol,
    toBarangay: toLgu,
    capacityReferred: capRef,
    capacityDeclined: capDec,
  );
}

// ─── Rescue outcomes (cases accepted in the period, counted in animals) ────

enum RescueOutcome {
  inProgress('Still in progress'),
  inTreatment('Under treatment'),
  recovered('Recovered (discharged)'),
  shelter('Integrated into the shelter'),
  adopter('Went to an adopter'),
  reporter('Released to the reporter'),
  transferred('Transferred'),
  died('Died'),
  unsuccessful('Rescue unsuccessful'),
  reunited('Reunited with owner'),
  referredOn('Referred after acceptance'),
  other('Other recorded outcome');

  const RescueOutcome(this.label);
  final String label;
}

RescueOutcome _outcomeOf(CaseDoc c, Map<String, dynamic> a) {
  final status = c['status'] as String? ?? '';
  final closure = c['closureReason'];
  if (a['deceasedAt'] != null || a['outcome'] == 'deceased' || closure == 'died') return RescueOutcome.died;
  if (a['dischargedAt'] != null) {
    return switch (a['postTreatmentAction']) {
      'intake' => a['intakeCompletedAt'] != null ? RescueOutcome.shelter : RescueOutcome.recovered,
      'release' => RescueOutcome.reporter,
      'transfer' => RescueOutcome.transferred,
      _ => c['adopterPickupConfirmedAt'] != null ? RescueOutcome.adopter : RescueOutcome.recovered,
    };
  }
  if (a['intakeCompletedAt'] != null) return RescueOutcome.shelter;
  if (const ['in_treatment', 'awaiting_adopter_pickup', 'dropoff'].contains(status)) return RescueOutcome.inTreatment;
  if (closure == 'reunited') return RescueOutcome.reunited;
  if (status == 'referred') return RescueOutcome.referredOn;
  if (status == 'completed' || status == 'closed') {
    return wasRetrieved(c) ? RescueOutcome.other : RescueOutcome.unsuccessful;
  }
  if (status == 'cancelled') {
    if (closure == 'rescuedOutsideWorkflow') return RescueOutcome.other;
    return wasRetrieved(c) ? RescueOutcome.other : RescueOutcome.unsuccessful;
  }
  return RescueOutcome.inProgress;
}

class RescueOutcomes {
  const RescueOutcomes({
    required this.acceptedCases,
    required this.byOutcome,
    required this.rescuedAnimals,
    required this.concludedAnimals,
    required this.treatedAnimals,
    required this.recoveredAnimals,
  });

  /// Cases accepted in the period.
  final int acceptedCases;

  /// Their animals, by where each one is now.
  final Map<RescueOutcome, int> byOutcome;

  /// Animals physically retrieved.
  final int rescuedAnimals;

  /// Animals whose rescue attempt is decided: retrieved, or closed without
  /// being retrieved. Still-open attempts, reunions with the owner and
  /// cases referred on are not counted as failures.
  final int concludedAnimals;

  /// Retrieved animals that went to a vet.
  final int treatedAnimals;

  /// Animals discharged from treatment alive.
  final int recoveredAnimals;

  Ratio get successRate => Ratio(rescuedAnimals, concludedAnimals);
  Ratio get treatmentRate => Ratio(treatedAnimals, rescuedAnimals);
  int get totalAnimals => byOutcome.values.fold(0, (a, b) => a + b);
}

RescueOutcomes rescueOutcomesIn(Period p, List<CaseDoc> cases) {
  final byOutcome = {for (final o in RescueOutcome.values) o: 0};
  var acceptedCases = 0, rescued = 0, concluded = 0, treated = 0, recovered = 0;
  for (final c in cases.where(isOrgCase)) {
    if (!p.has(acceptedAtOf(c))) continue;
    acceptedCases++;
    final retrieved = wasRetrieved(c);
    final toVet = retrieved && _wentToTreatment(c);
    for (final a in animalsOf(c)) {
      final o = _outcomeOf(c, a);
      byOutcome[o] = byOutcome[o]! + 1;
      if (a['dischargedAt'] != null && o != RescueOutcome.died) recovered++;
      if (retrieved) {
        rescued++;
        concluded++;
        if (toVet) treated++;
      } else if (o == RescueOutcome.unsuccessful || o == RescueOutcome.died) {
        concluded++;
      }
    }
  }
  return RescueOutcomes(
    acceptedCases: acceptedCases,
    byOutcome: byOutcome,
    rescuedAnimals: rescued,
    concludedAnimals: concluded,
    treatedAnimals: treated,
    recoveredAnimals: recovered,
  );
}

// ─── Times ─────────────────────────────────────────────────────────────────

/// Hours from report to acceptance, for reports accepted in the period.
Spread responseHoursIn(Period p, List<CaseDoc> cases) => spreadOf([
      for (final c in cases.where(isOrgCase))
        if ((dateOf(c['createdAt']), acceptedAtOf(c)) case (final from?, final to?) when p.has(to) && !to.isBefore(from))
          to.difference(from).inMinutes / 60,
    ]);

/// Hours from report to the animal reaching a clinic or the shelter, for
/// rescues completed in the period.
Spread completionHoursIn(Period p, List<CaseDoc> cases) => spreadOf([
      for (final c in cases.where(isOrgCase))
        if ((dateOf(c['createdAt']), deliveredAtOf(c)) case (final from?, final to?) when p.has(to) && !to.isBefore(from))
          to.difference(from).inMinutes / 60,
    ]);

// ─── Transport ─────────────────────────────────────────────────────────────

class TransportStats {
  const TransportStats({
    required this.completion,
    required this.activeTransporters,
    required this.tripsCompleted,
    required this.offersSent,
    required this.offersAccepted,
    required this.offersDeclined,
    required this.offersExpired,
    required this.responseMinutes,
    required this.casesWithNoTaker,
  });

  /// Accepted trips (accepted in the period) that were completed, out of
  /// those that ended (completed, or cancelled after acceptance). Trips
  /// still under way are left out.
  final Ratio completion;

  /// Transporters who completed at least one trip in the period.
  final int activeTransporters;
  final int tripsCompleted;
  final int offersSent;
  final int offersAccepted;
  final int offersDeclined;
  final int offersExpired;

  /// Minutes from offer to the transporter's answer (accept or decline).
  final Spread responseMinutes;

  /// Cases whose every offer in the period was declined or expired.
  final int casesWithNoTaker;

  Ratio utilization(int verifiedTransporters) => Ratio(activeTransporters, verifiedTransporters);
}

TransportStats transportStatsIn(Period p, List<OfferDoc> offers) {
  final real = offers.where((o) => o['isDemo'] != true).toList();
  var done = 0, ended = 0, trips = 0, sent = 0, acc = 0, dec = 0, exp = 0;
  final active = <String>{};
  final minutes = <num>[];
  final byCase = <String, List<String>>{};
  for (final o in real) {
    final status = o['status'] as String? ?? '';
    final acceptedAt = dateOf(o['acceptedAt']);
    if (p.has(acceptedAt)) {
      if (status == 'completed') {
        done++;
        ended++;
      } else if (status == 'cancelled') {
        ended++;
      }
    }
    if (status == 'completed' && p.has(dateOf(o['completedAt']))) {
      trips++;
      active.add(o['riderId'] as String? ?? '');
    }
    final offeredAt = dateOf(o['offeredAt']);
    if (!p.has(offeredAt) || status == 'cancelled') continue;
    sent++;
    (byCase[o['caseId'] as String? ?? ''] ??= []).add(status);
    if (acceptedAt != null || status == 'accepted' || status == 'completed') {
      acc++;
    } else if (status == 'rejected') {
      dec++;
    } else if (status == 'expired') {
      exp++;
    }
    final answered = dateOf(o['respondedAt']) ?? acceptedAt ?? dateOf(o['rejectedAt']);
    if (answered != null && status != 'expired' && !answered.isBefore(offeredAt!)) {
      minutes.add(answered.difference(offeredAt).inSeconds / 60);
    }
  }
  active.remove('');
  return TransportStats(
    completion: Ratio(done, ended),
    activeTransporters: active.length,
    tripsCompleted: trips,
    offersSent: sent,
    offersAccepted: acc,
    offersDeclined: dec,
    offersExpired: exp,
    responseMinutes: spreadOf(minutes),
    casesWithNoTaker: byCase.entries
        .where((e) => e.key.isNotEmpty && e.value.every((s) => s == 'rejected' || s == 'expired'))
        .length,
  );
}
