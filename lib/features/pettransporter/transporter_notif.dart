import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/pettransporter/rescue_request.dart';
import 'package:respawnd1/features/pettransporter/service_screen.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';
import 'package:respawnd1/features/pettransporter/transporter_profile.dart';

class _NotifItem {
  final String refLabel;
  final String type;
  final String message;
  final DateTime timestamp;
  final String caseId;
  // Set only for a pending admin assignment offer notification — tapping
  // this one opens RescueRequest (Start Now / Decline) instead of
  // TransitProgressPage, since nothing has been accepted yet.
  final String? assignmentId;

  const _NotifItem({
    required this.refLabel,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.caseId,
    this.assignmentId,
  });

  String get id => assignmentId != null
      ? '${caseId}_offer_$assignmentId'
      : '${caseId}_${type}_${timestamp.millisecondsSinceEpoch}';
}

class TransporterNotifications extends StatefulWidget {
  const TransporterNotifications({super.key});

  @override
  State<TransporterNotifications> createState() =>
      _TransporterNotificationsState();
}

class _TransporterNotificationsState
    extends State<TransporterNotifications> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  StreamSubscription<QuerySnapshot>? _casesSub;
  StreamSubscription<QuerySnapshot>? _offersSub;
  final Map<String, StreamSubscription<QuerySnapshot>> _messageSubs = {};

  List<_NotifItem> _statusItems = [];
  List<_NotifItem> _offerItems = [];
  final Map<String, List<_NotifItem>> _messageItemsByCase = {};

  DateTime? _lastSeenAt;
  Set<String> _dismissedIds = {};
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _ready = true);
      return;
    }

    try {
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final ts = userDoc.data()?['lastTransporterNotificationsSeenAt'];
      if (ts is Timestamp) _lastSeenAt = ts.toDate();
    } catch (_) {}

    try {
      final dismissedSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dismissedTransporterNotifications')
          .where('dismissed', isEqualTo: true)
          .get();
      _dismissedIds = dismissedSnap.docs.map((d) => d.id).toSet();
    } catch (_) {}

    _casesSub = FirebaseFirestore.instance
        .collection('cases')
        .where('assignedVolunteerId', isEqualTo: uid)
        .snapshots()
        .listen(_onCasesUpdate);

    // Admin assignments (assign_rider_page.dart) create a pending offer doc
    // under cases/{caseId}/transportAssignments instead of touching the
    // case's own assignedVolunteerId — so the listener above alone never
    // sees a freshly-offered case. This collectionGroup query is what
    // actually notifies this rider that the admin has something for them.
    // Requires a Firestore composite collection-group index on
    // transportAssignments (riderId, status) — the first live query prints
    // the console's direct create-index link if it's still missing.
    _offersSub = FirebaseFirestore.instance
        .collectionGroup('transportAssignments')
        .where('riderId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen(
      _onOffersUpdate,
      onError: (e) => debugPrint(
          'TransporterNotifications: offers query failed (likely a '
              'missing Firestore composite index on transportAssignments '
              'riderId+status): $e'),
    );

    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'lastTransporterNotificationsSeenAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    if (mounted) setState(() => _ready = true);
  }

  String _labelFor(String docId) => '#${shortCaseId(docId)}';

  String _classifyStatusType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('assigned')) return 'New Assignment';
    if (lower.contains('arrived')) return 'Arrival Confirmed';
    if (lower.contains('rejected')) return 'Treatment Rejected';
    if (lower.contains('accepted')) return 'Treatment Accepted';
    if (lower.contains('completed') || lower.contains('rescued')) {
      return 'Case Completed';
    }
    return 'Status Update';
  }

  void _onCasesUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final label = _labelFor(doc.id);
      final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];

      for (final h in history) {
        final ts = h['timestamp'];
        if (ts is! Timestamp) continue;
        final statusMessage = h['status'] as String? ?? '';
        items.add(_NotifItem(
          refLabel: label,
          type: _classifyStatusType(statusMessage),
          message: statusMessage,
          timestamp: ts.toDate(),
          caseId: doc.id,
        ));
      }

      if (!_messageSubs.containsKey(doc.id)) {
        _messageSubs[doc.id] = FirebaseFirestore.instance
            .collection('cases')
            .doc(doc.id)
            .collection('messages')
            .snapshots()
            .listen((msgSnap) => _onMessagesUpdate(doc.id, label, msgSnap));
      }
    }

    if (mounted) setState(() => _statusItems = items);
  }

  void _onOffersUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final caseId = data['caseId'] as String?;
      if (caseId == null || caseId.isEmpty) continue;

      final ts = data['offeredAt'];
      items.add(_NotifItem(
        refLabel: _labelFor(caseId),
        type: 'New Assignment',
        message: 'You have a new rescue transport assignment. Tap to '
            'review and accept or decline.',
        timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
        caseId: caseId,
        assignmentId: doc.id,
      ));
    }

    if (mounted) setState(() => _offerItems = items);
  }

  void _onMessagesUpdate(String caseId, String label, QuerySnapshot snap) {
    final uid = _uid;
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['senderId'] == uid) continue;

      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;

      final senderName = data['senderName'] as String?;
      items.add(_NotifItem(
        refLabel: label,
        type: 'New Message',
        message: (senderName != null && senderName.isNotEmpty)
            ? '$senderName sent you a message.'
            : 'You have a new message.',
        timestamp: ts.toDate(),
        caseId: caseId,
      ));
    }

    if (mounted) setState(() => _messageItemsByCase[caseId] = items);
  }

  List<_NotifItem> get _allItems {
    final all = <_NotifItem>[
      ..._statusItems,
      ..._offerItems,
      for (final list in _messageItemsByCase.values) ...list,
    ];
    all.removeWhere((item) => _dismissedIds.contains(item.id));
    all.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return all;
  }

  String _timeAgo(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Future<void> _dismiss(_NotifItem item) async {
    setState(() => _dismissedIds = {..._dismissedIds, item.id});

    final uid = _uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dismissedTransporterNotifications')
          .doc(item.id)
          .set({
        'dismissed': true,
        'dismissedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  void _openItem(_NotifItem item) {
    _dismiss(item);

    final assignmentId = item.assignmentId;
    if (assignmentId != null) {
      // Pending offer — nothing accepted yet, so this goes to the
      // Start Now / Decline screen rather than the transit tracker.
      FirebaseFirestore.instance
          .collection('cases')
          .doc(item.caseId)
          .get()
          .then((doc) {
        if (!mounted) return;
        final data = doc.data() as Map<String, dynamic>? ?? {};
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RescueRequest(
              caseId: item.caseId,
              data: data,
              assignmentId: assignmentId,
            ),
          ),
        );
      });
      return;
    }

    // A status-update/message notification for a case that has since
    // reached a final state shouldn't drop the rider back into the transit
    // tracker for a trip that's already over — check first and show a
    // simple heads-up instead.
    FirebaseFirestore.instance
        .collection('cases')
        .doc(item.caseId)
        .get()
        .then((doc) {
      if (!mounted) return;
      final status = (doc.data()?['status'] as String? ?? '').toLowerCase();
      final isCompleted = status == 'closed' ||
          status.contains('completed') ||
          status.contains('ended');

      if (isCompleted) {
        _showCaseCompletedDialog();
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TransitProgressPage(caseId: item.caseId),
        ),
      );
    });
  }

  void _showCaseCompletedDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Case Completed',
            style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
          'This case has been completed.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK',
                style: GoogleFonts.zain(
                    fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _casesSub?.cancel();
    _offersSub?.cancel();
    for (final s in _messageSubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _allItems;

    return Theme(
      data: AppTheme.rescuerTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          toolbarHeight: 80,
          title: Text(
            'Notifications',
            style: GoogleFonts.tiltWarp(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 1,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Notifications',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'My Profile',
            ),
          ],
          onTap: (index) {
            if (index == 0) {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ServiceScreen()),
                );
              }
            } else if (index == 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const TransporterProfile()),
              );
            }
          },
        ),
        body: !_ready
            ? const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn),
        )
            : _uid == null
            ? Center(
          child: Text(
            'Sign in to see your notifications.',
            style: GoogleFonts.zain(
                fontSize: 15, color: AppColors.textSecondary),
          ),
        )
            : items.isEmpty
            ? Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_none,
                  size: 42, color: AppColors.textSecondary),
              const SizedBox(height: 10),
              Text(
                'No notifications yet.',
                style: GoogleFonts.zain(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 4),
              Text(
                'New assignments and messages will show up here.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ],
          ),
        )
            : ListView.builder(
          padding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isUnread = _lastSeenAt == null ||
                item.timestamp.isAfter(_lastSeenAt!);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TransporterNotificationTile(
                refLabel: item.refLabel,
                type: item.type,
                message: item.message,
                time: _timeAgo(item.timestamp),
                hasUnread: isUnread,
                onTap: () => _openItem(item),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TransporterNotificationTile extends StatelessWidget {
  final String refLabel;
  final String type;
  final String message;
  final String time;
  final bool hasUnread;
  final VoidCallback onTap;

  const _TransporterNotificationTile({
    required this.refLabel,
    required this.type,
    required this.message,
    required this.time,
    required this.onTap,
    this.hasUnread = false,
  });

  Color get _badgeColor {
    switch (type) {
      case 'New Assignment':
        return AppColors.greenrspwn;
      case 'New Message':
        return AppColors.lavenderrspwn;
      case 'Treatment Rejected':
        return Colors.redAccent;
      case 'Case Completed':
        return AppColors.greenrspwn;
      default:
        return AppColors.yellowrspwn;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.5),
              blurRadius: 15,
              offset: const Offset(0.0, 0.75),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 6, right: 10),
              decoration: BoxDecoration(
                color: _badgeColor,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$refLabel | $type',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  time,
                  style: GoogleFonts.zain(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                if (hasUnread) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.redAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}