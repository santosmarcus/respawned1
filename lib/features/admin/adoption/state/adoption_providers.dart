import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

final adoptionApplicationRepositoryProvider =
    Provider<AdoptionApplicationRepository>((ref) => AdoptionApplicationRepository());

final adoptionApplicationProvider = StreamProvider.family<AdoptionApplication?, String>((ref, id) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamApplication(id);
});

// autoDispose so a listener is torn down once nothing is watching it
// anymore, instead of staying subscribed to Firestore forever.
final adoptionsByStatusesProvider =
    StreamProvider.family.autoDispose<List<AdoptionApplication>, List<AdoptionStatus>>((ref, statuses) {
  final repo = ref.watch(adoptionApplicationRepositoryProvider);
  return _withOrg(ref, (orgId) => repo.streamByStatuses(statuses, organizationId: orgId));
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

final allAdoptionsProvider = StreamProvider.autoDispose<List<AdoptionApplication>>((ref) {
  final repo = ref.watch(adoptionApplicationRepositoryProvider);
  return _withOrg(ref, (orgId) => repo.streamAll(organizationId: orgId));
});

final adoptionsForAnimalProvider =
    StreamProvider.autoDispose.family<List<AdoptionApplication>, String>((ref, animalId) {
  final repo = ref.watch(adoptionApplicationRepositoryProvider);
  return _withOrg(ref, (orgId) => repo.streamForAnimal(animalId, organizationId: orgId));
});

final adoptionsForApplicantProvider =
    StreamProvider.autoDispose.family<List<AdoptionApplication>, String>((ref, adopterId) {
  final repo = ref.watch(adoptionApplicationRepositoryProvider);
  return _withOrg(ref, (orgId) => repo.streamForApplicant(adopterId, organizationId: orgId));
});

/// Staff queries are scoped to the signed-in account's organization (see
/// AdoptionApplicationRepository._scoped). Waits for the org id first so an
/// unfiltered query is never sent and refused.
Stream<T> _withOrg<T>(Ref ref, Stream<T> Function(String? orgId) build) {
  final orgId = ref.watch(currentOrganizationIdProvider.future);
  return Stream.fromFuture(orgId).asyncExpand(build);
}

final adoptionNotesProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, applicationId) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamNotes(applicationId);
});

final followUpsForAdoptionProvider = StreamProvider.family<List<FollowUpRecord>, String>((ref, applicationId) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamFollowUps(applicationId);
});
