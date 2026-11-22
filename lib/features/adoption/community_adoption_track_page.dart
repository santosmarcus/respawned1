import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/features/rescue/widgets/surrender_withdrawal_section.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/community_adoption_request.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/repos/community_adoption_request_repository.dart';
import 'package:respawnd1/core/widgets/animal_basic_info_row.dart';
import 'package:respawnd1/core/widgets/animal_image_gallery.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart' show genderIconFor;
import 'package:respawnd1/features/adoption/community_adoption_request_page.dart';
import 'package:respawnd1/features/adoption/community_listing_page.dart';
import 'package:respawnd1/features/adoption/community_profile.dart';
import 'package:respawnd1/features/rescue/widgets/community_report_section.dart';

/// A Community-Adoption-eligible rescue report. A report with one animal
/// opens straight to that animal's page ([CommunityAnimalPage]); one with
/// several lists them as adoption cards first. Reached from
/// PublicRescueCard / ExploreReportsMap / Activity whenever
/// `isCommunityAdoptionEligible` is true for the case.
class CommunityAdoptionTrackPage extends StatelessWidget {
  final String caseId;
  const CommunityAdoptionTrackPage({super.key, required this.caseId});

  @override
  Widget build(BuildContext context) {
    return _CaseStream(
      caseId: caseId,
      builder: (data) {
        final labels = CommunityAdoptionRequestRepository.animalLabelsOf(data);
        if (labels.length == 1) {
          return CommunityAnimalView(caseId: caseId, data: data, index: 0);
        }
        return _AnimalListScaffold(caseId: caseId, data: data, labels: labels);
      },
    );
  }
}

/// One animal of a Community Adoption listing, laid out like the shelter
/// adoption animal page (animal_page.dart AnimalPage).
class CommunityAnimalPage extends StatelessWidget {
  final String caseId;
  final int index;
  const CommunityAnimalPage({super.key, required this.caseId, required this.index});

  @override
  Widget build(BuildContext context) {
    return _CaseStream(
      caseId: caseId,
      builder: (data) => CommunityAnimalView(caseId: caseId, data: data, index: index),
    );
  }
}

class _CaseStream extends StatelessWidget {
  const _CaseStream({required this.caseId, required this.builder});

  final String caseId;
  final Widget Function(Map<String, dynamic> data) builder;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('cases').doc(caseId).snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        if (data != null) return builder(data);
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(backgroundColor: AppColors.background, elevation: 0),
          body: Center(
            child: snapshot.hasError || (snapshot.hasData && data == null)
                ? Text(
              'This listing is no longer available.',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            )
                : const CircularProgressIndicator(),
          ),
        );
      },
    );
  }
}

/// A report with several animals: each one as an adoption card.
class _AnimalListScaffold extends StatelessWidget {
  const _AnimalListScaffold({required this.caseId, required this.data, required this.labels});

  final String caseId;
  final Map<String, dynamic> data;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final animals = (data['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    final claimed = {
      for (final i in data['claimedAnimalIndexes'] as List? ?? const []) (i as num).toInt(),
    };
    final photos = List<String>.from(data['photoUrls'] ?? const []);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Community Adoption',
          style: GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          Text(
            'This report has ${labels.length} animals. Tap one to see its profile.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < labels.length; i++) ...[
            CommunityAnimalCard(
              profile: communityProfileOf(data, i),
              label: labels[i],
              species: (((i < animals.length ? animals[i] : data)['species'] ??
                  (i < animals.length ? animals[i] : data)['animalType']) as String?) ??
                  '',
              breed: ((i < animals.length ? animals[i] : data)['breed'] as String?) ?? '',
              photoUrl: photos.isEmpty ? null : photos.first,
              fallbackDescription: reportSummaryOf(data),
              statusLabel: claimed.contains(i) ? 'Adopted' : 'Available',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CommunityAnimalPage(caseId: caseId, index: i)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _AdoptionButtonSection(caseId: caseId, data: data),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// The animal page itself: photo gallery header, name and sex, Profile and
/// Medical tabs, then the adoption action — the same structure as the
/// shelter animal page, with the report's details in place of the
/// organization's records.
class CommunityAnimalView extends StatefulWidget {
  const CommunityAnimalView({super.key, required this.caseId, required this.data, required this.index});

  final String caseId;
  final Map<String, dynamic> data;
  final int index;

  @override
  State<CommunityAnimalView> createState() => _CommunityAnimalViewState();
}

class _CommunityAnimalViewState extends State<CommunityAnimalView> {
  int _tabIndex = 0; // 0 = Profile, 1 = Medical

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final index = widget.index;
    final animals = (data['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    final raw = index < animals.length ? Map<String, dynamic>.from(animals[index]) : data;
    final labels = CommunityAdoptionRequestRepository.animalLabelsOf(data);
    final p = communityProfileOf(data, index);
    final name = p.name.isNotEmpty ? p.name : (index < labels.length ? labels[index] : 'Animal');
    final species = ((raw['species'] ?? raw['animalType']) as String?) ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          AnimalImageGallery(
            photoUrls: List<String>.from(data['photoUrls'] ?? const []),
            height: 260,
            backgroundColor: AppColors.greenrspwn,
            overlays: [
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.chevron_left, size: 32, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          style: GoogleFonts.tiltWarp(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (genderIconFor(p.sex) != null) ...[
                        const SizedBox(width: 8),
                        Icon(genderIconFor(p.sex), size: 22, color: AppColors.textPrimary),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  const _YellowTag(label: 'Community Adoption'),
                  const SizedBox(height: 16),
                  _Tabs(tabIndex: _tabIndex, onTabChanged: (i) => setState(() => _tabIndex = i)),
                  const SizedBox(height: 16),
                  if (_tabIndex == 0)
                    _ProfileTab(data: data, raw: raw, profile: p, species: species)
                  else
                    _MedicalTab(raw: raw, profile: p),
                  const SizedBox(height: 28),
                  _AdoptionButtonSection(caseId: widget.caseId, data: data, focusIndex: index),
                  const SizedBox(height: 28),
                  _SectionHeader(label: 'Community Updates'),
                  const SizedBox(height: 8),
                  CommunityReportSection(caseId: widget.caseId),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.data, required this.raw, required this.profile, required this.species});

  final Map<String, dynamic> data;
  final Map<String, dynamic> raw;
  final CommunityAnimalProfile profile;
  final String species;

  String _v(String? s) => (s == null || s.trim().isEmpty) ? 'Not provided' : s.trim();

  @override
  Widget build(BuildContext context) {
    final p = profile;
    final description = p.about.isNotEmpty ? p.about : reportSummaryOf(data);
    final abandonment = data['abandonment'] is Map ? data['abandonment'] as Map : const {};
    final report = <(String, Object?)>[
      ('Report type', data['rescueType']),
      ('Reason for surrender', data['surrenderReason']),
      ('Explanation', data['surrenderExplanation']),
      ('Rehoming timeline', data['surrenderTimeline']),
      ('Acquired from', raw['acquisitionSource']),
      ('Time with owner', raw['stayDuration']),
      ('Time at location', abandonment['duration']),
      ('Where it was left', abandonment['location']),
      ('Behavior', (raw['behavior'] as List?)?.join(', ')),
      ('Gets along with (report)', (raw['compatibility'] as List?)?.join(', ')),
      ('Bite risk', raw['biteRisk']),
      ('Escape risk', raw['escapeRisk']),
    ].where((r) => r.$2 is String && (r.$2 as String).trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'Animal Information'),
        const SizedBox(height: 10),
        AnimalBasicInfoRow(fields: [
          InfoField('Species', _v(species)),
          InfoField('Age', _v(p.ageText.isNotEmpty ? p.ageText : raw['age'] as String?)),
          InfoField('Size', _v(p.size)),
          InfoField('Breed', _v(raw['breed'] as String?)),
          InfoField('Coat Length', _v(p.coatLength)),
          InfoField('Color / Markings', _v(raw['colorMarkings'] as String?)),
          if (p.birthdayText != null) InfoField('Birthday', p.birthdayText!),
        ]),
        const SizedBox(height: 20),
        _SectionHeader(label: 'Description'),
        const SizedBox(height: 6),
        Text(
          description.isEmpty ? 'No description yet.' : description,
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary, height: 1.5),
        ),
        const SizedBox(height: 20),
        for (final group in [
          ('Temperament', p.temperament.where(kTemperamentValues.contains).toList()),
          ('Compatibility', p.goodWith.where(kCompatibilityValues.contains).toList()),
          ('Training', p.training.where(kTrainingValues.contains).toList()),
          ('Rescue Background', const ['Community Adoption']),
        ])
          if (group.$2.isNotEmpty) ...[
            _SectionHeader(label: group.$1),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, children: [for (final t in group.$2) _YellowTag(label: t)]),
            const SizedBox(height: 20),
          ],
        if (report.isNotEmpty) ...[
          _SectionHeader(label: 'From the Report'),
          const SizedBox(height: 10),
          AnimalBasicInfoRow(fields: [
            for (final (label, value) in report) InfoField(label, (value as String).trim()),
          ]),
          const SizedBox(height: 20),
        ],
        // In place of the organization block: who is rehoming the animal.
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.person_outline, size: 22, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (data['reporterName'] as String?)?.trim().isNotEmpty == true
                        ? data['reporterName'] as String
                        : 'A community member',
                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
                  ),
                  Text(
                    'Reported this animal · Community Adoption',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MedicalTab extends StatelessWidget {
  const _MedicalTab({required this.raw, required this.profile});

  final Map<String, dynamic> raw;
  final CommunityAnimalProfile profile;

  @override
  Widget build(BuildContext context) {
    final p = profile;
    String yesNo(bool v) => v ? 'Yes' : 'No / Unknown';
    final assessment = <(String, Object?)>[
      ('Body condition', raw['bodyCondition']),
      ('Mobility', raw['mobility']),
      ('Alertness', raw['alertness']),
      ('Eyes, nose, mouth', raw['eyesNoseMouth']),
      ('Skin and coat', raw['skinAndCoat']),
      ('Appetite and hydration', raw['appetiteHydration']),
      ('Visible signs', (raw['visibleSigns'] as List?)?.join(', ')),
      ('Vaccination (report)', raw['vaccination']),
      ('Spayed/Neutered (report)', raw['spayNeuter']),
    ].where((r) => r.$2 is String && (r.$2 as String).trim().isNotEmpty).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'Health Summary'),
        const SizedBox(height: 10),
        AnimalBasicInfoRow(fields: [
          InfoField('Vaccinated', yesNo(p.vaccinated)),
          InfoField('Spayed / Neutered', yesNo(p.spayedNeutered)),
          InfoField('Dewormed', yesNo(p.dewormed)),
        ]),
        if (p.specialNeeds) ...[
          const SizedBox(height: 20),
          _SectionHeader(label: 'Special Needs'),
          const SizedBox(height: 6),
          Text(
            p.specialNeedsDetails.isEmpty ? 'Yes' : p.specialNeedsDetails,
            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary, height: 1.5),
          ),
        ],
        if (p.healthNotes.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(label: 'Health Notes'),
          const SizedBox(height: 6),
          Text(p.healthNotes, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary, height: 1.5)),
        ],
        if (assessment.isNotEmpty) ...[
          const SizedBox(height: 20),
          _SectionHeader(label: 'Reporter\'s Assessment'),
          const SizedBox(height: 10),
          AnimalBasicInfoRow(fields: [
            for (final (label, value) in assessment) InfoField(label, (value as String).trim()),
          ]),
        ],
        const SizedBox(height: 12),
        Text(
          'Health details come from the person who reported this animal and have '
              'not been checked by a veterinarian.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Profile / Medical pill selector, same look as the shelter animal page.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.tabIndex, required this.onTabChanged});

  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    Widget pill(String label, int i) => Expanded(
      child: GestureDetector(
        onTap: () => onTabChanged(i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: tabIndex == i ? AppColors.yellowrspwn : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
    return Container(
      decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(50)),
      child: Row(children: [pill('Profile', 0), pill('Medical', 1)]),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: GoogleFonts.tiltWarp(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
  );
}

class _YellowTag extends StatelessWidget {
  const _YellowTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
    decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(20)),
    child: Text(
      label,
      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    ),
  );
}

/// What the viewer can do on an open Community Adoption listing.
///
/// * The report's own reporter can't adopt it. They manage the listing
///   instead (CommunityListingPage): the adoption profile and the
///   interested adopters.
/// * Anyone else expresses interest, which opens a request they and the
///   reporter chat on; the reporter chooses an adopter and both sign the
///   adoption agreement (CommunityAdoptionRequestPage).
class _AdoptionButtonSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;

  /// The animal this page is about; pre-selected when expressing interest.
  final int? focusIndex;
  const _AdoptionButtonSection({
    required this.caseId,
    required this.data,
    this.focusIndex,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    final isSurrender = isSurrenderRescueType(data['rescueType'] as String?);
    if (uid == data['reporterId']) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pet Surrender: withdraw while active, or see why it was withdrawn.
          if (isSurrender) SurrenderWithdrawalSection(caseId: caseId, data: data),
          if (data['status'] == 'withdrawn')
            const SizedBox.shrink()
          else ...[
          _note(
            isSurrender
                ? 'You listed your pet for Community Adoption. Complete its adoption profile, talk '
                    'with the people who express interest, and choose the best fit. Your pet stays '
                    'in your care until then.'
                : 'You reported this animal, so you can\'t adopt it yourself. Help it '
                    'find a home instead: complete its adoption profile, talk with the '
                    'people who express interest, and choose the best fit.',
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            style: AppButtons.primary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityListingPage(caseId: caseId),
              ),
            ),
            child: Text(
              'Manage Community Adoption',
              style: GoogleFonts.tiltWarp(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ],
        ],
      );
    }

    // A withdrawn surrender takes no new inquiries (firestore.rules too);
    // any open ones were closed with a note when it was withdrawn.
    if (data['status'] == 'withdrawn') {
      return _note('The owner has withdrawn this pet from Community Adoption, so it is no longer '
          'available. Thank you for your interest.');
    }

    return StreamBuilder<List<CommunityAdoptionRequest>>(
      stream: CommunityAdoptionRequestRepository().watchForAdopter(
        caseId: caseId,
        adopterId: uid,
      ),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final mine = snap.data!;
        final open = mine.where(
              (r) =>
          r.status.isOpen || r.status == CommunityRequestStatus.completed,
        );
        if (open.isNotEmpty) {
          final r = open.first;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _note('Your request: ${r.status.label}.'),
              const SizedBox(height: 10),
              ElevatedButton(
                style: AppButtons.primary,
                onPressed: () => openCommunityAdoptionRequest(context, r.id),
                child: Text(
                  'View Your Request',
                  style: GoogleFonts.tiltWarp(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          );
        }

        final labels = CommunityAdoptionRequestRepository.animalLabelsOf(data);
        final claimed = {
          for (final i in data['claimedAnimalIndexes'] as List? ?? const [])
            (i as num).toInt(),
        };
        final available = [
          for (var i = 0; i < labels.length; i++)
            if (!claimed.contains(i)) i,
        ];
        if (focusIndex != null && claimed.contains(focusIndex)) {
          return _note('This animal has been adopted.');
        }
        if (available.isEmpty) {
          return _note('All animals in this report have been adopted.');
        }
        return ElevatedButton(
          style: AppButtons.primary,
          onPressed: () => _expressInterest(context, labels, available),
          child: Text(
            "I'm Interested in Adopting",
            style: GoogleFonts.tiltWarp(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
        );
      },
    );
  }

  Widget _note(String text) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.slaterspwn.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: GoogleFonts.zain(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Future<void> _expressInterest(
      BuildContext context,
      List<String> labels,
      List<int> available,
      ) async {
    final requestId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _InterestSheet(
        caseId: caseId,
        data: data,
        labels: labels,
        available: available,
        preselected: focusIndex,
      ),
    );
    if (requestId != null && context.mounted) {
      openCommunityAdoptionRequest(context, requestId);
    }
  }
}

/// Collects which animal(s), a contact number and a first message, then
/// creates the request.
class _InterestSheet extends StatefulWidget {
  const _InterestSheet({
    required this.caseId,
    required this.data,
    required this.labels,
    required this.available,
    this.preselected,
  });

  final String caseId;
  final Map<String, dynamic> data;
  final List<String> labels;
  final List<int> available;
  final int? preselected;

  @override
  State<_InterestSheet> createState() => _InterestSheetState();
}

class _InterestSheetState extends State<_InterestSheet> {
  final _contact = TextEditingController();
  final _intro = TextEditingController();
  late final Set<int> _selected = widget.available.contains(widget.preselected)
      ? {widget.preselected!}
      : widget.available.length == 1
      ? {widget.available.first}
      : {};
  String _name = 'A community member';
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).get().then((snap) {
      final u = snap.data();
      final full = '${u?['firstName'] ?? ''} ${u?['lastName'] ?? ''}'.trim();
      if (!mounted) return;
      setState(() {
        if (full.isNotEmpty) _name = full;
        if (_contact.text.isEmpty)
          _contact.text = (u?['phone'] as String?) ?? '';
      });
    });
  }

  @override
  void dispose() {
    _contact.dispose();
    _intro.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_selected.isEmpty)
      return setState(() => _error = 'Choose at least one animal.');
    if (_contact.text.trim().isEmpty)
      return setState(() => _error = 'Enter your contact number.');
    if (_intro.text.trim().length < 10) {
      return setState(
            () =>
        _error = 'Tell the reporter a little about yourself and your home.',
      );
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final indexes = _selected.toList()..sort();
      final id = await CommunityAdoptionRequestRepository().createRequest(
        caseId: widget.caseId,
        listerId: widget.data['reporterId'] as String,
        listerName:
        (widget.data['reporterName'] as String?)?.trim().isNotEmpty == true
            ? widget.data['reporterName'] as String
            : 'The reporter',
        adopterId: uid,
        adopterName: _name,
        adopterContact: _contact.text.trim(),
        introMessage: _intro.text.trim(),
        animalIndexes: indexes,
        animalLabels: [for (final i in indexes) widget.labels[i]],
      );
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not send your request: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Express Interest', style: GoogleFonts.tiltWarp(fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              'The reporter will see your request and can message you. They choose '
                  'the adopter, and you both sign an adoption agreement before the handover.',
              style: GoogleFonts.zain(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            if (widget.available.length > 1) ...[
              Text(
                'Which animal(s)?',
                style: GoogleFonts.zain(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final i in widget.available)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  activeColor: AppColors.textPrimary,
                  value: _selected.contains(i),
                  title: Text(
                    widget.labels[i],
                    style: GoogleFonts.zain(fontSize: 14),
                  ),
                  onChanged: (v) => setState(
                        () => v == true ? _selected.add(i) : _selected.remove(i),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _contact,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Your contact number',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _intro,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Message to the reporter',
                hintText:
                'Introduce yourself, your home and other pets, and why you\'d like to adopt.',
                alignLabelWithHint: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.error),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primary,
                onPressed: _saving ? null : _submit,
                child: Text(
                  'Send Request',
                  style: GoogleFonts.zain(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// One line describing the report for the card's description: the
/// reporter's description, else the surrender reason.
String reportSummaryOf(Map<String, dynamic> data) {
  final condition = (data['condition'] as String?)?.trim() ?? '';
  if (condition.isNotEmpty) return condition;
  return (data['surrenderReason'] as String?)?.trim() ?? '';
}
