import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/widgets/welcome_greeting.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_view.dart';
import 'package:respawnd1/features/adminhome/dashboard/admin_notifications.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_cache.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/independent_area_card.dart';
import 'package:respawnd1/features/adminhome/dashboard/today_view.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

enum _DashTab {
  today('Today'),
  analytics('Analytics');

  const _DashTab(this.label);
  final String label;
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  _DashTab _tab = _DashTab.today;

  /// Bell: notices sent to this account and the recent activity.
  void _openNotifications() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationsPage()));
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Scaffold(
      drawer: const AdminDrawer(active: AdminModule.dashboard),
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Menu',
            icon: const Icon(Icons.menu, color: AppColors.background),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        backgroundColor: AppColors.textPrimary,
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final count = ref.watch(adminBellCountProvider);
              return IconButton(
                tooltip: count == 0 ? 'Notifications' : '$count new notifications',
                icon: Badge(
                  isLabelVisible: count > 0,
                  backgroundColor: DashSeverity.critical.color,
                  label: Text(count > 99 ? '99+' : '$count'),
                  child: const Icon(Icons.notifications_outlined, color: AppColors.background),
                ),
                onPressed: _openNotifications,
              );
            },
          ),
        ],
        // Reference header: menu + bell on top, greeting below, then the
        // same tab bar every admin screen uses.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46 + AdminTabBar.height),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 46,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
                    child: WelcomeGreeting(
                      style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.background),
                    ),
                  ),
                ),
              ),
              AdminTabBar(
                tabs: [for (final t in _DashTab.values) AdminTab(t.label)],
                selectedIndex: _tab.index,
                onSelected: (i) => setState(() => _tab = _DashTab.values[i]),
              ),
            ],
          ),
        ),
      ),
      // Keeps the Today data loaded while module screens cover the
      // dashboard and while the Analytics tab is open.
      body: DashboardKeepAlive(
        child: SingleChildScrollView(
        key: PageStorageKey('admin-dashboard-${_tab.name}'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Center(
          // Mobile-first single column; capped width on tablets/web.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${weekdays[now.weekday - 1]}, ${shortDate(now)}',
                        style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textSecondary),
                      ),
                    ),
                    if (_tab == _DashTab.today) const _LivePill(),
                  ],
                ),
                if (_tab == _DashTab.analytics)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Align(alignment: Alignment.centerLeft, child: AnalyticsPeriodButton()),
                  ),
                const SizedBox(height: 14),
                // Independent rescuers: their area map, availability and
                // capacity first (nothing for shelters).
                if (_tab == _DashTab.today) const IndependentAreaCard(),
                if (_tab == _DashTab.today) const TodayView() else const AnalyticsView(),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

/// Whether the organization is taking new rescue reports
/// (`organizations/{id}.acceptingCases`, default true), plus its id.
final _orgAcceptingProvider = StreamProvider.autoDispose<({String? orgId, bool accepting})>((ref) async* {
  final orgId = await ref.watch(currentOrganizationIdProvider.future);
  if (orgId == null) {
    yield (orgId: null, accepting: true);
    return;
  }
  yield* FirebaseFirestore.instance
      .collection('organizations')
      .doc(orgId)
      .snapshots()
      .map((s) => (orgId: orgId, accepting: s.data()?['acceptingCases'] as bool? ?? true));
});

/// "Live" while the organization takes new rescue reports, "Paused" when an
/// admin turned that off. Admins tap it to switch; others just see it.
class _LivePill extends ConsumerWidget {
  const _LivePill();

  Future<void> _toggle(BuildContext context, String orgId, bool accepting) async {
    final turnOff = accepting;
    final ok = await showConfirmActionDialog(
      context,
      title: turnOff ? 'Pause new rescue reports?' : 'Go live again?',
      message: turnOff
          ? 'New reports in your service areas will go to other organizations until you turn this back on. '
              'Cases you already have are not affected.'
          : 'New rescue reports in your service areas will come to your organization again.',
      confirmLabel: turnOff ? 'Pause' : 'Go live',
    );
    if (!ok) return;
    try {
      await OrganizationRepository().setAcceptingCases(organizationId: orgId, accepting: !accepting);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not update: $e', kind: AppMessageKind.error));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(_orgAcceptingProvider).value;
    final accepting = state?.accepting ?? true;
    final isAdmin = ref.watch(isOrgAdminProvider).value ?? false;
    final orgId = state?.orgId;
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: accepting ? DashSeverity.ok.color : DashSeverity.warning.color),
          const SizedBox(width: 6),
          Text(accepting ? 'Live' : 'Paused', style: dashBody(size: 14, weight: FontWeight.w700)),
          if (isAdmin && orgId != null) ...[
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 16, color: AppColors.textSecondary),
          ],
        ],
      ),
    );
    if (!isAdmin || orgId == null) return pill;
    return Tooltip(
      message: accepting ? 'Taking new rescue reports. Tap to pause.' : 'New reports paused. Tap to go live.',
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _toggle(context, orgId, accepting),
        child: pill,
      ),
    );
  }
}
