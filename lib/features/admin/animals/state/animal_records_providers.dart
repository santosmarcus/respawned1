import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/medical_episode.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';

final animalRecordRepositoryProvider = Provider<AnimalRecordRepository>((ref) => AnimalRecordRepository());

final animalRecordProvider = StreamProvider.family<AnimalRecord?, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamAnimalRecord(animalId);
});

final allAnimalRecordsProvider = StreamProvider<List<AnimalRecord>>((ref) {
  return ref.watch(animalRecordRepositoryProvider).streamAllAnimalRecords();
});

final medicalEpisodesProvider = StreamProvider.family<List<MedicalEpisode>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamMedicalEpisodes(animalId);
});

final vaccinationsProvider = StreamProvider.family<List<VaccinationRecord>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamVaccinations(animalId);
});

final managementLogsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>((ref, animalId) {
  return ref.watch(animalRecordRepositoryProvider).streamManagementLogs(animalId);
});
