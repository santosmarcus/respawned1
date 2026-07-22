import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';

import '../../app_theme.dart';

const double _kNearbyRadiusKm = 5;

const List<String> _kDismissedCaseStatuses = [
  'dismissed',
  'cancelled',
  'withdrawn',
  'rejected',
];

class NearbyReportBanner extends StatefulWidget {
  const NearbyReportBanner({super.key});

  @override
  State<NearbyReportBanner> createState() => _NearbyReportBannerState();
}

class _NearbyReportBannerState extends State<NearbyReportBanner>
    with SingleTickerProviderStateMixin {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _casesSub;
  late final AnimationController _controller;
  late final Animation<Offset> _slide;

  double? _userLat;
  double? _userLng;
  String? _uid;

  final Set<String> _seenCaseIds = {};
  bool _sawFirstSnapshot = false;

  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _communityReportSubs = {};
  final Map<String, Set<String>> _seenCommunityReportIds = {};
  final Set<String> _communityReportsBaselined = {};

  static const Map<String, String> _communityReportTypeLabels = {
    'still_here': 'Animal still here',
    'moved': 'Animal moved',
    'rescued': 'Animal rescued',
    'no_animal': 'No animal present',
  };

  final List<_NearbyAlert> _queue = [];
  _NearbyAlert? _current;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _init();
  }

  Future<void> _init() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _uid = uid;

    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data = userDoc.data();
      final lat = (data?['lastLat'] as num?)?.toDouble();
      final lng = (data?['lastLng'] as num?)?.toDouble();
      if (lat == null || lng == null) return; // no known location yet
      _userLat = lat;
      _userLng = lng;
    } catch (_) {
      return;
    }

    _listenNearbyCases();
  }

  void _listenNearbyCases() {
    final lat = _userLat!;
    final lng = _userLng!;
    final latDelta = _kNearbyRadiusKm / 111;

    _casesSub = FirebaseFirestore.instance
        .collection('cases')
        .where('lat', isGreaterThanOrEqualTo: lat - latDelta)
        .where('lat', isLessThanOrEqualTo: lat + latDelta)
        .snapshots()
        .listen(_onCasesSnapshot, onError: (_) {});
  }

  void _onCasesSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final lat = _userLat;
    final lng = _userLng;
    if (lat == null || lng == null) return;

    if (!_sawFirstSnapshot) {
      for (final doc in snap.docs) {
        _seenCaseIds.add(doc.id);
        _maybeTrackCommunityReports(doc);
      }
      _sawFirstSnapshot = true;
      return;
    }

    for (final change in snap.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;
      final doc = change.doc;

      _maybeTrackCommunityReports(doc);

      if (change.type != DocumentChangeType.added) continue;
      if (_seenCaseIds.contains(doc.id)) continue;
      _seenCaseIds.add(doc.id);

      final data = doc.data();
      if (data == null) continue;
      if (data['reporterId'] == _uid) continue;

      final status = (data['status'] as String? ?? '').toLowerCase();
      if (_kDismissedCaseStatuses.contains(status)) continue;

      final caseLat = (data['lat'] as num?)?.toDouble();
      final caseLng = (data['lng'] as num?)?.toDouble();
      if (caseLat == null || caseLng == null) continue;

      if (haversineDistanceKm(lat, lng, caseLat, caseLng) > _kNearbyRadiusKm) {
        continue;
      }

      _enqueue(_NearbyAlert(
        caseId: doc.id,
        title: 'New rescue report near you',
        message: 'Tap to see if you can help.',
      ));
    }
  }

  void _maybeTrackCommunityReports(DocumentSnapshot<Map<String, dynamic>> doc) {
    final lat = _userLat;
    final lng = _userLng;
    if (lat == null || lng == null) return;
    if (_communityReportSubs.containsKey(doc.id)) return;

    final data = doc.data();
    if (data == null) return;
    final caseLat = (data['lat'] as num?)?.toDouble();
    final caseLng = (data['lng'] as num?)?.toDouble();
    if (caseLat == null || caseLng == null) return;
    if (haversineDistanceKm(lat, lng, caseLat, caseLng) > _kNearbyRadiusKm) return;

    _communityReportSubs[doc.id] = FirebaseFirestore.instance
        .collection('cases')
        .doc(doc.id)
        .collection('communityReports')
        .snapshots()
        .listen((crSnap) => _onCommunityReportsSnapshot(doc.id, crSnap), onError: (_) {});
  }

  void _onCommunityReportsSnapshot(
      String caseId, QuerySnapshot<Map<String, dynamic>> snap) {
    final seen = _seenCommunityReportIds.putIfAbsent(caseId, () => {});

    if (!_communityReportsBaselined.contains(caseId)) {
      for (final doc in snap.docs) {
        seen.add(doc.id);
      }
      _communityReportsBaselined.add(caseId);
      return;
    }

    for (final change in snap.docChanges) {
      if (change.type != DocumentChangeType.added) continue;
      final doc = change.doc;
      if (seen.contains(doc.id)) continue;
      seen.add(doc.id);

      final data = doc.data();
      if (data == null) continue;
      if (data['reporterId'] == _uid) continue; // don't alert on your own report

      final reporterName = data['reporterName'] as String? ?? 'Someone';
      final typeLabel =
          _communityReportTypeLabels[data['type'] as String?] ?? 'an update';

      _enqueue(_NearbyAlert(
        caseId: caseId,
        title: 'Update on a nearby report',
        message: '$reporterName reported: $typeLabel.',
      ));
    }
  }

  void _enqueue(_NearbyAlert alert) {
    if (!mounted) return;
    _queue.add(alert);
    if (_current == null) _showNext();
  }

  void _showNext() {
    if (_queue.isEmpty) {
      setState(() => _current = null);
      return;
    }
    final next = _queue.removeAt(0);
    setState(() => _current = next);
    _controller.forward(from: 0);

    _autoDismissTimer?.cancel();
    _autoDismissTimer = Timer(const Duration(seconds: 8), _dismissCurrent);
  }

  Future<void> _dismissCurrent() async {
    _autoDismissTimer?.cancel();
    if (!mounted || _current == null) return;
    await _controller.reverse();
    if (!mounted) return;
    _showNext();
  }

  void _openCurrent() {
    final alert = _current;
    if (alert == null) return;
    _autoDismissTimer?.cancel();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TrackCasePage(caseId: alert.caseId)),
    ).then((_) {
      if (mounted) _showNext();
    });
  }

  @override
  void dispose() {
    _casesSub?.cancel();
    for (final s in _communityReportSubs.values) {
      s.cancel();
    }
    _autoDismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_current == null) return const SizedBox.shrink();

    return SlideTransition(
      position: _slide,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _openCurrent,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.pets,
                          size: 20, color: AppColors.textPrimary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _current!.title,
                            style: GoogleFonts.tiltWarp(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _current!.message,
                            style: GoogleFonts.zain(
                              fontSize: 13,
                              color: AppColors.textPrimary.withOpacity(0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismissCurrent,
                      behavior: HitTestBehavior.opaque,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 18, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NearbyAlert {
  final String caseId;
  final String title;
  final String message;
  const _NearbyAlert({
    required this.caseId,
    required this.title,
    required this.message,
  });
}