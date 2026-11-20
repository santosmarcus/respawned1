import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/account/account_page.dart';
import 'package:respawnd1/features/admin/organizations/organization_review_page.dart';
import 'package:respawnd1/features/admin/volunteers/transporter_applications_page.dart';
import 'package:respawnd1/features/admin/volunteers/volunteer_applications_page.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/systemadmin/system_users_page.dart';

/// Home of a system admin (`users/{uid}.role == 'system_admin'`, set in the
/// Firebase console):
///  - Organizations: approve, reject or ask for changes on organization
///    sign-ups waiting for verification (the reviewOrganization callable).
///  - Volunteers / Transporters: approve or reject volunteer and pet
///    transporter applications (organization staff with the Volunteers
///    permission can too).
///  - Users: a read-only directory of every account, by organization and by
///    account type.
/// The console has no access to cases, animals, medical records or finances
/// (firestore.rules).
class SystemAdminHomeScreen extends StatefulWidget {
  const SystemAdminHomeScreen({super.key});

  @override
  State<SystemAdminHomeScreen> createState() => _SystemAdminHomeScreenState();
}

class _SystemAdminHomeScreenState extends State<SystemAdminHomeScreen> {
  int _index = 0;
  bool _signingOut = false;
  // Waiting counts for the tab badges.
  int _pendingOrgs = 0;
  int _pendingVolunteers = 0;
  int _pendingTransporters = 0;
  final List<StreamSubscription<int>> _subs = [];

  @override
  void initState() {
    super.initState();
    void watch(String collection, String field, void Function(int) set) {
      _subs.add(FirebaseFirestore.instance
          .collection(collection)
          .where(field, isEqualTo: 'pending')
          .snapshots()
          .map((s) => s.size)
          .listen((n) {
        if (mounted) setState(() => set(n));
      }, onError: (Object e) => debugPrint('[SystemAdmin] $collection count failed: $e')));
    }

    watch('organizations', 'verificationStatus', (n) => _pendingOrgs = n);
    watch('volunteerApplications', 'status', (n) => _pendingVolunteers = n);
    watch('transporterApplications', 'status', (n) => _pendingTransporters = n);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

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
    final menu = [
      AdminMenuAction(
        label: 'Account',
        icon: Icons.account_circle_outlined,
        onTap: () => Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const AccountPage(returnToDashboard: false))),
      ),
      AdminMenuAction(label: 'Log out', icon: Icons.logout, onTap: _signOut),
    ];
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(
        index: _index,
        children: [
          OrganizationReviewPage(title: 'Organization approvals', showBackButton: false, menuActions: menu),
          VolunteerApplicationsPage(showBackButton: false, menuActions: menu),
          TransporterApplicationsPage(showBackButton: false, menuActions: menu),
          SystemUsersPage(menuActions: menu),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.yellowrspwn,
        onDestinationSelected: (i) => setState(() => _index = i),
        labelTextStyle: WidgetStatePropertyAll(GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
        destinations: [
          _pendingDestination(_pendingOrgs, Icons.verified_outlined, Icons.verified, 'Organizations'),
          _pendingDestination(_pendingVolunteers, Icons.volunteer_activism_outlined, Icons.volunteer_activism, 'Volunteers'),
          _pendingDestination(_pendingTransporters, Icons.local_shipping_outlined, Icons.local_shipping, 'Transporters'),
          const NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Users',
          ),
        ],
      ),
    );
  }

  /// A tab whose icon carries the number of applications waiting.
  Widget _pendingDestination(int n, IconData icon, IconData selected, String label) {
    Widget badged(IconData i) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(i));
    return NavigationDestination(icon: badged(icon), selectedIcon: badged(selected), label: label);
  }
}
