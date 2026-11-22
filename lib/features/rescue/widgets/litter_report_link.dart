import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_page.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';

/// The puppy report to offer after [caseId] is filed: the first animal
/// with a litter whose puppies need attention, or null.
LitterReportLink? litterReportOffer(String caseId, List<FoundAnimalEntry> animals) {
  for (var i = 0; i < animals.length; i++) {
    final a = animals[i];
    final n = a.puppiesNeedingAttention;
    if (a.litterNeedsAttention && n != null && n > 0) {
      return LitterReportLink(parentCaseId: caseId, motherIndex: i, puppyCount: n);
    }
  }
  return null;
}

/// Same, from a saved case's animals[] (Track Case, "report them later").
/// Skipped once a puppy report is linked for that mother.
LitterReportLink? litterReportOfferFromCase(String caseId, Map<String, dynamic> data) {
  if ((data['litterReportCaseIds'] as List? ?? const []).isNotEmpty) return null;
  final animals = (data['animals'] as List?)?.whereType<Map>().toList() ?? const [];
  for (var i = 0; i < animals.length; i++) {
    final litter = animals[i]['litter'];
    if (litter is! Map || !litterConditionNeedsAttention(litter['condition'] as String?)) continue;
    final n = (litter['puppiesNeedingAttention'] as num?)?.toInt() ?? 0;
    if (n > 0) return LitterReportLink(parentCaseId: caseId, motherIndex: i, puppyCount: n);
  }
  return null;
}

Future<bool> confirmLitterReport(BuildContext context, LitterReportLink link) async {
  final n = link.puppyCount;
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text('Report the puppy${n == 1 ? '' : 'ies'} that need${n == 1 ? 's' : ''} help?'),
      content: Text(
        'You said $n pupp${n == 1 ? 'y needs' : 'ies need'} medical attention. A separate rescue report '
        'lets rescuers assess ${n == 1 ? 'it' : 'each one'} on ${n == 1 ? 'its' : 'their'} own, without treating '
        'the whole litter the same. It stays linked to this report. You can also do this later from the '
        'report\'s tracking page.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Later')),
        ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Report Now')),
      ],
    ),
  );
  return ok == true;
}

/// Litter links on a case: a puppy report's mother report, the mother's
/// puppy reports, and for the reporter the "report them" button when the
/// puppies needing attention have no report yet.
class LitterReportsSection extends StatelessWidget {
  const LitterReportsSection({super.key, required this.caseId, required this.data});

  final String caseId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final parent = data['litterOf'];
    final children = List<String>.from(data['litterReportCaseIds'] ?? const []);
    final isReporter = FirebaseAuth.instance.currentUser?.uid == data['reporterId'];
    final offer = isReporter ? litterReportOfferFromCase(caseId, data) : null;
    if (parent is! Map && children.isEmpty && offer == null) return const SizedBox.shrink();

    Widget link(String id, String label) => TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrackCasePage(caseId: id))),
          child: Text('$label #${shortCaseId(id)} →',
              style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Litter', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          if (parent is Map && parent['caseId'] is String) ...[
            Text('These puppies are from a litter reported with their mother.',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
            link(parent['caseId'] as String, "Mother's report"),
          ],
          for (final id in children) link(id, 'Puppy report'),
          if (offer != null) ...[
            Text(
              '${offer.puppyCount} pupp${offer.puppyCount == 1 ? 'y needs' : 'ies need'} medical attention and '
              'ha${offer.puppyCount == 1 ? 's' : 've'} no report of their own yet.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => RescuePage(litterLink: offer)),
              ),
              icon: const Icon(Icons.pets, size: 18, color: AppColors.textPrimary),
              label: Text('Report ${offer.puppyCount == 1 ? 'This Puppy' : 'These Puppies'}',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
          ],
        ],
      ),
    );
  }
}
