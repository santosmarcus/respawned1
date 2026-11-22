/// Rescue analytics (RESPAWND_ANALYTICS_PLAN R1–R10). Pure functions over
/// case documents (`{...data, 'id': caseId}`) and transport offers
/// (`cases/{id}/transportAssignments`), so they are unit-tested without
/// Firestore (test/features/adminhome/rescue_metrics_test.dart).
library;

import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';

typedef CaseDoc = Map<String, dynamic>;
typedef OfferDoc = Map<String, dynamic>;

RescueStatus _statusOf(CaseDoc c) => RescueStatus.fromFirestoreValue(c['status'] as String?);

/// Pet Surrender and withdrawn surrenders never reach the organization.
bool _isOrgCase(CaseDoc c) {
  final s = _statusOf(c);
  return s != RescueStatus.communityAdoption && s != RescueStatus.withdrawn && c['isDemo'] != true;
}

Map<String, dynamic>? _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

// ─── R1 / R2: where cases went instead of our care ─────────────────────────

enum ReferralKind {
  organization('Another organization took it'),
  volunteer('A rescue volunteer took it'),
  barangay('Non-rescue: barangay / LGU'),
  declinedAtCapacity('Declined: shelter full'),
  communityAdoption('Moved to Community Adoption');

  const ReferralKind(this.label);
  final String label;
}

class ReferralBreakdown {
  const ReferralBreakdown({
    required this.counts,
    required this.decided,
    required this.capacity,
    required this.trackingSince,
  });

  final Map<ReferralKind, int> counts;

  /// Cases whose review ended in the period: accepted, declined or
  /// referred (each case once).
  final int decided;

  /// Referred or declined because the shelter was full.
  final int capacity;

  /// When review decisions started being dated (`acceptedAt` /
  /// `rejectedAt`); null when none is.
  final DateTime? trackingSince;

  int get referred => counts.values.fold(0, (a, b) => a + b);
  Fraction get rate => Fraction(referred, decided);
  Fraction get capacityShare => Fraction(capacity, referred);
}

ReferralBreakdown referralsIn(Period p, List<CaseDoc> cases) {
  final counts = {for (final k in ReferralKind.values) k: 0};
  var decided = 0;
  var capacity = 0;
  for (final c in cases.where(_isOrgCase)) {
    final referral = _map(c['referral']);
    final link = _map(c['linkReferral']);
    final referredAt = dateOf(referral?['referredAt']);
    final linkAt = dateOf(link?['at']);
    final rejectedAt = dateOf(c['rejectedAt']);
    final acceptedAt = dateOf(c['acceptedAt']);
    var counted = false;

    if (p.has(referredAt)) {
      final kind = referral!['type'] == ReferralType.rescueVolunteer.name ? ReferralKind.volunteer : ReferralKind.organization;
      counts[kind] = counts[kind]! + 1;
      if (referral['referralReason'] == OrgReferralReason.shelterAtCapacity.name) capacity++;
      counted = true;
    } else if (p.has(linkAt)) {
      counts[ReferralKind.barangay] = counts[ReferralKind.barangay]! + 1;
      counted = true;
    } else if (p.has(rejectedAt)) {
      final reason = c['rejectionReason'];
      if (reason == RejectionReason.noShelterSpace.name) {
        counts[ReferralKind.declinedAtCapacity] = counts[ReferralKind.declinedAtCapacity]! + 1;
        capacity++;
      } else if (reason == RejectionReason.healthyAnimalLowUrgency.name) {
        counts[ReferralKind.communityAdoption] = counts[ReferralKind.communityAdoption]! + 1;
      }
      counted = true;
    }
    if (counted || p.has(acceptedAt)) decided++;
  }
  final since = earliest([
    for (final c in cases) ...[dateOf(c['acceptedAt']), dateOf(c['rejectedAt'])],
  ]);
  return ReferralBreakdown(counts: counts, decided: decided, capacity: capacity, trackingSince: since);
}

// ─── R3: who brought the animals in ────────────────────────────────────────

enum RetrievedBy {
  transporter('Pet transporter'),
  volunteer('Rescue volunteer'),
  staff('Organization staff');

  const RetrievedBy(this.label);
  final String label;
}

bool _isVolunteerRider(OfferDoc o) => ((o['riderType'] as String?) ?? '').toLowerCase().contains('volunteer');

/// Cases retrieved in the period, by who did it. A case counts once, even
/// with several transport legs (its latest completed leg decides).
Map<RetrievedBy, int> retrievalsIn(Period p, List<CaseDoc> cases, List<OfferDoc> offers) {
  final latestLeg = <String, OfferDoc>{};
  for (final o in offers) {
    if (o['isDemo'] == true || o['status'] != 'completed') continue;
    final at = dateOf(o['completedAt']);
    final caseId = o['caseId'] as String?;
    if (caseId == null || !p.has(at)) continue;
    final prev = latestLeg[caseId];
    if (prev == null || dateOf(prev['completedAt'])!.isBefore(at!)) latestLeg[caseId] = o;
  }
  final out = {for (final k in RetrievedBy.values) k: 0};
  final seen = <String>{};
  for (final e in latestLeg.entries) {
    final kind = _isVolunteerRider(e.value) ? RetrievedBy.volunteer : RetrievedBy.transporter;
    out[kind] = out[kind]! + 1;
    seen.add(e.key);
  }
  for (final c in cases.where(_isOrgCase)) {
    final id = c['id'] as String?;
    if (id == null || seen.contains(id)) continue;
    final staff = _map(c['organizationTransport']);
    if (staff != null && p.has(dateOf(staff['startedAt']))) {
      out[RetrievedBy.staff] = out[RetrievedBy.staff]! + 1;
    } else if (p.has(dateOf(c['transitCompletedAt'])) && (c['riderId'] as String? ?? '').isNotEmpty) {
      // Older direct claims have no offer document.
      out[RetrievedBy.transporter] = out[RetrievedBy.transporter]! + 1;
    }
  }
  return out;
}

// ─── R4 / R5: transport offers ─────────────────────────────────────────────

class OfferStats {
  const OfferStats({
    required this.acceptance,
    required this.minutesToAccept,
    required this.declined,
    required this.expired,
    required this.casesWithNoTaker,
    required this.declinedNoRiders,
  });

  /// Offers accepted out of offers answered or expired (cancelled ones and
  /// ones still waiting are left out).
  final Fraction acceptance;
  final MedianOf minutesToAccept;
  final int declined;
  final int expired;

  /// Cases whose every offer in the period was declined or expired.
  final int casesWithNoTaker;

  /// Reports declined with "No available riders".
  final int declinedNoRiders;
}

OfferStats offerStatsIn(Period p, List<OfferDoc> offers, List<CaseDoc> cases) {
  var accepted = 0, declined = 0, expired = 0;
  final minutes = <num>[];
  final byCase = <String, List<String>>{};
  for (final o in offers) {
    if (o['isDemo'] == true) continue;
    final offeredAt = dateOf(o['offeredAt']);
    if (!p.has(offeredAt)) continue;
    final status = o['status'] as String? ?? '';
    final acceptedAt = dateOf(o['acceptedAt']);
    if (status == 'cancelled') continue;
    (byCase[o['caseId'] as String? ?? ''] ??= []).add(status);
    if (acceptedAt != null || status == 'accepted' || status == 'completed') {
      accepted++;
      if (acceptedAt != null) minutes.add(acceptedAt.difference(offeredAt!).inMinutes);
    } else if (status == 'rejected') {
      declined++;
    } else if (status == 'expired') {
      expired++;
    }
  }
  final noTaker = byCase.entries
      .where((e) => e.key.isNotEmpty && e.value.isNotEmpty && e.value.every((s) => s == 'rejected' || s == 'expired'))
      .length;
  final noRiders = cases
      .where((c) => _isOrgCase(c) && c['rejectionReason'] == RejectionReason.noAvailableRiders.name && p.has(dateOf(c['rejectedAt'])))
      .length;
  return OfferStats(
    acceptance: Fraction(accepted, accepted + declined + expired),
    minutesToAccept: medianOf(minutes),
    declined: declined,
    expired: expired,
    casesWithNoTaker: noTaker,
    declinedNoRiders: noRiders,
  );
}

// ─── R7 / R8: leaving treatment ────────────────────────────────────────────
// (R6, animals in treatment now, is ShelterOccupancy.atVet on the dashboard,
// the same count as the clinic list; its daily trend is
// functions/analytics_snapshot_rules.js.)

enum TreatmentExit {
  shelter('Recovered: to the shelter'),
  adopter('Recovered: to an adopter'),
  reporter('Recovered: back with the reporter'),
  transferred('Recovered: transferred'),
  otherRecovered('Recovered: next step not recorded'),
  died('Died');

  const TreatmentExit(this.label);
  final String label;
  bool get recovered => this != TreatmentExit.died;
}

class TreatmentExits {
  const TreatmentExits(this.counts, this.days);
  final Map<TreatmentExit, int> counts;

  /// Days from clinic arrival to discharge, for animals discharged alive.
  final MedianOf days;

  int get total => counts.values.fold(0, (a, b) => a + b);
  Fraction get recoveredShare =>
      Fraction(counts.entries.where((e) => e.key.recovered).fold(0, (a, e) => a + e.value), total);
}

TreatmentExits treatmentExitsIn(Period p, List<CaseDoc> cases) {
  final counts = {for (final k in TreatmentExit.values) k: 0};
  final days = <num>[];
  for (final c in cases.where(_isOrgCase)) {
    final start = dateOf(c['treatmentAcceptedAt']) ?? dateOf(c['dateAdmitted']);
    final toAdopter = c['adopterPickupConfirmedAt'] != null || _map(c['adoptionRequest'])?['status'] == 'approved';
    for (final a in animalsOf(c)) {
      final died = dateOf(a['deceasedAt']);
      final discharged = dateOf(a['dischargedAt']);
      TreatmentExit? exit;
      if (p.has(died) && (a['outcome'] == 'deceased' || discharged == null)) {
        exit = TreatmentExit.died;
      } else if (p.has(discharged)) {
        exit = switch (a['postTreatmentAction']) {
          'intake' => TreatmentExit.shelter,
          'release' => TreatmentExit.reporter,
          'transfer' => TreatmentExit.transferred,
          _ => toAdopter ? TreatmentExit.adopter : TreatmentExit.otherRecovered,
        };
        if (start != null && !discharged!.isBefore(start)) days.add(discharged.difference(start).inHours / 24);
      }
      if (exit != null) counts[exit] = counts[exit]! + 1;
    }
  }
  return TreatmentExits(counts, medianOf(days));
}

// ─── R9: response time ─────────────────────────────────────────────────────

class ResponseTimes {
  const ResponseTimes(this.reportToAccepted, this.acceptedToPickup, this.pickupToClinic);

  /// Minutes, each measured on the cases that reached that step in the
  /// period.
  final MedianOf reportToAccepted;
  final MedianOf acceptedToPickup;
  final MedianOf pickupToClinic;
}

ResponseTimes responseTimesIn(Period p, List<CaseDoc> cases) {
  final a = <num>[], b = <num>[], c = <num>[];
  for (final x in cases.where(_isOrgCase)) {
    final created = dateOf(x['createdAt']);
    final accepted = dateOf(x['acceptedAt']);
    final picked = dateOf(x['pickedUpAt']);
    final clinic = dateOf(x['treatmentAcceptedAt']);
    void add(List<num> to, DateTime? from, DateTime? until) {
      if (from != null && p.has(until) && !until!.isBefore(from)) to.add(until.difference(from).inMinutes);
    }

    add(a, created, accepted);
    add(b, accepted, picked);
    add(c, picked, clinic);
  }
  return ResponseTimes(medianOf(a), medianOf(b), medianOf(c));
}

// ─── R10: intake and resolution ────────────────────────────────────────────

class IntakeVolume {
  const IntakeVolume(this.byUrgency, this.resolved);
  final Map<String, int> byUrgency;

  /// Of the reports received in the period, how many are finished now.
  final Fraction resolved;
  int get received => byUrgency.values.fold(0, (a, b) => a + b);
}

IntakeVolume intakeVolumeIn(Period p, List<CaseDoc> cases) {
  final byUrgency = <String, int>{};
  var done = 0;
  for (final c in cases.where((c) => _isOrgCase(c) && p.has(dateOf(c['createdAt'])))) {
    final u = (c['urgency'] as String?)?.trim();
    final key = (u == null || u.isEmpty) ? 'Not assessed' : u;
    byUrgency[key] = (byUrgency[key] ?? 0) + 1;
    if (_statusOf(c).isTerminal) done++;
  }
  return IntakeVolume(byUrgency, Fraction(done, byUrgency.values.fold(0, (a, b) => a + b)));
}
