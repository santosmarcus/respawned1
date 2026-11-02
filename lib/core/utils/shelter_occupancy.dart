import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';

/// The ONE canonical "is this animal currently housed" classifier — shared
/// by the dashboard Capacity card (admin_dashboard_home_widgets.dart) and
/// the Organization Profile "Shelter Capacity" over-capacity warning, so
/// the two can never quietly disagree about what counts as current
/// occupancy. Traced from the real AnimalRecord fields this codebase
/// already writes (archived/status/adoptionStatus) — no invented status
/// values. Excludes archived, deceased, and adopted-out animals; a
/// returned-from-adoption animal (back to adoptionStatus 'not_ready') is
/// correctly still counted as housed.
bool isCurrentlyHoused(AnimalRecord a) =>
    !a.archived && a.status != 'deceased' && a.adoptionStatus != 'adopted' && a.adoptionStatus != 'deceased';

/// One-shot occupancy count for a save-time check (e.g. "would this new
/// capacity put the shelter over capacity?") — the live dashboard card
/// uses the streamed `allAnimalRecordsProvider` instead; this is for
/// screens that aren't already watching that provider.
Future<int> currentShelterOccupancy() async {
  final snap = await FirebaseFirestore.instance.collection('animals').get();
  return snap.docs.map(AnimalRecord.fromFirestore).where(isCurrentlyHoused).length;
}

/// The default Animal Records list wants "will this animal remain relevant
/// to ongoing shelter operations" — narrower than [isCurrentlyHoused],
/// which deliberately still counts a pending transfer as physically
/// occupying a spot (correct for capacity math, wrong for this list: a
/// transfer in progress belongs at the bottom with Released/Deceased, not
/// mixed in with animals actively in the shelter's care). Adoptable,
/// unadoptable ("not ready"), reserved, in-treatment, and quarantined
/// animals are all still "in shelter" — only adopted (released),
/// transferred, and deceased animals are excluded.
bool isInShelter(AnimalRecord a) => isCurrentlyHoused(a) && !a.isTransferredOut;

/// The date this animal most recently left the shelter's active care, for
/// sorting the "outgoing" (adopted/transferred/deceased) group newest-
/// first. Falls back to updatedAt/createdAt for a legacy record missing
/// the specific terminal-event timestamp, so a record never crashes or
/// sorts as if it had no date at all.
DateTime? terminalDateOf(AnimalRecord a) {
  if (a.isDeceased) return a.deceasedAt ?? a.updatedAt ?? a.createdAt;
  if (a.isAdopted) return a.adoptedAt ?? a.updatedAt ?? a.createdAt;
  if (a.isTransferredOut) {
    final ts = a.raw['transferredAt'];
    return (ts is Timestamp ? ts.toDate() : null) ?? a.updatedAt ?? a.createdAt;
  }
  return a.updatedAt ?? a.createdAt;
}
