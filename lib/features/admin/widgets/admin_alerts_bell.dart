import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_alerts.dart';
import 'package:respawnd1/features/adminhome/dashboard/today_view.dart';

/// The app-bar bell for admin module pages. Same badge as the dashboard's
/// own bell (open critical + warning alerts from [dashboardAlertsProvider]);
/// tapping opens the dashboard's [PriorityActionsCard] in a sheet so an
/// admin can act on an alert without leaving the page they're on.
class AdminAlertsBell extends ConsumerWidget {
  const AdminAlertsBell({super.key});

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (context, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              const PriorityActionsCard(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      onPressed: () => _openSheet(context),
    );
  }
}
