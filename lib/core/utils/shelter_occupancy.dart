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
