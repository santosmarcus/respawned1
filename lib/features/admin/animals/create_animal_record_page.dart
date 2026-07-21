import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';

/// The existing animal-record form — reused as-is by both a standalone
/// "Create Record" entry point and, with [prefillData]/[linkedCaseId]/
/// [sourceAnimalIndex]/[stepCurrent]/[stepTotal] set, by
/// AnimalRecordsFlowPage's multi-animal creation flow. Not a parallel form.
class CreateAnimalRecordPage extends StatefulWidget {
  final Map<String, dynamic>? prefillData; // from intake
  final String? linkedCaseId;
  /// This animal's position in the source case's `animals[]` array (0 for
  /// legacy single-animal cases) — the duplicate-prevention key alongside
  /// [linkedCaseId]. Null when opened outside the multi-animal flow.
  final int? sourceAnimalIndex;
  /// 1-based step number / total steps, for the "Animal X of N" header and
  /// the Save and Continue vs Finish button label. Both null outside the
  /// multi-animal flow (plain "Create Record" label, no step header).
  final int? stepCurrent;
  final int? stepTotal;

  /// Edit mode — set both to reuse this same form for the Animal Record
  /// header's "Edit Profile" action instead of building a second form.
  /// When set, every field initializes from [existingData] (not
  /// [prefillData]), Save updates that doc in place instead of creating a
  /// new one, and the receipt-gating/duplicate-prevention checks that only
  /// make sense for a brand-new rescue-linked record are skipped.
  final String? existingAnimalId;
  final Map<String, dynamic>? existingData;

  /// True (default) when this page owns its own Navigator route — Save
  /// pops it on success, same as it always has. AnimalRecordsFlowPage sets
  /// this to false: it embeds this widget directly in its own build() (not
  /// via Navigator.push), and drives which animal is shown via its own
  /// reactive rebuild off completedAnimalRecordIndexesProvider — a pop from
  /// in here would close the whole flow after Animal 1 instead of letting
  /// it advance to Animal 2/3 in place.
  final bool popOnSuccess;

  const CreateAnimalRecordPage({
    super.key,
    this.prefillData,
    this.linkedCaseId,
    this.sourceAnimalIndex,
    this.stepCurrent,
    this.stepTotal,
    this.existingAnimalId,
    this.existingData,
    this.popOnSuccess = true,
  });

  bool get isEditing => existingAnimalId != null;

  @override
  State<CreateAnimalRecordPage> createState() =>
      _CreateAnimalRecordPageState();
}

class _CreateAnimalRecordPageState extends State<CreateAnimalRecordPage> {
  // Images — optional (see _FieldLabel below): no current business rule
  // requires at least one, so this never blocks submission.
  final _picker = ImagePicker();
  final List<XFile> _pickedImages = [];
  // Edit mode only — already-uploaded photos, individually removable;
  // newly picked images are uploaded and appended alongside whatever
  // remains of this list on Save.
  late List<String> _existingPhotoUrls =
      List<String>.from(widget.existingData?['photoUrls'] ?? const []);
  bool _isUploadingImages = false;
  String? _imageError;

  // Basic info
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  String? _selectedSpecies;
  // Breed has no dedicated input in the current design, but the record
  // model/other screens (animal_record_page.dart's list card/filtering)
  // already support it — captured from the report's prefill data below and
  // still persisted, just not user-editable here.
  String? _selectedBreed;
  String? _selectedSex;
  String? _selectedSize;
  String? _selectedCoatLength;
  bool _isAdoptable = true;
  bool _isLoading = false;

  // Health — unchecked when unknown, never inferred.
  bool _vaccinated = false;
  bool _spayedNeutered = false;
  bool _dewormed = false;

  // Temperament / Compatibility / Training all still write into the same
  // flat `keyCharacteristics` array the model already had — three separate
  // maps here only for the new form's grouped section labels, not a schema
  // change.
  final Map<String, bool> _temperament = {
    'Friendly': false,
    'Shy': false,
    'Playful': false,
    'Calm': false,
  };
  final Map<String, bool> _compatibility = {
    'Good with children': false,
    'Good with other pets': false,
    'First-time owner friendly': false,
  };
  final Map<String, bool> _training = {
    'Leash trained': false,
    'Crate trained': false,
    'Potty trained': false,
    'Knows commands': false,
  };

  // Rescue Background — 'Rescued' is auto-checked (not manually required)
  // whenever this record comes from the rescue workflow (linkedCaseId set).
  // Checkboxes (not a single choice) so a later transfer can be recorded
  // alongside the original Rescued source rather than replacing it.
  final Map<String, bool> _rescueBackground = {
    'Rescued': false,
    'Transferred': false,
    'Surrendered': false,
  };

  String get _saveButtonLabel {
    if (widget.isEditing) return 'Save Changes';
    if (widget.stepCurrent == null || widget.stepTotal == null) return 'Create Record';
    return widget.stepCurrent! >= widget.stepTotal! ? 'Finish' : 'Save and Continue';
  }

  // TODO(qr-nfc): generating a real per-animal QR/NFC tag, associating it
  // with this record, and printing/displaying it are not implemented.
  // Also TODO: NFC support, if it ends up sharing the same identifier as
  // the QR code rather than being independent.
  void _showTagNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR assignment is not available yet.')),
    );
  }

  @override
  void initState() {
    super.initState();
    if (widget.isEditing) {
      _prefillFromExisting();
    } else {
      _prefill();
    }
  }

  /// Edit mode — every field starts from the record's own saved values
  /// (never the original report; that prefill only applies to brand-new
  /// records).
  void _prefillFromExisting() {
    final d = widget.existingData!;
    _nameController.text = d['name'] as String? ?? '';
    _ageController.text = d['age'] as String? ?? '';
    _descriptionController.text = d['description'] as String? ?? '';
    _tagsController.text = List<String>.from(d['tags'] ?? const []).join(', ');
    _selectedSpecies = (d['species'] as String?)?.isNotEmpty == true ? d['species'] as String : null;
    _selectedBreed = (d['breed'] as String?)?.isNotEmpty == true ? d['breed'] as String : null;
    _selectedSex = (d['sex'] as String?)?.isNotEmpty == true ? d['sex'] as String : null;
    _selectedSize = (d['size'] as String?)?.isNotEmpty == true ? d['size'] as String : null;
    _selectedCoatLength = (d['coatLength'] as String?)?.isNotEmpty == true ? d['coatLength'] as String : null;
    _isAdoptable = d['adoptionStatus'] == 'adoptable';
    _vaccinated = d['vaccinated'] as bool? ?? false;
    _spayedNeutered = d['spayedNeutered'] as bool? ?? false;
    _dewormed = d['dewormed'] as bool? ?? false;

    final chars = List<String>.from(d['keyCharacteristics'] ?? const []);
    for (final key in _temperament.keys) {
      if (chars.contains(key)) _temperament[key] = true;
    }
    for (final key in _compatibility.keys) {
      if (chars.contains(key)) _compatibility[key] = true;
    }
    for (final key in _training.keys) {
      if (chars.contains(key)) _training[key] = true;
    }

    final background = List<String>.from(d['rescueBackground'] ?? const []);
    for (final key in _rescueBackground.keys) {
      if (background.contains(key)) _rescueBackground[key] = true;
    }
  }

  /// Prefills whatever the source rescue report/case already captured.
  /// Species/breed/sex/size/color/description/image come straight from the
  /// report — never invented. Fields the report never asked about (name,
  /// age, coat length, vaccination/sterilization status, temperament,
  /// etc.) are deliberately left blank/unchecked here, matching whatever
  /// default the field already has.
  void _prefill() {
    final d = widget.prefillData;
    if (d == null) return;

    _selectedSpecies = d['species'] as String?;

    final breed = (d['breed'] as String?)?.trim();
    if (breed != null && breed.isNotEmpty) {
      _selectedBreed = breed;
    }

    final sex = (d['sex'] as String?)?.trim();
    if (sex != null) {
      final match = ['Male', 'Female', 'Unknown']
          .cast<String?>()
          .firstWhere((s) => s!.toLowerCase() == sex.toLowerCase(), orElse: () => null);
      if (match != null) _selectedSex = match;
    }

    final size = (d['size'] as String?)?.trim();
    if (size != null) {
      final match = ['Small', 'Medium', 'Large']
          .cast<String?>()
          .firstWhere((s) => s!.toLowerCase() == size.toLowerCase(), orElse: () => null);
      if (match != null) _selectedSize = match;
    }

    // Report breed/"condition"/color-markings text folded into the
    // description so nothing captured at report time is lost, even though
    // this form has no dedicated breed/color field of its own.
    final descriptionParts = <String>[
      if ((d['description'] as String?)?.isNotEmpty ?? false) d['description'] as String,
      if ((d['colorMarkings'] as String?)?.isNotEmpty ?? false) 'Color/markings: ${d['colorMarkings']}',
    ];
    _descriptionController.text = descriptionParts.join('\n');

    // This record came from the rescue workflow — "Rescued" is implied,
    // not something the org has to remember to tick.
    if (widget.linkedCaseId != null) {
      _rescueBackground['Rescued'] = true;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: Text('Choose from Gallery', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.textPrimary),
              title: Text('Take Photo', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    if (source == ImageSource.gallery) {
      final files = await _picker.pickMultiImage(imageQuality: 80);
      if (files.isNotEmpty && mounted) {
        setState(() {
          _pickedImages.addAll(files);
          _imageError = null;
        });
      }
    } else {
      final file = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (file != null && mounted) {
        setState(() {
          _pickedImages.add(file);
          _imageError = null;
        });
      }
    }
  }

  void _removeImage(int index) => setState(() => _pickedImages.removeAt(index));

  Future<String> _uploadImage(XFile file, String storagePath) async {
    final ref = FirebaseStorage.instance.ref(storagePath);
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  Future<void> _createRecord() async {
    if (_isLoading) return; // guards against a duplicate Finish/Save tap
    if (_nameController.text.trim().isEmpty || _selectedSpecies == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in name and species.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _imageError = null;
    });

    try {
      // The animal must have physically arrived at the shelter before a
      // record can be created — re-checked here (not just at the Intake
      // Details button) against live Firestore state, so this can't be
      // bypassed by reaching this page through another path. See
      // RescueCaseRepository.confirmAnimalReceived, whose write to
      // `intakeReceivedAt` is what unlocks this. Doesn't apply when
      // editing an already-existing record.
      if (!widget.isEditing && widget.linkedCaseId != null) {
        final caseSnap = await FirebaseFirestore.instance.collection('cases').doc(widget.linkedCaseId).get();
        if (caseSnap.data()?['intakeReceivedAt'] == null) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('The animal must be confirmed received before creating records.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }

      // Duplicate-prevention: re-check against live Firestore state right
      // before writing, not just the flow page's snapshot from when it was
      // opened — guards the "user taps Confirm repeatedly" / two flow
      // instances open at once edge cases. Doesn't apply when editing.
      if (!widget.isEditing && widget.linkedCaseId != null && widget.sourceAnimalIndex != null) {
        final existing = await FirebaseFirestore.instance
            .collection('animals')
            .where('linkedCaseId', isEqualTo: widget.linkedCaseId)
            .where('sourceAnimalIndex', isEqualTo: widget.sourceAnimalIndex)
            .limit(1)
            .get();
        if (existing.docs.isNotEmpty) {
          if (mounted) {
            setState(() => _isLoading = false);
            Navigator.pop(context); // already created — just return to the flow
          }
          return;
        }
      }

      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

      // Pre-allocated (new records only) so image Storage paths can be
      // scoped under this record's own id (animalRecords/{id}/images/...)
      // before the document itself is written. Editing reuses the
      // existing id instead.
      final docRef = widget.isEditing
          ? FirebaseFirestore.instance.collection('animals').doc(widget.existingAnimalId)
          : FirebaseFirestore.instance.collection('animals').doc();

      final uploadedUrls = <String>[];
      if (_pickedImages.isNotEmpty) {
        setState(() => _isUploadingImages = true);
        try {
          for (var i = 0; i < _pickedImages.length; i++) {
            final file = _pickedImages[i];
            final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
            final filename = '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
            final url = await _uploadImage(file, 'animalRecords/${docRef.id}/images/$filename');
            uploadedUrls.add(url);
          }
        } catch (e) {
          // Never save with a partially-uploaded image set — keep the
          // picked images in the form so Save can be retried.
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isUploadingImages = false;
              _imageError = 'Could not upload image: $e';
            });
          }
          return;
        }
        if (mounted) setState(() => _isUploadingImages = false);
      }

      final selectedChars = [
        ..._temperament.entries.where((e) => e.value).map((e) => e.key),
        ..._compatibility.entries.where((e) => e.value).map((e) => e.key),
        ..._training.entries.where((e) => e.value).map((e) => e.key),
      ];

      final selectedBackground = _rescueBackground.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();

      final tags = _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final health = <String>[];
      if (_vaccinated) health.add('Vaccinated');
      if (_spayedNeutered) health.add('Spayed/Neutered');
      if (_dewormed) health.add('Dewormed');

      final sharedFields = {
        'name': _nameController.text.trim(),
        'age': _ageController.text.trim(),
        'species': _selectedSpecies,
        'breed': _selectedBreed ?? '',
        'sex': _selectedSex ?? '',
        'size': _selectedSize ?? '',
        'coatLength': _selectedCoatLength ?? '',
        'description': _descriptionController.text.trim(),
        'health': health,
        'vaccinated': _vaccinated,
        'spayedNeutered': _spayedNeutered,
        'dewormed': _dewormed,
        'keyCharacteristics': selectedChars,
        'rescueBackground': selectedBackground,
        'tags': tags,
        'adoptionStatus': _isAdoptable ? 'adoptable' : 'not_ready',
      };

      if (widget.isEditing) {
        await docRef.update({
          ...sharedFields,
          'photoUrls': [..._existingPhotoUrls, ...uploadedUrls],
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final fallbackPhotoUrl = widget.prefillData?['photoUrl'] as String?;
        await docRef.set({
          ...sharedFields,
          'status': 'intake',
          'linkedCaseId': widget.linkedCaseId ?? '',
          if (widget.sourceAnimalIndex != null) 'sourceAnimalIndex': widget.sourceAnimalIndex,
          'rescuedBy': widget.prefillData?['rescuedBy'] ?? 'Loved by the Gapz',
          'intakeStaffId': uid,
          'photoUrls': uploadedUrls.isNotEmpty ? uploadedUrls : (fallbackPhotoUrl != null ? [fallbackPhotoUrl] : []),
          'treatmentLog': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          // prefilled from intake/the source rescue report if available
          if (widget.prefillData != null) ...{
            'vetClinicName': widget.prefillData!['vetClinicName'] ?? '',
            'intakeNotes': widget.prefillData!['intakeNotes'] ?? '',
            'reporterName': widget.prefillData!['reporterName'] ?? '',
            'transporterName': widget.prefillData!['transporterName'] ?? '',
            if (widget.prefillData!['rescueDate'] is Timestamp) 'rescueDate': widget.prefillData!['rescueDate'],
          }
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.isEditing ? 'Profile updated!' : 'Animal record created!'),
            backgroundColor: Colors.green,
          ),
        );
        // See widget.popOnSuccess's doc comment — AnimalRecordsFlowPage
        // stays on screen and reactively advances to the next animal
        // itself instead of this page popping the whole flow.
        if (widget.popOnSuccess) Navigator.pop(context);
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
        title: Text(widget.isEditing ? 'Edit Profile' : 'Animal Records',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          if (!widget.isEditing)
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
              child: Text(
                  widget.isEditing
                      ? 'Edit Profile'
                      : (widget.stepCurrent != null && widget.stepTotal != null
                          ? 'Create Animal Record'
                          : 'Create New Record'),
                  style: GoogleFonts.tiltWarp(
                      fontSize: 20, color: AppColors.textPrimary)),
            ),
            if (widget.stepCurrent != null && widget.stepTotal != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text('Animal ${widget.stepCurrent} of ${widget.stepTotal}',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ),
            ],

            const SizedBox(height: 20),

            // ---- Images (optional) ------------------------------------
            _FieldLabel('Images (optional)'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _existingPhotoUrls.length; i++)
                  _ExistingImageThumb(
                    url: _existingPhotoUrls[i],
                    onRemove: _isLoading ? null : () => setState(() => _existingPhotoUrls.removeAt(i)),
                  ),
                for (var i = 0; i < _pickedImages.length; i++)
                  _PickedImageThumb(file: _pickedImages[i], onRemove: _isLoading ? null : () => _removeImage(i)),
                GestureDetector(
                  onTap: _isLoading ? null : _pickImages,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.greenrspwn, width: 1.5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.add_a_photo_outlined, size: 26, color: AppColors.greenrspwn),
                    ),
                  ),
                ),
              ],
            ),
            if (_isUploadingImages) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text('Uploading images…', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ],
            if (_imageError != null) ...[
              const SizedBox(height: 8),
              Text(_imageError!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ],

            const SizedBox(height: 20),

            // ---- Basic information -------------------------------------
            _FieldLabel('Basic Information'),
            const SizedBox(height: 8),

            _FieldLabel('Name'),
            _UnderlineField(controller: _nameController, hint: 'Enter'),
            const SizedBox(height: 16),

            _FieldLabel('Age'),
            _UnderlineField(controller: _ageController, hint: 'e.g. 2 years, 6 months'),
            const SizedBox(height: 16),

            _FieldLabel('Species'),
            const SizedBox(height: 6),
            Row(
              children: [
                _SpeciesCheck(
                  label: 'Dog',
                  selected: _selectedSpecies == 'Dog',
                  onTap: () => setState(() => _selectedSpecies = 'Dog'),
                ),
                const SizedBox(width: 12),
                _SpeciesCheck(
                  label: 'Cat',
                  selected: _selectedSpecies == 'Cat',
                  onTap: () => setState(() => _selectedSpecies = 'Cat'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Sex'),
                      _DropdownField(
                        value: _selectedSex,
                        hint: 'Select',
                        items: const ['Male', 'Female', 'Unknown'],
                        onChanged: (v) => setState(() => _selectedSex = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Size'),
                      _DropdownField(
                        value: _selectedSize,
                        hint: 'Select',
                        items: const ['Small', 'Medium', 'Large'],
                        onChanged: (v) => setState(() => _selectedSize = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _FieldLabel('Coat Length'),
            _DropdownField(
              value: _selectedCoatLength,
              hint: 'Select',
              items: const ['Short', 'Medium', 'Long'],
              onChanged: (v) => setState(() => _selectedCoatLength = v),
            ),

            const SizedBox(height: 20),

            // ---- Health --------------------------------------------------
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
                  label: 'Spayed/Neutered',
                  value: _spayedNeutered,
                  onChanged: (v) => setState(() => _spayedNeutered = v!),
                ),
                _CheckboxField(
                  label: 'Dewormed',
                  value: _dewormed,
                  onChanged: (v) => setState(() => _dewormed = v!),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ---- Temperament ----------------------------------------------
            _FieldLabel('Temperament'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: _temperament.keys
                  .map((key) => _CheckboxField(
                        label: key,
                        value: _temperament[key]!,
                        onChanged: (v) => setState(() => _temperament[key] = v!),
                      ))
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Compatibility ----------------------------------------------
            _FieldLabel('Compatibility'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: _compatibility.keys
                  .map((key) => _CheckboxField(
                        label: key,
                        value: _compatibility[key]!,
                        onChanged: (v) => setState(() => _compatibility[key] = v!),
                      ))
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Training ----------------------------------------------
            _FieldLabel('Training'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: _training.keys
                  .map((key) => _CheckboxField(
                        label: key,
                        value: _training[key]!,
                        onChanged: (v) => setState(() => _training[key] = v!),
                      ))
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Rescue Background ----------------------------------------
            _FieldLabel('Rescue Background'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12, runSpacing: 8,
              children: _rescueBackground.keys
                  .map((key) => _CheckboxField(
                        label: key,
                        value: _rescueBackground[key]!,
                        onChanged: (v) => setState(() => _rescueBackground[key] = v!),
                      ))
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Remaining fields -------------------------------------
            _FieldLabel('Description'),
            _UnderlineField(controller: _descriptionController, hint: 'Enter'),
            const SizedBox(height: 16),

            // Rescued by (autofill, read-only)
            _FieldLabel('Rescued by'),
            Text((widget.prefillData?['rescuedBy'] as String?) ?? 'Loved by the Gapz',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 16),

            // Rescue Case ID (autofill, read-only)
            _FieldLabel('Rescue Case ID'),
            Text(widget.linkedCaseId ?? 'Autofill',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 20),

            _FieldLabel('Adoptable'),
            const SizedBox(height: 4),
            Switch(
              value: _isAdoptable,
              onChanged: (v) => setState(() => _isAdoptable = v),
              activeColor: AppColors.greenrspwn,
            ),
            const SizedBox(height: 16),

            _FieldLabel('Tags'),
            _UnderlineField(controller: _tagsController, hint: 'e.g. senior, house-trained'),
            const SizedBox(height: 16),

            // Any tag already scanned during the original rescue report —
            // shown for reference only. It is NOT a generated animal-record
            // QR/NFC tag and the two are never conflated.
            if ((widget.prefillData?['scannedTagId'] as String?)?.isNotEmpty ?? false) ...[
              _FieldLabel('Scanned Tag (from rescue report)'),
              Text(widget.prefillData!['scannedTagId'] as String,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
            ],

            // QR + NFC — not functional yet. Disabled rather than a silent
            // no-op, so tapping it is honest about the current state
            // instead of doing nothing. See the class doc comment's TODO.
            // Never saves fake/placeholder QR data.
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showTagNotAvailable,
                    icon: const Icon(Icons.qr_code, size: 18, color: AppColors.textSecondary),
                    label: Text('Add QR', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.slaterspwn),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _showTagNotAvailable,
                    icon: const Icon(Icons.nfc, size: 18, color: AppColors.textSecondary),
                    label: Text('Add NFC tag', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.slaterspwn),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Create Record button — "Save and Continue" / "Finish" inside
            // the multi-animal flow, plain "Create Record" otherwise.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _createRecord,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.textPrimary))
                    : Text(_saveButtonLabel,
                        style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
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
  const _FieldLabel(this.label);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label,
          style: GoogleFonts.zain(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary)),
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

class _ExistingImageThumb extends StatelessWidget {
  final String url;
  final VoidCallback? onRemove;
  const _ExistingImageThumb({required this.url, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(url,
                width: 80,
                height: 80,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.tearspwn,
                    child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary))),
          ),
          if (onRemove != null)
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

class _PickedImageThumb extends StatelessWidget {
  final XFile file;
  final VoidCallback? onRemove;
  const _PickedImageThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      height: 80,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(File(file.path), width: 80, height: 80, fit: BoxFit.cover),
          ),
          if (onRemove != null)
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
