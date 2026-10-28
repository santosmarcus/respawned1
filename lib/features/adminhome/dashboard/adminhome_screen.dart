import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_view.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_alerts.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/today_view.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

enum _DashTab { today, analytics }

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  _DashTab _tab = _DashTab.today;
  final _priorityKey = GlobalKey();

  /// Bell: switch to Today and scroll to Priority actions.
  void _openPriorityActions() {
    setState(() => _tab = _DashTab.today);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _priorityKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.02,
        );
      }
    });
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
              final alerts = ref.watch(dashboardAlertsProvider);
              final open = alerts.count(DashSeverity.critical) + alerts.count(DashSeverity.warning);
              return IconButton(
                tooltip: open == 0 ? 'Priority actions' : '$open priority actions',
                icon: Badge(
                  isLabelVisible: open > 0,
                  backgroundColor: DashSeverity.critical.color,
                  label: Text(open > 99 ? '99+' : '$open'),
                  child: const Icon(Icons.notifications_outlined, color: AppColors.background),
                ),
                onPressed: _openPriorityActions,
              );
            },
          ),
        ],
        // Reference header: menu + bell on top, greeting below.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(46),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(48, 0, 16, 14),
              child: Text('Welcome, Admin', style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.background)),
            ),
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
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
      ),
      body: SingleChildScrollView(
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
                    if (_tab == _DashTab.analytics) const AnalyticsPeriodButton() else const _LivePill(),
                  ],
                ),
                const SizedBox(height: 12),
                _TabSwitch(value: _tab, onChanged: (t) => setState(() => _tab = t)),
                const SizedBox(height: 14),
                if (_tab == _DashTab.today) TodayView(priorityKey: _priorityKey) else const AnalyticsView(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Today's figures are live (current state), not a reporting period — so
/// this is a label, not a button.
class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 9, color: DashSeverity.ok.color),
          const SizedBox(width: 6),
          Text('Live', style: dashBody(size: 14, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _TabSwitch extends StatelessWidget {
  final _DashTab value;
  final ValueChanged<_DashTab> onChanged;
  const _TabSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget tab(_DashTab t, String label) {
      final on = value == t;
      return Expanded(
        child: Semantics(
          selected: on,
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => onChanged(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.textPrimary : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: on ? AppColors.background : AppColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: const Color(0xFFEFECE3), borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [tab(_DashTab.today, 'Today'), const SizedBox(width: 4), tab(_DashTab.analytics, 'Analytics')],
      ),
    );
  }
}
