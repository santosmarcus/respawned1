import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

enum _NotifKind { rescue, adoption }

class _NotifItem {
  final String refLabel;
  final String type;
  final String message;
  final DateTime timestamp;
  final _NotifKind kind;
  final String docId;

  const _NotifItem({
    required this.refLabel,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.kind,
    required this.docId,
  });

  String get id =>
      '${kind.name}_${docId}_${type}_${timestamp.millisecondsSinceEpoch}';
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  StreamSubscription<QuerySnapshot>? _casesSub;
  StreamSubscription<QuerySnapshot>? _adoptionsSub;
  final Map<String, StreamSubscription<QuerySnapshot>> _messageSubs = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _communityReportSubs = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _checkinSubs = {};

  List<_NotifItem> _caseStatusItems = [];
  List<_NotifItem> _adoptionStatusItems = [];
  final Map<String, List<_NotifItem>> _messageItemsByCase = {};
  final Map<String, List<_NotifItem>> _communityReportItemsByCase = {};
  final Map<String, List<_NotifItem>> _checkinItemsByAdoption = {};
  final Map<String, _NotifItem?> _dueItemsByAdoption = {};

  final Map<String, String> _adoptionStatusById = {};
  final Map<String, DateTime?> _adoptionDateById = {};
  final Map<String, String> _adoptionLabelById = {};
  final Map<String, Set<String>> _submittedCheckinIds = {};

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
      final ts = userDoc.data()?['lastNotificationsSeenAt'];
      if (ts is Timestamp) _lastSeenAt = ts.toDate();
    } catch (_) {}

    try {
      final dismissedSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dismissedNotifications')
          .where('dismissed', isEqualTo: true)
          .get();
      _dismissedIds = dismissedSnap.docs.map((d) => d.id).toSet();
    } catch (_) {}

    _casesSub = FirebaseFirestore.instance
        .collection('cases')
        .where('reporterId', isEqualTo: uid)
        .snapshots()
        .listen(_onCasesUpdate);

    _adoptionsSub = FirebaseFirestore.instance
        .collection('adoptions')
        .where('personal.adopterId', isEqualTo: uid)
        .snapshots()
        .listen(_onAdoptionsUpdate);

    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'lastNotificationsSeenAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    if (mounted) setState(() => _ready = true);
  }

  void _onCasesUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final label = '#${doc.id.length >= 7 ? doc.id.substring(0, 7).toUpperCase() : doc.id.toUpperCase()}';
      final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];

      for (final h in history) {
        final ts = h['timestamp'];
        if (ts is! Timestamp) continue;
        final statusMessage = h['status'] as String? ?? '';
        items.add(_NotifItem(
          refLabel: label,
          type: _classifyRescueStatusType(statusMessage),
          message: statusMessage,
          timestamp: ts.toDate(),
          kind: _NotifKind.rescue,
          docId: doc.id,
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

      if (!_communityReportSubs.containsKey(doc.id)) {
        _communityReportSubs[doc.id] = FirebaseFirestore.instance
            .collection('cases')
            .doc(doc.id)
            .collection('communityReports')
            .snapshots()
            .listen((crSnap) => _onCommunityReportsUpdate(doc.id, label, crSnap));
      }
    }

    if (mounted) setState(() => _caseStatusItems = items);
  }

  String _classifyRescueStatusType(String message) {
    if (message.contains('expressed interest to adopt')) {
      return 'New Adopter Interest';
    }
    if (message.contains('expressed interest to foster')) {
      return 'New Foster Interest';
    }
    return 'Status Update';
  }

  static const Map<String, String> _communityReportTypeLabels = {
    'still_here': 'Animal still here',
    'moved': 'Animal moved',
    'rescued': 'Animal rescued',
    'no_animal': 'No animal present',
  };

  void _onCommunityReportsUpdate(String caseId, String label, QuerySnapshot snap) {
    final uid = _uid;
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      // Don't notify the reporter about their own submitted report.
      if (data['reporterId'] == uid) continue;

      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;

      final reporterName = data['reporterName'] as String? ?? 'Someone';
      final typeLabel =
          _communityReportTypeLabels[data['type'] as String?] ?? 'an update';

      items.add(_NotifItem(
        refLabel: label,
        type: 'Community Report',
        message: '$reporterName reported: $typeLabel.',
        timestamp: ts.toDate(),
        kind: _NotifKind.rescue,
        docId: caseId,
      ));
    }

    if (mounted) setState(() => _communityReportItemsByCase[caseId] = items);
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
        type: 'New Reply',
        message: (senderName != null && senderName.isNotEmpty)
            ? '$senderName replied to your message.'
            : 'The organization replied to your message.',
        timestamp: ts.toDate(),
        kind: _NotifKind.rescue,
        docId: caseId,
      ));
    }

    if (mounted) setState(() => _messageItemsByCase[caseId] = items);
  }

  static const Map<String, String> _notifiableAdoptionMessages = {
    'Appointment booked.': 'Application Review',
    'Application approved. Appointment confirmed.': 'Time to Meet',
    'Adoption Completed!': 'Adoption Day',
    'Return request approved.': 'Return Approved',
  };
  static const _monitoredStatuses = {'completed', 'return_requested'};

  void _onAdoptionsUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final personal = (data['personal'] as Map?) ?? {};
      final animalName = personal['animalName'] as String? ?? 'Pet';
      final label = 'Adoption - $animalName';
      final status = data['status'] as String? ?? '';
      final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];

      for (final h in history) {
        final ts = h['timestamp'];
        if (ts is! Timestamp) continue;

        final statusMessage = h['status'] as String? ?? '';
        final notifType = _notifiableAdoptionMessages[statusMessage];
        if (notifType == null) continue;

        items.add(_NotifItem(
          refLabel: label,
          type: notifType,
          message: statusMessage,
          timestamp: ts.toDate(),
          kind: _NotifKind.adoption,
          docId: doc.id,
        ));
      }

      _adoptionLabelById[doc.id] = label;
      _adoptionStatusById[doc.id] = status;
      _adoptionDateById[doc.id] = extractAdoptionCompletedDate(data);

      if (!_checkinSubs.containsKey(doc.id)) {
        _checkinSubs[doc.id] = FirebaseFirestore.instance
            .collection('adoptions')
            .doc(doc.id)
            .collection('checkins')
            .snapshots()
            .listen((checkinSnap) => _onCheckinsUpdate(doc.id, checkinSnap));
      }

      _recomputeDueReminder(doc.id);
    }

    if (mounted) setState(() => _adoptionStatusItems = items);
  }

  void _onCheckinsUpdate(String adoptionId, QuerySnapshot snap) {
    final label = _adoptionLabelById[adoptionId] ?? 'Adoption';
    final submittedIds = <String>{};
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      submittedIds.add(doc.id);

      final data = doc.data() as Map<String, dynamic>;
      final ts = data['submittedAt'];
      if (ts is! Timestamp) continue;

      final checkinLabel = data['label'] as String? ?? 'Check-in';
      items.add(_NotifItem(
        refLabel: label,
        type: 'Post-Adoption Check-in',
        message: '$checkinLabel submitted.',
        timestamp: ts.toDate(),
        kind: _NotifKind.adoption,
        docId: adoptionId,
      ));
    }

    _submittedCheckinIds[adoptionId] = submittedIds;
    if (mounted) {
      setState(() => _checkinItemsByAdoption[adoptionId] = items);
    }
    _recomputeDueReminder(adoptionId);
  }

  void _recomputeDueReminder(String adoptionId) {
    final status = _adoptionStatusById[adoptionId];
    final adoptedDate = _adoptionDateById[adoptionId];
    final label = _adoptionLabelById[adoptionId] ?? 'Adoption';

    if (status == null ||
        !_monitoredStatuses.contains(status) ||
        adoptedDate == null) {
      if (mounted) setState(() => _dueItemsByAdoption[adoptionId] = null);
      return;
    }

    final submitted = _submittedCheckinIds[adoptionId] ?? {};
    final schedule = buildCheckinSchedule(adoptedDate);
    final now = DateTime.now();

    Checkpoint? due;
    for (final c in schedule) {
      if (!submitted.contains(c.id) && !c.dueDate.isAfter(now)) {
        due = c;
        break;
      }
    }

    final item = due == null
        ? null
        : _NotifItem(
      refLabel: label,
      type: 'Post-Adoption Check-in',
      message: '${due.label} is due.',
      timestamp: due.dueDate,
      kind: _NotifKind.adoption,
      docId: adoptionId,
    );

    if (mounted) setState(() => _dueItemsByAdoption[adoptionId] = item);
  }

  @override
  void dispose() {
    _casesSub?.cancel();
    _adoptionsSub?.cancel();
    for (final s in _messageSubs.values) {
      s.cancel();
    }
    for (final s in _communityReportSubs.values) {
      s.cancel();
    }
    for (final s in _checkinSubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  List<_NotifItem> get _allItems {
    final all = <_NotifItem>[
      ..._caseStatusItems,
      ..._adoptionStatusItems,
      for (final list in _messageItemsByCase.values) ...list,
      for (final list in _communityReportItemsByCase.values) ...list,
      for (final list in _checkinItemsByAdoption.values) ...list,
      for (final item in _dueItemsByAdoption.values)
        if (item != null) item,
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
          .collection('dismissedNotifications')
          .doc(item.id)
          .set({
        'dismissed': true,
        'dismissedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> _openItem(_NotifItem item) async {
    _dismiss(item);

    if (item.kind == _NotifKind.rescue) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TrackCasePage(caseId: item.docId)),
      );
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(item.docId)
          .get();
      final data = doc.data();
      if (data == null || !mounted) return;

      final status = data['status'] as String? ?? '';
      if (status == 'return_approved') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReturnApprovedPage(adoptionId: item.docId),
          ),
        );
        return;
      }
      if (status == 'completed' || status == 'return_requested') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostAdoptionMonitoringPage(adoptionId: item.docId),
          ),
        );
        return;
      }

      final personal = (data['personal'] as Map?) ?? {};
      final animalIdRaw = personal['animalId'];
      final animalName = personal['animalName'] as String? ?? item.refLabel;

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

      if (mounted) {
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
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final items = _allItems;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
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
                MaterialPageRoute(builder: (context) => const HomeScreen()),
              );
            }
          } else if (index == 2) {
            Navigator.pushReplacement(
              context, MaterialPageRoute(builder: (_) => const UserProfile()),
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
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
      )
          : items.isEmpty
          ? Center(
        child: Text(
          'No notifications yet.',
          style: GoogleFonts.zain(
            fontSize: 15,
            color: AppColors.textSecondary,
          ),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.symmetric(
            horizontal: 35, vertical: 12),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isUnread = _lastSeenAt == null ||
              item.timestamp.isAfter(_lastSeenAt!);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _NotificationTile(
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
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final String refLabel;
  final String type;
  final String message;
  final String time;
  final bool hasUnread;
  final VoidCallback onTap;

  const _NotificationTile({
    required this.refLabel,
    required this.type,
    required this.message,
    required this.time,
    required this.onTap,
    this.hasUnread = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
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