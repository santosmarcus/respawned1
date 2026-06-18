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
              .where('adopterId', isEqualTo: uid)
              .snapshots(),
          builder: (context, adoptionsSnap) {
            final loading = caseSnap.connectionState ==
                ConnectionState.waiting ||
                adoptionsSnap.connectionState == ConnectionState.waiting;

            if (loading) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.greenrspwn),
                ),
              );
            }

            final items = <ActivityItem>[];

            for (final doc in caseSnap.data?.docs ?? []) {
              final data = doc.data() as Map<String, dynamic>;
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
              final history =
                  (data['statusHistory'] as List?)?.cast<Map>() ?? [];
              final latestStatus = history.isNotEmpty
                  ? history.last['status'] as String? ?? 'Pending'
                  : 'Pending';
              final ts = data['createdAt'] as Timestamp?;

              items.add(ActivityItem(
                id: doc.id,
                type: ActivityType.adoption,
                title: 'Adoption - ${data['animalName'] ?? 'Animal'}',
                subtitle: '',
                status: latestStatus,
                animalType: '',
                urgency: '',
                createdAt: ts?.toDate(),
                docId: doc.id,
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

