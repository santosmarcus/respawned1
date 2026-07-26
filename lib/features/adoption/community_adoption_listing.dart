import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/community_adoption.dart';
import 'package:respawnd1/core/repos/community_adoption_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/success_dialog.dart';

/// The actual Community Adoption transaction screen — reached only from
/// community_adoption_track_page.dart's location-gated button, so by the
/// time someone lands here they're already confirmed to be physically at
/// the animal's last known location.
///
/// This is NOT a "list an animal for adoption" form — submitting this
/// screen directly finalizes the current user as adopter for whichever
/// animal(s) they select. Everything about each animal
/// (species/breed/sex/size/description/photos/location) is read-only,
/// carried over from the source rescue report; the adopter only fills in
/// a name per animal they're adopting, their own contact number, and the
/// post-adoption participation agreement.
///
/// Handles a case with more than one animal (rescue_page.dart's
/// `animals[]`): each animal can be adopted independently, by different
/// people at different times — see
/// CommunityAdoptionRepository.claimedAnimalIndexes. A single-animal case
/// (the common case) skips the selection UI entirely and behaves like a
/// simple one-animal confirmation.
class CommunityAdoptionListingPage extends StatefulWidget {
  final String caseId;
  const CommunityAdoptionListingPage({super.key, required this.caseId});

  @override
  State<CommunityAdoptionListingPage> createState() =>
      _CommunityAdoptionListingPageState();
}

class _AnimalOption {
  final int index;
  final String? species;
  final String? breed;
  final String? sex;
  final String? size;
  final bool claimedByOther;
  const _AnimalOption({
    required this.index,
    this.species,
    this.breed,
    this.sex,
    this.size,
    required this.claimedByOther,
  });
}

class _CommunityAdoptionListingPageState
    extends State<CommunityAdoptionListingPage> {
  final _repo = CommunityAdoptionRepository();

  bool _loading = true;
  bool _submitting = false;
  Map<String, dynamic> _caseData = {};
  List<_AnimalOption> _animalOptions = [];

  final Set<int> _selectedIndexes = {};
  final Map<int, TextEditingController> _nameControllers = {};
  final _contactController = TextEditingController();

  String _adopterName = 'You';
  bool _agreementAccepted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _nameControllers.values) {
      c.dispose();
    }
    _contactController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _rawAnimalAt(List<Map> animalsRaw, int index) {
    if (index < animalsRaw.length) return Map<String, dynamic>.from(animalsRaw[index]);
    return null;
  }

  Future<void> _load() async {
    try {
      final caseSnap =
      await FirebaseFirestore.instance.collection('cases').doc(widget.caseId).get();
      final caseData = caseSnap.data() ?? {};

      final animalsRaw = (caseData['animals'] as List?)?.whereType<Map>().toList() ?? const [];
      final total = _repo.totalAnimalCount(caseData);
      final claimed = await _repo.claimedAnimalIndexes(widget.caseId);

      final options = <_AnimalOption>[];
      for (var i = 0; i < total; i++) {
        final raw = _rawAnimalAt(animalsRaw, i);
        options.add(_AnimalOption(
          index: i,
          species: (raw?['species'] as String?) ?? (i == 0 ? caseData['animalType'] as String? : null),
          breed: (raw?['breed'] as String?) ?? (i == 0 ? caseData['breed'] as String? : null),
          sex: (raw?['sex'] as String?) ?? (i == 0 ? caseData['sex'] as String? : null),
          size: (raw?['size'] as String?) ?? (i == 0 ? caseData['size'] as String? : null),
          claimedByOther: claimed.contains(i),
        ));
      }

      final uid = FirebaseAuth.instance.currentUser?.uid;
      String adopterName = 'You';
      String? adopterContact;
      if (uid != null) {
        final userSnap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final userData = userSnap.data();
        final fullName =
        '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();
        if (fullName.isNotEmpty) adopterName = fullName;
        adopterContact = userData?['phone'] as String?;
      }

      if (!mounted) return;
      setState(() {
        _caseData = caseData;
        _animalOptions = options;
        // Single-animal case: pre-select it automatically so the form
        // behaves like a plain one-animal confirmation, no picking
        // required. Multi-animal: nothing pre-selected — the adopter
        // explicitly picks which one(s) they're taking.
        if (options.length == 1 && !options.first.claimedByOther) {
          _selectedIndexes.add(0);
        }
        for (final o in options) {
          _nameControllers[o.index] = TextEditingController();
        }
        _adopterName = adopterName;
        if (adopterContact != null && adopterContact.isNotEmpty) {
          _contactController.text = adopterContact;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleSelected(_AnimalOption option, bool selected) {
    setState(() {
      if (selected) {
        _selectedIndexes.add(option.index);
      } else {
        _selectedIndexes.remove(option.index);
      }
    });
  }

  Future<void> _submit() async {
    if (_selectedIndexes.isEmpty) {
      _showSnack('Please select at least one animal to adopt.');
      return;
    }
    for (final index in _selectedIndexes) {
      if ((_nameControllers[index]?.text.trim() ?? '').isEmpty) {
        _showSnack('Please enter a name for every animal you\'re adopting.');
        return;
      }
    }
    if (_contactController.text.trim().isEmpty) {
      _showSnack('Please enter your contact number.');
      return;
    }
    if (!_agreementAccepted) {
      _showSnack('Please agree to participate in post-adoption follow-up to continue.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final photoUrls = List<String>.from(_caseData['photoUrls'] ?? const []);
      final rescuedBy = (_caseData['reporterName'] as String?)?.trim().isNotEmpty == true
          ? _caseData['reporterName'] as String
          : 'A community member';
      final address = (_caseData['address'] as String?)?.trim().isNotEmpty == true
          ? _caseData['address'] as String
          : null;
      final lat = (_caseData['lat'] as num?)?.toDouble();
      final lng = (_caseData['lng'] as num?)?.toDouble();
      final description = (_caseData['condition'] as String?)?.trim().isNotEmpty == true
          ? _caseData['condition'] as String
          : null;

      final adoptions = _selectedIndexes.map((index) {
        final option = _animalOptions.firstWhere((o) => o.index == index);
        return CommunityAdoption(
          id: '',
          sourceCaseId: widget.caseId,
          animalIndex: index,
          photoUrls: photoUrls,
          name: _nameControllers[index]!.text.trim(),
          species: option.species ?? '',
          breed: option.breed,
          size: option.size,
          sex: option.sex,
          description: description,
          rescuedBy: rescuedBy,
          address: address,
          lat: lat,
          lng: lng,
          adopterId: uid,
          adopterName: _adopterName,
          adopterContact: _contactController.text.trim(),
          agreementAccepted: true,
        );
      }).toList();

      final createdIds = await _repo.adopt(adoptions: adoptions);

      if (!mounted) return;

      if (createdIds.length < adoptions.length) {
        await showSuccessDialog(
          context,
          title: 'Some Animals Already Claimed',
          message:
          'One or more of the animals you selected were just adopted by someone else. '
              '${createdIds.length} of ${adoptions.length} were adopted successfully.',
        );
      } else {
        final names = adoptions.map((a) => a.name).join(', ');
        await showSuccessDialog(
          context,
          title: 'Adoption Confirmed',
          message:
          '$names ${adoptions.length > 1 ? 'are' : 'is'} now adopted through Community Adoption. '
              'Thank you for giving ${adoptions.length > 1 ? 'them' : 'it'} a home.',
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack('Could not complete the adoption: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Text(
                        'Community Adoption',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        'Submitting this confirms you as adopter for the animal(s) you select.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 20),

                    _PhotoGallery(
                      photoUrls: List<String>.from(_caseData['photoUrls'] ?? const []),
                    ),

                    const SizedBox(height: 20),
                    _FieldLabel('Reported by'),
                    _ReadOnlyValue(
                      (_caseData['reporterName'] as String?)?.trim().isNotEmpty == true
                          ? _caseData['reporterName'] as String
                          : 'A community member',
                    ),

                    const SizedBox(height: 14),
                    _FieldLabel('Location'),
                    _ReadOnlyValue(
                      (_caseData['address'] as String?)?.trim().isNotEmpty == true
                          ? _caseData['address'] as String
                          : 'Not available',
                    ),

                    const SizedBox(height: 14),
                    _FieldLabel('Description'),
                    _ReadOnlyValue(
                      (_caseData['condition'] as String?)?.trim().isNotEmpty == true
                          ? _caseData['condition'] as String
                          : 'Not specified',
                    ),

                    const SizedBox(height: 20),
                    const Divider(color: AppColors.slaterspwn),
                    const SizedBox(height: 20),

                    if (_animalOptions.length == 1)
                      _buildSingleAnimalSection(_animalOptions.first)
                    else
                      _buildMultiAnimalSection(),

                    const SizedBox(height: 20),
                    const Divider(color: AppColors.slaterspwn),
                    const SizedBox(height: 20),

                    _FieldLabel('Adopter'),
                    _ReadOnlyValue(_adopterName),

                    const SizedBox(height: 14),
                    _FieldLabel('Your Contact Number', required: true),
                    const SizedBox(height: 6),
                    _UnderlineField(
                      controller: _contactController,
                      hint: 'Mobile number',
                      keyboardType: TextInputType.phone,
                    ),

                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => setState(() => _agreementAccepted = !_agreementAccepted),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _agreementAccepted,
                              onChanged: (v) => setState(() => _agreementAccepted = v ?? false),
                              activeColor: AppColors.textPrimary,
                              side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'By agreeing to this, you confirm that you are adopting the '
                                  'selected animal(s) through Community Adoption and will '
                                  'participate in post-adoption follow-up, providing updates on '
                                  'their wellbeing as requested by the organization.',
                              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),
                    Center(
                      child: SizedBox(
                        width: 260,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.yellowrspwn,
                            foregroundColor: AppColors.textPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: _submitting
                              ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          )
                              : Text(
                            _selectedIndexes.length > 1
                                ? 'Adopt ${_selectedIndexes.length} Animals'
                                : 'Adopt This Animal',
                            style: GoogleFonts.zain(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSingleAnimalSection(_AnimalOption option) {
    if (option.claimedByOther) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.slaterspwn,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          'This animal has already been adopted by someone else.',
          textAlign: TextAlign.center,
          style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel('Species'),
        _ReadOnlyValue(option.species ?? 'Not specified'),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel('Breed'),
                  _ReadOnlyValue(option.breed ?? 'Not specified'),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _FieldLabel('Sex'),
                  _ReadOnlyValue(option.sex ?? 'Not specified'),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _FieldLabel('Size'),
        _ReadOnlyValue(option.size ?? 'Not specified'),
        const SizedBox(height: 20),
        _FieldLabel('Name this animal', required: true),
        const SizedBox(height: 6),
        _UnderlineField(controller: _nameControllers[option.index]!, hint: 'Enter'),
      ],
    );
  }

  Widget _buildMultiAnimalSection() {
    final unclaimedCount = _animalOptions.where((o) => !o.claimedByOther).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel('This report covers ${_animalOptions.length} animals', required: true),
        const SizedBox(height: 4),
        Text(
          unclaimedCount > 0
              ? 'Select which animal(s) you\'re adopting. You may select more than one.'
              : 'All animals from this report have already been adopted.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final option in _animalOptions) _buildAnimalCard(option),
      ],
    );
  }

  Widget _buildAnimalCard(_AnimalOption option) {
    final selected = _selectedIndexes.contains(option.index);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: option.claimedByOther ? AppColors.slaterspwn.withOpacity(0.4) : Colors.white,
        border: Border.all(color: AppColors.slaterspwn),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!option.claimedByOther)
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: selected,
                    onChanged: (v) => _toggleSelected(option, v ?? false),
                    activeColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                )
              else
                const Icon(Icons.check_circle, size: 20, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Animal ${option.index + 1}${option.species != null ? ' — ${option.species}' : ''}',
                  style: GoogleFonts.zain(
                      fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
              if (option.claimedByOther)
                Text('Already adopted',
                    style: GoogleFonts.zain(
                        fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          if ((option.breed ?? '').isNotEmpty) _MiniInfoRow('Breed', option.breed!),
          if ((option.sex ?? '').isNotEmpty) _MiniInfoRow('Sex', option.sex!),
          if ((option.size ?? '').isNotEmpty) _MiniInfoRow('Size', option.size!),
          if (selected && !option.claimedByOther) ...[
            const SizedBox(height: 10),
            _FieldLabel('Name this animal', required: true),
            const SizedBox(height: 6),
            _UnderlineField(controller: _nameControllers[option.index]!, hint: 'Enter'),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      color: AppColors.yellowrspwn,
      padding: const EdgeInsets.fromLTRB(4, 8, 20, 20),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 28, color: AppColors.textPrimary),
            onPressed: () => Navigator.pop(context),
          ),
          Text(
            'Community Adoptions',
            style: GoogleFonts.tiltWarp(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  final List<String> photoUrls;
  const _PhotoGallery({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) {
      return Container(
        height: 180,
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.tearspwn,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 44, color: AppColors.textSecondary),
        ),
      );
    }
    return SizedBox(
      height: 180,
      child: PageView.builder(
        itemCount: photoUrls.length,
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            photoUrls[i],
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.tearspwn,
              child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const _FieldLabel(this.text, {this.required = false});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: text,
            style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          if (required)
            TextSpan(
              text: ' *',
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFE05353)),
            ),
        ],
      ),
    );
  }
}

class _ReadOnlyValue extends StatelessWidget {
  final String value;
  const _ReadOnlyValue(this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.slaterspwn)),
      ),
      child: Text(value, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
    );
  }
}

class _MiniInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _MiniInfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

class _UnderlineField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  const _UnderlineField({required this.controller, required this.hint, this.keyboardType});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 6),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.greenrspwn, width: 1.4)),
      ),
    );
  }
}