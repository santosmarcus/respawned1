import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/adminhome/admin_dashboard_home_widgets.dart';
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
      drawer: const AdminDrawer(active: AdminModule.dashboard),
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

            // Admin Information Priority spec — "what needs attention right
            // now" comes first, ahead of any lifetime/platform statistics.
            // Replaces the old hardcoded gauge ("232 Total Capacity") and
            // fake Pending Requests breakdown (Rescue 30 / Pet Transporter
            // 14 / Rescue Volunteer 30) — none of that was backed by a
            // Firestore query. Wrapped in a ProviderScope-aware Consumer
            // tree via ActionRequiredSection/CurrentOperationsSection
            // themselves (ConsumerWidgets), so this screen doesn't need to
            // become a ConsumerStatefulWidget itself just to host them.
            const ActionRequiredSection(),

            const SizedBox(height: 16),

            const TopMetricsRow(),

            const SizedBox(height: 16),

            const CurrentOperationsSection(),

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
                        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.3)),
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


