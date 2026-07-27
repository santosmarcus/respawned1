import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_review_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_page.dart';
import 'package:respawnd1/features/admin/collarTags/admin_collar_screen.dart';
import 'package:respawnd1/features/admin/donations/donation_admin_home.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// The one shared admin navigation drawer — every admin root page
/// (`AdminHomeScreen`, `RescueReportsPage`, `AdminAdoptionPage`,
/// `AnimalRecordsPage`, `AdminCollarTagScreen`) sets `drawer: const
/// AdminDrawer()` on its own `Scaffold` and opens it via a
/// `Builder`-wrapped menu `IconButton` calling `Scaffold.of(context).
/// openDrawer()` — this used to be duplicated byte-for-byte between
/// `adminhome_screen.dart` and `admin_collar_screen.dart`, with three other
/// admin pages having a menu button that did nothing at all (no `onPressed`
/// action, and no `drawer:` on their own `Scaffold` for it to open even if
/// it had one). One shared widget now, not a third copy.
class AdminDrawer extends ConsumerStatefulWidget {
  const AdminDrawer({super.key});

  @override
  ConsumerState<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends ConsumerState<AdminDrawer> {
  bool _signingOut = false;

  Future<void> _logOut() async {
    if (_signingOut) return; // disable repeated taps while processing
    setState(() => _signingOut = true);

    // Captured before any `await` — these stay usable even if the Drawer's
    // own BuildContext is deactivated once the drawer closes mid-flow.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context); // close the drawer, same pattern every other item uses

    try {
      await authService.value.signOut();

      // The admin-scoped case/adoption list providers are already
      // autoDispose (see rescue_reports_providers.dart / adoption_providers.dart)
      // so their Firestore listeners tear themselves down as soon as the
      // pages watching them are removed below. currentOrgMembershipProvider
      // is global (not tied to a specific page) so it's cleared explicitly.
      ref.invalidate(currentOrgMembershipProvider);

      // Remove every pushed admin route so the stale authenticated screen
      // can't linger on top of AuthWrapper's now-signed-out content —
      // AuthWrapper (the app's root, first route) reactively swaps to
      // LoginScreen on its own once authStateChanges() emits null.
      rootNavigator.popUntil((route) => route.isFirst);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Log out failed: $e')));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.textPrimary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.yellowrspwn,
                    child: Text('G', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Loved by the Gapz', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.background)),
                      Text('Admin Staff', style: GoogleFonts.zain(fontSize: 12, color: AppColors.background.withValues(alpha: 0.7))),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white24),

            // Menu items — order matches the project's required admin menu
            // order: Dashboard, Rescue, Adoptions, Donations, Records,
            // Events, Volunteers, Transporters, Shelter Resources, Collar
            // Tags. "Volunteer" and "Rescue Volunteers" used to be two
            // separate no-op placeholders — consolidated into one
            // Volunteers entry to match. Events, Volunteers, Transporters,
            // and Shelter Resources have no admin screen built yet, so they
            // stay no-op placeholders, same as before.
            _DrawerItem(
              label: 'Dashboard',
              onTap: () {
                final rootNavigator = Navigator.of(context, rootNavigator: true);
                Navigator.pop(context); // close the drawer
                // Pops every pushed admin route back to AdminHomeScreen
                // (the app's first/root route) — previously this only
                // closed the drawer and did nothing else, so "Dashboard"
                // appeared broken from any page other than the dashboard
                // itself.
                rootNavigator.popUntil((route) => route.isFirst);
              },
            ),
            _DrawerItem(
              label: 'Rescue',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueReportsPage()));
              },
            ),
            _DrawerItem(
              label: 'Adoptions',
              onTap: () {
                Navigator.pop(context);
                // Straight to the tabbed Adoption Applications page — the
                // separate admin adoption dashboard is no longer the
                // landing page for Adoptions.
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdoptionApplicationReviewPage()));
              },
            ),
            _DrawerItem(
              label: 'Donations',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DonationAdminHomeScreen()));
              },
            ),
            _DrawerItem(
              label: 'Records',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimalRecordsPage()));
              },
            ),
            _DrawerItem(label: 'Events', onTap: () {}),
            _DrawerItem(label: 'Volunteers', onTap: () {}),
            _DrawerItem(label: 'Transporters', onTap: () {}),
            _DrawerItem(label: 'Shelter Resources', onTap: () {}),
            _DrawerItem(
              label: 'Collar Tags',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCollarTagScreen()));
              },
            ),

            const Spacer(),

            // Log out
            Padding(
              padding: const EdgeInsets.all(20),
              child: GestureDetector(
                onTap: _signingOut ? null : _logOut,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Log out',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            color: _signingOut ? Colors.redAccent.withValues(alpha: 0.5) : Colors.redAccent,
                            fontWeight: FontWeight.w600)),
                    if (_signingOut) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      title: Text(label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.background, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
      dense: true,
    );
  }
}
