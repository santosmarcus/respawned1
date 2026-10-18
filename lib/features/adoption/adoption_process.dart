import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'adoption_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_step.dart';
import 'package:respawnd1/features/adoption/steps/adoption_day_step.dart';
import 'package:respawnd1/features/adoption/steps/adoption_intro_step.dart';
import 'package:respawnd1/features/adoption/steps/application_review_step.dart';
import 'package:respawnd1/features/adoption/steps/application_update_step.dart';
import 'package:respawnd1/features/adoption/steps/book_appointment_step.dart';
import 'package:respawnd1/features/adoption/steps/time_to_meet_step.dart';
import 'package:respawnd1/features/adoption/steps/withdrawn_step.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_step_tracker.dart';

// widget.animal is now always built from a live AnimalRecord
// (adoption_page.dart's animalRecordToCard) — the old hardcoded catalog
// this comment used to describe is gone. `widget.animal.id` is still a
// one-way stableIntIdFor hash of the real animal document id (kept only so
// this legacy int-keyed screen/AdoptionProcess/favorites pipeline doesn't
// need rewiring), so it can never be reversed back into a real
// `animals/{id}` id for a Firestore document lookup. Real
// document/query operations against the `animals` collection (reserve,
// clearReservationOnWithdrawal, admin-side "View Applications" linking)
// must use `widget.animal.animalRecordId` instead — the actual Firestore
// id, carried alongside `id` for exactly this purpose. `personal.animalId`
// stays on the submitted document only for backward-compatible display/
// dedupe matching against older applications written the same way;
// `personal.animalRecordId` (added below) is the real, reliable join key.
class AdoptionProcess extends StatefulWidget {
  final Animal animal;
  final String? existingAdoptionId;
  const AdoptionProcess({
    super.key,
    required this.animal,
    this.existingAdoptionId,
  });
  @override
  State<AdoptionProcess> createState() => _AdoptionProcessState();
}

class _AdoptionProcessState extends State<AdoptionProcess> {
  final AdoptionFormController _form = AdoptionFormController();

  final _picker = ImagePicker();
  AdoptionStep _step = AdoptionStep.intro;

  String? _adoptionId;
  bool _isSubmitting = false;
  bool _isLoadingExisting = false;

  // True once the organization has reserved this animal for this
  // applicant's approved application (AdoptionApplicationRepository.reserve,
  // admin-side) — read straight off this same doc's own reservedAt field,
  // no second lookup needed.
  bool _isReservedForMe = false;

  // Live updates so admin actions (interview scheduling, approval,
  // reservation, release, rejection) show up here without the applicant
  // needing to reopen this screen.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _adoptionSub;

  // Delivery — set by the organization once the animal is released (see
  // ReleaseDetailsPage's Release / Adoption Date, admin-side). Carries a
  // real time-of-day (not just midnight) once that screen's date+time
  // picker is used, so this doubles as both the "adoption day" gate below
  // and the date/time actually shown to the adopter here.
  DateTime? _scheduledReleaseDate;
  // How many delivery attempts have been used so far (each one spent by a
  // reschedule request — see _requestDeliveryReschedule). Capped at
  // kMaxDeliveryAttempts (shared with the admin Release page — see
  // AdoptionApplication — so the two screens can never disagree); the
  // Request Reschedule button disables itself once that cap is hit.
  int _deliveryAttempts = 0;

  AdoptionStep? _reviewStep;

  AdoptionStep get _displayStep => _reviewStep ?? _step;

  bool get _isReadOnly => _reviewStep != null;

  // The 5 circles on the tracker, left to right.
  static const List<AdoptionStep> _trackerSteps = [
    AdoptionStep.intro,
    AdoptionStep.bookAppointment,
    AdoptionStep.appReview,
    AdoptionStep.timeToMeet,
    AdoptionStep.adoptionDay,
  ];

  int get _displayIndex {
    final idx = _trackerSteps.indexOf(_displayStep);
    return idx == -1 ? _activeStepIndex : idx;
  }

  void _onTrackerTap(int index) {
    if (index > _activeStepIndex) return; // hasn't reached that phase yet
    final target = _trackerSteps[index];
    setState(() => _reviewStep = target == _step ? null : target);
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingAdoptionId != null) {
      _isLoadingExisting = true;
      _loadExistingAdoption();
      _adoptionSub = FirebaseFirestore.instance
          .collection('adoptions')
          .doc(widget.existingAdoptionId)
          .snapshots()
          .listen((_) {
            // Re-parses via the same _loadExistingAdoption path used on open —
            // no separate live-parsing logic to keep in sync with it.
            if (!_isLoadingExisting) _loadExistingAdoption();
          });
    } else {
      _prefillFromAccount();
    }
  }

  @override
  void dispose() {
    _adoptionSub?.cancel();
    _form.dispose();
    super.dispose();
  }

  int get _activeStepIndex {
    switch (_step) {
      case AdoptionStep.intro:
        return 0;
      case AdoptionStep.bookAppointment:
        return 1;
      case AdoptionStep.appReview:
        return 2;
      case AdoptionStep.timeToMeet:
        return 3;
      case AdoptionStep.adoptionDay:
        return 4;
      case AdoptionStep.appReject:
        return 2; // rejected stays at review
      case AdoptionStep.withdrawn:
        return 2; // withdrawn stays at review
    }
  }

  //select image
  Future<void> _pickUploadFile({required void Function(File) onPicked}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (picked != null) {
      onPicked(File(picked.path));
    }
  }

  static const _maxHomePhotos = 6;

  /// Adds to the existing selection rather than replacing it — repeated
  /// taps let the applicant keep adding more photos, matching "allow
  /// adding more images afterward." Capped at [_maxHomePhotos] total
  /// (existing + newly picked combined) — extra picks beyond the cap are
  /// dropped with a message rather than silently accepted.
  Future<void> _addHomePhotos() async {
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;

    final currentTotal =
        _form.existingHomePhotoUrls.length + _form.homePhotosFiles.length;
    final room = _maxHomePhotos - currentTotal;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can upload at most $_maxHomePhotos home photos.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final accepted = picked.take(room).toList();
    if (accepted.length < picked.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only $room more photo(s) can be added (max $_maxHomePhotos total).',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    setState(
      () => _form.homePhotosFiles.addAll(accepted.map((x) => File(x.path))),
    );
  }

  //upload helper
  Future<String?> _uploadFile(
    File? file,
    String pathSegment,
    String adoptionId,
  ) async {
    if (file == null) return null;
    final ref = FirebaseStorage.instance.ref(
      'adoptions/$adoptionId/$pathSegment.jpg',
    );
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// Uploads every picked Home Photo (any count — no fixed maximum) in
  /// parallel and returns the resulting URLs in the same order the files
  /// were picked. Kept entirely separate from _uploadFile's single-file
  /// Future.wait list below on purpose: unpacking a variable-length upload
  /// by a fixed position is exactly what caused the RangeError this
  /// replaces (see the class doc comment / _submitAdoptionForm).
  Future<List<String>> _uploadHomePhotos(
    List<File> files,
    String adoptionId,
  ) async {
    if (files.isEmpty) return const [];
    final urls = await Future.wait([
      for (var i = 0; i < files.length; i++)
        () async {
          final ref = FirebaseStorage.instance.ref(
            'adoptions/$adoptionId/home_photos/img_$i.jpg',
          );
          await ref.putFile(files[i]);
          return ref.getDownloadURL();
        }(),
    ]);
    return urls;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 3)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 90)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.greenrspwn,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _form.appointmentDate = picked);
  }

  //Firestore Helpers
  Future<void> _prefillFromAccount() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      final data = doc.data();
      if (data == null) return;

      setState(() {
        _form.nameCtrl.text =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        _form.phoneCtrl.text = data['phone'] ?? '';
        _form.emailCtrl.text =
            FirebaseAuth.instance.currentUser?.email ?? data['email'] ?? '';
        _form.homeAddressCtrl.text =
            data['homeAddress']?.toString() ??
            data['address']?.toString() ??
            data['city']?.toString() ??
            '';
      });
    } catch (_) {}
  }

  // Recognizes both the canonical statuses the admin Adoption Application
  // Review module now writes (pending/interview/approved/adopted) and the
  // legacy values this form used to write on its own before that module
  // existed — so an application submitted before this change still resumes
  // at the right step. See AdoptionStatus.fromFirestoreValue for the same
  // mapping used admin-side.
  // [hasAppointment]: a Pending application with an already-booked
  // appointment (booked but not yet admin-confirmed — see _saveAppointment,
  // which no longer advances status itself) should resume on the Review
  // step, not send the applicant back to re-book.
  AdoptionStep _stepForStatus(String? status, {required bool hasAppointment}) {
    switch (status) {
      case 'pending':
      case 'pending_appointment':
        return hasAppointment
            ? AdoptionStep.appReview
            : AdoptionStep.bookAppointment;
      case 'interview':
      case 'under_review':
        return AdoptionStep.appReview;
      case 'approved':
      case 'appointment_confirmed':
        return AdoptionStep.timeToMeet;
      case 'adopted':
      case 'completed':
      case 'return_requested':
      case 'return_approved':
        return AdoptionStep.adoptionDay;
      case 'rejected':
        return AdoptionStep.appReject;
      case 'withdrawn':
        return AdoptionStep.withdrawn;
      default:
        return AdoptionStep.intro;
    }
  }

  // Reloads every saved answer
  Future<void> _loadExistingAdoption() async {
    final id = widget.existingAdoptionId;
    if (id == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(id)
          .get();

      final data = doc.data();
      if (data == null) {
        if (mounted) setState(() => _isLoadingExisting = false);
        return;
      }

      final loadedStatus = data['status'] as String?;
      if (loadedStatus == 'withdrawn' || loadedStatus == 'rejected') {
        if (mounted) setState(() => _isLoadingExisting = false);
        await _prefillFromAccount();
        return;
      }

      final personal = (data['personal'] as Map?) ?? {};
      final household = (data['household'] as Map?) ?? {};
      final petExperience = (data['petExperience'] as Map?) ?? {};
      final currentPets = (petExperience['currentPets'] as Map?) ?? {};
      final lifestyle = (data['lifestyle'] as Map?) ?? {};
      final canAfford = (lifestyle['canAfford'] as Map?) ?? {};
      final uploads = (data['uploads'] as Map?) ?? {};
      final agreement = (data['agreement'] as Map?) ?? {};

      final appointmentTs = data['appointmentDate'];

      setState(() {
        _adoptionId = id;

        // Personal Information
        _form.nameCtrl.text = personal['adopterName'] as String? ?? '';
        _form.emailCtrl.text = personal['adopterEmail'] as String? ?? '';
        _form.ageCtrl.text = personal['adopterAge'] as String? ?? '';
        _form.phoneCtrl.text = personal['adopterPhone'] as String? ?? '';
        _form.homeAddressCtrl.text =
            personal['homeAddress']?.toString() ??
            personal['adopterHomeAddress']?.toString() ??
            personal['adopterCity']?.toString() ??
            '';

        // Household & Living Information
        _form.residenceType = household['residenceType'] as String?;
        _form.residenceOtherCtrl.text =
            household['residenceOther'] as String? ?? '';
        _form.ownershipStatus = household['ownershipStatus'] as String?;
        _form.householdMembers = household['householdMembers'] as int? ?? 0;

        // Pet Experience
        _form.hadPetsBefore = petExperience['hadPetsBefore'] as bool? ?? false;
        _form.currentDogs = currentPets['dogs'] as int? ?? 0;
        _form.currentCats = currentPets['cats'] as int? ?? 0;
        _form.currentBirds = currentPets['birds'] as int? ?? 0;
        _form.currentFish = currentPets['fish'] as int? ?? 0;
        _form.currentReptiles = currentPets['reptiles'] as int? ?? 0;
        _form.currentOther = currentPets['other'] as int? ?? 0;
        _form.currentOtherTypeCtrl.text =
            currentPets['otherType'] as String? ?? '';
        _form.petsVaccinated =
            petExperience['currentPetsVaccinated'] as String?;
        _form.petsSpayedNeutered =
            petExperience['currentPetsSpayedNeutered'] as String?;

        // Lifestyle & Care
        _form.hoursAlone = lifestyle['hoursAlone'] as String?;
        // Only accepted if it matches one of the dropdown's own options —
        // an older application may have freeform text here from before
        // this became a closed set; that legacy value just isn't
        // preselected rather than being force-mapped to a guess.
        final savedCaregiver = lifestyle['primaryCaregiver'] as String?;
        _form.primaryCaregiver = kCaregiverOptions.contains(savedCaregiver)
            ? savedCaregiver
            : null;
        _form.petStayLocation = lifestyle['petStayLocation'] as String?;
        _form.canAffordFood = canAfford['food'] as bool? ?? false;
        _form.canAffordVaccinations =
            canAfford['vaccinations'] as bool? ?? false;
        _form.canAffordVetVisits = canAfford['vetVisits'] as bool? ?? false;
        _form.canAffordEmergencyCare =
            canAfford['emergencyMedicalCare'] as bool? ?? false;
        _form.canAffordGrooming = canAfford['grooming'] as bool? ?? false;
        _form.canAffordCareSupplies =
            canAfford['careSupplies'] as bool? ?? false;
        _form.reasonCtrl.text = agreement['reason'] as String? ?? '';

        // Required Uploads (already uploaded — keep the saved URLs)
        _form.governmentIdUrl = uploads['governmentId'] as String?;
        _form.proofOfAddressUrl = uploads['proofOfAddress'] as String?;
        //_digitalSignatureUrl = uploads['digitalSignature'] as String?;
        // homePhotos may be a single legacy String or the current List —
        // same dual-shape tolerance the admin document reader already has.
        final homePhotosRaw = uploads['homePhotos'];
        _form.existingHomePhotoUrls = homePhotosRaw is List
            ? homePhotosRaw.whereType<String>().toList()
            : (homePhotosRaw is String && homePhotosRaw.isNotEmpty
                  ? [homePhotosRaw]
                  : []);

        // Agreements
        _form.agreeCare = agreement['care'] as bool? ?? false;
        _form.agreeNoAbandon = agreement['noAbandon'] as bool? ?? false;
        _form.agreeFollowup = agreement['followUp'] as bool? ?? false;
        _form.agreeAccurate = agreement['infoAccurate'] as bool? ?? false;
        _form.agreeNotGuaranteed =
            agreement['approvalNotGuaranteed'] as bool? ?? false;

        // Appointment
        if (appointmentTs is Timestamp) {
          _form.appointmentDate = appointmentTs.toDate();
        }
        _form.appointmentType =
            data['appointmentType'] as String? ?? _form.appointmentType;
        _form.appointmentTime = data['appointmentTime'] as String?;

        // Set by AdoptionApplicationRepository.reserve (admin-side) —
        // cleared again by unreserve/release.
        _isReservedForMe = data['reservedAt'] != null;

        // Delivery — written by ReleaseDetailsPage/releaseWithFollowUps
        // (admin-side) once the org schedules/marks the animal released.
        // ReleaseDetailsPage can also write a *draft* scheduledReleaseDate
        // while the admin is still configuring things (before "Mark as
        // Released" is actually pressed) — only treat it as a real,
        // finalized delivery once the application's own status confirms
        // the release actually went through, so the adopter never sees a
        // "Delivery scheduled" card for a date that isn't committed yet.
        final rawStatus = data['status'] as String?;
        const releasedStatuses = {
          'adopted',
          'completed',
          'return_requested',
          'return_approved',
        };
        final releaseDateTs = data['scheduledReleaseDate'];
        _scheduledReleaseDate =
            (releasedStatuses.contains(rawStatus) && releaseDateTs is Timestamp)
            ? releaseDateTs.toDate()
            : null;
        _deliveryAttempts = data['deliveryAttempts'] as int? ?? 0;

        var computedStep = _stepForStatus(
          rawStatus,
          hasAppointment: appointmentTs is Timestamp,
        );
        // The backend flips status to 'adopted' the moment the org
        // schedules the release (which may be a future date/time) — the
        // adopter shouldn't see "Adoption Day" until that scheduled
        // date/time has actually arrived. Until then, stay on "Time to
        // Meet" so the delivery date/time, attempts, and reschedule option
        // remain visible and actionable.
        if (computedStep == AdoptionStep.adoptionDay &&
            _scheduledReleaseDate != null &&
            DateTime.now().isBefore(_scheduledReleaseDate!)) {
          computedStep = AdoptionStep.timeToMeet;
        }
        _step = computedStep;
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingExisting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load your application: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _submitAdoptionForm() async {
    if (!(_form.formKey.currentState?.validate() ?? false)) return;

    // AdoptionRadioGroup/the caregiver dropdown aren't FormFields, so
    // _form.formKey.validate() above never sees them — every radio question in
    // this form could previously be submitted unanswered.
    final missingAnswers = <String>[
      if (_form.residenceType == null) 'Residence Type',
      if (_form.ownershipStatus == null) 'Ownership Status',
      if (_form.petsVaccinated == null) 'current pets vaccinated status',
      if (_form.petsSpayedNeutered == null)
        'current pets spayed/neutered status',
      if (_form.hoursAlone == null) 'hours animal will be left alone',
      if (_form.primaryCaregiver == null) 'Primary Caregiver',
      if (_form.petStayLocation == null) 'where pet will stay',
    ];
    if (missingAnswers.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please answer: ${missingAnswers.join(', ')}.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_form.agreeCare ||
        !_form.agreeNoAbandon ||
        !_form.agreeFollowup ||
        !_form.agreeAccurate ||
        !_form.agreeNotGuaranteed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please accept all agreements before submitting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      // Checked by both keys: personal.animalId (legacy — matches older
      // applications written before animalRecordId existed) and
      // personal.animalRecordId (the real animal doc id, reliable for
      // every application submitted after this fix). Neither alone is
      // guaranteed to see every prior application for this exact animal.
      final legacyExisting = FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalId', isEqualTo: '${widget.animal.id}')
          .get();
      final byRecordIdExisting = widget.animal.animalRecordId.isEmpty
          ? Future.value(null)
          : FirebaseFirestore.instance
                .collection('adoptions')
                .where(
                  'personal.animalRecordId',
                  isEqualTo: widget.animal.animalRecordId,
                )
                .get();
      final existingResults = await Future.wait([
        legacyExisting,
        byRecordIdExisting,
      ]);

      bool blocks(QuerySnapshot<Map<String, dynamic>>? snap) {
        if (snap == null) return false;
        return snap.docs.any((doc) {
          final status = doc.data()['status'] as String? ?? '';
          return status != 'rejected' && status != 'withdrawn';
        });
      }

      final stillActiveOrDone =
          blocks(existingResults[0]) || blocks(existingResults[1]);

      if (stillActiveOrDone) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${widget.animal.name} already has an ongoing or completed adoption.',
              ),
              backgroundColor: Colors.redAccent,
            ),
          );
          setState(() => _isSubmitting = false);
        }
        return;
      }

      final docRef = FirebaseFirestore.instance.collection('adoptions').doc();

      // Government ID / Proof of Address are the only two single-file
      // uploads left in this Future.wait — this list's length must always
      // match the two unpack lines directly below it. Home Photos is a
      // variable-length list and is uploaded separately via
      // _uploadHomePhotos precisely so it can never desync this fixed-size
      // unpack again (this positional mismatch — a disabled third upload
      // shrinking this list without the indices below being renumbered —
      // was the exact cause of the RangeError this replaces).
      final results = await Future.wait([
        _uploadFile(_form.governmentIdFile, 'government_id', docRef.id),
        _uploadFile(_form.proofOfAddressFile, 'proof_of_address', docRef.id),
        //_uploadFile(_digitalSignatureFile, 'digital_signature', docRef.id),
      ]);

      _form.governmentIdUrl = results[0];
      _form.proofOfAddressUrl = results[1];

      ///_digitalSignatureUrl = results[2];

      final newHomePhotoUrls = await _uploadHomePhotos(
        _form.homePhotosFiles,
        docRef.id,
      );
      final homePhotoUrls = [
        ..._form.existingHomePhotoUrls,
        ...newHomePhotoUrls,
      ];

      await docRef.set({
        'personal': {
          'adopterId': uid,
          // Legacy join key — a stringified stableIntIdFor hash, kept only
          // for matching against applications written the same way before
          // animalRecordId existed. Never reliably reversible to a real
          // animals/{id} doc; see the class doc comment above.
          'animalId': '${widget.animal.id}',
          // The real animals/{id} Firestore document id — the reliable join
          // key going forward for admin-side "View Applications" and any
          // other lookup that needs to resolve back to the actual
          // AnimalRecord. Omitted (not written as '') if unavailable.
          if (widget.animal.animalRecordId.isNotEmpty)
            'animalRecordId': widget.animal.animalRecordId,
          'animalName': widget.animal.name,
          'adopterName': _form.nameCtrl.text.trim(),
          'adopterEmail': _form.emailCtrl.text.trim(),
          'adopterAge': _form.ageCtrl.text.trim(),
          'adopterPhone': _form.phoneCtrl.text.trim(),
          'homeAddress': _form.homeAddressCtrl.text.trim(),
          // Legacy field kept for backward compatibility with older reads.
          'adopterCity': _form.homeAddressCtrl.text.trim(),
        },
        'household': {
          'residenceType': _form.residenceType,
          'residenceOther': _form.residenceType == 'Other'
              ? _form.residenceOtherCtrl.text.trim()
              : null,
          'ownershipStatus': _form.ownershipStatus,
          'householdMembers': _form.householdMembers,
        },
        'petExperience': {
          'hadPetsBefore': _form.hadPetsBefore,
          'currentPets': {
            'dogs': _form.currentDogs,
            'cats': _form.currentCats,
            'birds': _form.currentBirds,
            'fish': _form.currentFish,
            'reptiles': _form.currentReptiles,
            'other': _form.currentOther,
            'otherType': _form.currentOtherTypeCtrl.text.trim(),
          },
          'currentPetsVaccinated': _form.petsVaccinated,
          'currentPetsSpayedNeutered': _form.petsSpayedNeutered,
        },
        'lifestyle': {
          'hoursAlone': _form.hoursAlone,
          'primaryCaregiver': _form.primaryCaregiver,
          'petStayLocation': _form.petStayLocation,
          'canAfford': {
            'food': _form.canAffordFood,
            'vaccinations': _form.canAffordVaccinations,
            'vetVisits': _form.canAffordVetVisits,
            'emergencyMedicalCare': _form.canAffordEmergencyCare,
            'grooming': _form.canAffordGrooming,
            'careSupplies': _form.canAffordCareSupplies,
          },
        },
        'uploads': {
          'governmentId': _form.governmentIdUrl,
          'proofOfAddress': _form.proofOfAddressUrl,
          //'digitalSignature': _digitalSignatureUrl,
          // A list, not a single URL — every uploaded home photo is kept,
          // never overwritten by only the most recent one. The admin
          // Required Documents reader already accepts either shape.
          'homePhotos': homePhotoUrls,
        },
        'agreement': {
          'reason': _form.reasonCtrl.text.trim(),
          'care': _form.agreeCare,
          'noAbandon': _form.agreeNoAbandon,
          'followUp': _form.agreeFollowup,
          'infoAccurate': _form.agreeAccurate,
          'approvalNotGuaranteed': _form.agreeNotGuaranteed,
        },
        'status': 'pending',
        'statusHistory': [
          {'status': 'Form submitted.', 'timestamp': Timestamp.now()},
        ],
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _adoptionId = docRef.id;
        _step = AdoptionStep.bookAppointment;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveAppointment() async {
    if (_adoptionId == null) return;
    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId)
          .update({
            'appointmentType': _form.appointmentType,
            'appointmentDate': Timestamp.fromDate(_form.appointmentDate!),
            'appointmentTime': _form.appointmentTime,
            // Deliberately NOT writing 'status' here — the application stays
            // Pending (whatever it already was) until the admin's Confirm
            // Interview action moves it into Interview. This used to jump
            // straight to 'interview' the moment the applicant booked a slot,
            // skipping the admin confirmation step entirely.
            'statusHistory': FieldValue.arrayUnion([
              {'status': 'Appointment booked.', 'timestamp': Timestamp.now()},
            ]),
          });

      setState(() => _step = AdoptionStep.appReview);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to book appointment: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Clears every field back to a blank application
  void _resetProcessState() {
    _adoptionId = null;
    _step = AdoptionStep.intro;
    _reviewStep = null;

    _form.residenceType = null;
    _form.residenceOtherCtrl.clear();
    _form.ownershipStatus = null;
    _form.householdMembers = 0;

    _form.hadPetsBefore = false;
    _form.currentDogs = 0;
    _form.currentCats = 0;
    _form.currentBirds = 0;
    _form.currentFish = 0;
    _form.currentReptiles = 0;
    _form.currentOther = 0;
    _form.currentOtherTypeCtrl.clear();
    _form.petsVaccinated = null;
    _form.petsSpayedNeutered = null;

    _form.hoursAlone = null;
    _form.primaryCaregiver = null;
    _form.petStayLocation = null;
    _form.canAffordFood = false;
    _form.canAffordVaccinations = false;
    _form.canAffordVetVisits = false;
    _form.canAffordEmergencyCare = false;
    _form.canAffordGrooming = false;
    _form.canAffordCareSupplies = false;
    _form.reasonCtrl.clear();

    _form.governmentIdFile = null;
    _form.proofOfAddressFile = null;
    //_digitalSignatureFile = null;
    _form.homePhotosFiles.clear();
    _form.existingHomePhotoUrls = [];
    _form.governmentIdUrl = null;
    _form.proofOfAddressUrl = null;
    //_digitalSignatureUrl = null;

    _form.agreeCare = false;
    _form.agreeNoAbandon = false;
    _form.agreeFollowup = false;
    _form.agreeAccurate = false;
    _form.agreeNotGuaranteed = false;

    _form.appointmentDate = null;
    _form.appointmentType = 'On-site Visit';
    _form.appointmentTime = null;
  }

  Future<void> _withdrawApplication() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Withdraw Application?',
          style: GoogleFonts.tiltWarp(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to withdraw your adoption application for ${widget.animal.name}? This action cannot be undone.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Withdraw',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w700,
                color: Colors.redAccent,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || _adoptionId == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId)
          .update({
            'status': 'withdrawn',
            'withdrawnAt': FieldValue.serverTimestamp(),
            'statusHistory': FieldValue.arrayUnion([
              {
                'status': 'Application withdrawn by adopter.',
                'timestamp': Timestamp.now(),
              },
            ]),
          });

      // If this application had reserved the animal, safely release that
      // reservation so it becomes available again — never touches an
      // already-completed release (see the repository method's own doc
      // comment on why that's flagged for manual resolution instead).
      // Must be the real animals/{id} doc id (animalRecordId) — this is a
      // direct document lookup, not a query, so the stringified
      // stableIntIdFor hash (widget.animal.id) would never resolve to the
      // actual animal document and this call would silently no-op.
      if (widget.animal.animalRecordId.isNotEmpty) {
        await AdoptionApplicationRepository().clearReservationOnWithdrawal(
          applicationId: _adoptionId!,
          animalId: widget.animal.animalRecordId,
        );
      }

      setState(() => _step = AdoptionStep.withdrawn);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to withdraw: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Lets the adopter ask the organization to move the scheduled delivery
  /// date/time, capped at [kMaxDeliveryAttempts] total requests. Doesn't
  /// pick a new date itself — that stays with the organization — this just
  /// records the request (and spends one attempt) so the org can follow up.
  Future<void> _requestDeliveryReschedule() async {
    if (_adoptionId == null || _deliveryAttempts >= kMaxDeliveryAttempts) {
      return;
    }

    final nextAttempt = _deliveryAttempts + 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Request Reschedule?',
          style: GoogleFonts.tiltWarp(
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'This will use attempt $nextAttempt of $kMaxDeliveryAttempts. The '
          'organization will reach out to arrange a new delivery date '
          'and time for ${widget.animal.name}.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Request',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || _adoptionId == null || !mounted) return;

    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId)
          .update({
            'deliveryAttempts': nextAttempt,
            'rescheduleRequested': true,
            'rescheduleRequestedAt': FieldValue.serverTimestamp(),
            'statusHistory': FieldValue.arrayUnion([
              {
                'status':
                    'Adopter requested a delivery reschedule (attempt $nextAttempt of $kMaxDeliveryAttempts).',
                'timestamp': Timestamp.now(),
              },
            ]),
          });

      if (mounted) setState(() => _deliveryAttempts = nextAttempt);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request reschedule: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  //Build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      Icons.close,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Adopt ${widget.animal.name}',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tracker — tap a circle for a phase you've already reached to
            // review it (read-only); tap the current one again to return.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: AdoptionStepTracker(
                labels: kAdoptionStepLabels,
                activeIndex: _activeStepIndex,
                displayIndex: _displayIndex,
                rejected:
                    _step == AdoptionStep.appReject ||
                    _step == AdoptionStep.withdrawn,
                onStepTap: _onTrackerTap,
              ),
            ),

            if (_isReadOnly) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.slaterspwn.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Viewing a previous step — read only. Tap your '
                          'current step\'s circle above to return.',
                          style: GoogleFonts.zain(
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // body
            Expanded(
              child: _isLoadingExisting
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.greenrspwn,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: IgnorePointer(
                        ignoring: _isReadOnly,
                        child: _buildStepBody(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Rebuild after a step widget mutated [_form] (the steps call this where
  /// the page used to call `setState` directly).
  void _onFormChanged() => setState(() {});

  // switcher — the AdoptionStep enum decides which step widget is shown.
  Widget _buildStepBody() {
    switch (_displayStep) {
      case AdoptionStep.intro:
        return AdoptionIntroStep(
          form: _form,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          onAddHomePhotos: _addHomePhotos,
          onPickUploadFile: _pickUploadFile,
          onSubmit: _submitAdoptionForm,
          onChanged: _onFormChanged,
        );
      case AdoptionStep.bookAppointment:
        return BookAppointmentStep(
          form: _form,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          onSaveAppointment: _saveAppointment,
          onChanged: _onFormChanged,
        );
      case AdoptionStep.appReview:
        return ApplicationReviewStep(
          form: _form,
          animalName: widget.animal.name,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          onPickDate: _pickDate,
          onWithdraw: _withdrawApplication,
        );
      case AdoptionStep.timeToMeet:
        return TimeToMeetStep(
          form: _form,
          animalName: widget.animal.name,
          readOnly: _isReadOnly,
          isSubmitting: _isSubmitting,
          isReservedForMe: _isReservedForMe,
          scheduledReleaseDate: _scheduledReleaseDate,
          deliveryAttempts: _deliveryAttempts,
          onWithdraw: _withdrawApplication,
          onRequestReschedule: _requestDeliveryReschedule,
        );
      case AdoptionStep.adoptionDay:
        return AdoptionDayStep(
          animalName: widget.animal.name,
          scheduledReleaseDate: _scheduledReleaseDate,
          deliveryAttempts: _deliveryAttempts,
        );
      case AdoptionStep.appReject:
        return ApplicationUpdateStep(animalName: widget.animal.name);
      case AdoptionStep.withdrawn:
        return WithdrawnStep(
          animalName: widget.animal.name,
          readOnly: _isReadOnly,
          onStartOver: _resetProcessState,
        );
    }
  }
}

Widget _petThumbPlaceholder() => Container(
  width: 60,
  height: 60,
  decoration: BoxDecoration(
    color: AppColors.tearspwn,
    borderRadius: BorderRadius.circular(10),
  ),
  child: const Icon(Icons.pets, size: 26, color: AppColors.textPrimary),
);
