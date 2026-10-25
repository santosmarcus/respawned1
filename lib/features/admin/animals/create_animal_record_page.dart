import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';

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
  State<CreateAnimalRecordPage> createState() => _CreateAnimalRecordPageState();
}

class _CreateAnimalRecordPageState extends State<CreateAnimalRecordPage> {
  // Images — required for brand-new records (at least one), never required
  // to correct/re-save a legacy record that already opens without one — see
  // _createRecord's validation, gated on `!widget.isEditing`.
  final _picker = ImagePicker();
  final List<XFile> _pickedImages = [];
  // Edit mode only — already-uploaded photos, individually removable;
  // newly picked images are uploaded and appended alongside whatever
  // remains of this list on Save.
  late List<String> _existingPhotoUrls = List<String>.from(
    widget.existingData?['photoUrls'] ?? const [],
  );
  bool _isUploadingImages = false;
  String? _imageError;
  // Scrolled/focused into view when submission fails the image check.
  final _imagesSectionKey = GlobalKey();

  // Basic info
  final _nameController = TextEditingController();
  // Age is still stored as a single `age` string field on AnimalRecord
  // (e.g. "2 years") — every existing reader (cards, detail pages) keeps
  // working unchanged. Only this form's input changed, from a freeform
  // text field to a constrained amount+unit pair, normalized into that
  // same string format on save. amount options cover 1-30, generous enough
  // for any realistic shelter animal age in weeks, months, or years.
  static const _ageAmountOptions = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
    '11',
    '12',
    '13',
    '14',
    '15',
    '16',
    '17',
    '18',
    '19',
    '20',
    '21',
    '22',
    '23',
    '24',
    '25',
    '26',
    '27',
    '28',
    '29',
    '30',
  ];
  static const _ageUnitOptions = ['weeks', 'months', 'years'];
  String? _ageAmount;
  String? _ageUnit;
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  String? _selectedSpecies;
  // Editable at creation (free-text field below); locked/read-only once
  // the record exists — see the identity-lock spec these three fields
  // (Sex/Species/Breed) share.
  String? _selectedBreed;
  final _breedController = TextEditingController();
  String? _selectedSex;
  String? _selectedSize;
  String? _selectedCoatLength;
  bool _isAdoptable = true;
  bool _isLoading = false;

  // Preventive Care — unchecked when unknown, never inferred. Vaccinated
  // was removed from creation entirely (spec: vaccines are recorded after
  // creation via the Vaccines/Medical tab, where individual vaccine names/
  // dates/doses/boosters can be tracked correctly) — legacy documents that
  // already have a `vaccinated` boolean keep it untouched, since this
  // form's save payload no longer writes that key at all.
  bool _spayedNeutered = false;
  bool _dewormed = false;

  // Special Needs — separate from Preventive Care/Temperament/
  // Compatibility/Training and from the free-text current condition /
  // diagnosis / medical history / allergies fields (see
  // AnimalHealthDetails). A dropdown-style field opening a multi-select
  // bottom sheet (_openSpecialNeedsSheet) rather than an always-visible
  // checkbox list. hasSpecialNeeds is derived (see getter below), not a
  // separately-tracked toggle — selecting/clearing options in the sheet is
  // itself the deliberate action, applied only when "Done" is tapped.
  final Map<String, bool> _specialNeedsTypes = {
    for (final v in kSpecialNeedsTypeValues) v: false,
  };
  final _specialNeedsOtherController = TextEditingController();
  final _specialNeedsNotesController = TextEditingController();

  /// Selected structured values, with a valid trimmed "Other" custom entry
  /// folded in (deduped) and the literal "Other" placeholder itself never
  /// included. Empty when nothing valid is selected.
  List<String> get _selectedSpecialNeedsTypes {
    final result = <String>[
      for (final entry in _specialNeedsTypes.entries)
        if (entry.key != kSpecialNeedsOtherValue && entry.value) entry.key,
    ];
    if (_specialNeedsTypes[kSpecialNeedsOtherValue] == true) {
      final custom = _specialNeedsOtherController.text.trim();
      if (custom.isNotEmpty && !result.contains(custom)) result.add(custom);
    }
    return result;
  }

  /// hasSpecialNeeds = specialNeeds is not empty (spec section 5) — no
  /// separate stored/tracked flag in this form.
  bool get _hasSpecialNeeds => _selectedSpecialNeedsTypes.isNotEmpty;

  String get _specialNeedsSummary {
    final n = _selectedSpecialNeedsTypes.length;
    if (n == 0) return 'None selected';
    return '$n selected';
  }

  Future<void> _openSpecialNeedsSheet() async {
    final tempSelections = Map<String, bool>.from(_specialNeedsTypes);
    final tempOtherController = TextEditingController(
      text: _specialNeedsOtherController.text,
    );
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Special Needs',
                  style: GoogleFonts.tiltWarp(
                    fontSize: 17,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Select all that apply.',
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                for (final option in kSpecialNeedsTypeValues)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: AppColors.greenrspwn,
                    title: Text(
                      option,
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    value: tempSelections[option] ?? false,
                    onChanged: (v) => setSheetState(
                      () => tempSelections[option] = v ?? false,
                    ),
                  ),
                if (tempSelections[kSpecialNeedsOtherValue] == true) ...[
                  const SizedBox(height: 8),
                  _FieldLabel('Specify special need'),
                  _UnderlineField(
                    controller: tempOtherController,
                    hint: 'Enter',
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true) {
      setState(() {
        _specialNeedsTypes
          ..clear()
          ..addAll(tempSelections);
        _specialNeedsOtherController.text = tempOtherController.text;
      });
    }
  }

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

  // Rescue Background — single-select (Rescued / Transferred / Surrendered
  // describe how the animal came to the org in the first place, which is
  // one fact, not several that can be true at once). Auto-set to 'Rescued'
  // whenever this record comes from the rescue workflow (linkedCaseId set).
  static const _rescueBackgroundOptions = [
    'Rescued',
    'Transferred',
    'Surrendered',
  ];
  String? _rescueBackground;

  String get _saveButtonLabel {
    if (widget.isEditing) return 'Save Changes';
    if (widget.stepCurrent == null || widget.stepTotal == null)
      return 'Create Record';
    return widget.stepCurrent! >= widget.stepTotal!
        ? 'Finish'
        : 'Save and Continue';
  }

  /// True only on the save that actually makes this animal newly adoptable
  /// — a brand-new record created adoptable, or an edit that flips a
  /// previously not-ready animal to adoptable. False when re-saving an
  /// already-adoptable record's other fields, so that doesn't fire a
  /// second "ready for adoption" notification. See _notifyInterestedAdopter.
  bool get _becameAdoptableThisSave {
    if (!_isAdoptable) return false;
    if (!widget.isEditing) return true;
    return widget.existingData?['adoptionStatus'] != 'adoptable';
  }

  /// Lets whoever already expressed interest in adopting this animal (at
  /// report time via `interestedToAdopt`, or later via
  /// track_case_page.dart's "Interest to Adopt"/"Interest to Foster"
  /// buttons via `willingAdopterId`) know the moment it's actually ready —
  /// otherwise that interest just sits on the case with nothing telling
  /// them to come back.
  ///
  /// A single `statusHistory` entry on the case covers both audiences:
  /// notifications_screen.dart watches `cases` where `reporterId == uid`
  /// (covers the reporter's own interest) AND, separately, `cases` where
  /// `willingAdopterId == uid` (covers a different user's interest
  /// registered via track_case_page.dart's _registerInterest) — both
  /// build their notification feed straight from this same array, so one
  /// write reaches whichever of them actually exists on this case. No
  /// separate notification collection needed.
  ///
  /// Best-effort: never blocks or fails the record save itself.
  Future<void> _notifyInterestedAdopter({
    required String caseId,
    required String animalId,
    required String animalName,
  }) async {
    try {
      final caseSnap = await FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .get();
      final caseData = caseSnap.data();
      if (caseData == null) return;

      final reporterInterested = caseData['interestedToAdopt'] == 'yes';
      final willingAdopterId = caseData['willingAdopterId'] as String?;
      final hasWillingAdopter =
          willingAdopterId != null && willingAdopterId.isNotEmpty;
      if (!reporterInterested && !hasWillingAdopter) return;

      final displayName = animalName.isEmpty ? 'This animal' : animalName;
      final message =
          '$displayName is now ready for adoption! Reach out through the app to start the process.';

      await FirebaseFirestore.instance.collection('cases').doc(caseId).update({
        'statusHistory': FieldValue.arrayUnion([
          {'status': message, 'timestamp': Timestamp.now()},
        ]),
      });
    } catch (_) {
      // Never block the record save on a notification failure.
    }
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
    _breedController.text = _selectedBreed ?? '';
  }

  /// Parses a saved `age` string like "2 years" (or legacy free-text like
  /// "2 years, 6 months old") back into an amount+unit pair for the
  /// dropdowns to initialize from. Only ever matches the FIRST amount+unit
  /// it finds — a compound legacy value has no single amount+unit
  /// representation in this constrained selector, and normalizes down to
  /// just that first part once saved again (the intended effect of
  /// replacing freeform age entry with a structured one).
  void _parseAge(String raw) {
    final match = RegExp(
      r'(\d+)\s*(week|month|year)s?',
      caseSensitive: false,
    ).firstMatch(raw);
    if (match == null) return;
    final amount = int.tryParse(match.group(1)!);
    if (amount == null || amount < 1 || amount > 30) return;
    _ageAmount = '$amount';
    _ageUnit = '${match.group(2)!.toLowerCase()}s';
  }

  /// Edit mode — every field starts from the record's own saved values
  /// (never the original report; that prefill only applies to brand-new
  /// records).
  void _prefillFromExisting() {
    final d = widget.existingData!;
    _nameController.text = d['name'] as String? ?? '';
    _parseAge(d['age'] as String? ?? '');
    _descriptionController.text = d['description'] as String? ?? '';
    _tagsController.text = List<String>.from(d['tags'] ?? const []).join(', ');
    _selectedSpecies = (d['species'] as String?)?.isNotEmpty == true
        ? d['species'] as String
        : null;
    _selectedBreed = (d['breed'] as String?)?.isNotEmpty == true
        ? d['breed'] as String
        : null;
    _selectedSex = (d['sex'] as String?)?.isNotEmpty == true
        ? d['sex'] as String
        : null;
    _selectedSize = (d['size'] as String?)?.isNotEmpty == true
        ? d['size'] as String
        : null;
    _selectedCoatLength = (d['coatLength'] as String?)?.isNotEmpty == true
        ? d['coatLength'] as String
        : null;
    _isAdoptable = d['adoptionStatus'] == 'adoptable';
    // 'vaccinated' is intentionally never read back into form state here —
    // the field was removed from creation/edit entirely (spec section 4).
    // A legacy document's existing `vaccinated` value is left untouched by
    // this form's save payload (that key is simply never written), so
    // editing other fields on an old record can't silently clobber it.
    _spayedNeutered = d['spayedNeutered'] as bool? ?? false;
    _dewormed = d['dewormed'] as bool? ?? false;

    final existingSpecialNeedsTypes = List<String>.from(
      d['specialNeedsTypes'] ?? const [],
    );
    final existingSpecialNeedsNotes =
        (d['specialNeedsNotes'] as String?)?.trim() ?? '';
    final unmatched = <String>[];
    for (final value in existingSpecialNeedsTypes) {
      if (_specialNeedsTypes.containsKey(value)) {
        _specialNeedsTypes[value] = true;
      } else {
        unmatched.add(value);
      }
    }
    if (unmatched.isNotEmpty) {
      _specialNeedsTypes[kSpecialNeedsOtherValue] = true;
      _specialNeedsOtherController.text = unmatched.join(', ');
    }
    _specialNeedsNotesController.text = existingSpecialNeedsNotes;

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
    _rescueBackground = _rescueBackgroundOptions.cast<String?>().firstWhere(
      (key) => background.contains(key),
      orElse: () => null,
    );
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
      final match = ['Male', 'Female', 'Unknown'].cast<String?>().firstWhere(
        (s) => s!.toLowerCase() == sex.toLowerCase(),
        orElse: () => null,
      );
      if (match != null) _selectedSex = match;
    }

    final size = (d['size'] as String?)?.trim();
    if (size != null) {
      final match = ['Small', 'Medium', 'Large'].cast<String?>().firstWhere(
        (s) => s!.toLowerCase() == size.toLowerCase(),
        orElse: () => null,
      );
      if (match != null) _selectedSize = match;
    }

    // Report breed/"condition"/color-markings text folded into the
    // description so nothing captured at report time is lost, even though
    // this form has no dedicated breed/color field of its own.
    final descriptionParts = <String>[
      if ((d['description'] as String?)?.isNotEmpty ?? false)
        d['description'] as String,
      if ((d['colorMarkings'] as String?)?.isNotEmpty ?? false)
        'Color/markings: ${d['colorMarkings']}',
    ];
    _descriptionController.text = descriptionParts.join('\n');

    // This record came from the rescue workflow — "Rescued" is implied,
    // not something the org has to remember to tick.
    if (widget.linkedCaseId != null) {
      _rescueBackground = 'Rescued';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _breedController.dispose();
    _specialNeedsOtherController.dispose();
    _specialNeedsNotesController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: AppColors.textPrimary,
              ),
              title: Text(
                'Choose from Gallery',
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: AppColors.textPrimary,
              ),
              title: Text(
                'Take Photo',
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
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
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );
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
    // Image required for brand-new records only — a legacy record already
    // open for editing is never blocked just because it has no photo yet.
    final missingImage =
        !widget.isEditing &&
        _existingPhotoUrls.isEmpty &&
        _pickedImages.isEmpty;

    // Required fields — breed is deliberately not checked here: this form
    // has no editable breed input at all (see the field's own comment
    // above), only ever set from an intake report's prefill, so there is
    // nothing to validate against when creating a record from scratch.
    final missing = <String>[
      if (missingImage) 'At least one image',
      if (_nameController.text.trim().isEmpty) 'Name',
      if (_selectedSpecies == null) 'Species',
      if (_selectedSex == null) 'Gender',
      if (_ageAmount == null || _ageUnit == null) 'Age',
      if (_selectedSize == null) 'Size',
      if (_selectedCoatLength == null) 'Coat Length',
      if (_rescueBackground == null) 'Rescue Background',
      if (_descriptionController.text.trim().isEmpty) 'Description',
    ];
    if (missing.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please fill in: ${missing.join(', ')}.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      if (missingImage) {
        setState(() => _imageError = 'At least one image is required.');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final imageCtx = _imagesSectionKey.currentContext;
          if (imageCtx != null) {
            Scrollable.ensureVisible(
              imageCtx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        });
      }
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
        final caseSnap = await FirebaseFirestore.instance
            .collection('cases')
            .doc(widget.linkedCaseId)
            .get();
        final caseData = caseSnap.data();
        // Multi-animal Intake evaluates receipt per animal (spec) — one
        // received animal must never unlock record creation for another.
        // Falls back to the case-level flag for a legacy case with no
        // animals[] array, or when this creation isn't scoped to one
        // specific animal at all.
        final animalsRaw = caseData?['animals'] as List?;
        final sourceIndex = widget.sourceAnimalIndex;
        bool received;
        if (sourceIndex != null &&
            animalsRaw != null &&
            sourceIndex >= 0 &&
            sourceIndex < animalsRaw.length) {
          final animal = animalsRaw[sourceIndex];
          received = animal is Map && animal['receivedAt'] != null;
        } else {
          received = caseData?['intakeReceivedAt'] != null;
        }
        if (!received) {
          if (mounted) {
            setState(() => _isLoading = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'The animal must be confirmed received before creating records.',
                ),
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
      if (!widget.isEditing &&
          widget.linkedCaseId != null &&
          widget.sourceAnimalIndex != null) {
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
          ? FirebaseFirestore.instance
                .collection('animals')
                .doc(widget.existingAnimalId)
          : FirebaseFirestore.instance.collection('animals').doc();

      final uploadedUrls = <String>[];
      if (_pickedImages.isNotEmpty) {
        setState(() => _isUploadingImages = true);
        try {
          for (var i = 0; i < _pickedImages.length; i++) {
            final file = _pickedImages[i];
            final ext = file.path.contains('.')
                ? file.path.split('.').last
                : 'jpg';
            final filename = '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
            final url = await _uploadImage(
              file,
              'animalRecords/${docRef.id}/images/$filename',
            );
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

      // Still written as a list (matching AnimalRecord.rescueBackground's
      // existing List<String> field/every reader of it) — just 0 or 1
      // entries now that selection is single-choice.
      final selectedBackground = _rescueBackground == null
          ? <String>[]
          : [_rescueBackground!];

      final tags = _tagsController.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final health = <String>[];
      if (_spayedNeutered) health.add('Spayed/Neutered');
      if (_dewormed) health.add('Dewormed');
      if (_hasSpecialNeeds) health.add('Special Needs');
      final selectedSpecialNeedsTypes = _selectedSpecialNeedsTypes;
      final specialNeedsNotes = _specialNeedsNotesController.text.trim();

      final sharedFields = {
        'name': _nameController.text.trim(),
        'age': '$_ageAmount $_ageUnit',
        'species': _selectedSpecies,
        'breed': _selectedBreed ?? '',
        'sex': _selectedSex ?? '',
        'size': _selectedSize ?? '',
        'coatLength': _selectedCoatLength ?? '',
        'description': _descriptionController.text.trim(),
        'health': health,
        // 'vaccinated' deliberately not written here at all (spec section
        // 4) — an existing legacy value on `docRef` is left exactly as-is
        // by this partial `update()`/first-time `set()`.
        'spayedNeutered': _spayedNeutered,
        'dewormed': _dewormed,
        'specialNeeds': _hasSpecialNeeds,
        'specialNeedsTypes': selectedSpecialNeedsTypes,
        'specialNeedsNotes': _hasSpecialNeeds && specialNeedsNotes.isNotEmpty
            ? specialNeedsNotes
            : null,
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
          if (widget.sourceAnimalIndex != null)
            'sourceAnimalIndex': widget.sourceAnimalIndex,
          'rescuedBy': widget.prefillData?['rescuedBy'] ?? 'Loved by the Gapz',
          'intakeStaffId': uid,
          'photoUrls': uploadedUrls.isNotEmpty
              ? uploadedUrls
              : (fallbackPhotoUrl != null ? [fallbackPhotoUrl] : []),
          'treatmentLog': [],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          // prefilled from intake/the source rescue report if available
          if (widget.prefillData != null) ...{
            'vetClinicName': widget.prefillData!['vetClinicName'] ?? '',
            'intakeNotes': widget.prefillData!['intakeNotes'] ?? '',
            'reporterName': widget.prefillData!['reporterName'] ?? '',
            'transporterName': widget.prefillData!['transporterName'] ?? '',
            if (widget.prefillData!['rescueDate'] is Timestamp)
              'rescueDate': widget.prefillData!['rescueDate'],
          },
        });
      }

      final actorDisplayName = FirebaseAuth.instance.currentUser?.displayName
          ?.trim();
      final actorEmail = FirebaseAuth.instance.currentUser?.email;
      final logRepo = AnimalRecordRepository();
      if (widget.isEditing) {
        final prevSpecialNeedsTypes =
            (widget.existingData?['specialNeedsTypes'] as List?)
                ?.cast<String>() ??
            const <String>[];
        final specialNeedsChanged =
            prevSpecialNeedsTypes.toSet() !=
                selectedSpecialNeedsTypes.toSet() ||
            (widget.existingData?['specialNeeds'] as bool? ?? false) !=
                _hasSpecialNeeds;
        await logRepo.logManagementEvent(
          animalId: docRef.id,
          eventType: 'profile_edited',
          action: 'Profile edited',
          actorId: uid,
          actorName: (actorDisplayName?.isNotEmpty ?? false)
              ? actorDisplayName
              : 'Admin Staff',
          actorEmail: actorEmail,
        );
        if (specialNeedsChanged) {
          await logRepo.logManagementEvent(
            animalId: docRef.id,
            eventType: 'special_needs_changed',
            action: 'Special Needs changed',
            actorId: uid,
            actorName: (actorDisplayName?.isNotEmpty ?? false)
                ? actorDisplayName
                : 'Admin Staff',
            actorEmail: actorEmail,
            previousValues: {'specialNeedsTypes': prevSpecialNeedsTypes},
            newValues: {'specialNeedsTypes': selectedSpecialNeedsTypes},
          );
        }
      } else {
        await logRepo.logManagementEvent(
          animalId: docRef.id,
          eventType: 'record_created',
          action: 'Animal Record created',
          actorId: uid,
          actorName: (actorDisplayName?.isNotEmpty ?? false)
              ? actorDisplayName
              : 'Admin Staff',
          actorEmail: actorEmail,
          sourceModule: widget.linkedCaseId != null
              ? 'rescue'
              : 'animalRecords',
          sourceRecordId: widget.linkedCaseId,
        );
      }

      final caseIdForNotification =
          widget.linkedCaseId ??
          widget.existingData?['linkedCaseId'] as String?;
      if (_becameAdoptableThisSave &&
          caseIdForNotification != null &&
          caseIdForNotification.isNotEmpty) {
        await _notifyInterestedAdopter(
          caseId: caseIdForNotification,
          animalId: docRef.id,
          animalName: _nameController.text.trim(),
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEditing ? 'Profile updated!' : 'Animal record created!',
            ),
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
        title: Text(
          widget.isEditing ? 'Edit Profile' : 'Animal Records',
          style: GoogleFonts.tiltWarp(
            fontSize: 18,
            color: AppColors.background,
          ),
        ),
        actions: [
          if (!widget.isEditing)
            IconButton(
              icon: const Icon(
                Icons.notifications_outlined,
                color: AppColors.background,
              ),
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
                  fontSize: 20,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (widget.stepCurrent != null && widget.stepTotal != null) ...[
              const SizedBox(height: 4),
              Center(
                child: Text(
                  'Animal ${widget.stepCurrent} of ${widget.stepTotal}',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Center(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                  children: const [
                    TextSpan(
                      text: '* ',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(text: 'Required fields'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ---- Images -------------------------------------------------
            // Required for new records (spec section 2); optional when
            // editing a legacy record that may not have one yet.
            Container(
              key: _imagesSectionKey,
              child: _FieldLabel('Images', required: !widget.isEditing),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _existingPhotoUrls.length; i++)
                  _ExistingImageThumb(
                    url: _existingPhotoUrls[i],
                    onRemove: _isLoading
                        ? null
                        : () => setState(() => _existingPhotoUrls.removeAt(i)),
                  ),
                for (var i = 0; i < _pickedImages.length; i++)
                  _PickedImageThumb(
                    file: _pickedImages[i],
                    onRemove: _isLoading ? null : () => _removeImage(i),
                  ),
                GestureDetector(
                  onTap: _isLoading ? null : _pickImages,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.greenrspwn,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.add_a_photo_outlined,
                        size: 26,
                        color: AppColors.greenrspwn,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_isUploadingImages) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Uploading images…',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
            if (_imageError != null) ...[
              const SizedBox(height: 8),
              Text(
                _imageError!,
                style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent),
              ),
            ],

            const SizedBox(height: 20),

            // ---- Basic information -------------------------------------
            _FieldLabel('Basic Information'),
            const SizedBox(height: 8),

            _FieldLabel('Name', required: true),
            _UnderlineField(controller: _nameController, hint: 'Enter'),
            const SizedBox(height: 16),

            _FieldLabel('Age', required: true),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _DropdownField(
                    value: _ageAmount,
                    hint: 'Amount',
                    items: _ageAmountOptions,
                    onChanged: (v) => setState(() => _ageAmount = v),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DropdownField(
                    value: _ageUnit,
                    hint: 'Unit',
                    items: _ageUnitOptions,
                    onChanged: (v) => setState(() => _ageUnit = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            _FieldLabel('Species', required: true),
            const SizedBox(height: 6),
            // Locked once the record exists — species is a core identity
            // field, never changeable after creation (only at creation
            // time, via the checkboxes below).
            if (widget.isEditing)
              _LockedFieldValue(value: _selectedSpecies ?? 'Not specified')
            else
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

            _FieldLabel('Breed'),
            const SizedBox(height: 6),
            // Same lock rule as Species/Sex — editable only at creation.
            if (widget.isEditing)
              _LockedFieldValue(value: _selectedBreed ?? 'Not specified')
            else
              TextField(
                controller: _breedController,
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'e.g. Aspin, Shih Tzu, Domestic Shorthair',
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
                ),
                onChanged: (v) => _selectedBreed = v.trim().isEmpty ? null : v.trim(),
              ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FieldLabel('Sex', required: true),
                      // Locked once the record exists — same identity-lock
                      // rule as Species/Breed above.
                      if (widget.isEditing)
                        _LockedFieldValue(value: _selectedSex ?? 'Not specified')
                      else
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
                      _FieldLabel('Size', required: true),
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

            _FieldLabel('Coat Length', required: true),
            _DropdownField(
              value: _selectedCoatLength,
              hint: 'Select',
              items: const ['Short', 'Medium', 'Long'],
              onChanged: (v) => setState(() => _selectedCoatLength = v),
            ),

            const SizedBox(height: 20),

            // ---- Preventive Care -------------------------------------------
            // Renamed from "Health" (visible label only — Firestore fields
            // spayedNeutered/dewormed are unchanged). Vaccinated was removed
            // from creation entirely; vaccines are recorded afterward via
            // the Medical tab's Vaccines workflow, where individual vaccine
            // names/dates/doses/boosters can be tracked correctly.
            _FieldLabel('Preventive Care'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
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
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Vaccines can be added after the Animal Record is created from the Medical tab.',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ---- Special Needs --------------------------------------------
            // Separate from Preventive Care/Temperament/Compatibility/
            // Training and from current condition/diagnosis/medical
            // history/allergies — never merged into those lists.
            // Dropdown-style field opening a multi-select bottom sheet.
            _FieldLabel('Special Needs'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _openSpecialNeedsSheet,
              child: InputDecorator(
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.only(bottom: 8),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppColors.textPrimary),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _specialNeedsSummary,
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
            if (_selectedSpecialNeedsTypes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final need in _selectedSpecialNeedsTypes)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.tearspwn.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        need,
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _FieldLabel('Additional special-needs information'),
            _UnderlineField(
              controller: _specialNeedsNotesController,
              hint: 'Optional',
            ),

            const SizedBox(height: 20),

            // ---- Description ------------------------------------------
            // Shown above Temperament (spec section 7) on both creation
            // and display pages.
            _FieldLabel('Description', required: true),
            _UnderlineField(controller: _descriptionController, hint: 'Enter'),

            const SizedBox(height: 20),

            // ---- Temperament ----------------------------------------------
            _FieldLabel('Temperament'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: _temperament.keys
                  .map(
                    (key) => _CheckboxField(
                      label: key,
                      value: _temperament[key]!,
                      onChanged: (v) => setState(() => _temperament[key] = v!),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Compatibility ----------------------------------------------
            _FieldLabel('Compatibility'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: _compatibility.keys
                  .map(
                    (key) => _CheckboxField(
                      label: key,
                      value: _compatibility[key]!,
                      onChanged: (v) =>
                          setState(() => _compatibility[key] = v!),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Training ----------------------------------------------
            _FieldLabel('Training'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: _training.keys
                  .map(
                    (key) => _CheckboxField(
                      label: key,
                      value: _training[key]!,
                      onChanged: (v) => setState(() => _training[key] = v!),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 20),

            // ---- Rescue Background (single-select) -------------------------
            // Fixed-position checkbox rows, not ChoiceChips — chips reflow/
            // resize on selection (the chip that's checked can grow, and the
            // Wrap can reorder as widths change), which reads as the whole
            // control "moving" every time you pick an option. Rows in a
            // Column never resize or reorder; only their checkmark changes.
            // Still single-select — checking one clears the other two.
            _FieldLabel('Rescue Background', required: true),
            const SizedBox(height: 4),
            Column(
              children: [
                for (final key in _rescueBackgroundOptions)
                  CheckboxListTile(
                    key: ValueKey(key),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: AppColors.greenrspwn,
                    title: Text(
                      key,
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    value: _rescueBackground == key,
                    onChanged: (checked) => setState(
                      () => _rescueBackground = (checked ?? false) ? key : null,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // ---- Remaining fields -------------------------------------
            // Rescued by (autofill, read-only)
            _FieldLabel('Rescued by'),
            Text(
              (widget.prefillData?['rescuedBy'] as String?) ??
                  'Loved by the Gapz',
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),

            // Rescue Case ID (autofill, read-only)
            _FieldLabel('Rescue Case ID'),
            Text(
              widget.linkedCaseId ?? 'Autofill',
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),

            _FieldLabel('Adoptable'),
            const SizedBox(height: 4),
            Switch(
              value: _isAdoptable,
              onChanged: (v) => setState(() => _isAdoptable = v),
              activeThumbColor: AppColors.greenrspwn,
            ),
            const SizedBox(height: 16),

            _FieldLabel('Tags'),
            _UnderlineField(
              controller: _tagsController,
              hint: 'e.g. senior, house-trained',
            ),
            const SizedBox(height: 16),

            // Any tag already scanned during the original rescue report —
            // shown for reference only. It is NOT a generated animal-record
            // QR/NFC tag and the two are never conflated.
            if ((widget.prefillData?['scannedTagId'] as String?)?.isNotEmpty ??
                false) ...[
              _FieldLabel('Scanned Tag (from rescue report)'),
              Text(
                widget.prefillData!['scannedTagId'] as String,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // QR — not functional yet. Disabled rather than a silent
            // no-op, so tapping it is honest about the current state
            // instead of doing nothing. See the class doc comment's TODO.
            // Never saves fake/placeholder QR data. NFC tag assignment was
            // removed from this form entirely (QR/NFC generation stays
            // deferred; a legacy record's own scanned tag, if any, is
            // still shown read-only above).
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _showTagNotAvailable,
                icon: const Icon(
                  Icons.qr_code,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                label: Text(
                  'Add QR',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.slaterspwn),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Text(
                        _saveButtonLabel,
                        style: GoogleFonts.tiltWarp(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
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
  // One shared label widget for every field on this form, rather than
  // hand-styling an asterisk per label — [required] must stay in sync with
  // the actual `missing` check in _createRecord() (see the field list
  // there), never marked just because a field "feels" mandatory.
  final bool required;
  const _FieldLabel(this.label, {this.required = false});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: GoogleFonts.zain(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      if (required)
        const Text(
          ' *',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.redAccent,
          ),
        ),
    ],
  );
}

class _UnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _UnderlineField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.textPrimary),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
      ),
      isDense: true,
      contentPadding: const EdgeInsets.only(bottom: 8),
    ),
    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
  );
}

/// Read-only display for Sex/Species/Breed once an Animal Record exists —
/// these are core identity fields, editable only at creation. Kept clearly
/// readable (full-strength text/border colors, not dimmed) with a small
/// lock icon as the only visual cue that it's non-interactive, rather than
/// disabling the original dropdown/checkbox widgets (which would still
/// look tappable).
class _LockedFieldValue extends StatelessWidget {
  final String value;
  const _LockedFieldValue({required this.value});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: AppColors.slaterspwn.withValues(alpha: 0.2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppColors.slaterspwn),
    ),
    child: Row(
      children: [
        Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
        const Icon(Icons.lock_outline, size: 15, color: AppColors.textSecondary),
      ],
    ),
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
    hint: Text(
      hint,
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
    ),
    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
    decoration: const InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.only(bottom: 8),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.textPrimary),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
      ),
    ),
    items: items
        .map(
          (item) => DropdownMenuItem(
            value: item,
            child: Text(item, style: GoogleFonts.zain(fontSize: 14)),
          ),
        )
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
        width: 18,
        height: 18,
        child: Checkbox(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
      ),
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
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : Colors.transparent,
            border: Border.all(color: AppColors.textPrimary, width: 1.5),
            borderRadius: BorderRadius.circular(2),
          ),
          child: selected
              ? const Icon(Icons.check, size: 12, color: Colors.white)
              : null,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
        ),
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
            child: Image.network(
              url,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 80,
                height: 80,
                color: AppColors.tearspwn,
                child: const Icon(
                  Icons.image_not_supported_outlined,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE05353),
                    shape: BoxShape.circle,
                  ),
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
            child: Image.file(
              File(file.path),
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: -6,
              right: -6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE05353),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
