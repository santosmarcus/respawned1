import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AdminDrawer(),
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

            // Stats grid
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.3,
              children: [
                _StatCard(
                  label: 'Total Rescues',
                  value: '124',
                  trend: '+1.2%',
                  trendLabel: 'vs Last month',
                ),
                _StatCard(
                  label: 'Total Adoptions',
                  value: '12',
                  showTrend: false,
                ),
                _StatCard(
                  label: 'Total Volunteer Events',
                  value: '124',
                  trend: '+1.2%',
                  trendLabel: 'vs Last month',
                ),
                _StatCard(
                  label: 'Total Donations',
                  value: 'Php. 23,495',
                  showTrend: false,
                  valueFontSize: 20,
                ),
              ],
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final String? trend;
  final String? trendLabel;
  final bool showTrend;
  final double valueFontSize;

  const _StatCard({
    required this.label,
    required this.value,
    this.trend,
    this.trendLabel,
    this.showTrend = true,
    this.valueFontSize = 28,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const Spacer(),
          Text(value,
              style: GoogleFonts.tiltWarp(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          if (showTrend && trend != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.trending_up,
                    size: 12, color: Colors.green),
                const SizedBox(width: 4),
                Text('$trend\n${trendLabel ?? ''}',
                    style: GoogleFonts.zain(
                        fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

