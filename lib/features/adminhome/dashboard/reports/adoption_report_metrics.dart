/// Adoption KPIs for Reports by area → Adoptions. Pure functions over
/// animal records (`{...data, 'id': id}`), adoption applications
/// (`{...data, 'id': id, 'animalRecordId': ...}`), their follow-ups and the
/// listing engagement counters (animal_engagement_repository.dart), tested
/// in test/features/adminhome/reports/adoption_report_metrics_test.dart.
library;

import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart' show readyForAdoptionAtOf;
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

typedef AnimalDoc = Map<String, dynamic>;
typedef AdoptionDoc = Map<String, dynamic>;

/// An adoption is a success when the animal isn't returned within this
/// many days of handover (decided with the organization).
const int kSuccessWindowDays = 90;

// Thresholds for the "needs attention" animal list.
const int kHighViews = 20; // unique daily viewers in the period
const int kHighSaves = 5;
const int kLongListedDays = 60;
const int kLowViews = 5;
const int kLowViewsAfterDays = 14;

/// When the animal entered care most recently before [before]: its intake,
/// or its return from an earlier adoption.
DateTime? _intakeBefore(AnimalDoc a, DateTime before) {
  final returned = dateOf(a['returnedAt']);
  if (returned != null && returned.isBefore(before)) return returned;
  return dateOf(a['createdAt']) ?? dateOf(a['intakeDate']);
}

/// Days from intake to completed adoption, for animals adopted in [p].
Spread intakeToAdoptionDaysIn(Period p, List<AnimalDoc> animals) => spreadOf([
      for (final a in animals)
        if (dateOf(a['adoptedAt']) case final adopted? when p.has(adopted))
          if (_intakeBefore(a, adopted) case final intake? when !adopted.isBefore(intake))
            adopted.difference(intake).inHours / 24,
    ]);

/// Adoption rate: animals adopted in [p] out of the animals available for
/// adoption at some point in [p] (listed ready by the end of the period,
/// and not adopted, dead or archived before it began).
Ratio adoptionRateIn(Period p, List<AnimalDoc> animals) {
  var available = 0, adopted = 0;
  for (final a in animals) {
    final adoptedAt = dateOf(a['adoptedAt']);
    final ready = readyForAdoptionAtOf(a);
    final listedNow = const ['adoptable', 'reserved'].contains(a['adoptionStatus']);
    final wasListed = (ready != null && ready.isBefore(p.to)) || listedNow || p.has(adoptedAt);
    if (!wasListed) continue;
    if (adoptedAt != null && adoptedAt.isBefore(p.from)) continue;
    final died = dateOf(a['deceasedAt']);
    if (died != null && died.isBefore(p.from)) continue;
    if (a['archived'] == true && adoptedAt == null && died == null) continue;
    available++;
    if (p.has(adoptedAt)) adopted++;
  }
  return Ratio(adopted, available);
}

// ─── Follow-ups ────────────────────────────────────────────────────────────

class FollowUpStats {
  const FollowUpStats({required this.responses, required this.completion, required this.overdueNow});

  /// Due check-ins (date in the period and passed, not cancelled) the
  /// adopter answered.
  final Ratio responses;

  /// Due check-ins closed by staff (confirmed or completed), with or
  /// without the adopter's answer.
  final Ratio completion;

  /// Open check-ins past their date right now (any period).
  final int overdueNow;
}

FollowUpStats followUpStatsIn(Period p, List<Map<String, dynamic>> followUps, DateTime now) {
  var due = 0, answered = 0, closed = 0, overdue = 0;
  for (final f in followUps) {
    final status = f['status'] as String? ?? 'scheduled';
    if (status == 'cancelled') continue;
    final date = dateOf(f['scheduledDate']);
    if (date == null) continue;
    final open = status == 'scheduled' || status == 'reminderSent';
    if (open && date.isBefore(now)) overdue++;
    if (!p.has(date) || date.isAfter(now)) continue;
    due++;
    if (f['submittedAt'] != null || status == 'submitted' || status == 'confirmed') answered++;
    if (status == 'confirmed' || status == 'completed') closed++;
  }
  return FollowUpStats(responses: Ratio(answered, due), completion: Ratio(closed, due), overdueNow: overdue);
}

// ─── Returns ───────────────────────────────────────────────────────────────

/// Return requests that went ahead (not in review, declined or cancelled).
const kReturnedStatuses = ['approved', 'retrievalUnscheduled', 'retrievalScheduled', 'retrieved', 'intake'];

DateTime? handoverOf(AdoptionDoc a) => dateOf(a['releasedAt']) ?? dateOf(a['adoptedAt']);

Map<String, dynamic>? returnOf(AdoptionDoc a) => mapOf(a['returnRequest']);

bool _isReturn(AdoptionDoc a) => kReturnedStatuses.contains(returnOf(a)?['status']);

class ReturnStats {
  const ReturnStats({
    required this.total,
    required this.success,
    required this.returnRate,
    required this.reasons,
    required this.daysBeforeReturn,
    required this.statusNow,
    required this.rehomed,
    required this.windowEndsBefore,
  });

  /// Returns asked for in the period that went ahead.
  final int total;

  /// Adoptions handed over in the period whose 90-day window has ended,
  /// kept (not returned within the window).
  final Ratio success;

  /// The same adoptions, returned within the window.
  final Ratio returnRate;

  /// Recorded reasons of [total] ("Other" shows what was written).
  final Map<String, int> reasons;

  /// Days from handover to the return request.
  final Spread daysBeforeReturn;

  /// Where those returned animals are now.
  final Map<String, int> statusNow;

  /// Returned animals adopted again since, out of the returned animals
  /// whose record was found.
  final Ratio rehomed;

  /// Handovers on or after this date are still inside their window.
  final DateTime windowEndsBefore;
}

String _animalStatusNow(AnimalDoc? a) {
  if (a == null) return 'Record not found';
  if (a['deceasedAt'] != null || a['status'] == 'deceased') return 'Died';
  if (a['transferStatus'] != null) return 'Transferred';
  return switch (a['adoptionStatus']) {
    'adopted' => 'Adopted again',
    'adoptable' => 'Listed for adoption',
    'reserved' => 'Reserved for an adopter',
    _ => 'In care, not listed yet',
  };
}

ReturnStats returnStatsIn(Period p, List<AdoptionDoc> adoptions, List<AnimalDoc> animals, DateTime now) {
  const window = Duration(days: kSuccessWindowDays);
  final animalById = {for (final a in animals) a['id'] as String? ?? '': a};
  var measured = 0, returnedInWindow = 0;
  final reasons = <String, int>{};
  final days = <num>[];
  final statusNow = <String, int>{};
  var found = 0, rehomed = 0;
  final seenAnimals = <String>{};
  for (final a in adoptions) {
    final home = handoverOf(a);
    final r = returnOf(a);
    final asked = dateOf(r?['requestedAt']);
    if (home != null && p.has(home) && !home.add(window).isAfter(now)) {
      measured++;
      if (_isReturn(a) && asked != null && !asked.isAfter(home.add(window))) returnedInWindow++;
    }
    if (!_isReturn(a) || !p.has(asked)) continue;
    final reason = (r!['reason'] as String?)?.trim() ?? '';
    final other = (r['reasonOther'] as String?)?.trim() ?? '';
    final key = reason.isEmpty ? 'Not stated' : (reason == 'Other' && other.isNotEmpty ? 'Other: $other' : reason);
    reasons[key] = (reasons[key] ?? 0) + 1;
    if (home != null && !asked!.isBefore(home)) days.add(asked.difference(home).inHours / 24);
    // Each returned animal once, even if returned twice in the period.
    final animalId = a['animalRecordId'] as String? ?? '';
    if (animalId.isEmpty || !seenAnimals.add(animalId)) continue;
    final animal = animalById[animalId];
    final s = _animalStatusNow(animal);
    statusNow[s] = (statusNow[s] ?? 0) + 1;
    if (animal != null) {
      found++;
      final readopted = dateOf(animal['adoptedAt']);
      if (readopted != null && readopted.isAfter(asked!) && animal['adoptedApplicationId'] != a['id']) rehomed++;
    }
  }
  return ReturnStats(
    total: reasons.values.fold(0, (x, y) => x + y),
    success: Ratio(measured - returnedInWindow, measured),
    returnRate: Ratio(returnedInWindow, measured),
    reasons: reasons,
    daysBeforeReturn: spreadOf(days),
    statusNow: statusNow,
    rehomed: Ratio(rehomed, found),
    windowEndsBefore: now.subtract(window),
  );
}

// ─── Promotion funnel ──────────────────────────────────────────────────────

class AdoptionFunnel {
  const AdoptionFunnel({
    required this.views,
    required this.saves,
    required this.applications,
    required this.approved,
    required this.adopted,
    required this.trackingSince,
  });

  /// Unique daily profile viewers in the period (passive engagement).
  final int views;

  /// Favorites added in the period (expressions of interest).
  final int saves;

  /// Applications submitted in the period, and how far they got.
  final int applications;
  final int approved;
  final int adopted;

  /// The first day engagement was recorded; null when none is.
  final DateTime? trackingSince;

  Ratio get viewToSave => Ratio(saves, views);
  Ratio get viewToApplication => Ratio(applications, views);
  Ratio get applicationToApproval => Ratio(approved, applications);
  Ratio get approvalToAdoption => Ratio(adopted, approved);
}

DateTime? engagementDayOf(Map<String, dynamic> e) => DateTime.tryParse('${e['day'] ?? ''}');

bool _isApproved(AdoptionDoc a) =>
    a['approvedAt'] != null ||
    const ['approved', 'appointment_confirmed', 'adopted', 'completed', 'return_requested', 'return_approved']
        .contains(a['status']);

bool _isAdopted(AdoptionDoc a) =>
    a['adoptedAt'] != null || const ['adopted', 'completed', 'return_requested', 'return_approved'].contains(a['status']);

AdoptionFunnel adoptionFunnelIn(Period p, List<Map<String, dynamic>> engagement, List<AdoptionDoc> adoptions) {
  var views = 0, saves = 0;
  DateTime? since;
  for (final e in engagement) {
    final day = engagementDayOf(e);
    if (day == null) continue;
    if (since == null || day.isBefore(since)) since = day;
    if (!p.has(day)) continue;
    views += (e['views'] as num?)?.toInt() ?? 0;
    saves += (e['saves'] as num?)?.toInt() ?? 0;
  }
  final apps = adoptions.where((a) => p.has(dateOf(a['createdAt']))).toList();
  return AdoptionFunnel(
    views: views,
    saves: saves,
    applications: apps.length,
    approved: apps.where(_isApproved).length,
    adopted: apps.where(_isAdopted).length,
    trackingSince: since,
  );
}

// ─── Animals that need attention ───────────────────────────────────────────

enum ListingFlag {
  viewedNoApplications('Viewed a lot, no applications'),
  savedNoApplications('Saved often, no applications'),
  longListed('Listed $kLongListedDays+ days without adoption'),
  lowEngagement('Few views after $kLowViewsAfterDays days listed');

  const ListingFlag(this.label);
  final String label;
}

typedef ListingRow = ({String animalId, String name, int views, int saves, int applications, int? daysListed, List<ListingFlag> flags});

/// Animals listed now (adoptable or reserved) with their engagement in the
/// period, applications ever made for them, days listed, and flags. The
/// view-based flags appear only once view tracking covers the animal's time
/// listed ([trackingSince]).
List<ListingRow> listingRows(
  Period p,
  List<AnimalDoc> animals,
  List<Map<String, dynamic>> engagement,
  List<AdoptionDoc> adoptions,
  DateTime now, {
  DateTime? trackingSince,
}) {
  final views = <String, int>{}, saves = <String, int>{};
  for (final e in engagement) {
    final day = engagementDayOf(e);
    final id = e['animalId'] as String? ?? '';
    if (day == null || id.isEmpty || !p.has(day)) continue;
    views[id] = (views[id] ?? 0) + ((e['views'] as num?)?.toInt() ?? 0);
    saves[id] = (saves[id] ?? 0) + ((e['saves'] as num?)?.toInt() ?? 0);
  }
  final apps = <String, int>{};
  for (final a in adoptions) {
    final id = a['animalRecordId'] as String? ?? '';
    if (id.isNotEmpty) apps[id] = (apps[id] ?? 0) + 1;
  }
  final rows = <ListingRow>[];
  for (final a in animals) {
    if (!const ['adoptable', 'reserved'].contains(a['adoptionStatus']) || a['archived'] == true) continue;
    final id = a['id'] as String? ?? '';
    final ready = readyForAdoptionAtOf(a);
    final days = ready == null ? null : now.difference(ready).inDays;
    final v = views[id] ?? 0, s = saves[id] ?? 0, n = apps[id] ?? 0;
    final tracked = trackingSince != null && ready != null && !ready.isBefore(trackingSince);
    final flags = <ListingFlag>[
      if (v >= kHighViews && n == 0) ListingFlag.viewedNoApplications,
      if (s >= kHighSaves && n == 0) ListingFlag.savedNoApplications,
      if (days != null && days >= kLongListedDays) ListingFlag.longListed,
      if (tracked && days != null && days >= kLowViewsAfterDays && v < kLowViews) ListingFlag.lowEngagement,
    ];
    final name = (a['name'] as String?)?.trim();
    rows.add((
      animalId: id,
      name: (name == null || name.isEmpty) ? (a['species'] as String? ?? 'Animal') : name,
      views: v,
      saves: s,
      applications: n,
      daysListed: days,
      flags: flags,
    ));
  }
  rows.sort((x, y) => y.flags.length != x.flags.length
      ? y.flags.length.compareTo(x.flags.length)
      : (y.daysListed ?? 0).compareTo(x.daysListed ?? 0));
  return rows;
}
