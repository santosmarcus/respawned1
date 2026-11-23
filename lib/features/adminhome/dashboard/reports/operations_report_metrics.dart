/// Shelter and volunteer KPIs for Reports by area → Shelter and
/// Volunteers & transporters. Pure functions, tested in
/// test/features/adminhome/reports/operations_report_metrics_test.dart.
/// What is true right now (occupancy, capacity, transporters online) comes
/// from the dashboard's live providers (ShelterOccupancy, TransportSupply)
/// and isn't recomputed here.
library;

import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

// ─── Shelter flow ──────────────────────────────────────────────────────────

/// When an animal left the organization's care, and how.
({DateTime at, String how})? exitOf(Map<String, dynamic> a) {
  final adopted = dateOf(a['adoptedAt']);
  if (adopted != null) return (at: adopted, how: 'Adopted');
  final died = dateOf(a['deceasedAt']);
  if (died != null) return (at: died, how: 'Died');
  final transferred = dateOf(a['transferredAt']);
  if (a['transferStatus'] != null && transferred != null) return (at: transferred, how: 'Transferred');
  return null;
}

class ShelterFlow {
  const ShelterFlow({required this.admissions, required this.readmissions, required this.discharges, required this.stayDays});

  /// New animal records in the period.
  final int admissions;

  /// Animals back from an adoption in the period.
  final int readmissions;

  /// Animals that left care in the period, by how.
  final Map<String, int> discharges;

  /// Days in care of the animals that left in the period (intake, or last
  /// return, to exit).
  final Spread stayDays;

  int get dischargeTotal => discharges.values.fold(0, (a, b) => a + b);
}

ShelterFlow shelterFlowIn(Period p, List<Map<String, dynamic>> animals) {
  var admissions = 0, readmissions = 0;
  final discharges = <String, int>{};
  final stays = <num>[];
  for (final a in animals) {
    if (a['isDemo'] == true) continue;
    final intake = dateOf(a['createdAt']) ?? dateOf(a['intakeDate']);
    if (p.has(intake)) admissions++;
    final returned = dateOf(a['returnedAt']);
    if (p.has(returned)) readmissions++;
    final exit = exitOf(a);
    if (exit == null || !p.has(exit.at)) continue;
    discharges[exit.how] = (discharges[exit.how] ?? 0) + 1;
    final from = (returned != null && returned.isBefore(exit.at)) ? returned : intake;
    if (from != null && !exit.at.isBefore(from)) stays.add(exit.at.difference(from).inHours / 24);
  }
  return ShelterFlow(admissions: admissions, readmissions: readmissions, discharges: discharges, stayDays: spreadOf(stays));
}

// ─── Volunteers ────────────────────────────────────────────────────────────

/// One event (not cancelled) and its sign-ups (`registrations`, each with
/// `uid` and the `attended` mark staff set).
typedef EventRow = ({DateTime startAt, bool isPast, List<Map<String, dynamic>> registrations});

class VolunteerStats {
  const VolunteerStats({
    required this.registered,
    required this.active,
    required this.eventsHeld,
    required this.signUps,
    required this.attendance,
  });

  /// Everyone who has ever signed up for the organization's events.
  final int registered;

  /// Of them, those marked present at an event in the period.
  final int active;
  final int eventsHeld;

  /// Sign-ups for events held in the period.
  final int signUps;

  /// Sign-ups marked present, out of sign-ups whose attendance was taken.
  final Ratio attendance;

  Ratio get participation => Ratio(active, registered);
}

VolunteerStats volunteerStatsIn(Period p, List<EventRow> events) {
  final everyone = <String>{}, active = <String>{};
  var held = 0, signUps = 0, marked = 0, came = 0;
  for (final e in events) {
    for (final r in e.registrations) {
      everyone.add(r['uid'] as String? ?? '');
    }
    if (!p.has(e.startAt) || !e.isPast) continue;
    held++;
    signUps += e.registrations.length;
    for (final r in e.registrations) {
      if (r['attended'] is bool) marked++;
      if (r['attended'] == true) {
        came++;
        active.add(r['uid'] as String? ?? '');
      }
    }
  }
  everyone.remove('');
  active.remove('');
  return VolunteerStats(
    registered: everyone.length,
    active: active.length,
    eventsHeld: held,
    signUps: signUps,
    attendance: Ratio(came, marked),
  );
}
