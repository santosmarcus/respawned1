import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../app_theme.dart';
import 'public_rescue_item.dart';
import 'public_rescue_card.dart';

class PublicRescueFeed extends StatelessWidget {
  final int? previewCount;
  final bool standalone;

  const PublicRescueFeed({
    super.key,
    this.previewCount,
    this.standalone = false,
  });
  Stream<QuerySnapshot<Map<String, dynamic>>> get _stream =>
      FirebaseFirestore.instance
          .collection('cases')
          .where('status', isEqualTo: 'assigned') // "Ongoing" — same as admin
          .orderBy('createdAt', descending: true)
          .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn),
            ),
          );
        }

        if (snapshot.hasError) {
          return _emptyState('Could not load community reports right now.');
        }

        final approvedDocs = (snapshot.data?.docs ?? [])
            .where((d) => (d.data()['adminApproved'] as bool?) == true)
            .toList();

        final docs = previewCount != null
            ? approvedDocs.take(previewCount!).toList()
            : approvedDocs;

        if (docs.isEmpty) {
          return _emptyState(
              'No ongoing rescues to explore yet. Check back soon!');
        }

        final items = docs.map(PublicRescueItem.fromDoc).toList();

        if (previewCount != null) {
          return _RescueCarousel(items: items);
        }

        return ListView.separated(
          shrinkWrap: !standalone,
          physics: standalone
              ? const AlwaysScrollableScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) => PublicRescueCard(item: items[i]),
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
          style:
          GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.slaterspwn),
        ),
      ),
    );
  }
}

class _RescueCarousel extends StatefulWidget {
  final List<PublicRescueItem> items;
  const _RescueCarousel({required this.items});

  @override
  State<_RescueCarousel> createState() => _RescueCarouselState();
}

class _RescueCarouselState extends State<_RescueCarousel> {
  final _controller = PageController();
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
          height: 160,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                width: active ? 9 : 7,
                height: active ? 9 : 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? AppColors.textPrimary : AppColors.slaterspwn,
                ),
              );
            }),
          ),
        ],
      ],
    );
  }
}