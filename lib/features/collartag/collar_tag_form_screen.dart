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
  final CollarTagData? existingTag;

  const CollarTagFormScreen({
    super.key,
    this.existingTag,
  });

  @override
  State<CollarTagFormScreen> createState() => _CollarTagFormScreenState();
}

class _CollarTagFormScreenState extends State<CollarTagFormScreen> {
  // Pet Info
  final _nameCtrl = TextEditingController();
  final _breedCtrl = TextEditingController(); // specific breed
  final _colorCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  DateTime? _birthdayDate;
  String _birthdayRawFallback = '';
  String? _sex; // 'M' or 'F'
  String? _petType; // 'Dog' or 'Cat'

  // Health
  bool _spayedNeutered = false;
  bool _vaccinated = false;
  File? _vaccinationImage;

  bool _hasAllergies = false;
  final _allergiesCtrl = TextEditingController();

  bool _hasMedicalCondition = false;
  final _medicalCtrl = TextEditingController();

  //Owner
  final _ownerNameCtrl = TextEditingController();
  final _ownerMobileCtrl = TextEditingController();
  // Pet image
  File? _petImage;
  bool _submitting = false;

  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();

    final tag = widget.existingTag;
    if (tag != null) {
      _nameCtrl.text = tag.name;
      _colorCtrl.text = tag.colorMarkings;
      _descCtrl.text = tag.briefDescription;

      _spayedNeutered = tag.isSpayedNeutered;
      _vaccinated = tag.isVaccinated;

      _ownerNameCtrl.text = tag.ownerName;
      _ownerMobileCtrl.text = tag.ownerMobile;

      // Sex
      final sexUpper = tag.sex.trim().toUpperCase();
      _sex = (sexUpper == 'M' || sexUpper == 'F') ? sexUpper : null;

      //Bday
      _birthdayDate = _tryParseDate(tag.birthday);
      if (_birthdayDate == null) _birthdayRawFallback = tag.birthday;

      //Breed
      final breedParts = tag.breed.split(' - ');
      if (breedParts.length == 2 &&
          (breedParts[0] == 'Dog' || breedParts[0] == 'Cat')) {
        _petType = breedParts[0];
        _breedCtrl.text = breedParts[1];
      } else {
        _breedCtrl.text = tag.breed;
      }

      // Allergies
      final allergiesText = tag.allergies.trim();
      _hasAllergies =
          allergiesText.isNotEmpty && allergiesText.toLowerCase() != 'none';
      if (_hasAllergies) _allergiesCtrl.text = allergiesText;

      // Medical condition
      final medicalText = tag.medicalCondition.trim();
      _hasMedicalCondition =
          medicalText.isNotEmpty && medicalText.toLowerCase() != 'none';
      if (_hasMedicalCondition) _medicalCtrl.text = medicalText;

      if (tag.petImagePath != null) {
        _petImage = File(tag.petImagePath!);
      }

      if (tag.vaccinationImagePath != null) {
        _vaccinationImage = File(tag.vaccinationImagePath!);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _breedCtrl, _colorCtrl, _descCtrl,
      _allergiesCtrl, _medicalCtrl, _ownerNameCtrl, _ownerMobileCtrl
    ]) {
      c.dispose();
    }
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

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdayDate ?? DateTime(now.year - 1, now.month, now.day),
      firstDate: DateTime(1990),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        _birthdayDate = picked;
        _birthdayRawFallback = '';
      });
    }
  }

  DateTime? _tryParseDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    final parts = value.split('/');
    if (parts.length == 3) {
      final month = int.tryParse(parts[0]);
      final day = int.tryParse(parts[1]);
      final year = int.tryParse(parts[2]);
      if (month != null && day != null && year != null) {
        try {
          return DateTime(year, month, day);
        } catch (_) {}
      }
    }
    return null;
  }

  String _formatDate(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';

  String get _birthdayDisplay =>
      _birthdayDate != null ? _formatDate(_birthdayDate!) : _birthdayRawFallback;

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
      final isEditing = widget.existingTag != null;

      final tagRef = isEditing
          ? FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('collarTags')
          .doc(widget.existingTag!.tagId)
          : FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('collarTags')
          .doc();

      final tagId = isEditing
          ? widget.existingTag!.tagId!
          : tagRef.id;

      // Upload images
      String? petImageUrl;
      String? vacImageUrl;

      if (_petImage != null) {
        petImageUrl = await _uploadImage(
            _petImage!, 'collar_tags/$uid/$tagId/pet.jpg');
      }
      if (_vaccinated && _vaccinationImage != null) {
        vacImageUrl = await _uploadImage(
            _vaccinationImage!, 'collar_tags/$uid/$tagId/vaccination.jpg');
      }

      final breedValue = _petType != null
          ? '$_petType - ${_breedCtrl.text.trim()}'
          : _breedCtrl.text.trim();

      final allergiesValue =
      (_hasAllergies && _allergiesCtrl.text.trim().isNotEmpty)
          ? _allergiesCtrl.text.trim()
          : 'None';

      final medicalValue =
      (_hasMedicalCondition && _medicalCtrl.text.trim().isNotEmpty)
          ? _medicalCtrl.text.trim()
          : 'None';

      final tagData = CollarTagData(
        tagId: tagId,
        petImageUrl: petImageUrl,
        petImagePath: _petImage?.path,
        name: _nameCtrl.text.trim(),
        birthday: _birthdayDisplay,
        sex: _sex ?? '',
        breed: breedValue,
        colorMarkings: _colorCtrl.text.trim(),
        briefDescription: _descCtrl.text.trim(),
        isSpayedNeutered: _spayedNeutered,
        isVaccinated: _vaccinated,
        vaccinationImageUrl: vacImageUrl,
        vaccinationImagePath: _vaccinated ? _vaccinationImage?.path : null,
        allergies: allergiesValue,
        medicalCondition: medicalValue,
        ownerName: _ownerNameCtrl.text.trim(),
        ownerMobile: _ownerMobileCtrl.text.trim(),
        createdAt: widget.existingTag?.createdAt ?? DateTime.now(),
      );


      await tagRef.set(
        {
          ...tagData.toFirestore(),
          'tagId': tagId,
          'ownerId': uid,
        },
        SetOptions(merge: true),
      );

      await FirebaseFirestore.instance
          .collection('collarTags')
          .doc(tagId)
          .set(
        {
          ...tagData.toFirestore(),
          'tagId': tagId,
          'ownerId': uid,
        },
        SetOptions(merge: true),
      );

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
          onPressed: () => Navigator.pop(context),
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
            const SizedBox(height: 8),
            _sectionLabel('Pet Information'),
            const SizedBox(height: 10),

            // Pet image
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: _pickPetImage,
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
                    child: _petImage != null
                        ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(_petImage!, fit: BoxFit.cover),
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
            _field(_nameCtrl, 'Name'),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: _datePickerField(
                  label: 'Birthday',
                  displayText: _birthdayDisplay,
                  onTap: _pickBirthday,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sex',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _SingleChoiceRow(
                      value: _sex,
                      options: const ['M', 'F'],
                      onChanged: (v) => setState(() => _sex = v),
                    ),
                  ],
                ),
              ),
            ]),

            const SizedBox(height: 14),
            Text(
              'Pet Type',
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            _SingleChoiceRow(
              value: _petType,
              options: const ['Dog', 'Cat'],
              onChanged: (v) => setState(() => _petType = v),
            ),
            if (_petType != null) ...[
              const SizedBox(height: 10),
              _field(
                _breedCtrl,
                _petType == 'Dog'
                    ? 'Breed (e.g. Labrador Retriever)'
                    : 'Breed (e.g. Persian)',
              ),
            ],

            const SizedBox(height: 10),
            _field(_colorCtrl, 'Color/Markings'),
            const SizedBox(height: 10),
            _sectionLabel('Brief Pet Description'),
            const SizedBox(height: 6),
            _field(_descCtrl, 'Enter description'),

            const SizedBox(height: 24),
            _sectionLabel('Health Information'),
            const SizedBox(height: 8),
            _YesNoRow(
              label: 'Spayed/Neutered',
              value: _spayedNeutered,
              onChanged: (v) => setState(() => _spayedNeutered = v),
            ),
            const SizedBox(height: 10),
            _YesNoRow(
              label: 'Vaccinated',
              value: _vaccinated,
              onChanged: (v) => setState(() => _vaccinated = v),
            ),

            if (_vaccinated) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: _pickVaccinationImage,
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
                      child: _vaccinationImage != null
                          ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(_vaccinationImage!, fit: BoxFit.cover),
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
            ],

            const SizedBox(height: 14),
            _sectionLabel('Allergies'),
            const SizedBox(height: 6),
            _YesNoRow(
              label: 'Does your pet have allergies?',
              value: _hasAllergies,
              onChanged: (v) => setState(() => _hasAllergies = v),
            ),
            if (_hasAllergies) ...[
              const SizedBox(height: 8),
              _field(_allergiesCtrl, 'Enter allergies'),
            ],

            const SizedBox(height: 14),
            _sectionLabel('Current/Existing Medical Condition'),
            const SizedBox(height: 6),
            _YesNoRow(
              label: 'Does your pet have a medical condition?',
              value: _hasMedicalCondition,
              onChanged: (v) => setState(() => _hasMedicalCondition = v),
            ),
            if (_hasMedicalCondition) ...[
              const SizedBox(height: 8),
              _field(_medicalCtrl, 'Enter condition'),
            ],

            const SizedBox(height: 16),
            _sectionLabel('Owner Information'),
            const SizedBox(height: 10),
            _field(_ownerNameCtrl, 'Name'),
            const SizedBox(height: 10),
            _field(_ownerMobileCtrl, 'Mobile Number',
                keyboardType: TextInputType.phone),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: _submitting
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
      ),
    );
  }
}


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

Widget _datePickerField({
  required String label,
  required String displayText,
  required VoidCallback onTap,
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
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.background.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.slaterspwn, width: 1),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayText.isEmpty ? 'Select date' : displayText,
                    style: GoogleFonts.zain(
                      fontSize: 15,
                      color: displayText.isEmpty
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ),
                const Icon(Icons.calendar_today,
                    size: 18, color: AppColors.textPrimary),
              ],
            ),
          ),
        ),
      ],
    );


class _SingleChoiceRow extends StatelessWidget {
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _SingleChoiceRow({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => onChanged(option),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Radio<String>(
                    value: option,
                    groupValue: value,
                    activeColor: AppColors.textPrimary,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (v) => onChanged(v ?? option),
                  ),
                  const SizedBox(width: 2),
                  Text(option,
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// Yes/No for health-related questions
class _YesNoRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _YesNoRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  Widget _option(String text, bool optionValue) {
    return GestureDetector(
      onTap: () => onChanged(optionValue),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Radio<bool>(
            value: optionValue,
            groupValue: value,
            activeColor: AppColors.textPrimary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) => onChanged(v ?? optionValue),
          ),
          const SizedBox(width: 2),
          Text(text,
              style:
              GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style:
              GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ),
        _option('Yes', true),
        const SizedBox(width: 8),
        _option('No', false),
      ],
    );
  }
}