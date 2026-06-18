import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';

class CreateAnimalRecordPage extends StatefulWidget {
  final Map<String, dynamic>? prefillData; // from intake
  final String? linkedCaseId;

  const CreateAnimalRecordPage({
    super.key,
    this.prefillData,
    this.linkedCaseId,
  });

  @override
  State<CreateAnimalRecordPage> createState() =>
      _CreateAnimalRecordPageState();
}

class _CreateAnimalRecordPageState extends State<CreateAnimalRecordPage> {
  // Basic info
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedSpecies;
  String? _selectedBreed;
  String? _selectedSex;
  String? _selectedSize;
  String? _selectedCoatLength;
  DateTime? _dateOfBirth;
  bool _isAdoptable = true;
  bool _isLoading = false;

  // Health
  bool _vaccinated = false;
  bool _spayedNeutered = false;
  bool _dewormed = false;

  // Vaccines — rabies always, others depend on species
  bool _rabies = false;
  bool _vaccine2 = false; // 5-in-1 or 3-in-1
  bool _vaccine3 = false; // Bordetella or FeLV

  // Key Characteristics
  final Map<String, bool> _characteristics = {
    'Good With Children': false,
    'Knows Commands': false,
    'First-Time Owner Friendly': false,
    'Low Maintenance': false,
    'Shy': false,
    'Playful': false,
    'Calm': false,
    'Good With Other Animals': false,
    'Special Needs': false,
    'Leash Trained': false,
    'Crate Trained': false,
    'Protective': false,
  };

  // Rescue Background
  final Map<String, bool> _rescueBackground = {
    'Rescued from street': false,
    'Abandoned': false,
    'Rescued from abuse': false,
    'Surrendered by Owner': false,
    'Transferred from Shelter': false,
  };

  bool get _isDog => _selectedSpecies == 'Dog';

  String get _vaccine2Label => _isDog ? '5-in-1' : '3-in-1';
  String get _vaccine3Label => _isDog ? 'Bordetella' : 'FeLV';

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  void _prefill() {
    final d = widget.prefillData;
    if (d == null) return;
    _selectedSpecies = d['species'];
    _descriptionController.text = d['description'] ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createRecord() async {
    if (_nameController.text.trim().isEmpty || _selectedSpecies == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in name and species.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      final selectedChars = _characteristics.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final selectedBackground = _rescueBackground.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final vaccinesGiven = <String>[];
      if (_rabies) vaccinesGiven.add('Rabies');
      if (_vaccine2) vaccinesGiven.add(_vaccine2Label);
      if (_vaccine3) vaccinesGiven.add(_vaccine3Label);

      final health = <String>[];
      if (_vaccinated) health.add('Vaccinated');
      if (_spayedNeutered) health.add('Spayed/Neutered');
      if (_dewormed) health.add('Dewormed');

      await FirebaseFirestore.instance.collection('animals').add({
        'name': _nameController.text.trim(),
        'species': _selectedSpecies,
        'breed': _selectedBreed ?? '',
        'sex': _selectedSex ?? '',
        'size': _selectedSize ?? '',
        'coatLength': _selectedCoatLength ?? '',
        'dateOfBirth': _dateOfBirth != null
            ? Timestamp.fromDate(_dateOfBirth!)
            : null,
        'description': _descriptionController.text.trim(),
        'health': health,
        'vaccinated': _vaccinated,
        'spayedNeutered': _spayedNeutered,
        'dewormed': _dewormed,
        'vaccinesGiven': vaccinesGiven,
        'keyCharacteristics': selectedChars,
        'rescueBackground': selectedBackground,
        'adoptionStatus': _isAdoptable ? 'adoptable' : 'not_ready',
        'status': 'intake',
        'linkedCaseId': widget.linkedCaseId ?? '',
        'rescuedBy': 'Loved by the Gapz',
        'intakeStaffId': uid,
        'photoUrls': [],
        'treatmentLog': [],
        'createdAt': FieldValue.serverTimestamp(),
        // prefilled from intake if available
        if (widget.prefillData != null) ...{
          'vetClinicName': widget.prefillData!['vetClinicName'] ?? '',
          'intakeNotes': widget.prefillData!['intakeNotes'] ?? '',
          'reporterName': widget.prefillData!['reporterName'] ?? '',
          'transporterName': widget.prefillData!['transporterName'] ?? '',
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Animal record created!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Animal Records',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text('Create New Record',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 20, color: AppColors.textPrimary)),
            ),

            const SizedBox(height: 20),

            // Images
            _FieldLabel('Images', required: true),
            const SizedBox(height: 8),
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                border: Border.all(
                    color: AppColors.greenrspwn,
                    style: BorderStyle.solid,
                    width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(Icons.add,
                    size: 28, color: AppColors.greenrspwn),
              ),
            ),

            const SizedBox(height: 20),

            // Name
            _FieldLabel('Name'),
            _UnderlineField(
                controller: _nameController, hint: 'Enter'),

            const SizedBox(height: 16),

            // Species + Breed
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Species'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _SpeciesCheck(
                            label: 'Dog',
                            selected: _selectedSpecies == 'Dog',
                            onTap: () => setState(() {
                              _selectedSpecies = 'Dog';
                              _vaccine2 = false;
                              _vaccine3 = false;
                            }),
                          ),
                          const SizedBox(width: 12),
                          _SpeciesCheck(
                            label: 'Cat',
                            selected: _selectedSpecies == 'Cat',
                            onTap: () => setState(() {
                              _selectedSpecies = 'Cat';
                              _vaccine2 = false;
                              _vaccine3 = false;
                            }),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Breed'),
                      _DropdownField(
                        value: _selectedBreed,
                        hint: 'Select',
                        items: _selectedSpecies == 'Dog'
                            ? ['Aspin', 'Labrador', 'Shih Tzu', 'Poodle', 'Other']
                            : ['Puspin', 'Persian', 'Siamese', 'Other'],
                        onChanged: (v) =>
                            setState(() => _selectedBreed = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Date of Birth + Sex
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Date of Birth'),
                      GestureDetector(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime(2022),
                            firstDate: DateTime(2010),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null)
                            setState(() => _dateOfBirth = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.only(bottom: 8),
                          decoration: const BoxDecoration(
                            border: Border(
                                bottom: BorderSide(
                                    color: AppColors.textPrimary)),
                          ),
                          child: Row(
                            mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _dateOfBirth == null
                                    ? 'mm/dd/yyyy'
                                    : '${_dateOfBirth!.month}/${_dateOfBirth!.day}/${_dateOfBirth!.year}',
                                style: GoogleFonts.zain(
                                    fontSize: 14,
                                    color: _dateOfBirth == null
                                        ? AppColors.textSecondary
                                        : AppColors.textPrimary),
                              ),
                              const Icon(Icons.calendar_today_outlined,
                                  size: 16,
                                  color: AppColors.textPrimary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Sex'),
                      _DropdownField(
                        value: _selectedSex,
                        hint: 'Select',
                        items: ['Male', 'Female', 'Unknown'],
                        onChanged: (v) =>
                            setState(() => _selectedSex = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Size + Coat Length
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Size'),
                      _DropdownField(
                        value: _selectedSize,
                        hint: 'Select',
                        items: ['Small', 'Medium', 'Large'],
                        onChanged: (v) =>
                            setState(() => _selectedSize = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Coat Length'),
                      _DropdownField(
                        value: _selectedCoatLength,
                        hint: 'Select',
                        items: ['Short', 'Medium', 'Long'],
                        onChanged: (v) =>
                            setState(() => _selectedCoatLength = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Health
            _FieldLabel('Health'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16, runSpacing: 8,
              children: [
                _CheckboxField(
                  label: 'Vaccinated',
                  value: _vaccinated,
                  onChanged: (v) => setState(() => _vaccinated = v!),
                ),
                _CheckboxField(
                  label: 'Spayed/\nNeutered',
                  value: _spayedNeutered,
                  onChanged: (v) =>
                      setState(() => _spayedNeutered = v!),
                ),
                _CheckboxField(
                  label: 'Dewormed',
                  value: _dewormed,
                  onChanged: (v) => setState(() => _dewormed = v!),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Key Characteristics
            _FieldLabel('Key Characteristics'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: _characteristics.keys.map((key) {
                return _CheckboxField(
                  label: key,
                  value: _characteristics[key]!,
                  onChanged: (v) =>
                      setState(() => _characteristics[key] = v!),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Rescue Background
            _FieldLabel('Rescue Background'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: _rescueBackground.keys.map((key) {
                return _CheckboxField(
                  label: key,
                  value: _rescueBackground[key]!,
                  onChanged: (v) =>
                      setState(() => _rescueBackground[key] = v!),
                );
              }).toList(),
            ),

            const SizedBox(height: 20),

            // Description
            _FieldLabel('Description'),
            _UnderlineField(
                controller: _descriptionController, hint: 'Enter'),

            const SizedBox(height: 16),

            // Rescued by (autofill)
            _FieldLabel('Rescued by'),
            Text('Autofill',
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textSecondary)),

            const SizedBox(height: 16),

            // Rescue Case ID (autofill)
            _FieldLabel('Rescue Case ID'),
            Text(widget.linkedCaseId ?? 'Autofill',
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textSecondary)),

            const SizedBox(height: 20),

            // Vaccines
            _FieldLabel('Vaccines'),
            const SizedBox(height: 8),

            // Rabies always shown
            _CheckboxField(
              label: 'Rabies',
              value: _rabies,
              onChanged: (v) => setState(() => _rabies = v!),
            ),

            const SizedBox(height: 8),

            // Species-specific vaccines
            if (_selectedSpecies != null) ...[
              Wrap(
                spacing: 12, runSpacing: 8,
                children: [
                  _CheckboxField(
                    label: _vaccine2Label,
                    value: _vaccine2,
                    onChanged: (v) => setState(() => _vaccine2 = v!),
                  ),
                  _CheckboxField(
                    label: _vaccine3Label,
                    value: _vaccine3,
                    onChanged: (v) => setState(() => _vaccine3 = v!),
                  ),
                ],
              ),
            ] else
              Text('Select species to see vaccine options',
                  style: GoogleFonts.zain(
                      fontSize: 12, color: AppColors.textSecondary)),

            const SizedBox(height: 20),

            // Adoptable toggle
            _FieldLabel('Adoptable'),
            const SizedBox(height: 8),
            Switch(
              value: _isAdoptable,
              onChanged: (v) => setState(() => _isAdoptable = v),
              activeColor: AppColors.greenrspwn,
            ),

            const SizedBox(height: 20),

            // QR + NFC buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.qr_code,
                        size: 18, color: AppColors.textPrimary),
                    label: Text('Add QR code',
                        style: GoogleFonts.zain(
                            fontSize: 13, color: AppColors.textPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding:
                      const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {},
                    icon: const Icon(Icons.nfc,
                        size: 18, color: AppColors.textPrimary),
                    label: Text('Add NFC tag',
                        style: GoogleFonts.zain(
                            fontSize: 13, color: AppColors.textPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(
                          color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding:
                      const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Create Record button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.textPrimary))
                    : Text('Create Record',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16,
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

// Reusable widgets
class _FieldLabel extends StatelessWidget {
  final String label;
  final bool required;
  const _FieldLabel(this.label, {this.required = false});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label,
          style: GoogleFonts.zain(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
      if (required)
        const Text(' *',
            style: TextStyle(color: Colors.red, fontSize: 14)),
    ],
  );
}

class _UnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _UnderlineField(
      {required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle:
      GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
      enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary)),
      focusedBorder: const UnderlineInputBorder(
          borderSide:
          BorderSide(color: AppColors.textPrimary, width: 1.5)),
      isDense: true,
      contentPadding: const EdgeInsets.only(bottom: 8),
    ),
    style: GoogleFonts.zain(
        fontSize: 14, color: AppColors.textPrimary),
  );
}

class _DropdownField extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final Function(String?) onChanged;
  const _DropdownField({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    value: value,
    hint: Text(hint,
        style: GoogleFonts.zain(
            fontSize: 14, color: AppColors.textSecondary)),
    style: GoogleFonts.zain(
        fontSize: 14, color: AppColors.textPrimary),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.only(bottom: 8),
      enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary)),
      focusedBorder: UnderlineInputBorder(
          borderSide:
          BorderSide(color: AppColors.textPrimary, width: 1.5)),
    ),
    items: items
        .map((item) => DropdownMenuItem(
        value: item,
        child: Text(item,
            style: GoogleFonts.zain(fontSize: 14))))
        .toList(),
    onChanged: onChanged,
  );
}

class _CheckboxField extends StatelessWidget {
  final String label;
  final bool value;
  final Function(bool?) onChanged;
  const _CheckboxField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 18, height: 18,
        child: Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.textPrimary,
          side: const BorderSide(
              color: AppColors.textPrimary, width: 1.5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(2)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 6),
      Text(label,
          style: GoogleFonts.zain(
              fontSize: 12, color: AppColors.textPrimary)),
    ],
  );
}

class _SpeciesCheck extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SpeciesCheck({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 18, height: 18,
          decoration: BoxDecoration(
            color: selected
                ? AppColors.textPrimary
                : Colors.transparent,
            border: Border.all(
                color: AppColors.textPrimary, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: selected
              ? const Icon(Icons.check,
              size: 12, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 6),
        Text(label,
            style: GoogleFonts.zain(
                fontSize: 13, color: AppColors.textPrimary)),
      ],
    ),
  );
}