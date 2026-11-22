import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/core/utils/user_autofill.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_adoption.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart' show kCaregiverOptions;
import 'package:respawnd1/features/adoption/widgets/adoption_form_widgets.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_upload_widgets.dart';

/// Rescue gaps 6/10, step 1: the adoption request for a rescued animal, from
/// the reporter who said they want to adopt it or the user who registered
/// interest on Track Case. Saves `adoptions/{id}` with
/// `source: 'rescue_case'` and status pending; the organization confirms it
/// on Rescue Details. Every agreement in [kRescueAdoptionAgreements] must be
/// accepted.
///
/// Like the shelter adoption form, it also asks about pet experience,
/// lifestyle and what the adopter can afford, and needs a Government ID.
/// Those answers are saved as `petExperience`, `lifestyle` and
/// `uploads.governmentId`, in the same shape the adoption form saves them.
class RescueAdoptionFormPage extends StatefulWidget {
  const RescueAdoptionFormPage({super.key, required this.caseId, required this.caseData});

  final String caseId;
  final Map<String, dynamic> caseData;

  @override
  State<RescueAdoptionFormPage> createState() => _RescueAdoptionFormPageState();
}

class _RescueAdoptionFormPageState extends State<RescueAdoptionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _otherPets = TextEditingController();
  final _caretaker = TextEditingController();
  String? _homeType;
  bool _landlordAllowsPets = false;

  // Pet Experience (same questions as the adoption form).
  bool _hadPetsBefore = false;
  bool _hasCurrentPets = false;
  final Map<String, int> _currentPets = {'dogs': 0, 'cats': 0, 'birds': 0, 'fish': 0, 'reptiles': 0, 'other': 0};
  final _otherPetType = TextEditingController();
  String? _petsVaccinated;
  String? _petsSpayedNeutered;

  // Lifestyle & Care (same questions as the adoption form).
  String? _hoursAlone;
  String? _primaryCaregiver;
  String? _petStayLocation;
  final Map<String, bool> _canAfford = {
    'food': false,
    'vaccinations': false,
    'vetVisits': false,
    'emergencyMedicalCare': false,
    'grooming': false,
    'careSupplies': false,
  };

  // Required upload.
  final _picker = ImagePicker();
  File? _governmentIdFile;
  final Map<String, bool> _agreed = {for (final (k, _, _) in kRescueAdoptionAgreements) k: false};
  bool _saving = false;

  static const _homeTypes = ['Own house', 'Renting', 'Living with family', 'Other'];

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final u = (await FirebaseFirestore.instance.collection('users').doc(user.uid).get()).data() ?? const {};
    if (!mounted) return;
    setState(() {
      _name.text = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim();
      _phone.text = (u['phone'] ?? u['phoneNumber'] ?? '').toString();
      _email.text = user.email ?? (u['email'] ?? '').toString();
      _address.text = (u['address'] ?? '').toString();
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _otherPets, _caretaker, _otherPetType]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allAgreed => _agreed.values.every((v) => v);

  int get _totalCurrentPets => _currentPets.values.fold(0, (a, b) => a + b);

  /// The added questions that aren't form fields, still unanswered.
  List<String> _missingAnswers() => [
    if (_hasCurrentPets && _totalCurrentPets == 0) 'how many current pets you have',
    if (_hasCurrentPets && _currentPets['other']! > 0 && _otherPetType.text.trim().isEmpty) 'other pet type',
    if (_hasCurrentPets && _petsVaccinated == null) 'current pets vaccinated status',
    if (_hasCurrentPets && _petsSpayedNeutered == null) 'current pets spayed/neutered status',
    if (_hoursAlone == null) 'hours animal will be left alone',
    if (_primaryCaregiver == null) 'Primary Caregiver',
    if (_petStayLocation == null) 'where pet will stay',
  ];

  void _setHasCurrentPets(bool value) => setState(() {
    _hasCurrentPets = value;
    if (value) return;
    // Unticked: nothing hidden is saved.
    _currentPets.updateAll((_, _) => 0);
    _otherPetType.clear();
    _petsVaccinated = null;
    _petsSpayedNeutered = null;
  });

  Future<void> _pickGovernmentId() async {
    final picked = await pickImageWithSource(context, _picker, maxWidth: 1280);
    if (picked != null && mounted) setState(() => _governmentIdFile = File(picked.path));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final missing = _missingAnswers();
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnackBar('Please answer: ${missing.join(', ')}.', kind: AppMessageKind.error));
      return;
    }
    if (_governmentIdFile == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnackBar('Please upload your Government ID.', kind: AppMessageKind.error));
      return;
    }
    if (!_allAgreed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnackBar('Accept all the agreements to send your request.', kind: AppMessageKind.error));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    // So the next form that asks for an address can fill it in.
    UserAutofill.rememberAddress(_address.text);
    try {
      final c = widget.caseData;
      final orgId = (c['organizationId'] as String?) ?? '';
      final species = (c['animalType'] ?? (c['animals'] is List && (c['animals'] as List).isNotEmpty
          ? ((c['animals'] as List).first as Map)['species']
          : null) ??
          'Rescued animal')
          .toString();
      final now = Timestamp.now();
      final docRef = FirebaseFirestore.instance.collection('adoptions').doc();
      // Same storage path as the adoption form; storage.rules allows the
      // upload before the request document exists.
      final idRef = FirebaseStorage.instance.ref('adoptions/${docRef.id}/government_id.jpg');
      await idRef.putFile(_governmentIdFile!);
      final governmentIdUrl = await idRef.getDownloadURL();
      await docRef.set({
        'source': kRescueAdoptionSource,
        'caseId': widget.caseId,
        // Unowned report: stamped when an organization accepts the case
        // (stampRescueAdoptionOrganization in functions/rescue_adoption.js).
        if (orgId.isNotEmpty) 'organizationId': orgId,
        'status': 'pending',
        'personal': {
          'adopterId': uid,
          'adopterName': _name.text.trim(),
          'adopterPhone': _phone.text.trim(),
          'adopterEmail': _email.text.trim(),
          'animalName': 'Rescue #${widget.caseId.substring(0, 6)} ($species)',
        },
        'rescueApplication': {
          'address': _address.text.trim(),
          'homeType': _homeType,
          'landlordAllowsPets': _homeType == 'Renting' ? _landlordAllowsPets : null,
          'otherPets': _otherPets.text.trim(),
          'caretaker': _caretaker.text.trim(),
          'role': c['reporterId'] == uid ? 'reporter' : 'interested user',
        },
        // Same shape as the adoption form saves.
        'petExperience': {
          'hadPetsBefore': _hadPetsBefore,
          'hasCurrentPets': _hasCurrentPets,
          'currentPets': {..._currentPets, 'otherType': _otherPetType.text.trim()},
          'currentPetsVaccinated': _hasCurrentPets ? _petsVaccinated : 'Not Applicable',
          'currentPetsSpayedNeutered': _hasCurrentPets ? _petsSpayedNeutered : 'Not Applicable',
        },
        'lifestyle': {
          'hoursAlone': _hoursAlone,
          'primaryCaregiver': _primaryCaregiver,
          'petStayLocation': _petStayLocation,
          'canAfford': Map<String, bool>.from(_canAfford),
        },
        'uploads': {'governmentId': governmentIdUrl},
        'agreement': {
          for (final (k, _, _) in kRescueAdoptionAgreements) k: true,
          'acceptedAt': now,
          'pickupWindowHours': kAdopterPickupWindow.inHours,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'statusHistory': [
          {'status': 'Adoption request sent for a rescued animal.', 'timestamp': now},
        ],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          'Request sent. The organization will confirm it and tell you when the animal is ready for pickup.',
          kind: AppMessageKind.success));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnackBar('Could not send your request: $e', kind: AppMessageKind.error));
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Adopt this rescue', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'The organization reviews your request and confirms you as the adopter. You will be told when the animal '
                  'is ready for pickup.',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, decoration: _dec('Full name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            TextFormField(
              controller: _phone,
              decoration: _dec('Mobile number'),
              keyboardType: TextInputType.phone,
              validator: (v) => AppValidators.phFlexiblePhone(v, required: true),
            ),
            TextFormField(
              controller: _email,
              decoration: _dec('Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => AppValidators.email(v, required: false),
            ),
            TextFormField(controller: _address, decoration: _dec('Home address'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _homeType,
              decoration: _dec('Home'),
              items: [for (final h in _homeTypes) DropdownMenuItem(value: h, child: Text(h))],
              onChanged: (v) => setState(() => _homeType = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            if (_homeType == 'Renting')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _landlordAllowsPets,
                onChanged: (v) => setState(() => _landlordAllowsPets = v),
                title: Text('My landlord allows pets', style: GoogleFonts.zain(fontSize: 14)),
              ),
            TextFormField(controller: _otherPets, decoration: _dec('Other pets at home (or "None")'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            TextFormField(controller: _caretaker, decoration: _dec('Who will mainly care for the animal'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 18),

            // Pet Experience
            Text('Pet Experience', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Owned pets before?', style: GoogleFonts.zain(fontSize: 14)),
              value: _hadPetsBefore,
              onChanged: (v) => setState(() => _hadPetsBefore = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('I currently have pets', style: GoogleFonts.zain(fontSize: 14)),
              value: _hasCurrentPets,
              onChanged: (v) => _setHasCurrentPets(v ?? false),
            ),
            if (_hasCurrentPets) ...[
              for (final (key, label) in const [
                ('dogs', 'Dogs'),
                ('cats', 'Cats'),
                ('birds', 'Birds'),
                ('fish', 'Fish'),
                ('reptiles', 'Reptiles'),
                ('other', 'Other'),
              ])
                AdoptionCounterField(
                  label: label,
                  value: _currentPets[key]!,
                  onChanged: (v) => setState(() => _currentPets[key] = v),
                ),
              if (_currentPets['other']! > 0)
                TextFormField(controller: _otherPetType, decoration: _dec('Specify other pet type')),
              const SizedBox(height: 12),
              AdoptionRadioGroup<String>(
                label: 'Are all current pets vaccinated?',
                value: _petsVaccinated,
                options: const ['Yes', 'Some', 'None'],
                onChanged: (v) => setState(() => _petsVaccinated = v),
              ),
              const SizedBox(height: 12),
              AdoptionRadioGroup<String>(
                label: 'Are all current pets spayed/neutered?',
                value: _petsSpayedNeutered,
                options: const ['Yes', 'Some', 'None'],
                onChanged: (v) => setState(() => _petsSpayedNeutered = v),
              ),
            ],
            const SizedBox(height: 18),

            // Lifestyle & Care
            Text('Lifestyle & Care', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            AdoptionRadioGroup<String>(
              label: 'Hours animal will be left alone',
              value: _hoursAlone,
              options: const ['Less than 2 hours', '2-4', '5-8', 'More than 8 hours'],
              onChanged: (v) => setState(() => _hoursAlone = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _primaryCaregiver,
              decoration: _dec('Primary Caregiver'),
              items: [for (final o in kCaregiverOptions) DropdownMenuItem(value: o, child: Text(o))],
              onChanged: (v) => setState(() => _primaryCaregiver = v),
            ),
            const SizedBox(height: 12),
            AdoptionRadioGroup<String>(
              label: 'Where will pet stay?',
              value: _petStayLocation,
              options: const ['Indoors', 'Outdoors', 'Mixed'],
              onChanged: (v) => setState(() => _petStayLocation = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Can you afford? (check all that apply)',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                const AdoptionInfoTooltip(
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
            for (final (key, label) in const [
              ('food', 'Food'),
              ('vaccinations', 'Vaccinations'),
              ('vetVisits', 'Vet Visits'),
              ('emergencyMedicalCare', 'Emergency Medical Care'),
              ('grooming', 'Grooming'),
              ('careSupplies', 'Care Supplies'),
            ])
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                value: _canAfford[key],
                onChanged: (v) => setState(() => _canAfford[key] = v ?? false),
              ),
            const SizedBox(height: 18),

            // Required upload
            Text('Required Upload', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            AdoptionUploadRow(
              label: 'Government ID',
              file: _governmentIdFile,
              onPick: _pickGovernmentId,
              onRemove: () => setState(() => _governmentIdFile = null),
            ),
            const SizedBox(height: 18),
            Text('Agreements', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            for (final (key, title, body) in kRescueAdoptionAgreements)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed[key],
                onChanged: (v) => setState(() => _agreed[key] = v ?? false),
                title: Text(title, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
                subtitle: Text(body, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving || !_allAgreed ? null : _submit,
              style: AppButtons.primary,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Send adoption request', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
