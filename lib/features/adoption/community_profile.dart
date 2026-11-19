import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/repos/community_adoption_request_repository.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

const List<String> kCommunitySexOptions = ['Male', 'Female', 'Unknown'];
const List<String> kCommunitySizeOptions = ['Small', 'Medium', 'Large'];
const List<String> kCommunityCoatOptions = ['Short', 'Medium', 'Long'];

/// The reporter's adoption profile for one animal of a Community Adoption
/// listing — the same kinds of details a shelter adoption card shows (name,
/// age, sex, size, coat, about, health tags and key characteristics).
/// Stored on the case as `communityListing.animals.<index>`.
class CommunityAnimalProfile {
  final String name;
  final DateTime? birthday;
  final String ageEstimate;
  final String sex;
  final String size;
  final String coatLength;
  final String about;
  final bool vaccinated;
  final bool spayedNeutered;
  final bool dewormed;
  final bool specialNeeds;
  final String specialNeedsDetails;
  final List<String> temperament;
  final List<String> goodWith;
  final List<String> training;
  final String healthNotes;

  const CommunityAnimalProfile({
    this.name = '',
    this.birthday,
    this.ageEstimate = '',
    this.sex = '',
    this.size = '',
    this.coatLength = '',
    this.about = '',
    this.vaccinated = false,
    this.spayedNeutered = false,
    this.dewormed = false,
    this.specialNeeds = false,
    this.specialNeedsDetails = '',
    this.temperament = const [],
    this.goodWith = const [],
    this.training = const [],
    this.healthNotes = '',
  });

  factory CommunityAnimalProfile.fromMap(Map<String, dynamic> m) {
    List<String> list(String k) => List<String>.from(m[k] ?? const []);
    String str(String k) => (m[k] as String?)?.trim() ?? '';
    final b = m['birthday'];
    return CommunityAnimalProfile(
      name: str('name'),
      birthday: b is Timestamp ? b.toDate() : null,
      ageEstimate: str('ageEstimate'),
      sex: str('sex'),
      size: str('size'),
      coatLength: str('coatLength'),
      about: str('about'),
      vaccinated: m['vaccinated'] == true,
      spayedNeutered: m['spayedNeutered'] == true,
      dewormed: m['dewormed'] == true,
      specialNeeds: m['specialNeeds'] == true,
      specialNeedsDetails: str('specialNeedsDetails'),
      temperament: list('temperament'),
      goodWith: list('goodWith'),
      training: list('training'),
      healthNotes: str('healthNotes'),
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    if (birthday != null) 'birthday': Timestamp.fromDate(birthday!),
    'ageEstimate': ageEstimate,
    'sex': sex,
    'size': size,
    'coatLength': coatLength,
    'about': about,
    'vaccinated': vaccinated,
    'spayedNeutered': spayedNeutered,
    'dewormed': dewormed,
    'specialNeeds': specialNeeds,
    'specialNeedsDetails': specialNeedsDetails,
    'temperament': temperament,
    'goodWith': goodWith,
    'training': training,
    'healthNotes': healthNotes,
  };

  bool get isComplete =>
      name.isNotEmpty &&
          (birthday != null || ageEstimate.isNotEmpty) &&
          about.isNotEmpty;

  /// "2 years old", "5 months old", or the reporter's estimate.
  String get ageText {
    final b = birthday;
    if (b == null) return ageEstimate;
    final now = DateTime.now();
    var months = (now.year - b.year) * 12 + now.month - b.month;
    if (now.day < b.day) months--;
    if (months < 1) return 'Under a month old';
    if (months < 12) return '$months month${months == 1 ? '' : 's'} old';
    final years = months ~/ 12;
    return '$years year${years == 1 ? '' : 's'} old';
  }

  /// The chips a shelter adoption card shows for health.
  List<String> get healthTags => [
    if (vaccinated) 'Vaccinated',
    if (spayedNeutered) 'Spayed/Neutered',
    if (dewormed) 'Dewormed',
    if (specialNeeds) 'Special Needs',
  ];

  String? get birthdayText {
    final b = birthday;
    return b == null ? null : '${b.month}/${b.day}/${b.year}';
  }
}

/// Profile for animal [index] of a case, falling back to the report's own
/// species/sex/size so the card is never blank.
CommunityAnimalProfile communityProfileOf(Map<String, dynamic> caseData, int index) {
  final saved = CommunityAdoptionRequestRepository.listingDetailsOf(caseData)[index];
  final animals = (caseData['animals'] as List?)?.whereType<Map>().toList() ?? const [];
  final raw = index < animals.length ? animals[index] : (index == 0 ? caseData : const {});
  final p = CommunityAnimalProfile.fromMap(saved ?? const {});
  // Before the reporter saves a profile, start from what the report already
  // says (a Pet Surrender's per-animal answers).
  final fromReport = saved == null;
  final reportGoodWith = [
    for (final v in raw['compatibility'] as List? ?? const [])
      if (kCompatibilityValues.contains(v)) v as String,
  ];
  return CommunityAnimalProfile(
    name: p.name,
    birthday: p.birthday,
    ageEstimate: fromReport ? (raw['age'] as String? ?? '') : p.ageEstimate,
    sex: p.sex.isNotEmpty ? p.sex : (raw['sex'] as String? ?? ''),
    size: p.size.isNotEmpty ? p.size : (raw['size'] as String? ?? ''),
    coatLength: p.coatLength,
    about: p.about,
    vaccinated: fromReport
        ? raw['vaccination'] == 'Fully vaccinated (up to date)'
        : p.vaccinated,
    spayedNeutered: fromReport ? raw['spayNeuter'] == 'Yes' : p.spayedNeutered,
    dewormed: p.dewormed,
    specialNeeds: p.specialNeeds,
    specialNeedsDetails: p.specialNeedsDetails,
    temperament: p.temperament,
    goodWith: fromReport ? reportGoodWith : p.goodWith,
    training: p.training,
    healthNotes: p.healthNotes,
  );
}

/// Full-screen editor for one animal's profile, opened from the reporter's
/// Manage Community Adoption page.
class CommunityProfileEditPage extends StatefulWidget {
  const CommunityProfileEditPage({
    super.key,
    required this.caseId,
    required this.index,
    required this.label,
    required this.initial,
    this.onSave,
  });

  final String caseId;
  final int index;
  final String label;
  final CommunityAnimalProfile initial;

  /// Saves the profile; defaults to the case document. Tests pass a fake.
  final Future<void> Function(CommunityAnimalProfile profile)? onSave;

  @override
  State<CommunityProfileEditPage> createState() => _CommunityProfileEditPageState();
}

class _CommunityProfileEditPageState extends State<CommunityProfileEditPage> {
  late final _name = TextEditingController(text: widget.initial.name);
  late final _age = TextEditingController(text: widget.initial.ageEstimate);
  late final _about = TextEditingController(text: widget.initial.about);
  late final _specialNeeds = TextEditingController(text: widget.initial.specialNeedsDetails);
  late final _healthNotes = TextEditingController(text: widget.initial.healthNotes);
  late DateTime? _birthday = widget.initial.birthday;
  late String? _sex = _orNull(widget.initial.sex, kCommunitySexOptions);
  late String? _size = _orNull(widget.initial.size, kCommunitySizeOptions);
  late String? _coat = _orNull(widget.initial.coatLength, kCommunityCoatOptions);
  late bool _vaccinated = widget.initial.vaccinated;
  late bool _spayed = widget.initial.spayedNeutered;
  late bool _dewormed = widget.initial.dewormed;
  late bool _hasSpecialNeeds = widget.initial.specialNeeds;
  late final Set<String> _temperament = {...widget.initial.temperament};
  late final Set<String> _goodWith = {...widget.initial.goodWith};
  late final Set<String> _training = {...widget.initial.training};
  bool _saving = false;
  String? _error;

  static String? _orNull(String v, List<String> options) => options.contains(v) ? v : null;

  @override
  void dispose() {
    for (final c in [_name, _age, _about, _specialNeeds, _healthNotes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? now,
      firstDate: DateTime(now.year - 25),
      lastDate: now,
      helpText: 'Birthday (approximate is fine)',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  CommunityAnimalProfile _profile() => CommunityAnimalProfile(
    name: _name.text.trim(),
    birthday: _birthday,
    ageEstimate: _age.text.trim(),
    sex: _sex ?? '',
    size: _size ?? '',
    coatLength: _coat ?? '',
    about: _about.text.trim(),
    vaccinated: _vaccinated,
    spayedNeutered: _spayed,
    dewormed: _dewormed,
    specialNeeds: _hasSpecialNeeds,
    specialNeedsDetails: _hasSpecialNeeds ? _specialNeeds.text.trim() : '',
    temperament: _temperament.toList(),
    goodWith: _goodWith.toList(),
    training: _training.toList(),
    healthNotes: _healthNotes.text.trim(),
  );

  Future<void> _save() async {
    final profile = _profile();
    if (!profile.isComplete) {
      setState(() => _error = 'Please add a name, a birthday or estimated age, and a short description.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final save = widget.onSave ??
              (p) => CommunityAdoptionRequestRepository().saveAnimalProfile(widget.caseId, widget.index, p.toMap());
      await save(profile);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Profile saved.'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save the profile: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Each dropdown is keyed by its own field name so sibling dropdowns never
  // share a key (two unset dropdowns once collided and crashed this form).
  Widget _dropdown(String field, String hint, String? value, List<String> options, ValueChanged<String?> onChanged) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$field:$value'),
      initialValue: value,
      isExpanded: true,
      isDense: true,
      decoration: InputDecoration(isDense: true, hintText: hint),
      items: [for (final o in options) DropdownMenuItem(value: o, child: Text(o))],
      onChanged: onChanged,
    );
  }

  Widget _chips(Set<String> set, List<String> options) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final o in options)
        RescueToggleChip(
          label: o,
          selected: set.contains(o),
          onTap: () => setState(() {
            if (!set.remove(o)) set.add(o);
          }),
        ),
    ],
  );

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    activeColor: AppColors.textPrimary,
    value: value,
    title: Text(label, style: GoogleFonts.zain(fontSize: 14)),
    onChanged: (v) => setState(() => onChanged(v ?? false)),
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
  );

  @override
  Widget build(BuildContext context) {
    final b = _birthday;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.yellowrspwn,
        title: Text('${widget.label} — Adoption Profile', style: GoogleFonts.tiltWarp(fontSize: 16)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _section('Basic Information'),
          RescueFieldLabel('Name', required: true),
          RescueTextField(_name, 'What should adopters call it?'),
          const SizedBox(height: 14),
          RescueFieldLabel('Birthday or estimated age', required: true),
          const SizedBox(height: 4),
          RescuePickerField(
            label: b == null ? 'Pick a birthday (if known)' : 'Birthday: ${b.month}/${b.day}/${b.year}',
            icon: Icons.cake_outlined,
            onTap: _pickBirthday,
          ),
          const SizedBox(height: 6),
          RescueTextField(_age, 'Or estimated age, e.g. about 1 year old'),
          const SizedBox(height: 14),
          RescueFieldLabel('Sex'),
          _dropdown('sex', 'Select sex', _sex, kCommunitySexOptions, (v) => setState(() => _sex = v)),
          const SizedBox(height: 14),
          RescueFieldLabel('Size'),
          _dropdown('size', 'Select size', _size, kCommunitySizeOptions, (v) => setState(() => _size = v)),
          const SizedBox(height: 14),
          RescueFieldLabel('Coat length'),
          _dropdown('coat', 'Select coat length', _coat, kCommunityCoatOptions, (v) => setState(() => _coat = v)),
          const SizedBox(height: 14),
          RescueFieldLabel('About this animal', required: true),
          TextField(
            controller: _about,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Personality, routine, where it stays now, why it would be a good pet…',
            ),
          ),

          _section('Health'),
          _check('Vaccinated', _vaccinated, (v) => _vaccinated = v),
          _check('Spayed / Neutered', _spayed, (v) => _spayed = v),
          _check('Dewormed', _dewormed, (v) => _dewormed = v),
          _check('Has special needs', _hasSpecialNeeds, (v) => _hasSpecialNeeds = v),
          if (_hasSpecialNeeds) RescueTextField(_specialNeeds, 'Describe the special needs'),
          const SizedBox(height: 8),
          RescueFieldLabel('Health notes'),
          RescueTextField(_healthNotes, 'e.g. dewormed last month, healed leg wound'),

          _section('Key Characteristics'),
          RescueFieldLabel('Temperament'),
          const SizedBox(height: 6),
          _chips(_temperament, kTemperamentValues),
          const SizedBox(height: 14),
          RescueFieldLabel('Good with'),
          const SizedBox(height: 6),
          _chips(_goodWith, kCompatibilityValues),
          const SizedBox(height: 14),
          RescueFieldLabel('Training'),
          const SizedBox(height: 6),
          _chips(_training, kTrainingValues),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.error)),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            style: AppButtons.primary,
            onPressed: _saving ? null : _save,
            child: Text('Save Profile', style: GoogleFonts.zain(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// One Community Adoption animal as the shelter adoption card
/// ([AnimalRecordCard]) — the same widget the Adopt a Stray list uses, fed
/// an [AnimalRecord] built from the reporter's profile and the report.
class CommunityAnimalCard extends StatelessWidget {
  const CommunityAnimalCard({
    super.key,
    required this.profile,
    required this.label,
    required this.species,
    required this.breed,
    this.photoUrl,
    this.statusLabel,
    this.fallbackDescription = '',
    this.onTap,
  });

  final CommunityAnimalProfile profile;
  final String label;
  final String species;
  final String breed;
  final String? photoUrl;
  final String? statusLabel;

  /// Shown when the reporter hasn't written an "About" yet (e.g. the
  /// report's description or surrender reason).
  final String fallbackDescription;
  final VoidCallback? onTap;

  AnimalRecord get record {
    final p = profile;
    return AnimalRecord.fromMap('community_$label', {
    'name': p.name.isNotEmpty ? p.name : label,
    'age': p.ageText,
    'species': species,
    'breed': breed,
    'sex': p.sex,
    'size': p.size,
    'coatLength': p.coatLength,
    'description': p.about.isNotEmpty ? p.about : fallbackDescription,
    'vaccinated': p.vaccinated,
    'spayedNeutered': p.spayedNeutered,
    'dewormed': p.dewormed,
    'specialNeeds': p.specialNeeds,
    if (p.specialNeedsDetails.isNotEmpty) 'specialNeedsNotes': p.specialNeedsDetails,
    'keyCharacteristics': [...p.temperament, ...p.goodWith, ...p.training],
    'adoptionStatus': statusLabel == 'Adopted' ? 'adopted' : 'adoptable',
    'photoUrls': [?photoUrl],
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimalRecordCard(
      animal: record,
      onTap: onTap ?? () {},
      publicStatusLabel: statusLabel,
      // Same chips as the Adopt a Stray list: health tags, with Special
      // Needs left to the card's own badge.
      extraChips: [
        for (final t in profile.healthTags)
          if (t != 'Special Needs') CardChip(t),
      ],
      showInShelterBadge: false,
    );
  }
}
