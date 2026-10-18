import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'activity_card.dart';
import 'activity_item.dart';

String _animalSummary(List animals) {
  final counts = <String, int>{};
  final order = <String>[];
  for (final a in animals) {
    final species = (a is Map ? a['species'] : null) as String?;
    if (species == null || species.isEmpty) continue;
    if (!counts.containsKey(species)) order.add(species);
    counts[species] = (counts[species] ?? 0) + 1;
  }
  if (counts.isEmpty) return '';
  return order.map((s) {
    final c = counts[s]!;
    return '$c ${c == 1 ? s : '${s}s'}';
  }).join(', ');
}

class ActivityFeed extends StatelessWidget {
  final bool standalone;

  ActivityFeed({super.key, this.standalone = false});

  final String? uid = FirebaseAuth.instance.currentUser?.uid;

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return _emptyState('Sign in to see your activity');
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .where('reporterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, caseSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('adoptions')
              .where('personal.adopterId', isEqualTo: uid)
              .snapshots(),
          builder: (context, adoptionsSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('petAlerts')
                  .where('reporterId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, alertsSnap) {
                final loading = caseSnap.connectionState ==
                    ConnectionState.waiting ||
                    adoptionsSnap.connectionState == ConnectionState.waiting ||
                    alertsSnap.connectionState == ConnectionState.waiting;

                if (loading) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(
                      child: CircularProgressIndicator(color: AppColors.greenrspwn),
                    ),
                  );
                }

                final items = <ActivityItem>[];

                // Rejected is deliberately NOT in this set (Rejected Rescue
                // Reports spec §2) — a rejected report must keep showing up
                // in the reporter's own Activity feed instead of vanishing,
                // even though it's still hidden from everyone else's public
                // Explore feed by the separate isCasePublic predicate. Only
                // used for petAlerts below, which this round doesn't touch.
                const dismissedStatuses = {'dismissed', 'cancelled', 'withdrawn', 'rejected'};
                const rescueDismissedStatuses = {'dismissed', 'cancelled', 'withdrawn'};

                for (final doc in caseSnap.data?.docs ?? []) {
                  final data = doc.data() as Map<String, dynamic>;
                  final rawStatus = (data['status'] as String? ?? '').toLowerCase();
                  if (rescueDismissedStatuses.contains(rawStatus)) continue;

                  final isRejected = rawStatus == 'rejected';
                  // Once the reporter has opened a rejected report's
                  // one-time success screen and tapped Close, it's marked
                  // hiddenFromExplore (same flag CaseSummaryPage._close
                  // already sets) — from that point it belongs in History
                  // only, not in the active Activity list.
                  if (isRejected && data['hiddenFromExplore'] == true) continue;
                  final isEndedRescue = !isRejected &&
                      (rawStatus == 'closed' ||
                          rawStatus.contains('completed') ||
                          rawStatus.contains('ended'));
                  if (isEndedRescue) continue;

                  final caseGroupId = data['groupId'] as String?;
                  if (caseGroupId != null && caseGroupId != doc.id) continue;

                  final history =
                      (data['statusHistory'] as List?)?.cast<Map>() ?? [];
                  final latestStatus = history.isNotEmpty
                      ? history.last['status'] as String? ?? 'Pending'
                      : 'Pending';
                  final ts = data['createdAt'] as Timestamp?;
                  final createdAt = ts is Timestamp ? ts.toDate() : null;
                  DateTime? lastUpdatedAt = createdAt;
                  if (history.isNotEmpty) {
                    final lastHistoryTs = history.last['timestamp'];
                    if (lastHistoryTs is Timestamp) {
                      lastUpdatedAt = lastHistoryTs.toDate();
                    }
                  }

                  final animals = data['animals'] as List?;
                  final animalSummary = (animals != null && animals.isNotEmpty)
                      ? _animalSummary(animals)
                      : (data['animalType'] as String? ?? '');

                  final photoList = (data['photoUrls'] as List?)?.cast<String>() ?? [];

                  String? rejectionReasonLabel;
                  DateTime? rejectedAt;
                  bool communityAdoptionEligible = false;
                  if (isRejected) {
                    final reasonName = data['rejectionReason'] as String?;
                    final reason = RejectionReason.fromName(reasonName);
                    final otherText = data['rejectionReasonOther'] as String?;
                    rejectionReasonLabel = reason == RejectionReason.other
                        ? ((otherText?.trim().isNotEmpty ?? false) ? otherText! : 'Other')
                        : reason.label;
                    for (final h in history) {
                      final s = h['status'] as String? ?? '';
                      final hts = h['timestamp'];
                      if (s.startsWith('Case rejected') && hts is Timestamp) {
                        rejectedAt = hts.toDate();
                      }
                    }
                    communityAdoptionEligible = isCommunityAdoptionEligible(
                      status: rawStatus,
                      rejectionReason: reasonName,
                      rescueType: data['rescueType'] as String?,
                    );
                  }

                  items.add(ActivityItem(
                    id: doc.id,
                    type: ActivityType.rescue,
                    title: 'Rescue Report #${shortCaseId(doc.id)}',
                    subtitle: data['address'] as String? ?? '-',
                    status: latestStatus,
                    animalType: animalSummary,
                    urgency: data['urgency'] as String? ?? '',
                    createdAt: createdAt,
                    lastUpdatedAt: lastUpdatedAt,
                    docId: doc.id,
                    photoUrl: photoList.isNotEmpty ? photoList.first : null,
                    isRejected: isRejected,
                    rejectionReasonLabel: rejectionReasonLabel,
                    rejectedAt: rejectedAt,
                    communityAdoptionEligible: communityAdoptionEligible,
                  ));
                }

                for (final doc in adoptionsSnap.data?.docs ?? []) {
                  final data = doc.data() as Map<String, dynamic>;
                  final status = data['status'] as String? ?? '';

                  const finishedAdoptionStatuses = {
                    'completed',
                    'return_requested',
                    'return_approved',
                    'withdrawn',
                    'rejected',
                  };
                  if (finishedAdoptionStatuses.contains(status)) {
                    continue;
                  }

                  final personal = (data['personal'] as Map?) ?? {};
                  final history =
                      (data['statusHistory'] as List?)?.cast<Map>() ?? [];
                  final latestStatus = history.isNotEmpty
                      ? history.last['status'] as String? ?? 'Pending'
                      : 'Pending';
                  final ts = data['createdAt'] as Timestamp?;

                  items.add(ActivityItem(
                    id: doc.id,
                    type: ActivityType.adoption,
                    title: 'Adoption - ${personal['animalName'] ?? 'Animal'}',
                    subtitle: '',
                    status: latestStatus,
                    animalType: '',
                    urgency: '',
                    createdAt: ts?.toDate(),
                    docId: doc.id,
                  ));
                }

                for (final doc in alertsSnap.data?.docs ?? []) {
                  final data = doc.data() as Map<String, dynamic>;
                  final groupId = data['groupId'] as String?;
                  if (groupId != null && groupId != doc.id) continue;

                  final status = (data['status'] as String? ?? 'open').toLowerCase();
                  if (dismissedStatuses.contains(status)) continue;

                  final kind = data['type'] as String? ?? 'lost'; // 'lost' | 'found'
                  final statusLabel = switch (status) {
                    'verified' => 'Match verified — coordinating handover',
                    'resolved' => 'Resolved',
                    _ => kind == 'lost'
                        ? 'Searching for possible matches'
                        : 'Checking against open lost pet alerts',
                  };
                  final ts = data['createdAt'] as Timestamp?;
                  final photoList = (data['photoUrls'] as List?)?.cast<String>() ?? [];

                  items.add(ActivityItem(
                    id: doc.id,
                    type: ActivityType.lostFoundPet,
                    title: kind == 'lost'
                        ? 'Lost Pet Report #${shortCaseId(doc.id)}'
                        : 'Found Pet Report #${shortCaseId(doc.id)}',
                    subtitle: data['address'] as String? ?? '-',
                    status: statusLabel,
                    animalType: data['species'] as String? ?? '',
                    urgency: '',
                    createdAt: ts?.toDate(),
                    docId: doc.id,
                    alertKind: kind,
                    photoUrl: photoList.isNotEmpty ? photoList.first : null,
                  ));
                }

                items.sort((a, b) =>
                    (b.lastUpdatedAt ?? b.createdAt ?? DateTime(0))
                        .compareTo(a.lastUpdatedAt ?? a.createdAt ?? DateTime(0)));

                if (items.isEmpty) {
                  return _emptyState(
                      'No activity yet.');
                }

                if (standalone) {
                  return ListView.separated(
                    // Navigation State spec §11 — preserves scroll offset
                    // when the admin opens an item's detail page and backs
                    // out to this list.
                    key: const PageStorageKey('activity_feed_list'),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => ActivityCard(item: items[i]),
                  );
                }

                final visible =
                items.length > 3 ? items.sublist(0, 3) : items;

                return _ActivityCarousel(items: visible);
              },
            );
          },
        );
      },
    );
  }


  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [ BoxShadow(
            color: AppColors.slaterspwn,
            blurRadius: 1,
            offset: const Offset(0, 3),
          ),
          ],
        ),
        child: Text(
          message, textAlign: TextAlign.center,
          style: GoogleFonts.tiltWarp(
              fontSize: 14, color: AppColors.slaterspwn),
        ),
      ),
    );
  }
}

// Swipeable carousel, matching the style previously used for the Explore
// Reports preview on Home: one card per swipe with the next one peeking at
// the edge, and a dot per item below.
class _ActivityCarousel extends StatefulWidget {
  final List<ActivityItem> items;
  const _ActivityCarousel({required this.items});

  @override
  State<_ActivityCarousel> createState() => _ActivityCarouselState();
}

class _ActivityCarouselState extends State<_ActivityCarousel> {
  late final PageController _controller =
  PageController(viewportFraction: 0.88);
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth * 0.88 - 12;
            return SizedBox(
              width: double.infinity,
              child: Stack(
                children: [
                  for (final item in widget.items)
                    Visibility(
                      visible: false,
                      maintainSize: true,
                      maintainAnimation: true,
                      maintainState: true,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SizedBox(
                          width: cardWidth,
                          child: ActivityCard(item: item),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: PageView.builder(
                      controller: _controller,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: widget.items.length,
                      itemBuilder: (context, i) =>
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: SingleChildScrollView(
                              child: ActivityCard(item: widget.items[i]),
                            ),
                          ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (widget.items.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(widget.items.length, (i) {
              final active = i == _page;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? AppColors.textPrimary : AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}