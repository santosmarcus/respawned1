import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'public_rescue_card.dart';
import 'public_rescue_item.dart';
import 'package:firebase_auth/firebase_auth.dart';


class PublicRescueFeed extends StatelessWidget {
  final int? previewCount;
  final bool standalone;

  const PublicRescueFeed({
    super.key,
    this.previewCount,
    this.standalone = false,
  });

  static const _dismissedStatuses = {
    'dismissed',
    'cancelled',
    'withdrawn',
    'rejected',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .orderBy('serverCreatedAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn),
            ),
          );
        }

        if (snap.hasError) {
          return _emptyState('Could not load reports right now.');
        }

        final docs = snap.data?.docs ?? [];
        final items = <PublicRescueItem>[];
        final currentUserId = FirebaseAuth.instance.currentUser?.uid;

        for (final doc in docs) {
          final data = doc.data();
          final status = (data['status'] as String? ?? '').toLowerCase();
          if (data['reporterId'] == currentUserId) continue;
          if (_dismissedStatuses.contains(status)) continue;

          final groupId = data['groupId'] as String?;
          if (groupId != null && groupId != doc.id) continue;

          items.add(PublicRescueItem.fromDoc(doc));
        }

        if (items.isEmpty) {
          return _emptyState('No public reports yet.');
        }

        final visible = (!standalone &&
            previewCount != null &&
            previewCount! < items.length)
            ? items.sublist(0, previewCount!)
            : items;

        if (standalone) {
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: visible.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) => PublicRescueCard(item: visible[i]),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => PublicRescueCard(item: visible[i]),
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
          boxShadow: [
            BoxShadow(
              color: AppColors.slaterspwn,
              blurRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.slaterspwn),
        ),
      ),
    );
  }
}