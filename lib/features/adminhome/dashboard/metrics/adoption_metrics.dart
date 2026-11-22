/// Adoption analytics (RESPAWND_ANALYTICS_PLAN A3–A6). Pure functions over
/// adoption documents (`{...data, 'id': id}`) and their follow-ups
/// (`adoptions/{id}/followUps`), tested in
/// test/features/adminhome/adoption_metrics_test.dart.
library;

import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';

typedef AdoptionDoc = Map<String, dynamic>;
typedef FollowUpDoc = Map<String, dynamic>;

/// An adoption counts as a success when the animal was not returned within
/// this many days of handover (decided with the organization).
const int kAdoptionSuccessWindowDays = 90;

/// How long after a check-in's date an answer still counts as on time.
const int kCheckInGraceDays = 14;

// ─── A3: post-adoption check-ins ───────────────────────────────────────────

class CheckInStats {
  const CheckInStats({required this.answered, required this.onTime, required this.overdueNow});

  /// Check-ins due in the period (not cancelled, date already passed)
  /// that the adopter answered.
  final Fraction answered;

  /// Of those answered, how many came within [kCheckInGraceDays].
  final Fraction onTime;

  /// Every check-in overdue right now (any period).
  final int overdueNow;
}

bool _answered(FollowUpDoc f) {
  final status = f['status'];
  if (f['submittedAt'] != null || status == 'submitted' || status == 'confirmed') return true;
  // Completed by staff without the adopter's answer doesn't count.
  return status == 'completed' && (f['manualCompletionReason'] as String? ?? '').isEmpty;
}

CheckInStats checkInsIn(Period p, List<FollowUpDoc> followUps, DateTime now) {
  var due = 0, answered = 0, onTime = 0, overdue = 0;
  for (final f in followUps) {
    final status = f['status'] as String? ?? 'scheduled';
    if (status == 'cancelled') continue;
    final date = dateOf(f['scheduledDate']);
    if (date == null) continue;
    final open = status == 'scheduled' || status == 'reminderSent';
    if (open && date.isBefore(now)) overdue++;
    if (!p.has(date) || date.isAfter(now)) continue;
    due++;
    if (_answered(f)) {
      answered++;
      final at = dateOf(f['submittedAt']);
      if (at != null && !at.isAfter(date.add(const Duration(days: kCheckInGraceDays)))) onTime++;
    }
  }
  return CheckInStats(answered: Fraction(answered, due), onTime: Fraction(onTime, answered), overdueNow: overdue);
}

// ─── A4 / A5: success and returns ──────────────────────────────────────────

/// When the animal went home: the release, else the adoption date.
DateTime? handoverOf(AdoptionDoc a) => dateOf(a['releasedAt']) ?? dateOf(a['adoptedAt']);

const _returnedStatuses = ['approved', 'retrievalUnscheduled', 'retrievalScheduled', 'retrieved', 'intake'];

Map<String, dynamic>? _returnOf(AdoptionDoc a) {
  final r = a['returnRequest'];
  return r is Map ? Map<String, dynamic>.from(r) : null;
}

/// A return that went ahead (not still in review, declined or cancelled).
bool _isReturn(Map<String, dynamic>? r) => r != null && _returnedStatuses.contains(r['status']);

class AdoptionCohort {
  const AdoptionCohort({required this.measured, required this.returned, required this.windowEndsBefore});

  /// Adoptions handed over in the period whose [kAdoptionSuccessWindowDays]
  /// window has already ended.
  final int measured;

  /// Of those, returned within the window.
  final int returned;

  /// Handovers on or after this date are still inside their window.
  final DateTime windowEndsBefore;

  Fraction get success => Fraction(measured - returned, measured);
  Fraction get returnRate => Fraction(returned, measured);
}

AdoptionCohort adoptionCohortIn(Period p, List<AdoptionDoc> adoptions, DateTime now) {
  const window = Duration(days: kAdoptionSuccessWindowDays);
  var measured = 0, returned = 0;
  for (final a in adoptions) {
    final home = handoverOf(a);
    if (home == null || !p.has(home) || home.add(window).isAfter(now)) continue;
    measured++;
    final r = _returnOf(a);
    final asked = dateOf(r?['requestedAt']);
    if (_isReturn(r) && asked != null && !asked.isAfter(home.add(window))) returned++;
  }
  return AdoptionCohort(measured: measured, returned: returned, windowEndsBefore: now.subtract(window));
}

/// The return form's reasons (post_adoption_page.dart, AdoptionReturnForm)
/// and the support that might have kept the animal home.
const Map<String, String> kReturnRetentionSupport = {
  'Financial Difficulties': 'Low-cost vet care, food assistance',
  'Housing Restrictions': 'Temporary boarding',
  'Allergies or Health Concerns': 'None: rehome through the organization',
  'Conflict with Existing Pets': 'Behavioural training',
  'Behavioral Challenges': 'Behavioural training',
  'Change in Personal Circumstances': 'Temporary boarding',
  'Other': 'Read the explanation',
};

/// Returns requested in the period that went ahead, by reason (most first).
List<({String reason, int count, String support})> returnReasonsIn(Period p, List<AdoptionDoc> adoptions) {
  final counts = <String, int>{};
  for (final a in adoptions) {
    final r = _returnOf(a);
    if (!_isReturn(r) || !p.has(dateOf(r!['requestedAt']))) continue;
    final reason = (r['reason'] as String?)?.trim();
    final key = (reason == null || reason.isEmpty) ? 'Other' : reason;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  final list = [
    for (final e in counts.entries)
      (reason: e.key, count: e.value, support: kReturnRetentionSupport[e.key] ?? kReturnRetentionSupport['Other']!),
  ]..sort((a, b) => b.count.compareTo(a.count));
  return list;
}

// ─── A6: from application to adoption ──────────────────────────────────────

class ApplicationFunnel {
  const ApplicationFunnel(this.applied, this.approved, this.adopted);

  /// Applications submitted in the period, and how far they have got.
  final int applied;
  final int approved;
  final int adopted;

  Fraction get approvedShare => Fraction(approved, applied);
  Fraction get adoptedShare => Fraction(adopted, approved);
}

ApplicationFunnel applicationFunnelIn(Period p, List<AdoptionDoc> adoptions) {
  var applied = 0, approved = 0, adopted = 0;
  for (final a in adoptions) {
    if (!p.has(dateOf(a['createdAt']))) continue;
    applied++;
    final status = a['status'] as String? ?? '';
    final isAdopted = a['adoptedAt'] != null || const ['adopted', 'completed', 'return_requested', 'return_approved'].contains(status);
    if (isAdopted || a['approvedAt'] != null || status == 'approved' || status == 'appointment_confirmed') approved++;
    if (isAdopted) adopted++;
  }
  return ApplicationFunnel(applied, approved, adopted);
}
