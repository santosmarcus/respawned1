import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'activity_card.dart';
import 'activity_item.dart';

class ActivityFeed extends StatelessWidget {
  ActivityFeed({super.key});

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

                const dismissedStatuses = {'dismissed', 'cancelled', 'withdrawn', 'rejected'};

                for (final doc in caseSnap.data?.docs ?? []) {
                  final data = doc.data() as Map<String, dynamic>;
                  final rawStatus = (data['status'] as String? ?? '').toLowerCase();
                  if (dismissedStatuses.contains(rawStatus)) continue;

                  // A multi-animal report shares one groupId across several case
                  // docs (one per animal) — only the doc whose own id is that
                  // groupId represents the group in Activity.
                  final caseGroupId = data['groupId'] as String?;
                  if (caseGroupId != null && caseGroupId != doc.id) continue;

                  final history =
                      (data['statusHistory'] as List?)?.cast<Map>() ?? [];
                  final latestStatus = history.isNotEmpty
                      ? history.last['status'] as String? ?? 'Pending'
                      : 'Pending';
                  final ts = data['createdAt'] as Timestamp?;
                  final createdAt = ts is Timestamp ? ts.toDate() : null;

                  items.add(ActivityItem(
                    id: doc.id,
                    type: ActivityType.rescue,
                    title: 'Rescue Report #${doc.id.substring(0, 7).toUpperCase()}',
                    subtitle: data['address'] as String? ?? '-',
                    status: latestStatus,
                    animalType: data['animalType'] as String? ?? '',
                    urgency: data['urgency'] as String? ?? '',
                    createdAt: createdAt,
                    docId: doc.id,
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

                  items.add(ActivityItem(
                    id: doc.id,
                    type: ActivityType.lostFoundPet,
                    title: kind == 'lost'
                        ? 'Lost Pet Report #${doc.id.substring(0, 7).toUpperCase()}'
                        : 'Found Pet Report #${doc.id.substring(0, 7).toUpperCase()}',
                    subtitle: data['address'] as String? ?? '-',
                    status: statusLabel,
                    animalType: data['species'] as String? ?? '',
                    urgency: '',
                    createdAt: ts?.toDate(),
                    docId: doc.id,
                    alertKind: kind,
                  ));
                }

                items.sort((a, b) =>
                    (b.createdAt ?? DateTime(0))
                        .compareTo(a.createdAt ?? DateTime(0)));

                if (items.isEmpty) {
                  return _emptyState(
                      'No activity yet.');
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => ActivityCard(item: items[i]),
                );
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