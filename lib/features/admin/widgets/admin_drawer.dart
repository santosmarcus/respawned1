import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/admin/admin_adoption_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_page.dart';
import 'package:respawnd1/features/admin/collarTags/admin_collar_screen.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';

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
class AdminDrawer extends StatelessWidget {
  const AdminDrawer({super.key});

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

            // Menu items
            _DrawerItem(
              label: 'Dashboard',
              onTap: () => Navigator.pop(context),
            ),
            _DrawerItem(
              label: 'Rescue Report',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RescueReportsPage()));
              },
            ),
            _DrawerItem(
              label: 'Adoptions',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAdoptionPage()));
              },
            ),
            _DrawerItem(
              label: 'Donations',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAdoptionPage(showDonations: true)));
              },
            ),
            _DrawerItem(label: 'Volunteer', onTap: () {}),
            _DrawerItem(label: 'Pet Transporters', onTap: () {}),
            _DrawerItem(label: 'Rescue Volunteers', onTap: () {}),
            _DrawerItem(
              label: 'Animal Record',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AnimalRecordsPage()));
              },
            ),
            _DrawerItem(label: 'Shelter Resources', onTap: () {}),
            _DrawerItem(
              label: 'Pet Collar ID Tags',
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
                onTap: () async {
                  await AuthService().signOut();
                },
                child: Text('Log out', style: GoogleFonts.zain(fontSize: 14, color: Colors.redAccent, fontWeight: FontWeight.w600)),
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
