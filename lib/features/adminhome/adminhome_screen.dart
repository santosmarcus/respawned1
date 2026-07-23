import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';
import 'package:respawnd1/features/admin/admin_adoption_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_page.dart';
import 'package:respawnd1/features/admin/collarTags/admin_collar_screen.dart';
import 'package:respawnd1/features/adminhome/analytics_dashboard.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;
  AdminAnalyticsCategory _analyticsCategory = AdminAnalyticsCategory.rescue;
  String? _orgId;
  bool _resolvingOrg = true;

  @override
  void initState() {
    super.initState();
    _resolveOrg();
  }

  // Scopes analytics queries to the admin's own organization when one is on
  // file. During this testing phase `users/{uid}.organizationId` may not be
  // populated for every account yet — in that case we fail open and show
  // analytics across all organizations rather than an empty dashboard.
  Future<void> _resolveOrg() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      _orgId = doc.data()?['organizationId'] as String?;
    }
    if (mounted) setState(() => _resolvingOrg = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const _AdminDrawer(),
      appBar: AppBar(
        //leading: IconButton(
        //icon: const Icon(Icons.menu, color: AppColors.background),
        //onPressed: () {},
        //),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        backgroundColor: AppColors.textPrimary,
        title: Text(
          'Admin Dashboard',
          style: GoogleFonts.tiltWarp(
              fontSize: 18, color: AppColors.background),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome
            Text('Welcome, Admin',
                style: Theme.of(context).textTheme.headlineLarge),

            const SizedBox(height: 20),

            // Dashboard label
            Text('Dashboard',
                style: Theme.of(context).textTheme.titleLarge),

            const SizedBox(height: 16),

            // Gauge / capacity chart placeholder
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                  )
                ],
              ),
              child: Column(
                children: [
                  // Semicircle gauge placeholder
                  CustomPaint(
                    size: const Size(160, 80),
                    painter: _GaugePainter(value: 0.65),
                  ),
                  const SizedBox(height: 8),
                  Text('232',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                  Text('Total Capacity',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Pending Requests card
            _SectionCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 18, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Text('Pending Requests',
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                    ],
                  ),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Pending breakdown
            _SectionCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _StatItem(label: 'Rescue', value: '30'),
                  _Divider(),
                  _StatItem(label: 'Pet\nTransporter', value: '14'),
                  _Divider(),
                  _StatItem(label: 'Rescue\nVolunteer', value: '30'),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Analytics
            Text('Analytics',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),

            // Category picker — Rescue / Adoptions / Donations / Shelter
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: AdminAnalyticsCategory.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final category = AdminAnalyticsCategory.values[i];
                  final selected = _analyticsCategory == category;
                  return GestureDetector(
                    onTap: () => setState(() => _analyticsCategory = category),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.textPrimary : Colors.transparent,
                        border: Border.all(color: AppColors.textPrimary.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      alignment: Alignment.center,
                      child: Text(category.label,
                          style: GoogleFonts.zain(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: selected ? AppColors.background : AppColors.textPrimary)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 14),

            _resolvingOrg
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
            )
                : AdminAnalyticsSection(
              category: _analyticsCategory,
              orgId: _orgId,
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

// Gauge painter
class _GaugePainter extends CustomPainter {
  final double value; // 0.0 to 1.0

  _GaugePainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 18
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 10;

    // Background arc
    paint.color = AppColors.slaterspwn;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14159, // start at left (π)
      3.14159, // sweep half circle
      false,
      paint,
    );

    // Filled arc
    paint.color = AppColors.textPrimary;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      3.14159,
      3.14159 * value,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// Reusable widgets
class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
          )
        ],
      ),
      child: child,
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  const _StatItem({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.tiltWarp(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(
                fontSize: 11, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
        width: 1, height: 40, color: AppColors.slaterspwn);
  }
}

class _AdminDrawer extends StatelessWidget {
  const _AdminDrawer();

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
                    child: Text('G',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 20, color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Loved by the Gapz',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 14, color: AppColors.background)),
                      Text('Admin Staff',
                          style: GoogleFonts.zain(
                              fontSize: 12,
                              color: AppColors.background
                                  .withValues(alpha: 0.7))),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const RescueReportsPage()),
                );
              },
            ),
            _DrawerItem(
              label: 'Adoptions',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                      const AdminAdoptionPage()),
                );
              },
            ),
            _DrawerItem(
              label: 'Donations',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                      const AdminAdoptionPage(showDonations: true)),
                );
              },
            ),
            _DrawerItem(label: 'Volunteer', onTap: () {}),
            _DrawerItem(label: 'Pet Transporters', onTap: () {}),
            _DrawerItem(label: 'Rescue Volunteers', onTap: () {}),
            _DrawerItem(
              label: 'Animal Record',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AnimalRecordsPage()),
                );
              },
            ),
            _DrawerItem(label: 'Shelter Resources', onTap: () {}),
            _DrawerItem(
              label: 'Pet Collar ID Tags',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AdminCollarTagScreen()),
                );
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
                child: Text('Log out',
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w600)),
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
      title: Text(
        label,
        style: GoogleFonts.zain(
            fontSize: 15,
            color: AppColors.background,
            fontWeight: FontWeight.w500),
      ),
      trailing: const Icon(Icons.chevron_right,
          color: Colors.white38, size: 18),
      dense: true,
    );
  }
}