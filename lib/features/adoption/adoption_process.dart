import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'adoption_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/adoption/interview_scheduling.dart';

enum _AdoptionProcess {
  intro,           // 1st step - Lets start
  bookAppointment, // 2nd step  – Book appointment
  appReview,       // 3rd step  – Application review
  timeToMeet,      // 4th step  – Appointment confirmed
  adoptionDay,     // 5th step  – Adoption Day! (success)
  appReject,       // 5th step  – Application Update (rejected)
  withdrawn,       // 5th step  – Application withdrawn by adopter
}

const List<String> _stepLabels = [
  'Fill out adoption form',
  'Book appointment',
  'Application review',
  'Time to meet! | Adoption Fee',
  'Adoption Day',
];


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
  _AdoptionProcess _step = _AdoptionProcess.intro;

  // Form fields
  final _formKey = GlobalKey<FormState>();

  // Personal Information
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String? _city;

  // Household & Living Information
  String? _residenceType;
  final _residenceOtherCtrl = TextEditingController();
  String? _ownershipStatus;
  int _householdMembers = 0;

  //Pet Experience
  // Nullable so "not answered yet" is a real, detectable state — a plain
  // bool defaulting to false meant this could silently submit as "No"
  // without the applicant ever touching it.
  String? _hadPetsBeforeAnswer;
  int _currentDogs = 0;
  int _currentCats = 0;
  int _currentBirds = 0;
  int _currentFish = 0;
  int _currentReptiles = 0;
  int _currentOther = 0;
  final _currentOtherTypeCtrl = TextEditingController();
  String? _petsVaccinated;
  String? _petsSpayedNeutered;

  //Lifestyle & Care
  String? _hoursAlone;
  // Dropdown, not freeform text — a small closed set of real answers, same
  // reasoning as the rest of this form's radio questions.
  static const _caregiverOptions = ['Me', 'Family', 'Housekeeper'];
  String? _primaryCaregiver;
  String? _petStayLocation;
  bool _canAffordFood = false;
  bool _canAffordVaccinations = false;
  bool _canAffordVetVisits = false;
  bool _canAffordEmergencyCare = false;
  bool _canAffordGrooming = false;
  bool _canAffordCareSupplies= false;
  final _reasonCtrl = TextEditingController();

  //Required Uploads
  File? _governmentIdFile;
  File? _proofOfAddressFile;
  //File? _digitalSignatureFile;
  // Home Photos supports multiple images — a newly-picked list plus,
  // when resuming an in-progress application, whatever was already
  // uploaded in an earlier session (kept separate so removing one only
  // removes that one, exactly like CreateAnimalRecordPage's own
  // existing/newly-picked image split).
  final List<File> _homePhotosFiles = [];
  List<String> _existingHomePhotoUrls = [];

  String? _governmentIdUrl;
  String? _proofOfAddressUrl;
  //String? _digitalSignatureUrl;

  bool _isUploadingGovId = false;
  bool _isUploadingProof = false;
  bool _isUploadingSignature = false;
  bool _isUploadingHomePhotos = false;

  final _picker = ImagePicker();

  // Agreements
  bool _agreeCare = false;
  bool _agreeNoAbandon = false;
  bool _agreeFollowup = false;
  bool _agreeAccurate = false;
  bool _agreeNotGuaranteed = false;

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

  // Adoption fee / payment
  static const double adoptionFeeAmount = 500;
  bool _feePaid = false;
  String? _paymentMethod;

  // Appointment
  DateTime? _appointmentDate;
  String _appointmentType = 'On-site Visit';
  String? _appointmentTime;

  _AdoptionProcess? _reviewStep;

  _AdoptionProcess get _displayStep => _reviewStep ?? _step;

  bool get _isReadOnly => _reviewStep != null;

  // The 5 circles on the tracker, left to right.
  static const List<_AdoptionProcess> _trackerSteps = [
    _AdoptionProcess.intro,
    _AdoptionProcess.bookAppointment,
    _AdoptionProcess.appReview,
    _AdoptionProcess.timeToMeet,
    _AdoptionProcess.adoptionDay,
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

  // Interview visit types + day-of-week time slots — now the shared
  // interview_scheduling.dart source of truth (also used by the admin's
  // Reschedule action), not a copy private to this screen.
  List<String> get _slotsForDate {
    if (_appointmentDate == null) return [];
    return interviewSlotsForDate(_appointmentDate!);
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
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _residenceOtherCtrl.dispose();
    _currentOtherTypeCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  int get _activeStepIndex {
    switch (_step) {
      case _AdoptionProcess.intro:
        return 0;
      case _AdoptionProcess.bookAppointment:
        return 1;
      case _AdoptionProcess.appReview:
        return 2;
      case _AdoptionProcess.timeToMeet:
        return 3;
      case _AdoptionProcess.adoptionDay:
        return 4;
      case _AdoptionProcess.appReject:
        return 2; // rejected stays at review
      case _AdoptionProcess.withdrawn:
        return 2; // withdrawn stays at review
    }
  }

  //select image
  Future<void> _pickUploadFile({
    required void Function(File) onPicked,
  }) async {
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

    final currentTotal = _existingHomePhotoUrls.length + _homePhotosFiles.length;
    final room = _maxHomePhotos - currentTotal;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('You can upload at most $_maxHomePhotos home photos.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final accepted = picked.take(room).toList();
    if (accepted.length < picked.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Only $room more photo(s) can be added (max $_maxHomePhotos total).'), backgroundColor: Colors.redAccent),
      );
    }
    setState(() => _homePhotosFiles.addAll(accepted.map((x) => File(x.path))));
  }

  //upload helper
  Future<String?> _uploadFile(File? file, String pathSegment, String adoptionId) async {
    if (file == null) return null;
    final ref = FirebaseStorage.instance
        .ref('adoptions/$adoptionId/$pathSegment.jpg');
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// Uploads every picked Home Photo (any count — no fixed maximum) in
  /// parallel and returns the resulting URLs in the same order the files
  /// were picked. Kept entirely separate from _uploadFile's single-file
  /// Future.wait list below on purpose: unpacking a variable-length upload
  /// by a fixed position is exactly what caused the RangeError this
  /// replaces (see the class doc comment / _submitAdoptionForm).
  Future<List<String>> _uploadHomePhotos(List<File> files, String adoptionId) async {
    if (files.isEmpty) return const [];
    final urls = await Future.wait([
      for (var i = 0; i < files.length; i++)
            () async {
          final ref = FirebaseStorage.instance.ref('adoptions/$adoptionId/home_photos/img_$i.jpg');
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
    if (picked != null) setState(() => _appointmentDate = picked);
  }

  String _formatDate(DateTime d) =>
      '${_monthName(d.month)} ${d.day}, ${d.year}';

  String _monthName(int m) =>
      const [
        '', 'January', 'February', 'March', 'April', 'May', 'June',
        'July', 'August', 'September', 'October', 'November', 'December'
      ][m];


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
        _nameCtrl.text =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        _phoneCtrl.text =
            data['phone'] ?? '';
        _emailCtrl.text =
            FirebaseAuth.instance.currentUser?.email ?? data['email'] ?? '';
        _city = data['city'];
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
  _AdoptionProcess _stepForStatus(String? status, {required bool hasAppointment}) {
    switch (status) {
      case 'pending':
      case 'pending_appointment':
        return hasAppointment ? _AdoptionProcess.appReview : _AdoptionProcess.bookAppointment;
      case 'interview':
      case 'under_review':
        return _AdoptionProcess.appReview;
      case 'approved':
      case 'appointment_confirmed':
        return _AdoptionProcess.timeToMeet;
      case 'adopted':
      case 'completed':
      case 'return_requested':
      case 'return_approved':
        return _AdoptionProcess.adoptionDay;
      case 'rejected':
        return _AdoptionProcess.appReject;
      case 'withdrawn':
        return _AdoptionProcess.withdrawn;
      default:
        return _AdoptionProcess.intro;
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
        _nameCtrl.text = personal['adopterName'] as String? ?? '';
        _emailCtrl.text = personal['adopterEmail'] as String? ?? '';
        _ageCtrl.text = personal['adopterAge'] as String? ?? '';
        _phoneCtrl.text = personal['adopterPhone'] as String? ?? '';
        _addressCtrl.text = personal['adopterAddress'] as String? ?? '';
        _city = personal['adopterCity'] as String?;

        // Household & Living Information
        _residenceType = household['residenceType'] as String?;
        _residenceOtherCtrl.text =
            household['residenceOther'] as String? ?? '';
        _ownershipStatus = household['ownershipStatus'] as String?;
        _householdMembers = household['householdMembers'] as int? ?? 0;

        // Pet Experience
        _hadPetsBeforeAnswer = petExperience['hadPetsBefore'] == null
            ? null
            : ((petExperience['hadPetsBefore'] as bool? ?? false) ? 'Yes' : 'No');
        _currentDogs = currentPets['dogs'] as int? ?? 0;
        _currentCats = currentPets['cats'] as int? ?? 0;
        _currentBirds = currentPets['birds'] as int? ?? 0;
        _currentFish = currentPets['fish'] as int? ?? 0;
        _currentReptiles = currentPets['reptiles'] as int? ?? 0;
        _currentOther = currentPets['other'] as int? ?? 0;
        _currentOtherTypeCtrl.text = currentPets['otherType'] as String? ?? '';
        _petsVaccinated = petExperience['currentPetsVaccinated'] as String?;
        _petsSpayedNeutered =
        petExperience['currentPetsSpayedNeutered'] as String?;

        // Lifestyle & Care
        _hoursAlone = lifestyle['hoursAlone'] as String?;
        // Only accepted if it matches one of the dropdown's own options —
        // an older application may have freeform text here from before
        // this became a closed set; that legacy value just isn't
        // preselected rather than being force-mapped to a guess.
        final savedCaregiver = lifestyle['primaryCaregiver'] as String?;
        _primaryCaregiver = _caregiverOptions.contains(savedCaregiver) ? savedCaregiver : null;
        _petStayLocation = lifestyle['petStayLocation'] as String?;
        _canAffordFood = canAfford['food'] as bool? ?? false;
        _canAffordVaccinations = canAfford['vaccinations'] as bool? ?? false;
        _canAffordVetVisits = canAfford['vetVisits'] as bool? ?? false;
        _canAffordEmergencyCare =
            canAfford['emergencyMedicalCare'] as bool? ?? false;
        _canAffordGrooming = canAfford['grooming'] as bool? ?? false;
        _canAffordCareSupplies = canAfford['careSupplies'] as bool? ?? false;
        _reasonCtrl.text = agreement['reason'] as String? ?? '';

        // Required Uploads (already uploaded — keep the saved URLs)
        _governmentIdUrl = uploads['governmentId'] as String?;
        _proofOfAddressUrl = uploads['proofOfAddress'] as String?;
        //_digitalSignatureUrl = uploads['digitalSignature'] as String?;
        // homePhotos may be a single legacy String or the current List —
        // same dual-shape tolerance the admin document reader already has.
        final homePhotosRaw = uploads['homePhotos'];
        _existingHomePhotoUrls = homePhotosRaw is List
            ? homePhotosRaw.whereType<String>().toList()
            : (homePhotosRaw is String && homePhotosRaw.isNotEmpty ? [homePhotosRaw] : []);

        // Agreements
        _agreeCare = agreement['care'] as bool? ?? false;
        _agreeNoAbandon = agreement['noAbandon'] as bool? ?? false;
        _agreeFollowup = agreement['followUp'] as bool? ?? false;
        _agreeAccurate = agreement['infoAccurate'] as bool? ?? false;
        _agreeNotGuaranteed =
            agreement['approvalNotGuaranteed'] as bool? ?? false;

        // Appointment
        if (appointmentTs is Timestamp) {
          _appointmentDate = appointmentTs.toDate();
        }
        _appointmentType = data['appointmentType'] as String? ?? _appointmentType;
        _appointmentTime = data['appointmentTime'] as String?;

        // Adoption fee / payment
        final payment = (data['payment'] as Map?) ?? {};
        _feePaid = payment['status'] == 'paid';
        _paymentMethod = payment['method'] as String?;

        // Set by AdoptionApplicationRepository.reserve (admin-side) —
        // cleared again by unreserve/release.
        _isReservedForMe = data['reservedAt'] != null;

        _step = _stepForStatus(data['status'] as String?, hasAppointment: appointmentTs is Timestamp);
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
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // _RadioGroup/the caregiver dropdown aren't FormFields, so
    // _formKey.validate() above never sees them — every radio question in
    // this form could previously be submitted unanswered.
    final missingAnswers = <String>[
      if (_residenceType == null) 'Residence Type',
      if (_ownershipStatus == null) 'Ownership Status',
      if (_householdMembers <= 0) 'Number of Household Members',
      if (_hadPetsBeforeAnswer == null) 'Owned pets before',
      if (_petsVaccinated == null) 'current pets vaccinated status',
      if (_petsSpayedNeutered == null) 'current pets spayed/neutered status',
      if (_hoursAlone == null) 'hours animal will be left alone',
      if (_primaryCaregiver == null) 'Primary Caregiver',
      if (_petStayLocation == null) 'where pet will stay',
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

    if (!_canAffordFood ||
        !_canAffordVaccinations ||
        !_canAffordVetVisits ||
        !_canAffordEmergencyCare ||
        !_canAffordGrooming ||
        !_canAffordCareSupplies) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please confirm you can afford all listed pet care costs.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final missingUploads = <String>[
      if (_governmentIdFile == null && _governmentIdUrl == null)
        'Government ID',
      if (_proofOfAddressFile == null && _proofOfAddressUrl == null)
        'Proof of Address',
      if (_homePhotosFiles.isEmpty && _existingHomePhotoUrls.isEmpty)
        'at least one Home Photo',
    ];
    if (missingUploads.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please upload: ${missingUploads.join(', ')}.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_agreeCare ||
        !_agreeNoAbandon ||
        !_agreeFollowup ||
        !_agreeAccurate ||
        !_agreeNotGuaranteed) {
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
          .where('personal.animalRecordId', isEqualTo: widget.animal.animalRecordId)
          .get();
      final existingResults = await Future.wait([legacyExisting, byRecordIdExisting]);

      bool blocks(QuerySnapshot<Map<String, dynamic>>? snap) {
        if (snap == null) return false;
        return snap.docs.any((doc) {
          final status = doc.data()['status'] as String? ?? '';
          return status != 'rejected' && status != 'withdrawn';
        });
      }

      final stillActiveOrDone = blocks(existingResults[0]) || blocks(existingResults[1]);

      if (stillActiveOrDone) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  '${widget.animal.name} already has an ongoing or completed adoption.'),
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
        _uploadFile(_governmentIdFile, 'government_id', docRef.id),
        _uploadFile(_proofOfAddressFile, 'proof_of_address', docRef.id),
        //_uploadFile(_digitalSignatureFile, 'digital_signature', docRef.id),
      ]);

      _governmentIdUrl = results[0];
      _proofOfAddressUrl = results[1];
      ///_digitalSignatureUrl = results[2];

      final newHomePhotoUrls = await _uploadHomePhotos(_homePhotosFiles, docRef.id);
      final homePhotoUrls = [..._existingHomePhotoUrls, ...newHomePhotoUrls];

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
          'adopterName': _nameCtrl.text.trim(),
          'adopterEmail': _emailCtrl.text.trim(),
          'adopterAge': _ageCtrl.text.trim(),
          'adopterPhone': _phoneCtrl.text.trim(),
          'adopterAddress': _addressCtrl.text.trim(),
          'adopterCity': _city,
        },
        'household': {
          'residenceType': _residenceType,
          'residenceOther': _residenceType == 'Other'
              ? _residenceOtherCtrl.text.trim()
              : null,
          'ownershipStatus': _ownershipStatus,
          'householdMembers': _householdMembers,
        },
        'petExperience': {
          'hadPetsBefore': _hadPetsBeforeAnswer == 'Yes',
          'currentPets': {
            'dogs': _currentDogs,
            'cats': _currentCats,
            'birds': _currentBirds,
            'fish': _currentFish,
            'reptiles': _currentReptiles,
            'other': _currentOther,
            'otherType': _currentOtherTypeCtrl.text.trim(),
          },
          'currentPetsVaccinated': _petsVaccinated,
          'currentPetsSpayedNeutered': _petsSpayedNeutered,
        },
        'lifestyle': {
          'hoursAlone': _hoursAlone,
          'primaryCaregiver': _primaryCaregiver,
          'petStayLocation': _petStayLocation,
          'canAfford': {
            'food': _canAffordFood,
            'vaccinations': _canAffordVaccinations,
            'vetVisits': _canAffordVetVisits,
            'emergencyMedicalCare': _canAffordEmergencyCare,
            'grooming': _canAffordGrooming,
            'careSupplies':  _canAffordCareSupplies,

          },

        },
        'uploads': {
          'governmentId': _governmentIdUrl,
          'proofOfAddress': _proofOfAddressUrl,
          'homePhotos': homePhotoUrls,
        },
        'agreement': {
          'reason': _reasonCtrl.text.trim(),
          'care': _agreeCare,
          'noAbandon': _agreeNoAbandon,
          'followUp': _agreeFollowup,
          'infoAccurate': _agreeAccurate,
          'approvalNotGuaranteed': _agreeNotGuaranteed,
        },
        'status': 'pending',
        'statusHistory': [
          {
            'status': 'Form submitted.',
            'timestamp': Timestamp.now(),
          }
        ],
        'createdAt': FieldValue.serverTimestamp(),
      });

      setState(() {
        _adoptionId = docRef.id;
        _step = _AdoptionProcess.bookAppointment;
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
          .doc(_adoptionId).update({
        'appointmentType': _appointmentType,
        'appointmentDate': Timestamp.fromDate(_appointmentDate!),
        'appointmentTime': _appointmentTime,
        // Deliberately NOT writing 'status' here — the application stays
        // Pending (whatever it already was) until the admin's Confirm
        // Interview action moves it into Interview. This used to jump
        // straight to 'interview' the moment the applicant booked a slot,
        // skipping the admin confirmation step entirely.
        'statusHistory': FieldValue.arrayUnion([{
          'status': 'Appointment booked.',
          'timestamp': Timestamp.now(),
        }
        ]),
      });

      setState(() => _step = _AdoptionProcess.appReview);
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
    _step = _AdoptionProcess.intro;
    _reviewStep = null;

    _residenceType = null;
    _residenceOtherCtrl.clear();
    _ownershipStatus = null;
    _householdMembers = 0;

    _hadPetsBeforeAnswer = null;
    _currentDogs = 0;
    _currentCats = 0;
    _currentBirds = 0;
    _currentFish = 0;
    _currentReptiles = 0;
    _currentOther = 0;
    _currentOtherTypeCtrl.clear();
    _petsVaccinated = null;
    _petsSpayedNeutered = null;

    _hoursAlone = null;
    _primaryCaregiver = null;
    _petStayLocation = null;
    _canAffordFood = false;
    _canAffordVaccinations = false;
    _canAffordVetVisits = false;
    _canAffordEmergencyCare = false;
    _canAffordGrooming = false;
    _canAffordCareSupplies = false;
    _reasonCtrl.clear();

    _governmentIdFile = null;
    _proofOfAddressFile = null;
    //_digitalSignatureFile = null;
    _homePhotosFiles.clear();
    _existingHomePhotoUrls = [];
    _governmentIdUrl = null;
    _proofOfAddressUrl = null;
    //_digitalSignatureUrl = null;

    _agreeCare = false;
    _agreeNoAbandon = false;
    _agreeFollowup = false;
    _agreeAccurate = false;
    _agreeNotGuaranteed = false;

    _appointmentDate = null;
    _appointmentType = 'On-site Visit';
    _appointmentTime = null;
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
              fontWeight: FontWeight.bold, color: AppColors.textPrimary),
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
                  fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Withdraw',
              style: GoogleFonts.zain(
                  fontWeight: FontWeight.w700, color: Colors.redAccent),
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
          }
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

      setState(() => _step = _AdoptionProcess.withdrawn);
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
                    child: const Icon(Icons.close,
                        size: 22, color: AppColors.textPrimary),
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
              child: _StepTracker(
                labels: _stepLabels,
                activeIndex: _activeStepIndex,
                displayIndex: _displayIndex,
                rejected: _step == _AdoptionProcess.appReject ||
                    _step == _AdoptionProcess.withdrawn,
                onStepTap: _onTrackerTap,
              ),
            ),

            if (_isReadOnly) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.slaterspwn.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility_outlined,
                          size: 16, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Viewing a previous step — read only. Tap your '
                              'current step\'s circle above to return.',
                          style: GoogleFonts.zain(
                              fontSize: 12, color: AppColors.textPrimary),
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
                    color: AppColors.greenrspwn),
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

  // switcher
  Widget _buildStepBody() {
    switch (_displayStep) {
      case _AdoptionProcess.intro:
        return _buildIntro();
      case _AdoptionProcess.bookAppointment:
        return _buildBookAppointment();
      case _AdoptionProcess.appReview:
        return _buildAppReview();
      case _AdoptionProcess.timeToMeet:
        return _buildTimeToMeet();
      case _AdoptionProcess.adoptionDay:
        return _buildAdoptionDay();
      case _AdoptionProcess.appReject:
        return _buildAppUpdate();
      case _AdoptionProcess.withdrawn:
        return _buildWithdrawn();
    }
  }

  // 1st step - fill out form
  Widget _buildIntro() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fill out adoption form',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'Ready to give a rescue a loving forever home?',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Fill out this quick form to help us match you with the right rescue and confirm eligibility for adoption.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        const SizedBox(height: 24),

        Form(
          key: _formKey,
          child: Column(
            children: [
              // Personal Information
              _SectionTitle('Personal Information'),
              const SizedBox(height: 12),
              _FormField(
                controller: _nameCtrl,
                label: 'Name',
                hint: ' ',
                inputFormatters: [AppInputFormatters.nameOnly],
                validator: (v) => AppValidators.name(v, fieldName: 'Name'),
              ),
              const SizedBox(height: 12),
              _FormField(
                  controller: _emailCtrl,
                  label: 'Email',
                  hint: 'Email@email.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: AppValidators.email),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _FormField(
                        controller: _phoneCtrl,
                        label: 'Number',
                        hint: '+63 989 989 989',
                        keyboardType: TextInputType.phone,
                        inputFormatters: AppInputFormatters.phoneFlexible,
                        validator: AppValidators.phFlexiblePhone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormField(
                        controller: _ageCtrl,
                        label: 'Age',
                        hint: ' ',
                        keyboardType: TextInputType.number,
                        inputFormatters: [AppInputFormatters.digitsOnly],
                        validator: (v) => AppValidators.wholeNumber(
                          v,
                          fieldName: 'Age',
                          min: 18,
                        )),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _addressCtrl,
                label: 'Complete Address',
                hint: 'House No., Street, Barangay',
              ),
              const SizedBox(height: 12),
              _DropdownField<String>(
                label: 'City',
                value: _city,
                items: const [
                  'Quezon City',
                  'Manila',
                  'Caloocan',
                  'Taguig',
                  'Paranaque',
                  'Valenzuela',
                  'Las Pinas',
                  'Muntinlupa',
                  'Makati',
                  'Mandaluyong',
                  'Malabon',
                  'Marikina',
                  'Navotas',
                  'Pasig',
                  'Pateros',
                  'San Juan',
                  'Other'
                ],
                onChanged: (v) => setState(() => _city = v),
              ),

              const SizedBox(height: 22),

              // Household & Living Information
              _SectionTitle('Household & Living Information'),
              const SizedBox(height: 8),
              _RadioGroup<String>(
                label: 'Residence Type',
                value: _residenceType,
                required: true,
                options: const [
                  'House',
                  'Apartment',
                  'Condominium',
                  'Townhouse',
                  'Other'
                ],
                onChanged: (v) => setState(() => _residenceType = v),
              ),
              if (_residenceType == 'Other') ...[
                const SizedBox(height: 8),
                _FormField(
                    controller: _residenceOtherCtrl,
                    label: 'Please specify',
                    hint: ' '),
              ],
              const SizedBox(height: 16),
              _RadioGroup<String>(
                label: 'Ownership Status',
                value: _ownershipStatus,
                required: true,
                options: const ['Owned', 'Renting (Allowed Pets)', 'Living with Parents'],
                onChanged: (v) => setState(() => _ownershipStatus = v),
              ),
              const SizedBox(height: 12),
              _CounterField(
                label: 'Number of Household Members',
                required: true,
                value: _householdMembers,
                onChanged: (v) => setState(() => _householdMembers = v),
              ),

              const SizedBox(height: 22),

              // Pet Experience
              _SectionTitle('Pet Experience'),
              const SizedBox(height: 8),
              _RadioGroup<String>(
                label: 'Owned pets before?',
                value: _hadPetsBeforeAnswer,
                required: true,
                options: const ['Yes', 'No'],
                onChanged: (v) => setState(() => _hadPetsBeforeAnswer = v),
              ),
              const SizedBox(height: 8),
              Text('Current pets',
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              _CounterField(
                  label: 'Dogs',
                  value: _currentDogs,
                  onChanged: (v) => setState(() => _currentDogs = v)),
              _CounterField(
                  label: 'Cats',
                  value: _currentCats,
                  onChanged: (v) => setState(() => _currentCats = v)),
              _CounterField(
                  label: 'Birds',
                  value: _currentBirds,
                  onChanged: (v) => setState(() => _currentBirds = v)),
              _CounterField(
                  label: 'Fish',
                  value: _currentFish,
                  onChanged: (v) => setState(() => _currentFish = v)),
              _CounterField(
                  label: 'Reptiles',
                  value: _currentReptiles,
                  onChanged: (v) => setState(() => _currentReptiles = v)),
              _CounterField(
                  label: 'Other',
                  value: _currentOther,
                  onChanged: (v) => setState(() => _currentOther = v)),
              if (_currentOther > 0) ...[
                const SizedBox(height: 8),
                _FormField(
                    controller: _currentOtherTypeCtrl,
                    label: 'Specify other pet type',
                    hint: ' '),
              ],
              const SizedBox(height: 16),
              _RadioGroup<String>(
                label: 'Are all current pets vaccinated?',
                value: _petsVaccinated,
                required: true,
                options: const ['Yes', 'Some', 'None', 'Not Applicable'],
                onChanged: (v) => setState(() => _petsVaccinated = v),
              ),
              const SizedBox(height: 16),
              _RadioGroup<String>(
                label: 'Are all current pets spayed/neutered?',
                value: _petsSpayedNeutered,
                required: true,
                options: const ['Yes', 'Some', 'None', 'Not Applicable'],
                onChanged: (v) => setState(() => _petsSpayedNeutered = v),
              ),

              const SizedBox(height: 22),

              // Lifestyle & Care
              _SectionTitle('Lifestyle & Care'),
              const SizedBox(height: 8),
              _RadioGroup<String>(
                label: 'Hours animal will be left alone',
                value: _hoursAlone,
                required: true,
                options: const [
                  'Less than 2 hours',
                  '2-4',
                  '5-8',
                  'More than 8 hours'
                ],
                onChanged: (v) => setState(() => _hoursAlone = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('Primary Caregiver',
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: _primaryCaregiver,
                hint: Text('Select', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                items: _caregiverOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setState(() => _primaryCaregiver = v),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.yellowrspwn.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              _RadioGroup<String>(
                label: 'Where will pet stay?',
                value: _petStayLocation,
                required: true,
                options: const ['Indoors', 'Outdoors', 'Mixed'],
                onChanged: (v) => setState(() => _petStayLocation = v),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Text('Can you afford? (check all that apply)',
                          style: GoogleFonts.zain(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(width: 4),
                  const _InfoTooltip(
                    message:
                    'According to the McDuffy 2026 Guide, the starter budget for owning a pet in the Philippines is approximately ₱2,400 per month. This covers essential expenses such as food, veterinary care, grooming, supplies, treats, and emergency savings.\n\n'
                        'Estimated monthly costs:\n'
                        '• Food – ₱500\n'
                        '• Vaccines – ₱250\n'
                        '• Flea & Tick Prevention – ₱500\n'
                        '• Grooming – ₱250\n'
                        '• Supplies & Replacements – ₱300\n'
                        '• Treats – ₱200\n'
                        '• Emergency Fund – ₱250\n'
                        '• Miscellaneous – ₱150',
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Food'),
                value: _canAffordFood,
                onChanged: (v) => setState(() => _canAffordFood = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vaccinations'),
                value: _canAffordVaccinations,
                onChanged: (v) =>
                    setState(() => _canAffordVaccinations = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vet Visits'),
                value: _canAffordVetVisits,
                onChanged: (v) => setState(() => _canAffordVetVisits = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Emergency Medical Care'),
                value: _canAffordEmergencyCare,
                onChanged: (v) =>
                    setState(() => _canAffordEmergencyCare = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Grooming'),
                value: _canAffordGrooming,
                onChanged: (v) =>
                    setState(() => _canAffordGrooming = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Care Supplies'),
                value: _canAffordCareSupplies,
                onChanged: (v) =>
                    setState(() => _canAffordCareSupplies = v!),
              ),

              const SizedBox(height: 12),
              _FormField(
                controller: _reasonCtrl,
                label: 'Why do you want to adopt?',
                hint: 'Enter',
                maxLines: 4,
              ),

              const SizedBox(height: 22),

              // Required Uploads
              _SectionTitle('Required Uploads'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  _UploadBox(
                    label: 'Government ID',
                    file: _governmentIdFile,
                    isUploading: _isUploadingGovId,
                    required: true,
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _governmentIdFile = f),
                    ),
                  ),
                  _UploadBox(
                    label: 'Proof of Address',
                    file: _proofOfAddressFile,
                    isUploading: _isUploadingProof,
                    required: true,
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _proofOfAddressFile = f),
                    ),
                  ),
                  /*_UploadBox(
                    label: 'Digital Signature',
                    file: _digitalSignatureFile,
                    isUploading: _isUploadingSignature,
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _digitalSignatureFile = f),
                    ),
                  ),*/
                ],
              ),

              const SizedBox(height: 18),

              // Home Photos — multiple images, not a single fixed slot: add
              // more afterward, remove any one before submitting, every
              // selected photo is uploaded and its URL saved (never
              // overwritten by only the most recent pick).
              _HomePhotosPicker(
                existingUrls: _existingHomePhotoUrls,
                newFiles: _homePhotosFiles,
                isUploading: _isUploadingHomePhotos,
                onAdd: _addHomePhotos,
                onRemoveExisting: (i) => setState(() => _existingHomePhotoUrls.removeAt(i)),
                onRemoveNew: (i) => setState(() => _homePhotosFiles.removeAt(i)),
              ),

              const SizedBox(height: 22),

              // Agreements
              _SectionTitle('Agreements'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I will provide proper care'),
                value: _agreeCare,
                onChanged: (v) => setState(() => _agreeCare = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I will not abandon the animal'),
                value: _agreeNoAbandon,
                onChanged: (v) => setState(() => _agreeNoAbandon = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I agree to post-adoption follow ups'),
                value: _agreeFollowup,
                onChanged: (v) => setState(() => _agreeFollowup = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Information provided is accurate'),
                value: _agreeAccurate,
                onChanged: (v) => setState(() => _agreeAccurate = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title:
                const Text('I understand approval is not guaranteed'),
                value: _agreeNotGuaranteed,
                onChanged: (v) => setState(() => _agreeNotGuaranteed = v!),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        if (!_isReadOnly) ...[
          _PrimaryButton(
            label: _isSubmitting ? 'Submitting...' : "Submit",
            onTap: _isSubmitting ? null : _submitAdoptionForm,
          ),
          const SizedBox(height: 10),
          _SecondaryButton(
            label: 'Cancel',
            onTap: _isSubmitting ? null : () => Navigator.pop(context),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // 2nd step book appointment
  Widget _buildBookAppointment() {
    final slots = _slotsForDate;
    final isSunday = _appointmentDate != null &&
        _appointmentDate!.weekday == DateTime.sunday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Book appointment',
            style: GoogleFonts.tiltWarp(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Text('Just a few steps more.',
            style: GoogleFonts.zain(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          'As part of this process, we\'d like to schedule an interview with the organization to further assess suitability and answer any questions you may have.\n\nPlease choose a date that works best for you, and we\'ll confirm your appointment once your application has been reviewed.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        const SizedBox(height: 20),

        // visit type
        Row(
          children: kInterviewTypes.map((type) {
            final selected = _appointmentType == type;
            return GestureDetector(
              onTap: () => setState(() => _appointmentType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 10),
                padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.greenrspwn
                      : AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(type,
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // calendar
        Container(
          decoration: BoxDecoration(
            color: AppColors.yellowrspwn.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.greenrspwn, width: 1.2),
          ),
          child: Builder(
            builder: (context) {
              final firstDate = DateTime.now().add(const Duration(days: 1));
              final lastDate = DateTime.now().add(const Duration(days: 90));
              var initialDate = _appointmentDate ?? firstDate;
              if (initialDate.isBefore(firstDate)) initialDate = firstDate;
              if (initialDate.isAfter(lastDate)) initialDate = lastDate;
              // initialDate must itself be selectable — nudge off a Sunday
              // rather than let CalendarDatePicker's own assertion fail.
              if (isInterviewClosedDay(initialDate)) initialDate = initialDate.add(const Duration(days: 1));

              return CalendarDatePicker(
                initialDate: initialDate,
                firstDate: firstDate,
                lastDate: lastDate,
                // Sundays aren't just shown as unavailable — they can't be
                // tapped at all.
                selectableDayPredicate: (date) => !isInterviewClosedDay(date),
                onDateChanged: (picked) {
                  setState(() {
                    _appointmentDate = picked;
                    _appointmentTime = null;
                  });
                },
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // time slot selection
        Text(
          'Available times',
          style: GoogleFonts.tiltWarp(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),

        if (_appointmentDate == null)
          Text('Select a date above to see available times.',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textPrimary))
        else
          if (isSunday || slots.isEmpty)
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.slaterspwn.withOpacity(0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                isSunday
                    ? 'Closed on Sundays — please pick another day.'
                    : 'No slots available for this date.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textPrimary),
              ),
            )
          else
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: slots.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final slot = slots[i];
                  final selected = _appointmentTime == slot;
                  return GestureDetector(
                    onTap: () => setState(() => _appointmentTime = slot),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.greenrspwn
                            : AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected
                              ? AppColors.greenrspwn
                              : AppColors.slaterspwn,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        slot,
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

        // summary
        if (_appointmentDate != null && _appointmentTime != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available,
                    color: AppColors.greenrspwn, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_appointmentType  ·  ${_formatDate(
                        _appointmentDate!)}  ·  $_appointmentTime',
                    style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        if (!_isReadOnly)
          _PrimaryButton(
            label: _isSubmitting ? 'Booking...' : 'Book',
            onTap: (_appointmentDate == null || _appointmentTime == null ||
                _isSubmitting)
                ? null
                : _saveAppointment,
          ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 3rd step --- application review
  Widget _buildAppReview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application review',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'We\'ve received your interest in adopting ${widget.animal.name}.',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          'Please allow us time to review your form and confirm your appointment. If you need to reschedule, kindly update your meeting date at least 3 days before your appointment.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        // The actual booked interview date/time, so "confirm your
        // appointment" above isn't the only information the applicant sees
        // about a slot they already picked.
        if (_appointmentDate != null && _appointmentTime != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available, color: AppColors.greenrspwn, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_appointmentType  ·  ${_formatDate(_appointmentDate!)}  ·  $_appointmentTime',
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (!_isReadOnly) ...[
          const SizedBox(height: 28),
          _PrimaryButton(
            label: 'Change date',
            onTap: _isSubmitting ? null : _pickDate,
          ),

          const SizedBox(height: 12),
          _SecondaryButton(
            label: 'Withdraw Application',
            onTap: _isSubmitting ? null : _withdrawApplication,
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // 4th step --- meeting
  Widget _buildTimeToMeet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Time to meet! | Adoption Fee',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Your adoption application and interview appointment have been '
              'confirmed!',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              height: 1.4),
        ),
        const SizedBox(height: 6),
        Text(
          _feePaid
              ? 'Your adoption fee payment has been confirmed. We\'ll finalize '
              'the remaining requirements and prepare ${widget.animal.name} '
              'for their forever home.'
              : 'The next step is to complete your adoption fee payment to '
              'proceed with the adoption process. Once your payment has '
              'been confirmed, we\'ll finalize the remaining requirements '
              'and prepare your fur baby for their forever home. We are '
              'excited to get to know you as a potential adopter for '
              '${widget.animal.name}!',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        if (_appointmentDate != null) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withOpacity(0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.event_available,
                    color: AppColors.greenrspwn, size: 20),
                const SizedBox(width: 10),
                Text(
                  '${_appointmentType}  ·  ${_formatDate(_appointmentDate!)} ·  ${_appointmentTime!}',
                  style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ],

        if (_feePaid) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenrspwn.withOpacity(0.25),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    color: AppColors.greenrspwn, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Adoption fee paid'
                        '${_paymentMethod != null ? ' via $_paymentMethod' : ''}.',
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (_isReservedForMe) ...[
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.lavenderrspwn.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite, color: AppColors.textPrimary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${widget.animal.name} has been reserved for you!',
                      style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        ],

        if (!_isReadOnly) ...[
          const SizedBox(height: 28),
          if (!_feePaid)
            _PrimaryButton(
              label: 'Make Payment',
              onTap: _openReviewPayment,
            )
          else
          // The organization completes the actual handoff (Release
          // Animal, from the admin Adoption Application Review module) —
          // this screen just reflects that live once it happens, rather
          // than letting the applicant self-declare adoption complete.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.slaterspwn.withOpacity(0.35),
                borderRadius: BorderRadius.circular(30),
              ),
              child: Center(
                child: Text('Waiting for the organization to release the animal to you.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }

  // Opens the adoption-fee payment sheet (same presentation as the
  // donation flow's DonationReviewSheet). On a confirmed payment, the
  // sheet itself writes the 'payment' map + status history onto the
  // adoption doc and pops back with `true`, so we just flip local state to
  // reveal the "Adoption Day!" action without waiting for a full reload.
  Future<void> _openReviewPayment() async {
    if (_adoptionId == null) return;
    final paid = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewPaymentSheet(
        adoptionId: _adoptionId!,
        animalName: widget.animal.name,
        organizationName: 'Loved by the Gapz',
        feeAmount: adoptionFeeAmount,
        animalPhotoUrl: widget.animal.photoUrl,
      ),
    );

    if (paid == true && mounted) {
      setState(() => _feePaid = true);
      // Pull the confirmed method back from Firestore so the banner text
      // above is accurate without duplicating the write logic here.
      final doc = await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId)
          .get();
      final payment = (doc.data()?['payment'] as Map?) ?? {};
      if (mounted) {
        setState(() => _paymentMethod = payment['method'] as String?);
      }
    }
  }

  // 5th step -- adoption success
  Widget _buildAdoptionDay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Adoption Day!',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Congratulations on your new furry companion!',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'The organization will safely deliver your pet to your generalhome. You\'ll also receive an adoption agreement outlining terms and conditions, post-adoption guidelines, and return policies. For your convenience, you may review the Terms and Conditions in advance below.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),
        const SizedBox(height: 6),
        Text(
          'We\'re so happy for you and your new best friend!',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        const SizedBox(height: 16),

        Center(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => _TermsAndConditionsPage(
                    animalName: widget.animal.name,
                  ),
                ),
              );
            },
            child: Text(
              'View Terms and Conditions',
              style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.textPrimary,
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: 'Close',
          onTap: () {
            // Pop back to root (adoption list)
            Navigator.popUntil(context, (route) => route.isFirst);
          },
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 5th step --- adoption failed
  Widget _buildAppUpdate() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application Update',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Thank you for your interest in adopting ${widget.animal.name}.',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'After careful review, we feel this may not be the best match at this time.\n\nWe truly appreciate your willingness to give a rescue a loving generalhome, and we encourage you to consider other pets in need — your perfect companion could be waiting!',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: 'Close',
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),

        const SizedBox(height: 24),
      ],
    );
  }

  // 5th step --- application withdrawn by the adopter
  Widget _buildWithdrawn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Application Withdrawn',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'You\'ve withdrawn your adoption application for ${widget.animal.name}.',
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Text(
          'No further action is needed on your end. If you change your mind, you\'re welcome to submit a new application for this pet or explore other rescues looking for their forever home.',
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textPrimary, height: 1.5),
        ),

        const SizedBox(height: 28),

        _PrimaryButton(
          label: 'Okay',
          onTap: _isReadOnly
              ? null
              : () {
            // Confirming the withdrawal notice resets the whole process
            _resetProcessState();
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AdoptionPage()),
                  (route) => false,
            );
          },
        ),

        const SizedBox(height: 24),
      ],
    );
  }
}


// Review Payment sheet (Adoption Fee) — mirrors DonationReviewSheet's
// bottom-sheet design (donation_detail.dart) exactly: same handle bar,
// divider rhythm, bordered info/payment rows, and button styling, so the
// adoption fee flow feels like the same payment surface as donations.
//
// In production, "Pay" should call a Cloud Function that creates a
// PayMongo Payment Intent/Source for the selected method and amount, then
// either opens the returned checkout URL (card/e-wallet authorization) or
// polls/receives a webhook-driven update once PayMongo confirms the
// charge. That backend + webhook infrastructure isn't available in this
// environment, so the confirmation here is simulated — clearly marked
// below — while the surrounding UI, state, and Firestore write are the
// real integration points to keep when wiring PayMongo in.
class _ReviewPaymentSheet extends StatefulWidget {
  final String adoptionId;
  final String animalName;
  final String organizationName;
  final double feeAmount;
  // The animal's own real photo — kept entirely separate from the
  // applicant's uploaded Home Photos / documents (different fields,
  // different widgets); this summary card must never show either of those
  // instead of the animal itself.
  final String? animalPhotoUrl;

  const _ReviewPaymentSheet({
    required this.adoptionId,
    required this.animalName,
    required this.organizationName,
    required this.feeAmount,
    this.animalPhotoUrl,
  });

  @override
  State<_ReviewPaymentSheet> createState() => _ReviewPaymentSheetState();
}

class _ReviewPaymentSheetState extends State<_ReviewPaymentSheet> {
  String? _selectedPayment;
  bool _submitting = false;

  static const List<String> _paymentMethods = [
    'Credit Card',
    'PayPal',
    'GCash',
    'Maya',
  ];

  String get _formattedFee => widget.feeAmount % 1 == 0
      ? widget.feeAmount.toInt().toString()
      : widget.feeAmount.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Text('Review Payment',
                style: GoogleFonts.tiltWarp(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),

            const SizedBox(height: 16),

            // Adoption info row
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: widget.animalPhotoUrl != null
                      ? Image.network(
                    widget.animalPhotoUrl!,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _petThumbPlaceholder(),
                  )
                      : _petThumbPlaceholder(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Adopt ${widget.animalName}',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(widget.organizationName,
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              color: AppColors.textPrimary.withOpacity(0.7))),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            const Divider(thickness: 0.5),

            // Adoption fee (fixed by the organization — shown, not editable)
            Text('Adoption Fee',
                style: GoogleFonts.zain(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Container(
              height: 44,
              decoration: BoxDecoration(
                border:
                Border.all(color: AppColors.textPrimary.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('₱',
                        style: GoogleFonts.zain(
                            fontSize: 16, color: AppColors.textPrimary)),
                  ),
                  Text(_formattedFee,
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary)),
                ],
              ),
            ),

            const SizedBox(height: 16),
            const Divider(thickness: 0.5),

            // Payment method
            Text('Select Payment Method',
                style: GoogleFonts.zain(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            ..._paymentMethods.map((method) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: GestureDetector(
                onTap: _submitting
                    ? null
                    : () => setState(() => _selectedPayment = method),
                child: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedPayment == method
                          ? AppColors.textPrimary
                          : AppColors.textPrimary.withOpacity(0.2),
                      width: _selectedPayment == method ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _selectedPayment == method
                        ? AppColors.yellowrspwn.withOpacity(0.3)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Radio<String>(
                        value: method,
                        groupValue: _selectedPayment,
                        activeColor: AppColors.textPrimary,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: _submitting
                            ? null
                            : (v) => setState(() => _selectedPayment = v),
                      ),
                      Text(method,
                          style: GoogleFonts.zain(
                              fontSize: 14, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ),
            )),

            const SizedBox(height: 12),
            const Divider(thickness: 0.5),

            // Adoption fee summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Adoption Fee',
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary)),
                Text('₱$_formattedFee',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14, color: AppColors.textPrimary)),
              ],
            ),

            const SizedBox(height: 16),

            // Pay button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selectedPayment == null || _submitting)
                    ? null
                    : _pay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledBackgroundColor:
                  AppColors.yellowrspwn.withOpacity(0.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textPrimary),
                )
                    : Text('Pay',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pay() async {
    if (_selectedPayment == null) return;
    setState(() => _submitting = true);
    try {
      // ---- Simulated PayMongo confirmation (see class comment above) ----
      await Future.delayed(const Duration(milliseconds: 900));
      // --------------------------------------------------------------

      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(widget.adoptionId)
          .set({
        'payment': {
          'method': _selectedPayment,
          'amount': widget.feeAmount,
          'status': 'paid',
          'paidAt': Timestamp.now(),
          'paidBy': FirebaseAuth.instance.currentUser?.uid,
        },
        'statusHistory': FieldValue.arrayUnion([
          {
            'status':
            'Adoption fee payment received via $_selectedPayment.',
            'timestamp': Timestamp.now(),
          }
        ]),
      }, SetOptions(merge: true));

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _petThumbPlaceholder() => Container(
    width: 60,
    height: 60,
    decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
    child: const Icon(Icons.pets, size: 26, color: AppColors.textPrimary),
  );
}

// Terms and Conditions page (Adoption Day)
class _TermsAndConditionsPage extends StatelessWidget {
  final String animalName;

  const _TermsAndConditionsPage({required this.animalName});

  List<String> get _terms => [
    'I am over eighteen (18) years of age and can legally adopt.',
    '$animalName, hereinafter referred to as the pet, is being transferred '
        'to the adopting owner with the understanding that the adopter is '
        'taking possession of the pet to treat and be responsible for it as '
        'their own pet.',
    'The pet will be treated as a family member with loving care and '
        'affection. I/we will do my/our best to ensure the pet\'s safety and '
        'well-being.',
    'I/we will feed the pet at least twice a day and provide a fresh water '
        'supply at all times.',
    'I will not leave the pet outside my home and will not let it be '
        'isolated from the family. I will walk my pet on a leash or '
        'accompanied lead whenever I take my pet out, and will never keep it '
        'chained or tied up in a yard, garage, patio, balcony, or pen, or '
        'leave the pet outdoors, even in a fenced yard.',
    'I will not have the pet attack-trained, and will not use it for any '
        'purpose other than companionship. I will not have the pet\'s ears '
        'cropped, nor will I have its tail docked. I will never allow any '
        'physical, mental, or emotional abuse of the pet.',
    'I will take the pet to a licensed veterinarian when shots are due, but '
        'in no event later than one year after its last vet visit. I will '
        'ensure required and/or needed veterinary care, including rabies '
        'shots as required every one to three years, yearly booster shots '
        '(e.g. 5-in-1, 6-in-1 vaccines), and prompt treatment by a licensed '
        'veterinarian for any illness or injury.',
    'I/we affirm that no member of my household is allergic to or objects '
        'to keeping the pet, and that all household members have agreed to '
        'welcome the pet into the home.',
    'I/we agree to allow the organization to conduct reasonable post-'
        'adoption home visits or follow-up check-ins to ensure the pet\'s '
        'continued well-being.',
    'I/we understand that if, for any reason, I/we are no longer able to '
        'care for the pet, I/we will first return the pet to the '
        'organization rather than rehoming, abandoning, or surrendering it '
        'to another shelter or individual.',
    'I/we agree that a formal Adoption Agreement containing these terms '
        'will be reviewed and signed by both parties on the day of the '
        'adoption, and that this signed agreement will govern the adoption.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.chevron_left,
                    size: 30, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terms and Conditions',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Please read and agree to the following terms and '
                          'conditions before you continue. A formal Adoption '
                          'Agreement containing these terms will be reviewed '
                          'and signed by both parties on the day of the '
                          'adoption.',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                          height: 1.5),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'I hereby confirm the following terms and conditions '
                          'that:',
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(_terms.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${i + 1}.',
                                style: GoogleFonts.zain(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _terms[i],
                                style: GoogleFonts.zain(
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Step tracker widget
class _StepTracker extends StatelessWidget {
  final List<String> labels;
  final int activeIndex;
  final int? displayIndex;
  final bool rejected;
  final ValueChanged<int>? onStepTap;

  const _StepTracker({
    required this.labels,
    required this.activeIndex,
    this.displayIndex,
    this.rejected = false,
    this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(labels.length, (index) {
        final isDone = index < activeIndex;
        final isActive = index == activeIndex;
        final isReachable = index <= activeIndex;
        final isBeingViewed = displayIndex != null && index == displayIndex;

        return Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isReachable && onStepTap != null
                ? () => onStepTap!(index)
                : null,
            child: Column(
              children: [
                Row(
                  children: [
                    if (index != 0)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: isDone
                              ? AppColors.lavenderrspwn
                              : AppColors.slaterspwn,
                        ),
                      ),

                    Container(
                      width: isBeingViewed ? 18 : 14,
                      height: isBeingViewed ? 18 : 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDone || isActive
                            ? AppColors.lavenderrspwn
                            : Colors.transparent,
                        border: Border.all(
                          color: isBeingViewed
                              ? AppColors.yellowrspwn
                              : (isDone || isActive
                              ? AppColors.lavenderrspwn
                              : AppColors.slaterspwn),
                          width: isBeingViewed ? 2.5 : 1,
                        ),
                      ),
                      child: isDone
                          ? const Icon(
                        Icons.check,
                        size: 9,
                        color: AppColors.textPrimary,
                      )
                          : null,
                    ),

                    if (index != labels.length - 1)
                      Expanded(
                        child: Container(
                          height: 2,
                          color: index < activeIndex
                              ? AppColors.lavenderrspwn
                              : AppColors.slaterspwn,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 8),

                SizedBox(
                  width: 70,
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      fontWeight:
                      isActive ? FontWeight.w700 : FontWeight.w500,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _InfoTooltip extends StatefulWidget {
  final String message;

  const _InfoTooltip({required this.message});

  @override
  State<_InfoTooltip> createState() => _InfoTooltipState();
}

class _InfoTooltipState extends State<_InfoTooltip> {
  final GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        final dynamic tooltip = _tooltipKey.currentState;
        tooltip?.ensureTooltipVisible();
      },
      child: Tooltip(
        key: _tooltipKey,
        message: widget.message,
        preferBelow: true,
        triggerMode: TooltipTriggerMode.manual,
        showDuration: const Duration(seconds: 10),
        textStyle: GoogleFonts.zain(fontSize: 14, color: Colors.white),
        decoration: BoxDecoration(
          color: AppColors.textPrimary.withOpacity(0.95),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Icon(
          Icons.info_outline,
          size: 16,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: GoogleFonts.tiltWarp(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppColors.textPrimary),
    );
  }
}

// Reusable form field
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final int maxLines;
  final bool readOnly;
  final bool required;
  final String? Function(String?)? validator;
  final List<TextInputFormatter>? inputFormatters;

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.readOnly = false,
    this.required = true,
    this.validator,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (required)
              const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          readOnly: readOnly,
          inputFormatters: inputFormatters,
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
          validator: validator ??
              (required
                  ? (v) => (v == null || v.trim().isEmpty)
                  ? 'This field is required'
                  : null
                  : null),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textPrimary),
            filled: true,
            fillColor: readOnly
                ? AppColors.slaterspwn.withOpacity(0.3) : AppColors.yellowrspwn.withOpacity(0.3),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              BorderSide(color: AppColors.slaterspwn, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: AppColors.greenrspwn, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.2),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              const BorderSide(color: Colors.redAccent, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          value: value,
          items: items
              .map((e) => DropdownMenuItem(value: e, child: Text(e.toString())))
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.yellowrspwn.withOpacity(0.3),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.slaterspwn, width: 1),
            ),
          ),
        ),
      ],
    );
  }
}

class _RadioGroup<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> options;
  final ValueChanged<T?> onChanged;
  final bool required;

  const _RadioGroup({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            if (required)
              const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
          ],
        ),
        const SizedBox(height: 2),
        ...options.map((o) {
          return InkWell(
            onTap: () => onChanged(o),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Radio<T>(
                    value: o,
                    groupValue: value,
                    onChanged: onChanged,
                    activeColor: AppColors.greenrspwn,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      o.toString(),
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _CounterField extends StatelessWidget {
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool required;

  const _CounterField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  label,
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textPrimary),
                ),
                if (required)
                  const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
          ),
          _CounterButton(
            icon: Icons.remove,
            onTap: value > 0 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 28,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ),
          _CounterButton(
            icon: Icons.add,
            onTap: () => onChanged(value + 1),
          ),
        ],
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _CounterButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: onTap == null
                ? AppColors.slaterspwn.withOpacity(0.5)
                : AppColors.slaterspwn,
          ),
        ),
        child: Icon(icon,
            size: 14,
            color: onTap == null
                ? AppColors.textPrimary.withOpacity(0.5)
                : AppColors.textPrimary),
      ),
    );
  }
}

class _HomePhotosPicker extends StatelessWidget {
  final List<String> existingUrls;
  final List<File> newFiles;
  final bool isUploading;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemoveNew;

  const _HomePhotosPicker({
    required this.existingUrls,
    required this.newFiles,
    required this.isUploading,
    required this.onAdd,
    required this.onRemoveExisting,
    required this.onRemoveNew,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Home Photos', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(width: 4),
            const _InfoTooltip(
              message:
              'Upload clear photos of where your pet will live and spend most of its time.\n\n'
                  'Please include:\n'
                  '• The room or area where the pet will sleep/stay\n'
                  '• Any yard, balcony, or outdoor space it can access\n'
                  '• Fencing, gates, or enclosures (if any)\n'
                  '• General home layout so we can check it\'s pet-safe\n\n'
                  'This helps us confirm your home is a safe, suitable environment before approving the adoption.',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var i = 0; i < existingUrls.length; i++)
              _PhotoThumb(
                child: Image.network(existingUrls[i], fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                onRemove: () => onRemoveExisting(i),
              ),
            for (var i = 0; i < newFiles.length; i++)
              _PhotoThumb(
                child: Image.file(newFiles[i], fit: BoxFit.cover),
                onRemove: () => onRemoveNew(i),
              ),
            InkWell(
              onTap: isUploading ? null : onAdd,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.yellowrspwn.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenrspwn.withOpacity(0.6), width: 1.2),
                ),
                child: isUploading
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : const Center(child: Icon(Icons.add_a_photo_outlined, size: 24, color: AppColors.greenrspwn)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;
  const _PhotoThumb({required this.child, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 90,
      height: 90,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(width: 90, height: 90, child: child),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(color: Color(0xFFE05353), shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadBox extends StatelessWidget {
  final String label;
  final File? file;
  final bool isUploading;
  final VoidCallback onTap;
  final bool required;

  const _UploadBox({
    required this.label,
    required this.file,
    required this.onTap,
    this.isUploading = false,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
              if (required)
                const Text(' *', style: TextStyle(color: Colors.red, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: isUploading ? null : onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 130,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: file != null
                      ? AppColors.greenrspwn
                      : AppColors.greenrspwn.withOpacity(0.6),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: isUploading
                  ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
                  : file == null
                  ? const Center(
                child: Icon(Icons.add,
                    size: 26, color: AppColors.greenrspwn),
              )
                  : Image.file(file!, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }
}

// buttons
class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
          onTap == null ? AppColors.slaterspwn : AppColors.yellowrspwn,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _SecondaryButton({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.greenrspwn, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}