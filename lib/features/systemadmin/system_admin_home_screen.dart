import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/organizations/organization_review_page.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/systemadmin/system_users_page.dart';

/// Home of a system admin (`users/{uid}.role == 'system_admin'`, set in the
/// Firebase console). Two jobs only:
///  - Approvals: approve, reject or ask for changes on organization sign-ups
///    waiting for verification (the reviewOrganization callable).
///  - Users: a read-only directory of every account, by organization and by
///    account type.
/// Transporters are verified by organization staff, not here. The console has
/// no access to cases, animals, medical records or finances (firestore.rules).
class SystemAdminHomeScreen extends StatefulWidget {
  const SystemAdminHomeScreen({super.key});

  @override
  State<SystemAdminHomeScreen> createState() => _SystemAdminHomeScreenState();
}

class _SystemAdminHomeScreenState extends State<SystemAdminHomeScreen> {
  int _index = 0;
  bool _signingOut = false;
  final Stream<int> _pendingCount = FirebaseFirestore.instance
      .collection('organizations')
      .where('verificationStatus', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.size);

  Future<void> _signOut() async {
    if (_signingOut) return;
    setState(() => _signingOut = true);
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await authService.value.signOut();
      // AuthWrapper (the first route) shows the login screen once signed out.
      rootNavigator.popUntil((route) => route.isFirst);
    } catch (e) {
      messenger.showSnackBar(appSnackBar('Log out failed: $e', kind: AppMessageKind.error));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = [AdminMenuAction(label: 'Log out', icon: Icons.logout, onTap: _signOut)];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        children: [
          OrganizationReviewPage(title: 'Sign-up approvals', showBackButton: false, menuActions: menu),
          SystemUsersPage(menuActions: menu),
        ],
      ),
      bottomNavigationBar: StreamBuilder<int>(
        stream: _pendingCount,
        builder: (context, snap) {
          final pending = snap.data ?? 0;
          return NavigationBar(
            selectedIndex: _index,
            backgroundColor: AppColors.surface,
            indicatorColor: AppColors.yellowrspwn,
            onDestinationSelected: (i) => setState(() => _index = i),
            labelTextStyle: WidgetStatePropertyAll(GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
            destinations: [
              NavigationDestination(
                icon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.verified_outlined),
                ),
                selectedIcon: Badge(
                  isLabelVisible: pending > 0,
                  label: Text('$pending'),
                  child: const Icon(Icons.verified),
                ),
                label: 'Approvals',
              ),
              const NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Users',
              ),
            ],
          );
        },
      ),
    );
  }
}
