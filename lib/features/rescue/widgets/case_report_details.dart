import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Everything the reporter entered on the rescue form, laid out per rescue
/// type so Case Detail mirrors the form that was filled in:
///
/// * Pet Surrender — the surrender reason, explanation, rehoming timeline
///   and vet records, plus each animal's surrender answers.
/// * Lost Pet (a finder who asked for pickup) — the found animals and
///   their status, read from the linked `petAlerts` docs.
/// * Every other type — each animal's Health & Behavior and Risk
///   Assessment, the Abandonment follow-up answers, on-site and access
///   details, shelter coordination, witnesses and adoption interest.
///
/// Reports with two or more animals show each one as a collapsed card
/// that opens when tapped.
class CaseReportDetails extends StatelessWidget {
  const CaseReportDetails({
    super.key,
    required this.caseId,
    required this.data,
  });

  final String caseId;
  final Map<String, dynamic> data;

  String? get _type => data['rescueType'] as String?;
  bool get _isSurrender => _type == 'Pet Surrender';
  bool get _isLostPet => _type == 'Lost Pet';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CaseDetailRow('Rescue Type', _type),
        CaseDetailRow('Urgency', data['urgency']),
        CaseDetailRow('Description', data['condition']),
        if (_isLostPet)
          _LostPetSection(caseId: caseId, data: data)
        else
          _AnimalsSection(data: data, isSurrender: _isSurrender),
        if (_isSurrender)
          ..._surrenderRows(context)
        else if (!_isLostPet)
          ..._strayRows(),
        CaseDetailRow.optional('Scanned Tag ID', data['scannedTagId']),
      ],
    );
  }

  List<Widget> _surrenderRows(BuildContext context) {
    final vetRecords = List<String>.from(data['vetRecordUrls'] ?? const []);
    return [
      // Reports filed before these moved into each animal's card.
      CaseDetailRow.optional('Age of the Pet', data['surrenderAge']),
      CaseDetailRow.optional(
        'Length of Stay with Owner',
        data['surrenderDuration'],
      ),
      CaseDetailRow.optional('Acquired From', data['petAcquisitionSource']),
      const _SectionHeading('Surrender Details'),
      CaseDetailRow('Reason for Surrender', data['surrenderReason']),
      CaseDetailRow.optional(
        'Explanation and Actions Taken',
        data['surrenderExplanation'],
      ),
      CaseDetailRow('Rehoming Timeline', data['surrenderTimeline']),
      if (vetRecords.isNotEmpty) ...[
        Text('Vaccination Card / Vet Records', style: _labelStyle),
        const SizedBox(height: 6),
        _PhotoStrip(urls: vetRecords),
        const SizedBox(height: 12),
      ],
    ];
  }

  List<Widget> _strayRows() {
    final abandonment = data['abandonment'];
    final neglect = data['neglectAbuse'];
    final coordinate = data['coordinateWithShelter'] as String?;
    return [
      if (neglect is Map) ...[
        const _SectionHeading('Neglect or Abuse Details'),
        CaseDetailRow('What Was Observed', _list(neglect['observed'])),
        CaseDetailRow('Happening at Time of Report', neglect['happeningNow']),
        CaseDetailRow('Known Owner', neglect['ownerKnown']),
        CaseDetailRow.optional('Owner Details', neglect['ownerDetails']),
        CaseDetailRow('How Long / How Often', neglect['frequency']),
        const _SectionHeading('Reporting to Authorities', small: true),
        CaseDetailRow(
          'Reported to Barangay / Police',
          neglect['reportedToAuthorities'],
        ),
        CaseDetailRow.optional(
          'Blotter / Report Reference',
          neglect['reportReference'],
        ),
        CaseDetailRow('Willing to Be a Witness', neglect['willingWitness']),
        if (data['reportAnonymously'] == true)
          const CaseDetailRow('Reporter Identity', 'Confidential'),
      ],
      if (abandonment is Map) ...[
        const _SectionHeading('Abandonment Details'),
        CaseDetailRow('Time at Location', abandonment['duration']),
        CaseDetailRow('Where the Animal Was Left', abandonment['location']),
        CaseDetailRow('Access to Food and Water', abandonment['hasFoodWater']),
        CaseDetailRow.optional(
          'Reporter Can Provide Food and Water',
          abandonment['canProvideFoodWater'],
        ),
        CaseDetailRow('Who Left the Animal', abandonment['witness']),
        CaseDetailRow.optional(
          'Witness Details',
          abandonment['witnessDetails'],
        ),
        CaseDetailRow('Belongings Left', abandonment['belongingsLeft']),
        CaseDetailRow.optional(
          'Belongings Description',
          abandonment['belongingsDetails'],
        ),
      ],
      const _SectionHeading('Reporter Details'),
      CaseDetailRow('On-site with the Animal', data['onSite']),
      CaseDetailRow.optional('Access Instructions', data['accessInstructions']),
      if (data['communityCat'] == true)
        const CaseDetailRow('Community Cat', 'Yes'),
      CaseDetailRow('Coordinate with Shelter', _yesNo(coordinate)),
      if (coordinate == 'yes')
        CaseDetailRow.optional(
          'Best Time to Contact',
          data['bestTimeToContact'],
        ),
      if (coordinate == 'no') ...[
        CaseDetailRow('Witness Name', data['witnessName']),
        CaseDetailRow('Witness Mobile Number', data['witnessPhone']),
      ],
      CaseDetailRow('Interest to Adopt', _yesNo(data['interestedToAdopt'])),
    ];
  }
}

// ---- Animals -----------------------------------------------------------

class _AnimalsSection extends StatelessWidget {
  const _AnimalsSection({required this.data, required this.isSurrender});

  final Map<String, dynamic> data;
  final bool isSurrender;

  @override
  Widget build(BuildContext context) {
    final animals = data['animals'] as List?;
    if (animals != null && animals.isNotEmpty) {
      return _AnimalList(
        animals: [for (final a in animals) Map<String, dynamic>.from(a as Map)],
        isSurrender: isSurrender,
      );
    }

    // Reports saved before `animals[]` existed: one doc per animal,
    // linked by groupId.
    final legacy = _fromCaseFields(data);
    final groupId = data['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      return _AnimalList(animals: [legacy], isSurrender: isSurrender);
    }
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('publicCases')
          .where('groupId', isEqualTo: groupId)
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return _AnimalList(
          animals: docs.length <= 1
              ? [legacy]
              : [for (final d in docs) _fromCaseFields(d.data())],
          isSurrender: isSurrender,
        );
      },
    );
  }

  static Map<String, dynamic> _fromCaseFields(Map<String, dynamic> d) => {
    'species': d['animalType'] ?? d['species'],
    'breed': d['breed'],
    'sex': d['sex'],
    'size': d['size'],
    'colorMarkings': d['colorMarkings'],
    'biteRisk': d['biteRisk'],
    'escapeRisk': d['escapeRisk'],
  };
}

/// "No. of Animals" plus one block per animal: shown inline for a single
/// animal, or as collapsed cards when there are two or more.
class _AnimalList extends StatelessWidget {
  const _AnimalList({required this.animals, required this.isSurrender});

  final List<Map<String, dynamic>> animals;
  final bool isSurrender;

  @override
  Widget build(BuildContext context) {
    if (animals.length == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _animalRows(animals.first, isSurrender),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CaseDetailRow('No. of Animals', '${animals.length}'),
        for (var i = 0; i < animals.length; i++)
          CollapsibleAnimalCard(
            title: 'Animal ${i + 1} of ${animals.length}',
            subtitle: _animalSummary(animals[i]),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _animalRows(animals[i], isSurrender),
            ),
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}

String _animalSummary(Map<String, dynamic> a) => [
  a['species'],
  a['breed'],
  a['sex'],
].whereType<String>().where((s) => s.trim().isNotEmpty).join(' · ');

List<Widget> _animalRows(Map<String, dynamic> a, bool isSurrender) {
  final hasAssessment =
      a['bodyCondition'] != null ||
          a['mobility'] != null ||
          (a['behavior'] as List?)?.isNotEmpty == true;
  return [
    CaseDetailRow('Species', a['species']),
    CaseDetailRow('Breed / Mixed', a['breed']),
    CaseDetailRow('Sex', a['sex']),
    CaseDetailRow('Size', a['size']),
    if (isSurrender) CaseDetailRow.optional('Age', a['age']),
    CaseDetailRow('Color / Distinguishing Markings', a['colorMarkings']),
    if (hasAssessment) ...[
      const _SectionHeading('Health & Behavior Assessment', small: true),
      CaseDetailRow('Body Condition', a['bodyCondition']),
      CaseDetailRow('Mobility', a['mobility']),
      CaseDetailRow('Alertness', a['alertness']),
      CaseDetailRow('Eyes, Nose, Mouth', a['eyesNoseMouth']),
      CaseDetailRow('Skin and Coat', a['skinAndCoat']),
      CaseDetailRow('Appetite and Hydration', a['appetiteHydration']),
      // Neglect or Abuse only.
      CaseDetailRow.optional('Visible Signs of Harm', _list(a['harmSigns'])),
      if (isSurrender) ...[
        CaseDetailRow.optional('Vaccination Status', a['vaccination']),
        CaseDetailRow.optional('Spayed / Neutered', a['spayNeuter']),
        CaseDetailRow.optional('Acquired From', a['acquisitionSource']),
        CaseDetailRow.optional('Length of Stay with Owner', a['stayDuration']),
      ],
      CaseDetailRow('Behavior', _list(a['behavior'])),
      if (isSurrender)
        CaseDetailRow.optional('Gets Along With', _list(a['compatibility']))
      else
        CaseDetailRow.optional(
          'Environment and Safety',
          _list(a['environmentSafety']),
        ),
      CaseDetailRow.optional(
        'Needs Immediate Medical Attention',
        a['needsMedical'],
      ),
    ],
    if (a['biteRisk'] != null || a['escapeRisk'] != null) ...[
      const _SectionHeading('Risk Assessment', small: true),
      CaseDetailRow('Bite Risk', a['biteRisk']),
      CaseDetailRow('Escape Risk', a['escapeRisk']),
    ],
  ];
}

// ---- Lost Pet ------------------------------------------------------------

/// A Lost Pet case is created when a finder asks for pickup. The finder's
/// animals live on the linked `petAlerts` docs (one per animal), not on
/// the case.
class _LostPetSection extends StatelessWidget {
  const _LostPetSection({required this.caseId, required this.data});

  final String caseId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('petAlerts')
          .where('linkedCaseId', isEqualTo: caseId)
          .get(),
      builder: (context, snapshot) {
        final alerts = [
          for (final d in snapshot.data?.docs ?? const []) d.data(),
        ];
        if (alerts.isEmpty) {
          return CaseDetailRow('Species', data['animalType']);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _AnimalList(
              animals: [
                for (final a in alerts)
                  {
                    'species': a['species'],
                    'breed': a['breed'],
                    'sex': a['sex'],
                    'size': a['size'],
                    'colorMarkings': a['colorMarkings'],
                  },
              ],
              isSurrender: false,
            ),
            CaseDetailRow('Animal Status', alerts.first['animalStatus']),
          ],
        );
      },
    );
  }
}

// ---- Shared pieces -------------------------------------------------------

final TextStyle _labelStyle = GoogleFonts.zain(
  fontSize: 13,
  fontWeight: FontWeight.w600,
  color: AppColors.textPrimary,
);

String? _yesNo(Object? v) => switch (v) {
  'yes' => 'Yes',
  'no' => 'No',
  _ => v as String?,
};

String? _list(Object? v) {
  if (v is! List || v.isEmpty) return null;
  return v.join(', ');
}

/// Label above its value; '-' when unanswered.
class CaseDetailRow extends StatelessWidget {
  const CaseDetailRow(this.label, this.value, {super.key})
      : hideWhenEmpty = false;

  /// Hidden entirely when there is no value — for questions that are
  /// optional or only asked on some reports.
  const CaseDetailRow.optional(this.label, this.value, {super.key})
      : hideWhenEmpty = true;

  final String label;
  final Object? value;
  final bool hideWhenEmpty;

  @override
  Widget build(BuildContext context) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty && hideWhenEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _labelStyle),
          Text(
            text.isEmpty ? '-' : text,
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text, {this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: small ? 2 : 8, bottom: 10),
      child: Text(
        text,
        style: small
            ? GoogleFonts.zain(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        )
            : GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
      ),
    );
  }
}

/// A bordered card whose body stays hidden until its header is tapped.
class CollapsibleAnimalCard extends StatefulWidget {
  const CollapsibleAnimalCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  State<CollapsibleAnimalCard> createState() => _CollapsibleAnimalCardState();
}

class _CollapsibleAnimalCardState extends State<CollapsibleAnimalCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (widget.subtitle.isNotEmpty)
                          Text(
                            widget.subtitle,
                            style: GoogleFonts.zain(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: AppColors.textPrimary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: widget.child,
            ),
        ],
      ),
    );
  }
}

/// Tappable thumbnails that open full screen.
class _PhotoStrip extends StatelessWidget {
  const _PhotoStrip({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final url in urls)
          GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => Dialog(
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(child: Image.network(url)),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 72,
                  height: 72,
                  color: AppColors.slaterspwn,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
