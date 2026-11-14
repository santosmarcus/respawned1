import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_record.dart';
import 'package:respawnd1/core/models/rescue/medical_episode.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';

final animalRecordRepositoryProvider = Provider<AnimalRecordRepository>((ref) => AnimalRecordRepository());

final animalRecordProvider = StreamProvider.family<AnimalRecord?, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamAnimalRecord(animalId);
});

/// Staff only — every animal the signed-in staff account may list. Public
/// screens use [publicAnimalRecordsProvider].
final allAnimalRecordsProvider = StreamProvider<List<AnimalRecord>>((ref) {
  // Which animals may be listed depends on who is signed in.
  ref.watch(_signedInUidProvider);
  return ref.watch(animalRecordRepositoryProvider).streamAllAnimalRecords();
});

final _signedInUidProvider = StreamProvider<String?>((ref) {
  return FirebaseAuth.instance.authStateChanges().map((u) => u?.uid).distinct();
});

/// Public profiles for the adoption list and other non-staff screens.
final publicAnimalRecordsProvider = StreamProvider<List<AnimalRecord>>((ref) {
  return ref.watch(animalRecordRepositoryProvider).streamPublicAnimals();
});

final publicAnimalRecordProvider = StreamProvider.family<AnimalRecord?, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamPublicAnimal(animalId);
});

final recordsForCaseProvider = StreamProvider.family<List<AnimalRecord>, String>((ref, caseId) {
  return ref.watch(animalRecordRepositoryProvider).streamRecordsForCase(caseId);
});

final medicalEpisodesProvider = StreamProvider.family<List<MedicalEpisode>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamMedicalEpisodes(animalId);
});

final vaccinationsProvider = StreamProvider.family<List<VaccinationRecord>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamVaccinations(animalId);
});

final careRecordsProvider = StreamProvider.family<List<CareRecord>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamCareRecords(animalId);
});

final managementLogsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamManagementLogs(animalId);
});
