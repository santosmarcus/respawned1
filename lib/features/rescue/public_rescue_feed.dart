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
          // Once a case is done — 'completed', 'closed', or any variant
          // like 'Rescue Ended'/'rescue_completed' — it no longer belongs
          // in the public feed
          final isFinalStatus = status == 'closed' ||
              status.contains('completed') ||
              status.contains('ended');
          if (isFinalStatus) continue;
          if (data['hiddenFromExplore'] == true) continue;

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

        // Home preview — a swipeable carousel instead of a stacked list.
        return _RescueCarousel(items: visible);
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

// Swipeable carousel used for the Home preview of the public rescue feed.
class _RescueCarousel extends StatefulWidget {
  final List<PublicRescueItem> items;
  const _RescueCarousel({required this.items});

  @override
  State<_RescueCarousel> createState() => _RescueCarouselState();
}

class _RescueCarouselState extends State<_RescueCarousel> {
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
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            itemCount: widget.items.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: PublicRescueCard(item: widget.items[i]),
            ),
          ),
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
                  color: active
                      ? AppColors.textPrimary
                      : AppColors.slaterspwn,
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