import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';

final adoptionApplicationRepositoryProvider =
    Provider<AdoptionApplicationRepository>((ref) => AdoptionApplicationRepository());

final adoptionApplicationProvider = StreamProvider.family<AdoptionApplication?, String>((ref, id) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamApplication(id);
});

// autoDispose so a listener is torn down once nothing is watching it
// anymore, instead of staying subscribed to Firestore forever.
final adoptionsByStatusesProvider =
    StreamProvider.family.autoDispose<List<AdoptionApplication>, List<AdoptionStatus>>((ref, statuses) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamByStatuses(statuses);
});

/// Stable, cached single-status lists. [adoptionsByStatusesProvider] is a
/// StreamProvider.family keyed by a List, and Dart's List uses identity
/// equality — a fresh `[status]` literal built inline in a widget's build()
/// method (as every call site here used to write) registers as a brand-new
/// family key on every rebuild, which starts a brand-new Firestore listener
/// in the `loading` state; that listener resolving to data is itself what
/// triggers the next rebuild, which builds yet another fresh `[status]` list
/// — an unbroken loading/rebuild cycle. This was the exact cause of the
/// Adoption Applications page never leaving its loading animation. Callers
/// should use [statusFilter] instead of writing `[status]` directly so the
/// same status always resolves to the same family instance.
final Map<AdoptionStatus, List<AdoptionStatus>> _singleStatusLists = {
  for (final s in AdoptionStatus.values) s: List.unmodifiable([s]),
};

List<AdoptionStatus> statusFilter(AdoptionStatus status) => _singleStatusLists[status]!;

final allAdoptionsProvider = StreamProvider<List<AdoptionApplication>>((ref) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamAll();
});

final adoptionsForAnimalProvider = StreamProvider.family<List<AdoptionApplication>, String>((ref, animalId) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamForAnimal(animalId);
});

final adoptionsForApplicantProvider = StreamProvider.family<List<AdoptionApplication>, String>((ref, adopterId) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamForApplicant(adopterId);
});

final adoptionNotesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, applicationId) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamNotes(applicationId);
});

final followUpsForAdoptionProvider = StreamProvider.family<List<FollowUpRecord>, String>((ref, applicationId) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamFollowUps(applicationId);
});
