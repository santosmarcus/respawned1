import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

/// Notification types the backend sends to an applicant about their own
/// application (functions/adoptions.js tellApplicant). Each carries
/// `adoptionId`; tapping one opens [adopterPageForAdoption].
const Set<String> kApplicantAdoptionNotifTypes = {
  'adoption_no_show_rebook',
  'adoption_no_show_closed',
  'adoption_booking_reminder',
  'adoption_booking_withdrawn',
};

/// The adopter's screen for one of their applications: the return pickup
/// while a return is being collected, post-adoption check-ins once adopted,
/// otherwise the application's step-by-step process (which shows Book
/// Appointment again after a first no-show, or the closed/withdrawn state).
/// Null when the application can't be read.
Future<Widget?> adopterPageForAdoption(String adoptionId, {String fallbackName = 'Adoption'}) async {
  final doc = await FirebaseFirestore.instance.collection('adoptions').doc(adoptionId).get();
  final data = doc.data();
  if (data == null) return null;

  final status = data['status'] as String? ?? '';
  if (AdoptionStatus.adopted.queryValues.contains(status)) {
    final returnRequest = ReturnRequest.fromMap(data['returnRequest'] as Map<String, dynamic>?);
    if (returnRequest != null &&
        (returnRequest.status.isApprovedAwaitingSchedule ||
            returnRequest.status == ReturnRequestStatus.retrievalScheduled ||
            returnRequest.status == ReturnRequestStatus.retrieved)) {
      return ReturnApprovedPage(adoptionId: adoptionId);
    }
    return PostAdoptionMonitoringPage(adoptionId: adoptionId);
  }

  final personal = (data['personal'] as Map?) ?? const {};
  final animalIdRaw = personal['animalId'];
  final animalName = personal['animalName'] as String? ?? fallbackName;
  // AdoptionProcess reloads the application by id; the animal here only
  // supplies the header until then.
  final animal = Animal(
    id: animalIdRaw is int ? animalIdRaw : 0,
    name: animalName,
    breed: '',
    age: '',
    description: '',
    healthTags: const [],
    gender: AnimalGender.male,
    category: AnimalCategory.dog,
    cardColor: AppColors.greenrspwn,
  );
  return AdoptionProcess(animal: animal, existingAdoptionId: adoptionId);
}
