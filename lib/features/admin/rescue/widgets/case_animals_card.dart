import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';

/// Per-animal details. Current submissions keep every animal of a report
/// in this case's `animals` array; older group reports stored one case per
/// animal linked by `groupId` (read from publicCases); single-animal cases
/// show the case's own fields.
class CaseAnimalsSection extends StatelessWidget {
  final RescueCase currentCase;
  const CaseAnimalsSection({super.key, required this.currentCase});

  // Maps an `animals[]` entry onto the case-doc key shape.
  static Map<String, dynamic> animalMap(Map raw) => {
        'animalType': raw['species'],
        'breed': raw['breed'],
        'sex': raw['sex'],
        'size': raw['size'],
        'colorMarkings': raw['colorMarkings'],
        'bodyCondition': raw['bodyCondition'],
        'mobility': raw['mobility'],
        'alertness': raw['alertness'],
        'eyesNoseMouth': raw['eyesNoseMouth'],
        'skinAndCoat': raw['skinAndCoat'],
        'appetiteHydration': raw['appetiteHydration'],
        'behavior': raw['behavior'],
        'environmentSafety': raw['environmentSafety'],
        'biteRisk': raw['biteRisk'],
        'escapeRisk': raw['escapeRisk'],
      };

  @override
  Widget build(BuildContext context) {
    final animals = currentCase.raw['animals'] as List?;
    if (animals != null && animals.isNotEmpty) {
      return CaseAnimalsCard(animals: [for (final a in animals) animalMap(a as Map)]);
    }
    final groupId = currentCase.raw['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) return CaseAnimalsCard(animals: [currentCase.raw]);

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // The public copy carries the animal details and can be queried by
      // groupId whoever owns the sibling reports.
      future: FirebaseFirestore.instance.collection('publicCases').where('groupId', isEqualTo: groupId).get(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? const [];
        // This case's own animal shows at once; the rest fill in.
        if (docs.length <= 1) return CaseAnimalsCard(animals: [currentCase.raw]);
        return CaseAnimalsCard(
          animals: [for (final d in docs) d.data()],
          highlightIndex: docs.indexWhere((d) => d.id == currentCase.id),
        );
      },
    );
  }
}

/// Every animal of a case: basics, then bold **Health** and **Behavior**
/// sections. Used on Rescue Details and in Track Case's animal summary.
class CaseAnimalsCard extends StatelessWidget {
  final List<Map<String, dynamic>> animals;
  final int highlightIndex;
  const CaseAnimalsCard({super.key, required this.animals, this.highlightIndex = -1});

  // Tolerant parsing: a legacy value might be a single String instead of a
  // List, or missing; unknown option values are shown as they are.
  static List<String> _stringList(dynamic value) {
    if (value is List) return value.whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    if (value is String && value.trim().isNotEmpty) return [value.trim()];
    return const [];
  }

  static String? _s(Map<String, dynamic> data, String key) => (data[key] as String?)?.trim();

  static List<CaseInfoItem> _basics(Map<String, dynamic> data) {
    final bite = _s(data, 'biteRisk');
    final escape = _s(data, 'escapeRisk');
    return [
      CaseInfoItem('Species', _s(data, 'animalType')),
      CaseInfoItem('Breed / mixed', _s(data, 'breed')),
      CaseInfoItem('Sex', _s(data, 'sex')),
      CaseInfoItem('Size', _s(data, 'size')),
      CaseInfoItem('Bite risk', (bite?.isNotEmpty ?? false) ? bite : 'Not assessed'),
      CaseInfoItem('Escape risk', (escape?.isNotEmpty ?? false) ? escape : 'Not assessed'),
      CaseInfoItem('Color / markings', _s(data, 'colorMarkings'), wide: true),
    ];
  }

  static List<CaseInfoItem> _health(Map<String, dynamic> data) => [
        CaseInfoItem('Body condition', _s(data, 'bodyCondition')),
        CaseInfoItem('Mobility', _s(data, 'mobility')),
        CaseInfoItem('Alertness', _s(data, 'alertness')),
        CaseInfoItem('Eyes, nose, mouth', _s(data, 'eyesNoseMouth')),
        CaseInfoItem('Skin and coat', _s(data, 'skinAndCoat')),
        CaseInfoItem('Appetite and hydration', _s(data, 'appetiteHydration')),
      ];

  static List<CaseInfoItem> _behavior(Map<String, dynamic> data) => [
        CaseInfoItem('Behavior', _stringList(data['behavior']).join(', '), wide: true),
        CaseInfoItem('Environment and safety', _stringList(data['environmentSafety']).join(', '), wide: true),
      ];

  static Widget _subHeader(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Text(text, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
      );

  Widget _animal(Map<String, dynamic> data) {
    final health = _health(data);
    final behavior = _behavior(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CaseInfoGrid(card: false, items: _basics(data)),
        if (health.any((i) => i.hasValue)) ...[
          _subHeader('Health'),
          CaseInfoGrid(card: false, items: health),
        ],
        if (behavior.any((i) => i.hasValue)) ...[
          _subHeader('Behavior'),
          CaseInfoGrid(card: false, items: behavior),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = animals.length;
    return CaseCard(
      title: total == 1 ? 'Animal' : 'Animals ($total)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) const Divider(height: 20),
            if (total > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Animal ${i + 1} of $total${i == highlightIndex ? ' (this report)' : ''}',
                  style: GoogleFonts.zain(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
              ),
            _animal(animals[i]),
          ],
        ],
      ),
    );
  }
}
