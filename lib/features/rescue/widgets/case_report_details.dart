import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';

/// Everything the reporter entered on the rescue form, grouped into cards
/// so each kind of information has one place (shared by the reporter's
/// Track Case, staff Rescue Details and the transporter's job screen):
///
/// 1. Rescue details — type, urgency and why, and the type's own answers
///    (Surrender, Neglect or Abuse, Abandonment).
/// 2. Condition reported — the reporter's own description.
/// 3. Animal information — each animal's details, health, behavior and
///    risk. Lost Pet reads the finder's animals from the linked
///    `petAlerts` docs. Two or more animals show as collapsed cards.
/// 4. Location — address (unless the screen shows its own location card),
///    on-site, access instructions.
/// 5. Coordination — shelter coordination, contact time, witnesses and
///    adoption interest (not asked on Surrender / Lost Pet).
class CaseReportDetails extends StatelessWidget {
  const CaseReportDetails({
    super.key,
    required this.caseId,
    required this.data,
    this.showAddress = true,
  });

  final String caseId;
  final Map<String, dynamic> data;

  /// False on screens with their own location card (staff Rescue Details),
  /// so the address isn't shown twice.
  final bool showAddress;

  String? get _type => data['rescueType'] as String?;
  bool get _isSurrender => _type == 'Pet Surrender';
  bool get _isLostPet => _type == 'Lost Pet';

  @override
  Widget build(BuildContext context) {
    final condition = (data['condition'] as String?)?.trim() ?? '';
    final location = _locationRows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CaseDetailGroup(
          title: 'Rescue details',
          icon: Icons.assignment_outlined,
          children: [
            CaseDetailRow('Rescue Type', _type),
            _UrgencyRow(rescueType: _type, urgency: data['urgency'] as String?),
            if (_isSurrender) ..._surrenderRows(context) else if (!_isLostPet) ..._typeRows(),
            if (data['communityCat'] == true) const CaseDetailRow('Community Cat', 'Yes'),
            CaseDetailRow.optional('Scanned Tag ID', data['scannedTagId']),
          ],
        ),
        if (condition.isNotEmpty)
          CaseDetailGroup(
            title: 'Condition reported',
            icon: Icons.notes_outlined,
            children: [
              Text(
                condition,
                style: GoogleFonts.zain(fontSize: 14, height: 1.35, color: AppColors.textPrimary),
              ),
            ],
          ),
        CaseDetailGroup(
          title: 'Animal information',
          icon: Icons.pets_outlined,
          children: [
            if (_isLostPet)
              _LostPetSection(caseId: caseId, data: data)
            else
              _AnimalsSection(data: data, isSurrender: _isSurrender),
          ],
        ),
        if (location.isNotEmpty)
          CaseDetailGroup(
            // Without the address (the screen has its own location card)
            // this is only on-site and access.
            title: showAddress ? 'Location' : 'On-site and access',
            icon: Icons.place_outlined,
            children: location,
          ),
        if (!_isSurrender && !_isLostPet)
          CaseDetailGroup(
            title: 'Coordination',
            icon: Icons.handshake_outlined,
            children: _coordinationRows(),
          ),
      ],
    );
  }

  List<Widget> _locationRows() {
    final address = (data['address'] as String?)?.trim() ?? '';
    final onSite = data['onSite'];
    final access = (data['accessInstructions'] as String?)?.trim() ?? '';
    return [
      if (showAddress && address.isNotEmpty) CaseDetailRow('Address', address),
      if (!_isSurrender && !_isLostPet && onSite != null) CaseDetailRow('On-site with the Animal', onSite),
      if (access.isNotEmpty) CaseDetailRow('Access Instructions', access),
    ];
  }

  List<Widget> _surrenderRows(BuildContext context) {
    final vetRecords = List<String>.from(data['vetRecordUrls'] ?? const []);
    return [
      const _SectionHeading('Surrender', small: true),
      CaseDetailRow('Reason for Surrender', data['surrenderReason']),
      CaseDetailRow.optional(
        'Explanation and Actions Taken',
        data['surrenderExplanation'],
      ),
      CaseDetailRow('Rehoming Timeline', data['surrenderTimeline']),
      // Reports filed before these moved into each animal's card.
      CaseDetailRow.optional('Age of the Pet', data['surrenderAge']),
      CaseDetailRow.optional(
        'Length of Stay with Owner',
        data['surrenderDuration'],
      ),
      CaseDetailRow.optional('Acquired From', data['petAcquisitionSource']),
      if (vetRecords.isNotEmpty) ...[
        Text('Vaccination Card / Vet Records', style: _labelStyle),
        const SizedBox(height: 6),
        _PhotoStrip(urls: vetRecords),
        const SizedBox(height: 12),
      ],
    ];
  }

  /// Neglect or Abuse / Abandonment follow-up answers.
  List<Widget> _typeRows() {
    final abandonment = data['abandonment'];
    final neglect = data['neglectAbuse'];
    return [
      if (neglect is Map) ...[
        const _SectionHeading('Neglect or Abuse', small: true),
        CaseDetailRow('What Was Observed', _list(neglect['observed'])),
        CaseDetailRow('Happening at Time of Report', neglect['happeningNow']),
        CaseDetailRow('Known Owner', neglect['ownerKnown']),
        CaseDetailRow.optional('Owner Details', neglect['ownerDetails']),
        CaseDetailRow('How Long / How Often', neglect['frequency']),
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
        const _SectionHeading('Abandonment', small: true),
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
    ];
  }

  List<Widget> _coordinationRows() {
    final coordinate = data['coordinateWithShelter'] as String?;
    return [
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

/// One titled card of [CaseReportDetails]. Public so screens can add their
/// own groups in the same style.
class CaseDetailGroup extends StatelessWidget {
  const CaseDetailGroup({
    super.key,
    required this.title,
    required this.children,
    this.icon,
  });

  final String title;
  final IconData? icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDAD7CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: AppColors.textPrimary),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// Urgency with the reason it was set — it comes from the rescue type.
class _UrgencyRow extends StatelessWidget {
  const _UrgencyRow({required this.rescueType, required this.urgency});

  final String? rescueType;
  final String? urgency;

  @override
  Widget build(BuildContext context) {
    final u = urgency?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Urgency', style: _labelStyle),
          const SizedBox(height: 2),
          if (u.isEmpty)
            Text('Not provided', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
          else
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: urgencyColorFor(u),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(u,
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rescueType == null ? 'Set from the rescue type' : 'Set from the rescue type ($rescueType)',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
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
      return AnimalDetailsList(
        animals: [
          for (final a in animals)
            {
              ...Map<String, dynamic>.from(a as Map),
              // "Visible signs of injury / illness / harm" by rescue type.
              'visibleSignsLabel': _titleCase(
                visibleSignsLabelFor(data['rescueType'] as String?),
              ),
            },
        ],
        isSurrender: isSurrender,
      );
    }

    // Reports saved before `animals[]` existed: one doc per animal,
    // linked by groupId.
    final legacy = _fromCaseFields(data);
    final groupId = data['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      return AnimalDetailsList(animals: [legacy], isSurrender: isSurrender);
    }
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('publicCases')
          .where('groupId', isEqualTo: groupId)
          .get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        return AnimalDetailsList(
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
/// Each animal's details, health, behavior and risk (one animal shows its
/// rows directly; two or more show as collapsed cards). Public so the
/// lost/found report page shows a found animal exactly as staff see it.
class AnimalDetailsList extends StatelessWidget {
  const AnimalDetailsList({
    super.key,
    required this.animals,
    this.isSurrender = false,
  });

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
      // Injury, Illness and Neglect or Abuse only.
      CaseDetailRow.optional(
        a['visibleSignsLabel'] as String? ?? 'Visible Signs',
        // Reports from before the form change kept these as harmSigns.
        _list(a['visibleSigns'] ?? a['harmSigns']),
      ),
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
        final alerts = <Map<String, dynamic>>[
          for (final d in snapshot.data?.docs ??
              const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            d.data(),
        ];
        if (alerts.isEmpty) {
          return CaseDetailRow('Species', data['animalType']);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The whole petAlerts doc per animal: basic details plus the
            // Health & Behavior Assessment and risk fields the finder
            // answered (reports from before those were saved show only the
            // basic details).
            AnimalDetailsList(animals: alerts),
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

String _titleCase(String s) => s
    .split(' ')
    .map((w) => w.length <= 2 ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String? _list(Object? v) {
  if (v is! List || v.isEmpty) return null;
  return v.join(', ');
}

/// Label above its value; "Not provided" when unanswered.
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
            text.isEmpty ? 'Not provided' : text,
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
