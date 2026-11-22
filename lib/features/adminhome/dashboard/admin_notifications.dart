import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/services/notification_service.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';

/// The admin bell: notices the backend sent this account (critical report
/// escalations, referrals, transport offers declined, ...) and the
/// organization's recent activity.
///
/// Notices are `users/{uid}/notifications` (written by notifyStaff and the
/// other functions; the user may read them and set `isRead`). The bell's
/// number is unread notices plus activity since the page was last opened
/// (`users/{uid}.adminNotificationsSeenAt`).

// ─── Notices ─────────────────────────────────────────────────────────────

class AdminNotice {
  final String id;
  final String title;
  final String message;
  final String type;
  final DateTime? time;
  final bool isRead;
  final Map<String, dynamic> data;
  const AdminNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.time,
    required this.isRead,
    required this.data,
  });

  factory AdminNotice.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final ts = m['timestamp'];
    return AdminNotice(
      id: d.id,
      title: (m['title'] as String?)?.trim().isNotEmpty == true ? m['title'] as String : 'Update',
      message: m['message'] as String? ?? '',
      type: m['type'] as String? ?? '',
      time: ts is Timestamp ? ts.toDate() : null,
      isRead: m['isRead'] == true,
      data: m,
    );
  }

  bool get isUrgent => type == 'critical_report_escalated' || title.toUpperCase().startsWith('URGENT');

  IconData get icon => switch (type) {
    'critical_report_escalated' => Icons.priority_high,
    'case_referral' || 'referral_response' => Icons.swap_horiz,
    'transport_offer_outcome' => Icons.local_shipping,
    'transit_ended_staff' => Icons.report_gmailerrorred,
    'quarantine_ended' => Icons.health_and_safety,
    'shelter_location_missing' => Icons.location_off,
    'follow_up_overdue_staff' => Icons.assignment_late,
    'adoption_promotion_due' => Icons.campaign,
    'cash_out_needs_assignment' || 'cash_out_assigned' || 'cash_out_returned' => Icons.account_balance_wallet_outlined,
    _ => Icons.notifications,
  };
}

DocumentReference<Map<String, dynamic>>? _userDoc() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  return uid == null ? null : FirebaseFirestore.instance.collection('users').doc(uid);
}

/// This account's latest 50 notices, newest first.
final adminNoticesProvider = StreamProvider.autoDispose<List<AdminNotice>>((ref) {
  final user = _userDoc();
  if (user == null) return Stream.value(const []);
  return user
      .collection('notifications')
      .orderBy('timestamp', descending: true)
      .limit(50)
      .snapshots()
      .map((s) => s.docs.map(AdminNotice.fromDoc).toList());
});

/// When this account last opened the admin notifications page.
final adminNotificationsSeenAtProvider = StreamProvider.autoDispose<DateTime?>((ref) {
  final user = _userDoc();
  if (user == null) return Stream.value(null);
  return user.snapshots().map((d) {
    final v = d.data()?['adminNotificationsSeenAt'];
    return v is Timestamp ? v.toDate() : null;
  });
});

// ─── Recent activity ─────────────────────────────────────────────────────

class ActivityEvent {
  final IconData icon;
  final String title;
  final String subtitle;
  final DateTime time;
  final void Function(BuildContext) open;
  const ActivityEvent(this.icon, this.title, this.subtitle, this.time, this.open);
}

/// Built from timestamps already on loaded records (case reports,
/// treatment updates, adoption decisions, donations): no generated entries
/// and no extra query. Null while the rescue cases are still loading.
final recentActivityProvider = Provider.autoDispose<List<ActivityEvent>?>((ref) {
  final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
  final approved =
      ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved))).asData?.value ?? const [];
  final adopted =
      ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted))).asData?.value ?? const [];
  final canView = ref.watch(canViewFinancesProvider).asData?.value ?? false;
  final donations = canView ? ref.watch(recentDonationsProvider).asData?.value : null;
  if (snap == null) return null;

  String animalOf(RescueCase c) => c.speciesSummary.isEmpty ? 'Animal' : c.speciesSummary;
  return <ActivityEvent>[
    for (final c in snap.all)
      if (c.createdAt != null)
        ActivityEvent(
          Icons.sos,
          'New report · ${animalOf(c)}${c.address == null ? '' : ', ${c.address!.split(',').first}'}',
          c.reporterName ?? 'Community reporter',
          c.createdAt!,
              (ctx) => openRescueCase(ctx, c),
        ),
    for (final c in snap.of(RescueStage.treatment))
      if (c.treatmentUpdatedAt != null)
        ActivityEvent(
          Icons.healing,
          'Treatment update · ${animalOf(c)} #${c.shortCaseId}',
          [c.latestTreatmentUpdateType, c.vetClinicName].whereType<String>().join(' · '),
          c.treatmentUpdatedAt!,
              (ctx) => openTreatment(ctx, c),
        ),
    for (final a in approved)
      if (a.approvedAt != null)
        ActivityEvent(
          Icons.check,
          'Application approved · ${a.animalName}',
          a.adopterName,
          a.approvedAt!,
              (ctx) => openApplication(ctx, a),
        ),
    for (final a in adopted)
      if (a.adoptedAt != null)
        ActivityEvent(
          Icons.home,
          'Adopted · ${a.animalName}',
          a.adopterName,
          a.adoptedAt!,
              (ctx) => openApplication(ctx, a),
        ),
    for (final d in donations ?? const [])
      if (d.when != null)
        ActivityEvent(
          Icons.payments,
          d.isInKind ? 'In-kind donation recorded' : 'Donation ${formatPeso(d.amountValue)} recorded',
          d.campaignName.isEmpty ? d.displayName : d.campaignName,
          d.when!,
              (ctx) => openDonationsAdmin(ctx),
        ),
  ]..sort((a, b) => b.time.compareTo(a.time));
});

// ─── Bell count ──────────────────────────────────────────────────────────

/// Unread notices, plus activity since the page was last opened (the last
/// 24 hours for an account that never opened it).
final adminBellCountProvider = Provider.autoDispose<int>((ref) {
  final notices = ref.watch(adminNoticesProvider).asData?.value ?? const <AdminNotice>[];
  final events = ref.watch(recentActivityProvider) ?? const <ActivityEvent>[];
  final seenAt = ref.watch(adminNotificationsSeenAtProvider).asData?.value ??
      DateTime.now().subtract(const Duration(hours: 24));
  return notices.where((n) => !n.isRead).length + events.where((e) => e.time.isAfter(seenAt)).length;
});

// ─── Page ────────────────────────────────────────────────────────────────

class AdminNotificationsPage extends ConsumerStatefulWidget {
  const AdminNotificationsPage({super.key});

  @override
  ConsumerState<AdminNotificationsPage> createState() => _AdminNotificationsPageState();
}

class _AdminNotificationsPageState extends ConsumerState<AdminNotificationsPage> {
  /// When the page opened: activity after the previous visit is marked New
  /// for this visit, while the account's seen time moves to now.
  DateTime? _previousSeenAt;

  @override
  void initState() {
    super.initState();
    _previousSeenAt = ref.read(adminNotificationsSeenAtProvider).asData?.value;
    _userDoc()
        ?.set({'adminNotificationsSeenAt': FieldValue.serverTimestamp()}, SetOptions(merge: true))
        .catchError((Object e) => debugPrint('AdminNotificationsPage: could not save seen time: $e'));
  }

  Future<void> _openNotice(AdminNotice n) async {
    final user = _userDoc();
    if (!n.isRead && user != null) {
      user.collection('notifications').doc(n.id).update({'isRead': true}).catchError((_) {});
    }
    Widget? page;
    try {
      page = await NotificationService.pageFor(n.data);
    } catch (e) {
      debugPrint('AdminNotificationsPage: could not open ${n.type}: $e');
    }
    if (page == null || !mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
  }

  Future<void> _markAllRead(List<AdminNotice> unread) async {
    final user = _userDoc();
    if (user == null || unread.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final n in unread) {
      batch.update(user.collection('notifications').doc(n.id), {'isRead': true});
    }
    try {
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not mark as read: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final noticesAsync = ref.watch(adminNoticesProvider);
    final events = ref.watch(recentActivityProvider);
    final unread = (noticesAsync.asData?.value ?? const <AdminNotice>[]).where((n) => !n.isRead).toList();
    final since = _previousSeenAt ?? DateTime.now().subtract(const Duration(hours: 24));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: AppColors.background),
        title: Text('Notifications', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        actions: [
          if (unread.isNotEmpty)
            TextButton(
              onPressed: () => _markAllRead(unread),
              child: Text(
                'Mark all read',
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.yellowrspwn),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    icon: Icons.notifications_active_outlined,
                    title: 'For you',
                    trailing: unread.isEmpty
                        ? null
                        : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: StatusChip('${unread.length} unread', tone: ChipTone.red),
                    ),
                    child: noticesAsync.when(
                      loading: () => const DashLoading(),
                      error: (e, _) => DashError(what: 'notifications', error: e),
                      data: (notices) => notices.isEmpty
                          ? const DashEmpty('No notifications yet.', severity: DashSeverity.info)
                          : ExpandableList(
                        initialCount: 10,
                        moreLabel: 'All notifications',
                        children: [
                          for (final n in notices) _NoticeRow(notice: n, onTap: () => _openNotice(n)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    icon: Icons.history,
                    title: 'Recent activity',
                    child: events == null
                        ? const DashLoading()
                        : events.isEmpty
                        ? const DashEmpty('No recent activity recorded.', severity: DashSeverity.info)
                        : ExpandableList(
                      initialCount: 15,
                      moreLabel: 'All recent activity',
                      children: [
                        for (final e in events.take(100)) _EventRow(e: e, isNew: e.time.isAfter(since)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  final AdminNotice notice;
  final VoidCallback onTap;
  const _NoticeRow({required this.notice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = notice.isUrgent ? DashSeverity.critical.color : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.10), shape: BoxShape.circle),
              child: Icon(notice.icon, size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notice.title,
                    style: dashBody(size: 14.5, weight: notice.isRead ? FontWeight.w600 : FontWeight.w800, color: color),
                  ),
                  if (notice.message.isNotEmpty)
                    Text(notice.message, maxLines: 3, overflow: TextOverflow.ellipsis, style: dashMuted(12.5)),
                  Text(elapsedSince(notice.time), style: dashMuted(12)),
                ],
              ),
            ),
            if (!notice.isRead)
              Padding(
                padding: const EdgeInsets.only(left: 6, top: 4),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: DashSeverity.critical.color, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final ActivityEvent e;
  final bool isNew;
  const _EventRow({required this.e, this.isNew = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => e.open(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: const BoxDecoration(color: AppColors.tearspwn, shape: BoxShape.circle),
              child: Icon(e.icon, size: 15, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: dashBody(size: 14, weight: FontWeight.w700),
                  ),
                  Text('${e.subtitle.isEmpty ? '' : '${e.subtitle} · '}${elapsedSince(e.time)}', style: dashMuted()),
                ],
              ),
            ),
            if (isNew) const StatusChip('New', tone: ChipTone.amber),
          ],
        ),
      ),
    );
  }
}
