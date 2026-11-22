import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/donation/models.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_service.dart';
import 'sponsorable_animals.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/admin/stock/stock_service.dart' show stockUnits;

/// Starting values for a new campaign opened from somewhere else in the app
/// (e.g. a rescue case's outstanding treatment balance). Everything stays
/// editable in the form; the backend validates it as usual.
class CampaignPrefill {
  final String title;
  final String description;
  final double targetAmount;
  final String fundKind;
  final Set<String> purposeTags;
  final bool restricted;
  final String? linkedCaseId;
  final DateTime? deadline;

  const CampaignPrefill({
    required this.title,
    required this.description,
    required this.targetAmount,
    this.fundKind = 'campaign',
    this.purposeTags = const {},
    this.restricted = false,
    this.linkedCaseId,
    this.deadline,
  });

  /// A medical fundraiser for a case's uncovered treatment costs. Restricted,
  /// since donors give for this animal's treatment (functions/campaigns.js
  /// then never lets the money move to another campaign). The goal is the
  /// outstanding balance rounded up to the next ₱500.
  factory CampaignPrefill.forCaseTreatment(RescueCase rescueCase, double outstandingBalance) {
    final clinic = (rescueCase.vetClinicName ?? '').isNotEmpty ? rescueCase.vetClinicName! : 'the clinic';
    final condition = rescueCase.condition?.trim() ?? '';
    final goal = (outstandingBalance / 500).ceil() * 500.0;
    final now = DateTime.now();
    return CampaignPrefill(
      title: 'Help ${rescueCase.speciesSummary} #${rescueCase.shortCaseId} recover',
      description: [
        if (condition.isNotEmpty) condition,
        'Ongoing treatment at $clinic. Funds raised cover this rescue\'s veterinary bills.',
      ].join('\n\n'),
      targetAmount: goal,
      fundKind: 'medical',
      purposeTags: const {'Medicine & Treatment', 'Rescue'},
      restricted: true,
      linkedCaseId: rescueCase.id,
      deadline: DateTime(now.year, now.month, now.day + 30, 23, 59),
    );
  }
}

/// Figma "New Campaign" / "New Sponsorship" form
class DonationAdminCreatePage extends ConsumerStatefulWidget {
  final DonationListing? existing;
  final String initialType;
  /// Chosen in [SponsorAnimalPickerPage]: the form opens filled from its record.
  final AnimalRecord? initialAnimal;
  final CampaignPrefill? prefill;
  const DonationAdminCreatePage(
      {super.key, this.existing, this.initialType = 'donation', this.prefill, this.initialAnimal});

  @override
  ConsumerState<DonationAdminCreatePage> createState() => _DonationAdminCreatePageState();
}

class _InKindRow {
  String category;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController instructions;

  _InKindRow({required this.category, String description = '', int? quantity, String? unit, String? instructions})
      : description = TextEditingController(text: description),
        quantity = TextEditingController(text: quantity?.toString() ?? ''),
        // A unit saved before units became a fixed list is left unset.
        unit = TextEditingController(text: stockUnits.contains(unit) ? unit : ''),
        instructions = TextEditingController(text: instructions ?? '');

  void dispose() {
    description.dispose();
    quantity.dispose();
    unit.dispose();
    instructions.dispose();
  }
}

class _DonationAdminCreatePageState extends ConsumerState<DonationAdminCreatePage> {
  final _picker = ImagePicker();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _intendedUse = TextEditingController();

  late String _type;
  late String _fundKind;
  final Set<String> _tags = {};
  String? _animalId;
  bool _speciesDog = true;
  bool _speciesCat = true;
  bool _acceptInKind = false;
  bool _restricted = false;
  DateTime? _deadline;
  XFile? _image;
  String? _imageUrl;
  final List<_InKindRow> _inKind = [];
  bool _saving = false;
  /// The animal record behind [_animalId] once known, shown as a summary.
  AnimalRecord? _animal;
  /// Last values filled in from an animal record, so choosing another animal
  /// replaces them but never overwrites what the admin typed.
  final Map<String, String?> _autoFilled = {};
  Set<String>? _autoTags;

  bool get _isEdit => widget.existing != null;
  bool get _isSponsorship => _type == 'sponsorship';

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? widget.initialType;
    _fundKind = e?.fundKind ?? (_type == 'sponsorship' ? 'animal' : 'campaign');
    if (e != null) {
      _title.text = e.title;
      _description.text = e.description;
      _amount.text = _isSponsorship
          ? (e.monthlyAmount != null ? _plain(e.monthlyAmount!) : '')
          : (e.target > 0 ? _plain(e.target) : '');
      _intendedUse.text = e.intendedUse ?? '';
      _tags.addAll(e.purposeTags);
      _animalId = e.animalId;
      _acceptInKind = e.acceptInKind;
      _restricted = e.restricted;
      _deadline = e.endDate;
      _imageUrl = e.imageUrl;
      for (final it in e.inKindItems) {
        _inKind.add(_InKindRow(
          category: kInKindCategories.contains(it.category) ? it.category : 'Others',
          description: it.description,
          quantity: it.quantityNeeded,
          unit: it.unit,
          instructions: it.instructions,
        ));
      }
    }
    if (e == null && widget.initialAnimal != null) _applyAnimal(widget.initialAnimal!);
  }

  /// Fills the fields an animal record already answers. A field is only
  /// replaced while it is empty or still holds the previous animal's value.
  void _applyAnimal(AnimalRecord a) {
    _animalId = a.id;
    _animal = a;
    if (_isEdit || !_isSponsorship) return;

    void fill(String key, TextEditingController c, String value) {
      final current = c.text.trim();
      if (current.isEmpty || current == _autoFilled[key]) {
        c.text = value;
        _autoFilled[key] = value;
      }
    }

    fill('title', _title, a.name.trim());
    fill('description', _description, suggestedSponsorshipDescription(a));
    fill('intendedUse', _intendedUse, suggestedIntendedUse(a));

    final cover = sponsorshipCoverFor(a);
    if (_image == null && (_imageUrl == null || _imageUrl == _autoFilled['imageUrl'])) {
      _imageUrl = cover;
      _autoFilled['imageUrl'] = cover;
    }

    if (_tags.isEmpty || (_autoTags != null && _tags.length == _autoTags!.length && _tags.containsAll(_autoTags!))) {
      final tags = suggestedSponsorshipTags(a);
      _tags
        ..clear()
        ..addAll(tags);
      _autoTags = tags;
    }

    final species = a.species.toLowerCase();
    if (species == 'dog' && !_speciesDog) _speciesDog = true;
    if (species == 'cat' && !_speciesCat) _speciesCat = true;
    _fundKind = 'animal';
  }

  static String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    _intendedUse.dispose();
    for (final r in _inKind) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
    if (picked != null) setState(() => _image = picked);
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline != null && _deadline!.isAfter(now) ? _deadline! : now.add(const Duration(days: 30)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 730)),
    );
    // End of the chosen day, Philippine local time on the device.
    if (picked != null) setState(() => _deadline = DateTime(picked.year, picked.month, picked.day, 23, 59));
  }

  /// Client-side checks for fast feedback; the backend re-validates everything.
  String? _validate() {
    if (!_isEdit && _image == null && _imageUrl == null) return 'Add a cover image.';
    if (!_isSponsorship && _title.text.trim().isEmpty) return 'Enter a title.';
    if (_isSponsorship && _animalId == null) return 'Select the animal to sponsor.';
    if (_tags.isEmpty) return 'Select at least one tag.';
    if (parsePesoInput(_amount.text) == null) {
      return _isSponsorship ? 'Enter a valid monthly amount.' : 'Enter a valid target amount.';
    }
    if (_isSponsorship && _intendedUse.text.trim().isEmpty) return 'Describe how sponsorship funds will be used.';
    final editingDeadline = !_isEdit || const ['draft', 'active', 'paused'].contains(widget.existing!.status);
    if (!_isSponsorship && editingDeadline) {
      if (_deadline == null) return 'Choose the expected end date.';
      if (!_deadline!.isAfter(DateTime.now())) return 'The end date must be in the future.';
    }
    if (!_isSponsorship && _acceptInKind) {
      if (_inKind.isEmpty) return 'Add at least one in-kind item or turn off in-kind donations.';
      for (final r in _inKind) {
        if (r.description.text.trim().isEmpty) return 'Describe every in-kind item.';
        final q = r.quantity.text.trim();
        if (q.isNotEmpty && (int.tryParse(q) == null || int.parse(q) <= 0)) return 'In-kind quantities must be whole numbers.';
      }
    }
    return null;
  }

  Future<void> _save({required bool publish}) async {
    final problem = _validate();
    if (problem != null) {
      showAdminSnack(context, problem, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl = _imageUrl;
      if (_image != null) imageUrl = await DonationAdminService.uploadImage(_image!, 'campaigns');

      final amount = parsePesoInput(_amount.text)!;
      final data = <String, dynamic>{
        'type': _type,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'imageUrl': imageUrl,
        'animalId': _animalId,
        'fundKind': _fundKind,
        'purposeTags': _tags.toList(),
        'restricted': _restricted,
        if (_deadline != null) 'deadlineMs': _deadline!.millisecondsSinceEpoch,
        if (_isSponsorship) ...{
          'monthlyAmount': amount,
          'intendedUse': _intendedUse.text.trim(),
        } else ...{
          'targetAmount': amount,
          'acceptInKind': _acceptInKind,
          'inKindItems': _acceptInKind
              ? [
            for (final r in _inKind)
              {
                'category': r.category,
                'description': r.description.text.trim(),
                'quantityNeeded': r.quantity.text.trim().isEmpty ? null : int.parse(r.quantity.text.trim()),
                'unit': r.unit.text.trim(),
                'instructions': r.instructions.text.trim(),
              }
          ]
              : <Map<String, dynamic>>[],
        },
      };
      await DonationAdminService.saveCampaign(campaignId: widget.existing?.id, data: data, publish: publish);
      if (!mounted) return;
      showAdminSnack(context, _isEdit ? 'Changes saved.' : (publish ? 'Published.' : 'Saved as draft.'));
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final noun = _isSponsorship ? 'Sponsorship' : 'Campaign';
    final header = _isEdit ? 'Edit $noun' : 'New $noun';
    final animals = ref.watch(linkableAnimalsProvider);
    final openSponsorships = ref.watch(openSponsorshipsByAnimalProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          DonationAdminHeader(
            title: header,
            helpText: 'Fields marked * are required. "Save as Draft" keeps the listing hidden from users until you '
                'publish it. Funds marked restricted can never be moved to another campaign.',
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              children: [
                Center(
                  child: Text(_isEdit ? header : 'Create New $noun',
                      style: GoogleFonts.tiltWarp(fontSize: 19, color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 14),
                FieldLabel('Images', required: !_isEdit),
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: ImagePickBox(file: _image, url: _imageUrl, onTap: _pickImage)),
                const SizedBox(height: 18),

                FieldLabel('Title', required: !_isSponsorship),
                _underlineField(_title, _isSponsorship ? 'Defaults to the animal\'s name' : 'Enter'),
                const SizedBox(height: 18),

                if (_isSponsorship) ...[
                  const FieldLabel('Species'),
                  Row(
                    children: [
                      SquareCheck(value: _speciesDog, onChanged: (v) => setState(() => _speciesDog = v)),
                      const SizedBox(width: 6),
                      Text('Dog', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(width: 20),
                      SquareCheck(value: _speciesCat, onChanged: (v) => setState(() => _speciesCat = v)),
                      const SizedBox(width: 6),
                      Text('Cat', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
                FieldLabel('Name of Animal', required: _isSponsorship),
                animals.when(
                  loading: () => const LinearProgressIndicator(color: AppColors.textPrimary),
                  error: (e, _) => Text('Could not load animals: $e', style: GoogleFonts.zain(color: Colors.redAccent)),
                  data: (list) => _animalDropdown(list, openSponsorships),
                ),
                if (_isSponsorship) ..._animalSummary(animals.asData?.value),
                const SizedBox(height: 18),

                const FieldLabel('Donation Category'),
                DropdownButtonFormField<String>(
                  initialValue: _type,
                  decoration: const InputDecoration(border: UnderlineInputBorder()),
                  items: [
                    DropdownMenuItem(value: 'donation', child: Text('Donation', style: _dropdownStyle)),
                    DropdownMenuItem(value: 'sponsorship', child: Text('Sponsorship', style: _dropdownStyle)),
                  ],
                  // Type is fixed once created (payments/history depend on it).
                  onChanged: _isEdit
                      ? null
                      : (v) => setState(() {
                    _type = v ?? 'donation';
                    _fundKind = _type == 'sponsorship' ? 'animal' : 'campaign';
                  }),
                ),
                const SizedBox(height: 18),

                const FieldLabel('This listing funds'),
                DropdownButtonFormField<String>(
                  initialValue: _fundKind,
                  decoration: const InputDecoration(border: UnderlineInputBorder()),
                  items: [
                    for (final e in kFundKinds.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value, style: _dropdownStyle)),
                  ],
                  onChanged: (v) => setState(() => _fundKind = v ?? _fundKind),
                ),
                const SizedBox(height: 18),

                const FieldLabel('Tags (Select at least 1)', required: true),
                for (final t in kPurposeTags)
                  CheckRow(
                    label: t,
                    value: _tags.contains(t),
                    onChanged: (v) => setState(() => v ? _tags.add(t) : _tags.remove(t)),
                  ),
                const SizedBox(height: 12),

                const FieldLabel('Description'),
                _underlineField(_description, 'Enter Description', maxLines: 4),
                const SizedBox(height: 18),

                if (_isSponsorship) ...[
                  const FieldLabel('Intended use of funds', required: true),
                  _underlineField(_intendedUse, 'e.g. food, vaccines and vet check-ups', maxLines: 2),
                  const SizedBox(height: 18),
                ],

                FieldLabel(_isSponsorship ? 'Monthly Amount' : 'Enter Amount', required: true),
                const SizedBox(height: 8),
                Center(
                  child: SizedBox(
                    width: 180,
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        prefixText: '₱ ',
                        prefixStyle: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                      ),
                    ),
                  ),
                ),
                if (_isEdit && !_isSponsorship && widget.existing!.collected > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('Already raised: ${formatPesoExact(widget.existing!.collected)}',
                        textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                  ),
                const SizedBox(height: 18),

                if (!_isSponsorship) ...[
                  CheckRow(
                    label: 'Accept In-Kind donations',
                    bold: true,
                    value: _acceptInKind,
                    onChanged: (v) => setState(() {
                      _acceptInKind = v;
                      if (v && _inKind.isEmpty) _inKind.add(_InKindRow(category: kInKindCategories.first));
                    }),
                  ),
                  if (_acceptInKind) ...[
                    for (var i = 0; i < _inKind.length; i++) _inKindEditor(i),
                    Center(
                      child: IconButton(
                        tooltip: 'Add item',
                        icon: const Icon(Icons.add_circle_outline, color: AppColors.textPrimary),
                        onPressed: () => setState(() => _inKind.add(_InKindRow(category: kInKindCategories.first))),
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                ],

                CheckRow(
                  label: 'Funds restricted to this purpose',
                  bold: true,
                  value: _restricted,
                  onChanged: (v) => setState(() => _restricted = v),
                ),
                const SizedBox(height: 12),

                FieldLabel(_isSponsorship ? 'Expected Date (optional)' : 'Expected End Date', required: !_isSponsorship),
                _deadlineField(),
                const SizedBox(height: 32),

                Center(
                  child: YellowPillButton(
                    label: _isEdit ? 'Save Changes' : 'Create $noun',
                    busy: _saving,
                    onPressed: () => _save(publish: !_isEdit),
                  ),
                ),
                if (!_isEdit)
                  Center(
                    child: TextButton(
                      onPressed: _saving ? null : () => _save(publish: false),
                      child: Text('Save as Draft',
                          style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle get _dropdownStyle => GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary);

  Widget _underlineField(TextEditingController c, String hint, {int maxLines = 1}) => TextField(
    controller: c,
    maxLines: maxLines,
    minLines: 1,
    style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
      isDense: true,
      border: const UnderlineInputBorder(),
    ),
  );

  Widget _animalDropdown(List<AnimalRecord> all, Map<String, DonationListing> openSponsorships) {
    final list = all.where((a) {
      if (!_isSponsorship) return true;
      // Sponsorships: only animals that are ready to be sponsored and not
      // already listed by another open sponsorship.
      if (sponsorshipReadiness(a) != null) return false;
      final listing = openSponsorships[a.id];
      if (listing != null && listing.id != widget.existing?.id) return false;
      final s = a.species.toLowerCase();
      if (s == 'dog') return _speciesDog;
      if (s == 'cat') return _speciesCat;
      return _speciesDog && _speciesCat;
    }).toList();
    // Keep the saved animal selectable even if it no longer matches the filters.
    final ids = list.map((a) => a.id).toSet();
    final missing = _animalId != null && !ids.contains(_animalId);
    return DropdownButtonFormField<String?>(
      initialValue: _animalId,
      isExpanded: true,
      decoration: const InputDecoration(border: UnderlineInputBorder()),
      hint: Text('Select', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
      items: [
        if (!_isSponsorship) DropdownMenuItem<String?>(value: null, child: Text('None', style: _dropdownStyle)),
        if (missing)
          DropdownMenuItem<String?>(
              value: _animalId,
              child: Text(_animal?.name ?? widget.existing?.animalName ?? 'Current animal', style: _dropdownStyle)),
        for (final a in list)
          DropdownMenuItem<String?>(
            value: a.id,
            child: Text('${a.name}${a.species.isNotEmpty ? ' · ${a.species}' : ''}',
                overflow: TextOverflow.ellipsis, style: _dropdownStyle),
          ),
      ],
      onChanged: (v) => setState(() {
        final picked = v == null ? null : all.where((a) => a.id == v).firstOrNull;
        if (picked != null) {
          _applyAnimal(picked);
        } else {
          _animalId = v;
          _animal = null;
        }
      }),
    );
  }

  /// What the animal record already says, so admins don't re-type it.
  List<Widget> _animalSummary(List<AnimalRecord>? all) {
    final a = _animal ?? (all ?? const <AnimalRecord>[]).where((x) => x.id == _animalId).firstOrNull;
    if (_animalId == null) {
      if (_isEdit) return const [];
      return [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TextButton.icon(
            onPressed: () => Navigator.pushReplacement(
                context, MaterialPageRoute(builder: (_) => const SponsorAnimalPickerPage())),
            icon: const Icon(Icons.pets, size: 18, color: AppColors.textPrimary),
            label: Text('Browse animals ready to be sponsored',
                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ),
      ];
    }
    if (a == null) return const [];
    return [
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SponsorAnimalTile(animal: a),
            if (!_isEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'Title, photo, description, tags and intended use were filled in from this animal\'s record. '
                      'Review them and set the monthly amount.',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _deadlineField() {
    final locked = _isEdit && !const ['draft', 'active', 'paused'].contains(widget.existing!.status);
    return InkWell(
      onTap: locked ? null : _pickDeadline,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
        child: Row(
          children: [
            Expanded(
              child: Text(
                locked ? '${formatShortDate(_deadline)} — use "Extend" on the listing' : formatShortDate(_deadline),
                style: GoogleFonts.zain(fontSize: 15, color: _deadline == null ? AppColors.textSecondary : AppColors.textPrimary),
              ),
            ),
            if (_isSponsorship && _deadline != null && !locked)
              IconButton(
                tooltip: 'Clear date',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                onPressed: () => setState(() => _deadline = null),
              ),
            const Icon(Icons.edit_calendar_outlined, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }

  Widget _inKindEditor(int i) {
    final r = _inKind[i];
    InputDecoration box(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
      isDense: true,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.25))),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.greenrspwn)),
    );
    final style = GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary);
    final small = GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    // One card per item, every field full width: side-by-side fixed widths
    // cut off the category and drop-off text on phone screens.
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Item ${i + 1}',
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              IconButton(
                tooltip: 'Remove item',
                icon: const Icon(Icons.delete_outline, color: AppColors.textPrimary),
                onPressed: () {
                  final removed = _inKind[i];
                  setState(() => _inKind.removeAt(i));
                  // Its TextFields detach during this rebuild; dispose after.
                  WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Category', style: small),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: r.category,
                  isExpanded: true,
                  style: style,
                  decoration: box('Category'),
                  items: [
                    for (final c in kInKindCategories)
                      DropdownMenuItem(value: c, child: Text(c, style: style)),
                  ],
                  onChanged: (v) => setState(() => r.category = v ?? r.category),
                ),
                const SizedBox(height: 10),
                Text('Item', style: small),
                const SizedBox(height: 4),
                TextField(controller: r.description, style: style, decoration: box('e.g. dry dog food')),
                const SizedBox(height: 10),
                Text('Quantity needed', style: small),
                const SizedBox(height: 4),
                TextField(
                  controller: r.quantity,
                  keyboardType: TextInputType.number,
                  style: style,
                  decoration: box('e.g. 10'),
                ),
                const SizedBox(height: 8),
                UnitChips(
                  value: r.unit.text,
                  options: stockUnits,
                  onChanged: (u) => setState(() => r.unit.text = u),
                ),
                const SizedBox(height: 10),
                Text('Drop-off instructions', style: small),
                const SizedBox(height: 4),
                TextField(
                  controller: r.instructions,
                  style: style,
                  minLines: 1,
                  maxLines: 3,
                  decoration: box('Where and when to bring it'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
