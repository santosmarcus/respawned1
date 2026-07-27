import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'public_rescue_card.dart';
import 'public_rescue_item.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';

enum _DistanceFilter { all, nearby, farther }

const double _kNearbyRadiusKm = 5;

class PublicRescueFeed extends StatefulWidget {
  final int? previewCount;
  final bool standalone;

  const PublicRescueFeed({
    super.key,
    this.previewCount,
    this.standalone = false,
  });

  @override
  State<PublicRescueFeed> createState() => _PublicRescueFeedState();
}

class _PublicRescueFeedState extends State<PublicRescueFeed> {
  static const _dismissedStatuses = {
    'dismissed',
    'cancelled',
    'withdrawn',
    'rejected',
  };

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userDocSub;
  double? _userLat;
  double? _userLng;
  _DistanceFilter _filter = _DistanceFilter.all;

  @override
  void initState() {
    super.initState();
    _listenUserLocation();
  }

  void _listenUserLocation() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      final lat = (data?['lastLat'] as num?)?.toDouble();
      final lng = (data?['lastLng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      if (!mounted) return;
      setState(() {
        _userLat = lat;
        _userLng = lng;
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _userDocSub?.cancel();
    super.dispose();
  }

  double? _distanceKmFor(PublicRescueItem item) {
    final lat = _userLat;
    final lng = _userLng;
    if (lat == null || lng == null) return null;
    if (item.lat == null || item.lng == null) return null;
    return haversineDistanceKm(lat, lng, item.lat!, item.lng!);
  }

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

          // A report rejected specifically for being healthy/low-urgency
          // (and not a Lost Pet) transitions into Community Adoption
          // instead of disappearing like a normal rejection — keep it in
          // the feed so it can still be tracked and listed.
          final communityAdoptionEligible = isCommunityAdoptionEligible(
            status: data['status'] as String?,
            rejectionReason: data['rejectionReason'] as String?,
            rescueType: data['rescueType'] as String?,
          );

          if (_dismissedStatuses.contains(status) &&
              !communityAdoptionEligible) {
            continue;
          }
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

        final locationKnown = _userLat != null && _userLng != null;
        var filtered = items;

        if (widget.standalone && locationKnown) {
          if (_filter == _DistanceFilter.nearby) {
            filtered = items.where((i) {
              final d = _distanceKmFor(i);
              return d != null && d <= _kNearbyRadiusKm;
            }).toList();
          } else if (_filter == _DistanceFilter.farther) {
            filtered = items.where((i) {
              final d = _distanceKmFor(i);
              return d == null || d > _kNearbyRadiusKm;
            }).toList();
          }

          // Nearest-first whenever we know distances, regardless of filter.
          filtered = [...filtered]..sort((a, b) {
            final da = _distanceKmFor(a);
            final db = _distanceKmFor(b);
            if (da == null && db == null) return 0;
            if (da == null) return 1;
            if (db == null) return -1;
            return da.compareTo(db);
          });
        }

        final visible = (!widget.standalone &&
            widget.previewCount != null &&
            widget.previewCount! < filtered.length)
            ? filtered.sublist(0, widget.previewCount!)
            : filtered;

        if (widget.standalone) {
          return Column(
            children: [
              _buildFilterBar(locationKnown),
              Expanded(
                child: visible.isEmpty
                    ? _emptyState(_filter == _DistanceFilter.nearby
                    ? 'No reports within ${_kNearbyRadiusKm.toStringAsFixed(0)}km right now.'
                    : 'No reports match this filter.')
                    : ListView.separated(
                  key: const PageStorageKey('public_rescue_feed_list'),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => PublicRescueCard(
                    item: visible[i],
                    distanceKm: _distanceKmFor(visible[i]),
                  ),
                ),
              ),
            ],
          );
        }

        // Home preview — a swipeable carousel instead of a stacked list.
        return _RescueCarousel(items: visible);
      },
    );
  }

  Widget _buildFilterBar(bool locationKnown) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          _filterChip('All', _DistanceFilter.all, locationKnown: locationKnown),
          const SizedBox(width: 8),
          _filterChip('Nearby', _DistanceFilter.nearby, locationKnown: locationKnown),
          const SizedBox(width: 8),
          _filterChip('Farther away', _DistanceFilter.farther, locationKnown: locationKnown),
        ],
      ),
    );
  }

  Widget _filterChip(
      String label,
      _DistanceFilter value, {
        required bool locationKnown,
      }) {
    final selected = _filter == value;
    // "All" never needs a location; Nearby/Farther do.
    final enabled = value == _DistanceFilter.all || locationKnown;

    return ChoiceChip(
      label: Text(label, style: GoogleFonts.zain(fontSize: 12)),
      selected: selected,
      onSelected: enabled ? (_) => setState(() => _filter = value) : null,
      selectedColor: AppColors.greenrspwn,
      backgroundColor: AppColors.lavenderrspwn,
      disabledColor: AppColors.lavenderrspwn,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.slaterspwn),
      ),
      labelStyle: GoogleFonts.zain(
        fontSize: 12,
        color: AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
      ),
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