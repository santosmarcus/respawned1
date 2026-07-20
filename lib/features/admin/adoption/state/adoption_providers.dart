import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';

final adoptionApplicationRepositoryProvider =
    Provider<AdoptionApplicationRepository>((ref) => AdoptionApplicationRepository());

final adoptionApplicationProvider = StreamProvider.family<AdoptionApplication?, String>((ref, id) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamApplication(id);
});

final adoptionsByStatusesProvider = StreamProvider.family<List<AdoptionApplication>, List<AdoptionStatus>>((ref, statuses) {
  return ref.watch(adoptionApplicationRepositoryProvider).streamByStatuses(statuses);
});

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
