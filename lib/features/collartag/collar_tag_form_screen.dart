import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app_theme.dart';
import 'collar_tag_data_model.dart';
import 'collar_id_tag_screen.dart';

class CollarTagFormScreen extends StatefulWidget {
  const CollarTagFormScreen({super.key});

  @override
  State<CollarTagFormScreen> createState() => _CollarTagFormScreenState();
}

class _CollarTagFormScreenState extends State<CollarTagFormScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0; // 0 = pet info, 1 = health + owner info

  // Controllers – Pet Info
  final _nameCtrl = TextEditingController();
  final _birthdayCtrl = TextEditingController();
  final _sexCtrl = TextEditingController();
  final _breedCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  // Controllers – Health
  bool _spayedNeutered = false;
  bool _vaccinated = false;
  File? _vaccinationImage;
  final _allergiesCtrl = TextEditingController();
  final _medicalCtrl = TextEditingController();

  // Controllers – Owner
  final _ownerNameCtrl = TextEditingController();
  final _ownerMobileCtrl = TextEditingController();

  // Pet image
  File? _petImage;
  bool _submitting = false;

  final _picker = ImagePicker();

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _birthdayCtrl, _sexCtrl, _breedCtrl, _colorCtrl, _descCtrl,
      _allergiesCtrl, _medicalCtrl, _ownerNameCtrl, _ownerMobileCtrl
    ]) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickPetImage() async {
    final xf = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xf != null) setState(() => _petImage = File(xf.path));
  }

  Future<void> _pickVaccinationImage() async {
    final xf = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xf != null) setState(() => _vaccinationImage = File(xf.path));
  }

  void _nextPage() {
    if (_currentPage == 0) {
      _pageController.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentPage = 1);
    } else {
      _submit();
    }
  }

  Future<String?> _uploadImage(File file, String path) async {
    try {
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty || _ownerNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in pet name and owner name.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final tagRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('collarTags')
          .doc();

      final tagId = tagRef.id;

      // Upload images
      String? petImageUrl;
      String? vacImageUrl;

      if (_petImage != null) {
        petImageUrl = await _uploadImage(
            _petImage!, 'collar_tags/$uid/$tagId/pet.jpg');
      }
      if (_vaccinationImage != null) {
        vacImageUrl = await _uploadImage(
            _vaccinationImage!, 'collar_tags/$uid/$tagId/vaccination.jpg');
      }

      final tagData = CollarTagData(
        tagId: tagId,
        petImageUrl: petImageUrl,
        petImagePath: _petImage?.path,
        name: _nameCtrl.text.trim(),
        birthday: _birthdayCtrl.text.trim(),
        sex: _sexCtrl.text.trim(),
        breed: _breedCtrl.text.trim(),
        colorMarkings: _colorCtrl.text.trim(),
        briefDescription: _descCtrl.text.trim(),
        isSpayedNeutered: _spayedNeutered,
        isVaccinated: _vaccinated,
        vaccinationImageUrl: vacImageUrl,
        vaccinationImagePath: _vaccinationImage?.path,
        allergies: _allergiesCtrl.text.trim(),
        medicalCondition: _medicalCtrl.text.trim(),
        ownerName: _ownerNameCtrl.text.trim(),
        ownerMobile: _ownerMobileCtrl.text.trim(),
        createdAt: DateTime.now(),
      );

      // Save to user's collar tags
      await tagRef.set({
        ...tagData.toFirestore(),
        'tagId': tagId,
        'ownerId': uid,
      });

      // Also save to global public collection (for QR scan lookup)
      await FirebaseFirestore.instance
          .collection('collarTags')
          .doc(tagId)
          .set({
        ...tagData.toFirestore(),
        'tagId': tagId,
        'ownerId': uid,
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => CollarIdTagCardScreen(
              tagData: tagData,
              isNewlyCreated: true,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () {
            if (_currentPage == 1) {
              _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut);
              setState(() => _currentPage = 0);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        centerTitle: true,
        title: Text(
          'Create Collar Tags',
          style: GoogleFonts.tiltWarp(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          _PetInfoPage(
            petImage: _petImage,
            onPickImage: _pickPetImage,
            nameCtrl: _nameCtrl,
            birthdayCtrl: _birthdayCtrl,
            sexCtrl: _sexCtrl,
            breedCtrl: _breedCtrl,
            colorCtrl: _colorCtrl,
            descCtrl: _descCtrl,
            spayedNeutered: _spayedNeutered,
            vaccinated: _vaccinated,
            vaccinationImage: _vaccinationImage,
            onSpayedChanged: (v) => setState(() => _spayedNeutered = v),
            onVaccinatedChanged: (v) => setState(() => _vaccinated = v),
            onPickVaccination: _pickVaccinationImage,
            onNext: _nextPage,
            showNextOnly: true,
          ),
          _HealthOwnerPage(
            spayedNeutered: _spayedNeutered,
            vaccinated: _vaccinated,
            vaccinationImage: _vaccinationImage,
            onSpayedChanged: (v) => setState(() => _spayedNeutered = v),
            onVaccinatedChanged: (v) => setState(() => _vaccinated = v),
            onPickVaccination: _pickVaccinationImage,
            allergiesCtrl: _allergiesCtrl,
            medicalCtrl: _medicalCtrl,
            ownerNameCtrl: _ownerNameCtrl,
            ownerMobileCtrl: _ownerMobileCtrl,
            submitting: _submitting,
            onGenerate: _nextPage,
          ),
        ],
      ),
      ),
    );
  }
}

// ─── Page 1: Pet Info ────────────────────────────────────────────────────────

class _PetInfoPage extends StatelessWidget {
  final File? petImage;
  final VoidCallback onPickImage;
  final TextEditingController nameCtrl, birthdayCtrl, sexCtrl, breedCtrl,
      colorCtrl, descCtrl;
  final bool spayedNeutered, vaccinated;
  final File? vaccinationImage;
  final ValueChanged<bool> onSpayedChanged, onVaccinatedChanged;
  final VoidCallback onPickVaccination;
  final VoidCallback onNext;
  final bool showNextOnly;

  const _PetInfoPage({
    required this.petImage,
    required this.onPickImage,
    required this.nameCtrl,
    required this.birthdayCtrl,
    required this.sexCtrl,
    required this.breedCtrl,
    required this.colorCtrl,
    required this.descCtrl,
    required this.spayedNeutered,
    required this.vaccinated,
    required this.vaccinationImage,
    required this.onSpayedChanged,
    required this.onVaccinatedChanged,
    required this.onPickVaccination,
    required this.onNext,
    required this.showNextOnly,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _sectionLabel('Pet Information'),
          const SizedBox(height: 10),

          // Pet image picker
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onPickImage,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.textPrimary.withOpacity(0.3),
                        style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.tearspwn.withOpacity(0.3),
                  ),
                  child: petImage != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(petImage!, fit: BoxFit.cover),
                  )
                      : const Center(
                    child: Icon(Icons.add,
                        size: 32, color: AppColors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Insert Pet Image',
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textPrimary)),
                  const Text(' *',
                      style: TextStyle(color: Colors.red, fontSize: 13)),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          _field(nameCtrl, 'Name'),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(birthdayCtrl, 'Birthday')),
            const SizedBox(width: 10),
            Expanded(child: _field(sexCtrl, 'Sex')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _field(breedCtrl, 'Breed')),
            const SizedBox(width: 10),
            Expanded(child: _field(colorCtrl, 'Color/Markings')),
          ]),
          const SizedBox(height: 10),
          _sectionLabel('Brief Pet Description'),
          const SizedBox(height: 6),
          _field(descCtrl, 'Enter description'),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _HealthOwnerPage extends StatelessWidget {
  final bool spayedNeutered, vaccinated;
  final File? vaccinationImage;
  final ValueChanged<bool> onSpayedChanged, onVaccinatedChanged;
  final VoidCallback onPickVaccination;
  final TextEditingController allergiesCtrl, medicalCtrl,
      ownerNameCtrl, ownerMobileCtrl;
  final bool submitting;
  final VoidCallback onGenerate;

  const _HealthOwnerPage({
    required this.spayedNeutered,
    required this.vaccinated,
    required this.vaccinationImage,
    required this.onSpayedChanged,
    required this.onVaccinatedChanged,
    required this.onPickVaccination,
    required this.allergiesCtrl,
    required this.medicalCtrl,
    required this.ownerNameCtrl,
    required this.ownerMobileCtrl,
    required this.submitting,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _sectionLabel('Health Information'),
          const SizedBox(height: 8),
          _CheckRow(
              label: 'Spayed/Neutered',
              value: spayedNeutered,
              onChanged: onSpayedChanged),
          _CheckRow(
              label: 'Vaccinated',
              value: vaccinated,
              onChanged: onVaccinatedChanged),
          const SizedBox(height: 10),

          // Vaccination image
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onPickVaccination,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: AppColors.textPrimary.withOpacity(0.3),
                        style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(8),
                    color: AppColors.tearspwn.withOpacity(0.3),
                  ),
                  child: vaccinationImage != null
                      ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(vaccinationImage!, fit: BoxFit.cover),
                  )
                      : const Center(
                    child: Icon(Icons.add,
                        size: 28, color: AppColors.textPrimary),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('Vaccination Record\nImage',
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary)),
            ],
          ),

          const SizedBox(height: 14),
          _sectionLabel('Allergies'),
          const SizedBox(height: 6),
          _field(allergiesCtrl, 'Enter condition'),
          const SizedBox(height: 10),
          _sectionLabel('Current/Existing Medical Condition'),
          const SizedBox(height: 6),
          _field(medicalCtrl, 'Enter condition'),

          const SizedBox(height: 16),
          _sectionLabel('Owner Information'),
          const SizedBox(height: 10),
          _field(ownerNameCtrl, 'Name'),
          const SizedBox(height: 10),
          _field(ownerMobileCtrl, 'Mobile Number',
              keyboardType: TextInputType.phone),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: submitting ? null : onGenerate,
              style: ElevatedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: submitting
                  ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textPrimary),
              )
                  : Text('Generate Collar Tag',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary)),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// Shared helpers

Widget _sectionLabel(String text) => Text(
  text,
  style: GoogleFonts.tiltWarp(fontSize: 13, color: AppColors.textPrimary),
);

Widget _field(
    TextEditingController ctrl,
    String label, {
      TextInputType keyboardType = TextInputType.text,
      int maxLines = 1,
    }) =>
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 4),

        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: GoogleFonts.zain(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: label,
            hintStyle: GoogleFonts.zain(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),

            filled: true,
            fillColor: AppColors.background.withOpacity(0.3),

            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),

            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.slaterspwn,
                width: 1,
              ),
            ),

            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.greenrspwn,
                width: 1.5,
              ),
            ),
          ),
        ),
      ],
    );

class _CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CheckRow(
      {required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Radio<bool>(
            value: true,
            groupValue: value ? true : null,
            activeColor: AppColors.textPrimary,
            onChanged: (_) => onChanged(!value),
          ),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.zain(
                fontSize: 14, color: AppColors.textPrimary)),
      ],
    );
  }
}