import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/community_adoption_track_page.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:respawnd1/features/rescue/lost_found_track_case.dart';
import '../../app_theme.dart';
import 'activity_item.dart';


class ActivityCard extends StatelessWidget{
  final ActivityItem item;

  const ActivityCard({super.key, required this.item});

  Color get _accentColor => switch (item.type) {
    ActivityType.rescue => AppColors.lavenderrspwn,
    ActivityType.adoption => AppColors.greenrspwn,
    ActivityType.lostFoundPet =>
    item.alertKind == 'lost' ? AppColors.lavenderrspwn : AppColors.tearspwn,
  };

  IconData get _icon => switch (item.type) {
    ActivityType.rescue => Icons.pets_outlined,
    ActivityType.adoption => Icons.favorite_border,
    ActivityType.lostFoundPet =>
    item.alertKind == 'lost' ? Icons.search : Icons.pets,
  };

  String get _dateLabel{
    final d = item.createdAt;
    if (d == null) return '-';
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${months[d.month]} ${d.day}, ${d.year} $h:$min $ampm';
  }

  Future<void> _viewAdoption(BuildContext context) async {
    try {
      final adoptionDoc = await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(item.docId)
          .get();

      final adoptionData = adoptionDoc.data();
      if (adoptionData == null) return;

      final status = adoptionData['status'] as String? ?? '';
      if (status == 'completed' || status == 'return_requested' || status == 'return_approved') {
        if (context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  PostAdoptionMonitoringPage(adoptionId: item.docId),
            ),
          );
        }
        return;
      }

      final personal = (adoptionData['personal'] as Map?) ?? {};
      final animalIdRaw = personal['animalId'];
      final animalName = personal['animalName'] as String? ?? item.title;

      final animal = Animal(
        id: animalIdRaw is int ? animalIdRaw : 0,
        name: animalName,
        breed: '',
        age: '',
        description: '',
        healthTags: const [],
        gender: AnimalGender.male,
        category: AnimalCategory.dog,
        cardColor: AppColors.greenrspwn,
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AdoptionProcess(
              animal: animal,
              existingAdoptionId: item.docId,
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdoptionPage()),
        );
      }
    }
  }

  void _viewPetAlert(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LostFoundTrackCasePage(alertId: item.docId),
      ),
    );
  }

  Widget _thumbFallback() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_icon, color: AppColors.textPrimary, size: 24),
    );
  }

  @override
  Widget build(BuildContext context) {
    return  GestureDetector(
      onTap: () {
        if(item.type == ActivityType.rescue){
          // A Community-Adoption-eligible rejection routes to the CA
          // tracking page instead of the normal (now read-only) Track Case
          // page — an ordinary rejection just opens Track Case, which has
          // no admin-only actions for the reporter to begin with.
          Navigator.push(context,
            MaterialPageRoute(
              builder: (_) => item.isRejected && item.communityAdoptionEligible
                  ? CommunityAdoptionTrackPage(caseId: item.docId)
                  : TrackCasePage(caseId: item.docId),
            ),
          );
        } else if (item.type == ActivityType.adoption){
          _viewAdoption(context);
        } else if (item.type == ActivityType.lostFoundPet) {
          _viewPetAlert(context);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: AppColors.slaterspwn,
              blurRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                color: _accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(_icon, size: 16, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.title,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 13,
                          color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: item.photoUrl != null
                        ? Image.network(
                      item.photoUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return _thumbFallback();
                      },
                      errorBuilder: (_, __, ___) => _thumbFallback(),
                    )
                        : _thumbFallback(),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.access_time,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Text(_dateLabel,
                              style: GoogleFonts.zain(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ]),

                        const SizedBox(height: 6),

                        // Address and Animal type row (rescue + lost/found pet)
                        if ((item.type == ActivityType.rescue ||
                            item.type == ActivityType.lostFoundPet) &&
                            item.animalType.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(children: [
                            const Icon(Icons.location_on_outlined,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.zain(
                                    fontSize: 12,
                                    color: AppColors.textPrimary),
                              ),
                            ),
                          ]),
                          Row(children: [
                            const Icon(Icons.pets,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text(item.animalType,
                                style: GoogleFonts.zain(
                                    fontSize: 12,
                                    color: AppColors.textPrimary)),
                          ]),
                        ],

                        // Rejected Rescue Reports spec §2 — a clear
                        // "Rejected" state plus reason/date/reviewer, and a
                        // Community Adoption action when the rejection made
                        // this case eligible. Ordinary rejection stays
                        // read-only (tap still just opens Track Case).
                        if (item.isRejected) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE05353).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(Icons.block, size: 14, color: Color(0xFFE05353)),
                                  const SizedBox(width: 6),
                                  Text('Rejected',
                                      style: GoogleFonts.zain(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFFE05353))),
                                ]),
                                if (item.rejectionReasonLabel != null) ...[
                                  const SizedBox(height: 4),
                                  Text('Reason: ${item.rejectionReasonLabel}',
                                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                                if (item.rejectedAt != null) ...[
                                  const SizedBox(height: 2),
                                  Text('Rejected on ${_formatDate(item.rejectedAt!)}',
                                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                                ],
                                _ReviewedByLine(caseId: item.docId),
                                if (item.communityAdoptionEligible) ...[
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                          builder: (_) => CommunityAdoptionTrackPage(caseId: item.docId)),
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.greenrspwn.withOpacity(0.18),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text('View Community Adoption',
                                          style: GoogleFonts.zain(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: AppColors.greenrspwn)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),

                        // Status row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                item.isRejected ? 'Rejected' : item.status,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.zain(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (item.type == ActivityType.rescue ||
                                item.type == ActivityType.adoption ||
                                item.type == ActivityType.lostFoundPet)
                              Text(
                                item.isRejected && item.communityAdoptionEligible
                                    ? 'View Community Adoption →'
                                    : 'View details →',
                                style: GoogleFonts.zain(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



}

String _formatDate(DateTime d) {
  const months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
    'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[d.month]} ${d.day}, ${d.year}';
}

/// Best-effort "reviewed by" line for a rejected report — this app has no
/// per-case organization field (single-organization deployment, see
/// rescue_case.dart), so the closest available identity is the staff
/// member recorded on the case's own activityLogs 'rejected' entry
/// (RescueCaseRepository.rejectCase always writes one). Silently renders
/// nothing if the reporter's own security rules can't read that
/// subcollection or no entry is found yet, rather than blocking the card.
class _ReviewedByLine extends StatelessWidget {
  final String caseId;
  const _ReviewedByLine({required this.caseId});

  @override
  Widget build(BuildContext context) {
    // Filters by action == 'rejected' client-side rather than in the query
    // (no .where here) — matches RescueCaseRepository.streamActivityLogs's
    // own established pattern of ordering by timestamp only and never
    // combining it with an equality filter, which would need a composite
    // index this project doesn't define (no firestore.indexes.json).
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('activityLogs')
          .orderBy('timestamp', descending: true)
          .get(),
      builder: (context, snap) {
        final rejectionDocs =
            snap.data?.docs.where((d) => d.data()['action'] == 'rejected') ?? const [];
        final actorName = rejectionDocs.isNotEmpty ? rejectionDocs.first.data()['actorName'] as String? : null;
        if (actorName == null || actorName.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Reviewed by: $actorName',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        );
      },
    );
  }
}