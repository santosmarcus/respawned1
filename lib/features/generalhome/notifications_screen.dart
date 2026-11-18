import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/services/notification_service.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/donation/models.dart';
import 'package:respawnd1/features/donation/sponsorship_detail.dart';
import 'package:respawnd1/features/generalhome/certificates_page.dart';
import 'package:respawnd1/features/generalhome/history_screen.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:respawnd1/features/adoption/adopter_adoption_route.dart';

const double _kNearbyRadiusKm = 5;

const List<String> _kDismissedCaseStatuses = [
  'dismissed',
  'cancelled',
  'withdrawn',
  'rejected',
];

// donation: users/{uid}/notifications written by the backend (donation /
// sponsorship confirmations, in-kind received / cancelled / follow-up, goal
// reached, sponsorship ended, and the applicant's no-show / booking
// reminders, which open their application).
enum _NotifKind { rescue, adoption, donation }

/// users/{uid}/notifications `type` → the label shown before the title.
const Map<String, String> _kDonationNotifLabels = {
  'donation_confirmed': 'Donation',
  'goal_reached': 'Donation',
  'sponsorship_confirmed': 'Sponsorship',
  'sponsorship_lapsed': 'Sponsorship',
  'sponsorship_renewal': 'Sponsorship',
  'inkind_pledged': 'In-Kind Donation',
  'inkind_received': 'In-Kind Donation',
  'inkind_cancelled': 'In-Kind Donation',
  'inkind_followup': 'In-Kind Donation',
  'certificate': 'Certificate',
  // functions/adoptions.js tellApplicant: about the applicant's own
  // application (kApplicantAdoptionNotifTypes); opens that application.
  'adoption_no_show_rebook': 'Adoption',
  'adoption_no_show_closed': 'Adoption',
  'adoption_booking_reminder': 'Adoption',
  'adoption_booking_withdrawn': 'Adoption',
  'adoption_interview_confirmed': 'Adoption',
  // escalateCriticalReports (functions/index.js): opens the case.
  'critical_report_escalated': 'Urgent Rescue',
};

/// Notification types whose tap opens Profile → Certificates.
const Set<String> _kCertificateNotifTypes = {
  'certificate',
  'donation_confirmed',
  'sponsorship_confirmed',
  'inkind_received',
};

class _NotifItem {
  final String refLabel;
  final String type;
  final String message;
  final DateTime timestamp;
  final _NotifKind kind;
  final String docId;
  /// users/{uid}/notifications `type`, for [_NotifKind.donation] items.
  final String? sourceType;
  /// The notification document, for [_NotifKind.donation] items.
  final Map<String, dynamic>? data;

  const _NotifItem({
    required this.refLabel,
    required this.type,
    required this.message,
    required this.timestamp,
    required this.kind,
    required this.docId,
    this.sourceType,
    this.data,
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
  StreamSubscription<QuerySnapshot>? _willingAdopterCasesSub;
  StreamSubscription<QuerySnapshot>? _adoptionsSub;
  StreamSubscription<QuerySnapshot>? _donationNotifsSub;
  final Map<String, StreamSubscription<QuerySnapshot>> _messageSubs = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _communityReportSubs = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _checkinSubs = {};
  final Map<String, StreamSubscription<QuerySnapshot>> _followUpSubs = {};

  StreamSubscription<DocumentSnapshot>? _userDocSub;
  StreamSubscription<QuerySnapshot>? _nearbyCasesSub;
  final Map<String, StreamSubscription<QuerySnapshot>> _nearbyCommunityReportSubs = {};
  double? _userLat;
  double? _userLng;
  bool _nearbyListenerStarted = false;
  List<_NotifItem> _nearbyCaseItems = [];
  final Map<String, List<_NotifItem>> _nearbyCommunityReportItemsByCase = {};

  List<_NotifItem> _caseStatusItems = [];
  List<_NotifItem> _willingAdopterCaseItems = [];
  List<_NotifItem> _adoptionStatusItems = [];
  List<_NotifItem> _donationItems = [];
  final Map<String, List<_NotifItem>> _messageItemsByCase = {};
  final Map<String, List<_NotifItem>> _communityReportItemsByCase = {};
  final Map<String, List<_NotifItem>> _checkinItemsByAdoption = {};
  final Map<String, _NotifItem?> _dueItemsByAdoption = {};

  final Map<String, String> _adoptionLabelById = {};

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

    _willingAdopterCasesSub = FirebaseFirestore.instance
        .collection('cases')
        .where('willingAdopterId', isEqualTo: uid)
        .snapshots()
        .listen(_onWillingAdopterCasesUpdate);

    _adoptionsSub = FirebaseFirestore.instance
        .collection('adoptions')
        .where('personal.adopterId', isEqualTo: uid)
        .snapshots()
        .listen(_onAdoptionsUpdate);

    _donationNotifsSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots()
        .listen(_onDonationNotificationsUpdate, onError: (_) {});

    _listenUserLocation(uid);

    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {'lastNotificationsSeenAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );

    if (mounted) setState(() => _ready = true);
  }

  // Listen live (instead of a one-shot get) so this picks up the user's
  // location the moment it's saved, whichever screen ends up writing it
  // first (ExploreReportsMap, NearbyReportBanner's own fallback, etc).
  void _listenUserLocation(String uid) {
    _userDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((userDoc) {
      final data = userDoc.data();
      final lat = (data?['lastLat'] as num?)?.toDouble();
      final lng = (data?['lastLng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      _userLat = lat;
      _userLng = lng;
      if (!_nearbyListenerStarted) {
        _nearbyListenerStarted = true;
        _listenNearbyCases();
      }
    }, onError: (_) {});
  }

  void _listenNearbyCases() {
    final lat = _userLat!;
    final latDelta = _kNearbyRadiusKm / 111;

    _nearbyCasesSub = FirebaseFirestore.instance
        .collection('publicCases')
        .where('lat', isGreaterThanOrEqualTo: lat - latDelta)
        .where('lat', isLessThanOrEqualTo: lat + latDelta)
        .snapshots()
        .listen(_onNearbyCasesUpdate, onError: (_) {});
  }

  void _onNearbyCasesUpdate(QuerySnapshot snap) {
    final lat = _userLat;
    final lng = _userLng;
    final uid = _uid;
    if (lat == null || lng == null) return;

    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['reporterId'] == uid) continue; // your own reports show above

      final status = (data['status'] as String? ?? '').toLowerCase();
      if (_kDismissedCaseStatuses.contains(status)) continue;

      final caseLat = (data['lat'] as num?)?.toDouble();
      final caseLng = (data['lng'] as num?)?.toDouble();
      if (caseLat == null || caseLng == null) continue;
      if (haversineDistanceKm(lat, lng, caseLat, caseLng) > _kNearbyRadiusKm) {
        continue;
      }

      final label = '#${shortCaseId(doc.id)}';
      final ts = data['createdAt'];

      items.add(_NotifItem(
        refLabel: label,
        type: 'Nearby Report',
        message: 'A new rescue report came in near you — tap to see if you can help.',
        timestamp: ts is Timestamp ? ts.toDate() : DateTime.now(),
        kind: _NotifKind.rescue,
        docId: doc.id,
      ));

      if (!_nearbyCommunityReportSubs.containsKey(doc.id)) {
        _nearbyCommunityReportSubs[doc.id] = FirebaseFirestore.instance
            .collection('cases')
            .doc(doc.id)
            .collection('communityReports')
            .snapshots()
            .listen((crSnap) =>
            _onNearbyCommunityReportsUpdate(doc.id, label, crSnap));
      }
    }

    if (mounted) setState(() => _nearbyCaseItems = items);
  }

  void _onNearbyCommunityReportsUpdate(
      String caseId, String label, QuerySnapshot snap) {
    final uid = _uid;
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      // Don't notify you about your own community report on someone
      // else's nearby case.
      if (data['reporterId'] == uid) continue;

      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;

      final reporterName = data['reporterName'] as String? ?? 'Someone';
      final typeLabel =
          _communityReportTypeLabels[data['type'] as String?] ?? 'an update';

      items.add(_NotifItem(
        refLabel: label,
        type: 'Nearby Update',
        message: '$reporterName reported: $typeLabel.',
        timestamp: ts.toDate(),
        kind: _NotifKind.rescue,
        docId: caseId,
      ));
    }

    if (mounted) {
      setState(() => _nearbyCommunityReportItemsByCase[caseId] = items);
    }
  }

  void _onCasesUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final label = '#${shortCaseId(doc.id)}';
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

  void _onWillingAdopterCasesUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final label = '#${shortCaseId(doc.id)}';
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
    }

    if (mounted) setState(() => _willingAdopterCaseItems = items);
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

  void _onDonationNotificationsUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final ts = data['timestamp'];
      if (ts is! Timestamp) continue;
      final sourceType = data['type'] as String? ?? '';
      final title = data['title'] as String? ?? 'Update';
      items.add(_NotifItem(
        // Staff case notices (notifyStaff in functions/index.js) carry a
        // caseId; label them as rescue notices, not donations.
        refLabel: _kDonationNotifLabels[sourceType] ??
            (((data['caseId'] as String?) ?? '').isNotEmpty ? 'Rescue' : 'Donation'),
        type: title,
        message: data['message'] as String? ?? '',
        timestamp: ts.toDate(),
        kind: _NotifKind.donation,
        docId: doc.id,
        sourceType: sourceType,
        data: data,
      ));
    }
    if (mounted) setState(() => _donationItems = items);
  }

  // Exact-match messages (fixed text, no variable content).
  static const Map<String, String> _notifiableAdoptionMessages = {
    'Form submitted.': 'Application Submitted',
    'Appointment booked.': 'Application Review',
    'Interview confirmed by organization.': 'Interview Confirmed',
    'Interview rescheduled by organization.': 'Interview Rescheduled',
    'Animal reserved for this applicant.': 'Animal Reserved',
    'Reservation cleared.': 'Reservation Cleared',
    'Animal retrieved from adopter.': 'Return Completed',
    'Application approved. Appointment confirmed.': 'Time to Meet',
    'Adoption Completed!': 'Adoption Day',
    'Animal released — adoption completed.': 'Adoption Day',
    'Return request approved.': 'Return Approved',
    'Return approved.': 'Return Approved',
    'Retrieval scheduled.': 'Return Pickup Scheduled',
    'Post-adoption monitoring completed.': 'Post-Adoption',
    'Return initiated by the organization.': 'Return Initiated',
  };
  // Prefix-match messages whose text carries variable content (a reason, an
  // actor name, ...) — checked in order after the exact-match map misses.
  static const Map<String, String> _notifiableAdoptionMessagePrefixes = {
    'Return declined': 'Return Declined',
    // Messages below end with an actor name / reason, so they match by prefix.
    'Application approved': 'Application Approved',
    'Application rejected': 'Application Not Approved',
    'Interview completed': 'Interview Completed',
    'Applicant marked as no-show': 'Missed Interview',
    // Written as 'Return initiated by organization (<name>).'
    'Return initiated by organization': 'Return Initiated',
    'Admin recorded an unsuccessful delivery attempt': 'Delivery Update',
    'Follow-up submission confirmed': 'Post-Adoption',
    'Warning marked resolved': 'Post-Adoption',
    'Follow-up reminder sent': 'Post-Adoption Reminder',
    'A follow-up was rescheduled': 'Post-Adoption',
    // AdoptionApplicationRepository.sendWarning writes 'Warning sent:
    // $category.' — the category is variable, so this is a prefix match.
    'Warning sent:': 'Post-Adoption Warning',
  };

  String? _classifyAdoptionStatusType(String message) {
    final exact = _notifiableAdoptionMessages[message];
    if (exact != null) return exact;
    for (final entry in _notifiableAdoptionMessagePrefixes.entries) {
      if (message.startsWith(entry.key)) return entry.value;
    }
    return null;
  }

  void _onAdoptionsUpdate(QuerySnapshot snap) {
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final personal = (data['personal'] as Map?) ?? {};
      final animalName = personal['animalName'] as String? ?? 'Pet';
      final label = 'Adoption - $animalName';
      final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];

      for (final h in history) {
        final ts = h['timestamp'];
        if (ts is! Timestamp) continue;

        final statusMessage = h['status'] as String? ?? '';
        final notifType = _classifyAdoptionStatusType(statusMessage);
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

      if (!_checkinSubs.containsKey(doc.id)) {
        _checkinSubs[doc.id] = FirebaseFirestore.instance
            .collection('adoptions')
            .doc(doc.id)
            .collection('checkins')
            .snapshots()
            .listen((checkinSnap) => _onCheckinsUpdate(doc.id, checkinSnap));
      }

      if (!_followUpSubs.containsKey(doc.id)) {
        _followUpSubs[doc.id] = FirebaseFirestore.instance
            .collection('adoptions')
            .doc(doc.id)
            .collection('followUps')
            .snapshots()
            .listen((followUpSnap) => _onFollowUpsUpdate(doc.id, followUpSnap));
      }
    }

    if (mounted) setState(() => _adoptionStatusItems = items);
  }

  void _onCheckinsUpdate(String adoptionId, QuerySnapshot snap) {
    final label = _adoptionLabelById[adoptionId] ?? 'Adoption';
    final items = <_NotifItem>[];

    for (final doc in snap.docs) {
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

    if (mounted) {
      setState(() => _checkinItemsByAdoption[adoptionId] = items);
    }
  }

  void _onFollowUpsUpdate(String adoptionId, QuerySnapshot snap) {
    final label = _adoptionLabelById[adoptionId] ?? 'Adoption';
    final now = DateTime.now();

    DateTime? dueDate;
    int? dueSequence;
    for (final doc in snap.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final status = data['status'] as String? ?? 'scheduled';
      if (status == 'completed' || status == 'cancelled' || data['submittedAt'] != null) continue;
      final scheduledTs = data['scheduledDate'];
      if (scheduledTs is! Timestamp) continue;
      final scheduled = scheduledTs.toDate();
      if (scheduled.isAfter(now)) continue;
      if (dueDate == null || scheduled.isBefore(dueDate)) {
        dueDate = scheduled;
        dueSequence = (data['sequenceNumber'] as num?)?.toInt();
      }
    }

    final item = dueDate == null
        ? null
        : _NotifItem(
      refLabel: label,
      type: 'Post-Adoption Check-in',
      message: 'Follow-up ${dueSequence ?? ''} is due.',
      timestamp: dueDate,
      kind: _NotifKind.adoption,
      docId: adoptionId,
    );

    if (mounted) setState(() => _dueItemsByAdoption[adoptionId] = item);
  }

  @override
  void dispose() {
    _casesSub?.cancel();
    _willingAdopterCasesSub?.cancel();
    _adoptionsSub?.cancel();
    _donationNotifsSub?.cancel();
    _userDocSub?.cancel();
    _nearbyCasesSub?.cancel();
    for (final s in _messageSubs.values) {
      s.cancel();
    }
    for (final s in _communityReportSubs.values) {
      s.cancel();
    }
    for (final s in _nearbyCommunityReportSubs.values) {
      s.cancel();
    }
    for (final s in _checkinSubs.values) {
      s.cancel();
    }
    for (final s in _followUpSubs.values) {
      s.cancel();
    }
    super.dispose();
  }

  List<_NotifItem> get _allItems {
    final all = <_NotifItem>[
    ..._caseStatusItems,
    ..._willingAdopterCaseItems,
    ..._adoptionStatusItems,
    ..._donationItems,
    ..._nearbyCaseItems,
    for (final list in _messageItemsByCase.values) ...list,
    for (final list in _communityReportItemsByCase.values) ...list,
    for (final list in _nearbyCommunityReportItemsByCase.values) ...list,
    for (final list in _checkinItemsByAdoption.values) ...list,
    for (final item in _dueItemsByAdoption.values)
    ?item,
    ];
    all.removeWhere((item) => _dismissedIds.contains(item.id));
    final deduped = <String, _NotifItem>{for (final item in all) item.id: item};
    final result = deduped.values.toList();
    result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return result;
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

  /// "Renew your sponsorship?" — sponsorships are one-time 30-day payments,
  /// so the sponsor chooses: pay for another 30 days (the backend starts the
  /// new period when the current one ends), stop, or decide later.
  Future<void> _askToRenewSponsorship(_NotifItem item) async {
    final uid = _uid;
    final data = item.data ?? const <String, dynamic>{};
    final donationId = data['donationId'] as String?;
    final campaignId = data['campaignId'] as String?;
    if (uid == null || donationId == null || campaignId == null) return;

    final db = FirebaseFirestore.instance;
    final DocumentSnapshot<Map<String, dynamic>> donationSnap;
    final DocumentSnapshot<Map<String, dynamic>> campaignSnap;
    try {
      donationSnap = await db.collection('donations').doc(donationId).get();
      campaignSnap = await db.collection('campaigns').doc(campaignId).get();
    } catch (_) {
      if (mounted) _showInfo('Could not load this sponsorship', 'Please check your connection and try again.');
      return;
    }
    if (!mounted) return;

    final donation = donationSnap.data();
    final status = donation?['sponsorshipStatus'] as String?;
    final endsAt = (donation?['nextChargeDate'] as Timestamp?)?.toDate();
    if (donation == null || status != 'active') {
      _dismiss(item);
      _showInfo('Sponsorship', switch (status) {
        'renewed' => 'You already renewed this sponsorship. Thank you!',
        'cancelled' => 'You stopped this sponsorship. You can sponsor again anytime from Donations.',
        _ => 'This sponsorship has ended. You can sponsor again anytime from Donations.',
      });
      return;
    }
    if (!campaignSnap.exists) {
      _showInfo('Sponsorship', 'This sponsorship listing is no longer available.');
      return;
    }

    final listing = DonationListing.fromFirestore(campaignSnap);
    final name = (listing.animalName ?? '').isNotEmpty ? listing.animalName! : listing.title;
    final amount = (data['amount'] as num?)?.toDouble() ??
        (donation['nextChargeAmount'] as num?)?.toDouble() ??
        (donation['amount'] as num?)?.toDouble() ??
        0;
    final endText = endsAt == null ? 'soon' : 'on ${formatDate(endsAt)}';

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Continue sponsoring $name?', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
        content: Text(
          'Your current sponsorship ends $endText. Continue for another 30 days'
              '${amount > 0 ? ' for ${formatPeso(amount)}' : ''}? The new period starts when the current one ends.',
          style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'later'),
            child: Text('Not now', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'stop'),
            child: Text('Stop sponsoring', style: GoogleFonts.zain(fontSize: 16, color: AppColors.error)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'continue'),
            child: Text('Continue',
                style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
    if (!mounted || choice == null || choice == 'later') return;
    _dismiss(item);

    if (choice == 'stop') {
      try {
        const update = {'sponsorshipStatus': 'cancelled'};
        await Future.wait([
          db.collection('donations').doc(donationId).update(update),
          db.collection('users').doc(uid).collection('history').doc(donationId).update(update),
        ]);
        if (mounted) {
          _showInfo('Sponsorship stopped',
              'Your sponsorship of $name will not be renewed. Your support until it ends $endText still counts — thank you!');
        }
      } catch (_) {
        if (mounted) _showInfo('Could not stop the sponsorship', 'Please try again.');
      }
      return;
    }

    if (listing.status != 'active' || amount <= 0) {
      _showInfo('Sponsorship', 'This sponsorship is not accepting new payments right now.');
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SponsorshipReviewSheet(sponsorship: listing, amount: amount),
    );
  }

  void _showInfo(String title, String message) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(title, style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      content: Text(message, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('OK', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );

  Future<void> _openItem(_NotifItem item) async {
    // A renewal question stays listed until it is answered.
    if (item.sourceType != 'sponsorship_renewal') _dismiss(item);

    if (item.kind == _NotifKind.donation) {
      final uid = _uid;
      if (uid != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .doc(item.docId)
            .update({'isRead': true})
            .catchError((_) {});
      }
      if (item.sourceType == 'sponsorship_renewal') {
        await _askToRenewSponsorship(item);
        return;
      }
      // A notice about a rescue case (critical report escalation, referral,
      // transit ended, ...) opens the same screen as its push, never the
      // donation history.
      final caseId = item.data?['caseId'] as String?;
      if (caseId != null && caseId.isNotEmpty) {
        Widget? page;
        try {
          page = await NotificationService.pageFor(item.data!);
        } catch (_) {}
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => page ?? TrackCasePage(caseId: caseId)),
        );
        return;
      }
      final adoptionId = item.data?['adoptionId'] as String?;
      if (kApplicantAdoptionNotifTypes.contains(item.sourceType) && adoptionId != null && adoptionId.isNotEmpty) {
        try {
          final page = await adopterPageForAdoption(adoptionId);
          if (page == null || !mounted) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        } catch (_) {}
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _kCertificateNotifTypes.contains(item.sourceType)
              ? const CertificatesPage()
              : const HistoryPage(initialTab: 2),
        ),
      );
      return;
    }

    if (item.kind == _NotifKind.rescue) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => TrackCasePage(caseId: item.docId)),
      );
      return;
    }

    try {
      final page = await adopterPageForAdoption(item.docId, fallbackName: item.refLabel);
      if (page == null || !mounted) return;
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
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
              color: Colors.grey.withValues(alpha: 0.5),
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
                      color: AppColors.error,
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