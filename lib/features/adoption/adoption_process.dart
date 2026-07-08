import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'adoption_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

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
  'Time to meet!',
  'Adoption Day',
];


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
  String? _city;

  // Household & Living Information
  String? _residenceType;
  final _residenceOtherCtrl = TextEditingController();
  String? _ownershipStatus;
  bool _allowsPets = false;
  int _householdMembers = 0;

  //Pet Experience
  bool _hadPetsBefore = false;
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
  final _caregiverCtrl = TextEditingController();
  String? _petStayLocation;
  bool _canAffordFood = false;
  bool _canAffordVaccinations = false;
  bool _canAffordVetVisits = false;
  bool _canAffordEmergencyCare = false;
  bool _canAffordGrooming = false;
  bool _canAffordCareSupplies= false;
  String? _monthlyBudget;
  final _reasonCtrl = TextEditingController();

  //Required Uploads
  File? _governmentIdFile;
  File? _proofOfAddressFile;
  File? _digitalSignatureFile;
  File? _homePhotosFile;

  String? _governmentIdUrl;
  String? _proofOfAddressUrl;
  String? _digitalSignatureUrl;
  String? _homePhotosUrl;

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

  // Appointment
  DateTime? _appointmentDate;
  String _appointmentType = 'On-site Visit';
  String? _appointmentTime;

  // timeslots
  static const Map<int, List<String>> _timeSlots = {
    0: ['9:00 AM', '10:00 AM', '11:00 AM', '2:00 PM', '3:00 PM', '4:00 PM'],
    1: [
      '9:00 AM',
      '10:00 AM',
      '11:00 AM',
      '1:00 PM',
      '2:00 PM',
      '3:00 PM',
      '4:00 PM'
    ],
    2: ['10:00 AM', '11:00 AM', '2:00 PM', '3:00 PM'],
    3: ['9:00 AM', '10:00 AM', '11:00 AM', '1:00 PM', '3:00 PM', '4:00 PM'],
    4: ['9:00 AM', '10:00 AM', '2:00 PM', '3:00 PM', '4:00 PM'],
    5: ['10:00 AM', '11:00 AM', '12:00 PM'],
    6: [], // Sunday – closed
  };

  List<String> get _slotsForDate {
    if (_appointmentDate == null) return [];
    final dow = (_appointmentDate!.weekday - 1) % 7;
    return _timeSlots[dow] ?? [];
  }

  @override
  void initState() {
    super.initState();
    if (widget.existingAdoptionId != null) {
      _isLoadingExisting = true;
      _loadExistingAdoption();
    } else {
      _prefillFromAccount();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _residenceOtherCtrl.dispose();
    _currentOtherTypeCtrl.dispose();
    _caregiverCtrl.dispose();
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

  //upload helper
  Future<String?> _uploadFile(File? file, String pathSegment, String adoptionId) async {
    if (file == null) return null;
    final ref = FirebaseStorage.instance
        .ref('adoptions/$adoptionId/$pathSegment.jpg');
    await ref.putFile(file);
    return await ref.getDownloadURL();
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

  _AdoptionProcess _stepForStatus(String? status) {
    switch (status) {
      case 'pending_appointment':
        return _AdoptionProcess.bookAppointment;
      case 'under_review':
        return _AdoptionProcess.appReview;
      case 'appointment_confirmed':
        return _AdoptionProcess.timeToMeet;
      case 'completed':
        return _AdoptionProcess.adoptionDay;
      case 'return_requested':
        return _AdoptionProcess.adoptionDay;
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

  // Reloads every saved answer from a previously-submitted application so
  // the person can see exactly what they entered instead of a blank form.
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
        _city = personal['adopterCity'] as String?;

        // Household & Living Information
        _residenceType = household['residenceType'] as String?;
        _residenceOtherCtrl.text =
            household['residenceOther'] as String? ?? '';
        _ownershipStatus = household['ownershipStatus'] as String?;
        _allowsPets = household['landlordAllowsPets'] as bool? ?? false;
        _householdMembers = household['householdMembers'] as int? ?? 0;

        // Pet Experience
        _hadPetsBefore = petExperience['hadPetsBefore'] as bool? ?? false;
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
        _caregiverCtrl.text = lifestyle['primaryCaregiver'] as String? ?? '';
        _petStayLocation = lifestyle['petStayLocation'] as String?;
        _canAffordFood = canAfford['food'] as bool? ?? false;
        _canAffordVaccinations = canAfford['vaccinations'] as bool? ?? false;
        _canAffordVetVisits = canAfford['vetVisits'] as bool? ?? false;
        _canAffordEmergencyCare =
            canAfford['emergencyMedicalCare'] as bool? ?? false;
        _canAffordGrooming = canAfford['grooming'] as bool? ?? false;
        _canAffordCareSupplies = canAfford['careSupplies'] as bool? ?? false;
        _monthlyBudget = lifestyle['monthlyBudget'] as String?;
        _reasonCtrl.text = agreement['reason'] as String? ?? '';

        // Required Uploads (already uploaded — keep the saved URLs)
        _governmentIdUrl = uploads['governmentId'] as String?;
        _proofOfAddressUrl = uploads['proofOfAddress'] as String?;
        _digitalSignatureUrl = uploads['digitalSignature'] as String?;
        _homePhotosUrl = uploads['homePhotos'] as String?;

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

        _step = _stepForStatus(data['status'] as String?);
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

      // Safety net: don't allow a second non-rejected adoption for the same
      // animal, even if the entry-point check was somehow bypassed.
      final existing = await FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalId', isEqualTo: widget.animal.id)
          .get();

      final stillActiveOrDone = existing.docs.any((doc) {
        final data = doc.data();
        final status = data['status'] as String? ?? '';
        return status != 'rejected' && status != 'withdrawn';
      });

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

      final results = await Future.wait([
        _uploadFile(_governmentIdFile, 'government_id', docRef.id),
        _uploadFile(_proofOfAddressFile, 'proof_of_address', docRef.id),
        _uploadFile(_digitalSignatureFile, 'digital_signature', docRef.id),
        _uploadFile(_homePhotosFile, 'home_photos', docRef.id),
      ]);

      _governmentIdUrl = results[0];
      _proofOfAddressUrl = results[1];
      _digitalSignatureUrl = results[2];
      _homePhotosUrl = results[3];

      await docRef.set({
        'personal': {
          'adopterId': uid,
          'animalId': widget.animal.id,
          'animalName': widget.animal.name,
          'adopterName': _nameCtrl.text.trim(),
          'adopterEmail': _emailCtrl.text.trim(),
          'adopterAge': _ageCtrl.text.trim(),
          'adopterPhone': _phoneCtrl.text.trim(),
          'adopterCity': _city,
        },
        'household': {
          'residenceType': _residenceType,
          'residenceOther': _residenceType == 'Other'
              ? _residenceOtherCtrl.text.trim()
              : null,
          'ownershipStatus': _ownershipStatus,
          'landlordAllowsPets':
          _ownershipStatus == 'Renting' ? _allowsPets : null,
          'householdMembers': _householdMembers,
        },
        'petExperience': {
          'hadPetsBefore': _hadPetsBefore,
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
          'primaryCaregiver': _caregiverCtrl.text.trim(),
          'petStayLocation': _petStayLocation,
          'canAfford': {
            'food': _canAffordFood,
            'vaccinations': _canAffordVaccinations,
            'vetVisits': _canAffordVetVisits,
            'emergencyMedicalCare': _canAffordEmergencyCare,
            'grooming': _canAffordGrooming,
            'careSupplies':  _canAffordCareSupplies,

          },
          'monthlyBudget': _monthlyBudget,
        },
        'uploads': {
          'governmentId': _governmentIdUrl,
          'proofOfAddress': _proofOfAddressUrl,
          'digitalSignature': _digitalSignatureUrl,
          'homePhotos': _homePhotosUrl,
        },
        'agreement': {
          'reason': _reasonCtrl.text.trim(),
          'care': _agreeCare,
          'noAbandon': _agreeNoAbandon,
          'followUp': _agreeFollowup,
          'infoAccurate': _agreeAccurate,
          'approvalNotGuaranteed': _agreeNotGuaranteed,
        },
        'status': 'pending_appointment',
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
        'status': 'under_review',
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

  Future<void> _updateStatus(String status,
      String statusMessage,
      _AdoptionProcess nextStep,) async {
    if (_adoptionId == null) return;
    setState(() => _isSubmitting = true);

    try {
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(_adoptionId)
          .update({
        'status': status,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': statusMessage,
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      setState(() => _step = nextStep);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Application withdrawn by adopter.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

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
                  Text(
                    'Adopt ${widget.animal.name}',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Tracker
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _StepTracker(
                labels: _stepLabels,
                activeIndex: _activeStepIndex,
                rejected: _step == _AdoptionProcess.appReject ||
                    _step == _AdoptionProcess.withdrawn,
              ),
            ),

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
                child: _buildStepBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // switcher
  Widget _buildStepBody() {
    switch (_step) {
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
              _FormField(controller: _nameCtrl, label: 'Name', hint: ' '),
              const SizedBox(height: 12),
              _FormField(
                  controller: _emailCtrl,
                  label: 'Email',
                  hint: 'Email@email.com',
                  keyboardType: TextInputType.emailAddress),
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
                        keyboardType: TextInputType.phone),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FormField(
                        controller: _ageCtrl,
                        label: 'Age',
                        hint: ' ',
                        keyboardType: TextInputType.number),
                  ),
                ],
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
                options: const ['Owned', 'Renting', 'Living with Parents'],
                onChanged: (v) => setState(() => _ownershipStatus = v),
              ),
              if (_ownershipStatus == 'Renting') ...[
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('If renting, landlord allows pets',
                      style: GoogleFonts.zain(fontSize: 14)),
                  value: _allowsPets,
                  onChanged: (v) => setState(() => _allowsPets = v),
                ),
              ],
              const SizedBox(height: 12),
              _CounterField(
                label: 'Number of Household Members',
                value: _householdMembers,
                onChanged: (v) => setState(() => _householdMembers = v),
              ),

              const SizedBox(height: 22),

              // Pet Experience
              _SectionTitle('Pet Experience'),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Owned pets before?',
                    style: GoogleFonts.zain(fontSize: 14)),
                value: _hadPetsBefore,
                onChanged: (v) => setState(() => _hadPetsBefore = v),
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
                options: const ['Yes', 'Some', 'None', 'Not Applicable'],
                onChanged: (v) => setState(() => _petsVaccinated = v),
              ),
              const SizedBox(height: 16),
              _RadioGroup<String>(
                label: 'Are all current pets spayed/neutered?',
                value: _petsSpayedNeutered,
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
                options: const [
                  'Less than 2 hours',
                  '2-4',
                  '5-8',
                  'More than 8 hours'
                ],
                onChanged: (v) => setState(() => _hoursAlone = v),
              ),
              const SizedBox(height: 12),
              _FormField(
                  controller: _caregiverCtrl,
                  label: 'Primary Caregiver',
                  hint: 'Enter'),
              const SizedBox(height: 16),
              _RadioGroup<String>(
                label: 'Where will pet stay?',
                value: _petStayLocation,
                options: const ['Indoors', 'Outdoors', 'Mixed'],
                onChanged: (v) => setState(() => _petStayLocation = v),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text('Can you afford? (check all that apply)',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
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
              _RadioGroup<String>(
                label: 'Monthly Pet Budget',
                value: _monthlyBudget,
                options: const [
                  'Under P1,000',
                  'P1,000-P3,000',
                  'P3,000-P5,000',
                  'Above P5,000'
                ],
                onChanged: (v) => setState(() => _monthlyBudget = v),
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
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _governmentIdFile = f),
                    ),
                  ),
                  _UploadBox(
                    label: 'Proof of Address',
                    file: _proofOfAddressFile,
                    isUploading: _isUploadingProof,
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _proofOfAddressFile = f),
                    ),
                  ),
                  _UploadBox(
                    label: 'Digital Signature',
                    file: _digitalSignatureFile,
                    isUploading: _isUploadingSignature,
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _digitalSignatureFile = f),
                    ),
                  ),
                  _UploadBox(
                    label: 'Home Photos',
                    file: _homePhotosFile,
                    isUploading: _isUploadingHomePhotos,
                    onTap: () => _pickUploadFile(
                      onPicked: (f) => setState(() => _homePhotosFile = f),
                    ),
                  ),
                ],
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

        _PrimaryButton(
          label: _isSubmitting ? 'Submitting...' : "Submit",
          onTap: _isSubmitting ? null : _submitAdoptionForm,
        ),
        const SizedBox(height: 10),
        _SecondaryButton(
          label: 'Cancel',
          onTap: _isSubmitting ? null : () => Navigator.pop(context),
        ),

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
          children: ['On-site Visit', 'Online'].map((type) {
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
          child: CalendarDatePicker(
            initialDate: _appointmentDate ??
                DateTime.now().add(const Duration(days: 1)),
            firstDate: DateTime.now().add(const Duration(days: 1)),
            lastDate: DateTime.now().add(const Duration(days: 90)),
            onDateChanged: (picked) {
              setState(() {
                _appointmentDate = picked;
                _appointmentTime = null;
              });
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

        const SizedBox(height: 12),

        // ---------- for testing only!!
        Row(
          children: [
            Expanded(
              child: _SecondaryButton(
                label: 'Approved →',
                onTap: _isSubmitting
                    ? null
                    : () =>
                    _updateStatus('appointment_confirmed',
                      'Application approved. Appointment confirmed.',
                      _AdoptionProcess.timeToMeet,),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _SecondaryButton(
                label: 'Rejected →',
                onTap: _isSubmitting
                    ? null
                    : () =>
                    _updateStatus('rejected', 'Application was not approved.',
                      _AdoptionProcess.appReject,),
              ),
            ),
          ],
        ),
        // ---------- for testing only ^^^^

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
          'Time to meet!',
          style: GoogleFonts.tiltWarp(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 12),
        Text(
          'Your adoption application and interview appointment have been confirmed! We are excited to get to know you as a potential adopter for ${widget
              .animal.name} for today!',
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

        const SizedBox(height: 28),

        _PrimaryButton(
          label: _isSubmitting ? 'Updating...' : 'Adoption Day!',
          onTap: _isSubmitting
              ? null
              : () =>
              _updateStatus('completed', 'Adoption Completed!',
                _AdoptionProcess.adoptionDay,),
        ),

        const SizedBox(height: 24),
      ],
    );
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
          label: 'Close',
          onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
        ),

        const SizedBox(height: 24),
      ],
    );
  }
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
  final bool rejected;

  const _StepTracker({
    required this.labels,
    required this.activeIndex,
    this.rejected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(labels.length, (index) {
        final isDone = index < activeIndex;
        final isActive = index == activeIndex;

        return Expanded(
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
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDone || isActive
                          ? AppColors.lavenderrspwn
                          : Colors.transparent,
                      border: Border.all(
                        color: isDone || isActive
                            ? AppColors.lavenderrspwn
                            : AppColors.slaterspwn,
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

  const _FormField({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.readOnly = false,
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
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          readOnly: readOnly,
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
          validator: (v) =>
          (v == null || v.trim().isEmpty) ? 'This field is required' : null,
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

  const _RadioGroup({
    required this.label,
    required this.value,
    required this.options,
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

  const _CounterField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary),
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

class _UploadBox extends StatelessWidget {
  final String label;
  final File? file;
  final bool isUploading;
  final VoidCallback onTap;

  const _UploadBox({
    required this.label,
    required this.file,
    required this.onTap,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
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