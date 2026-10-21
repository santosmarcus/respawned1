import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/app_theme.dart';

class ServiceHomeScreen extends StatefulWidget {
  const ServiceHomeScreen({super.key});

  @override
  State<ServiceHomeScreen> createState() => _ServiceHomeScreenState();
}

class _ServiceHomeScreenState extends State<ServiceHomeScreen> {
  bool _isOnline = false;
  int _currentIndex = 0;

  void _toggleOnline() {
    setState(() => _isOnline = !_isOnline);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Service page'),
        actions: [
          IconButton(
            icon: const Icon(Icons.code, color: AppColors.textPrimary),
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
      body: Column(
        children: [
          // Map area
          Expanded(
            flex: 4,
            child: Stack(
              children: [
                // Map placeholder — replace with GoogleMap widget later
                Container(color: AppColors.slaterspwn),

                // Filter icon top right
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                        )
                      ],
                    ),
                    child: const Icon(Icons.tune,
                        color: AppColors.textPrimary, size: 20),
                  ),
                ),

                // Go Online button centered at bottom of map
                Positioned(
                  bottom: 16,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GestureDetector(
                      onTap: _toggleOnline,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        decoration: BoxDecoration(
                          color: _isOnline
                              ? AppColors.greenrspwn
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(50),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.power_settings_new,
                              color: _isOnline
                                  ? AppColors.background
                                  : AppColors.textPrimary,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isOnline ? 'Go Offline' : 'Go Online',
                              style: GoogleFonts.tiltWarp(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: _isOnline
                                    ? AppColors.background
                                    : AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom panel
          Expanded(
            flex: 3,
            child: Container(
              color: AppColors.background,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Status banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.slaterspwn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _isOnline
                          ? 'You are currently online.'
                          : 'You are currently offline.',
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  Text('Service Request',
                      style: Theme.of(context).textTheme.headlineLarge),

                  const SizedBox(height: 12),

                  // Request list
                  Expanded(
                    child: _isOnline
                        ? StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('cases')
                          .where('status', isEqualTo: 'pending')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData ||
                            snapshot.data!.docs.isEmpty) {
                          return _EmptyRequests();
                        }

                        return ListView.separated(
                          itemCount: snapshot.data!.docs.length,
                          separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final doc = snapshot.data!.docs[index];
                            final data =
                            doc.data() as Map<String, dynamic>;
                            return _RequestCard(data: data);
                          },
                        );
                      },
                    )
                        : _EmptyRequests(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.slaterspwn,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'There are no requests for now.\nGo Online',
        textAlign: TextAlign.center,
        style: GoogleFonts.zain(
          fontSize: 14,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RequestCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.slaterspwn,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.pets, color: AppColors.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['animalType'] ?? 'Animal',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 14, color: AppColors.textPrimary),
                ),
                Text(
                  data['description'] ?? '',
                  style: GoogleFonts.zain(
                      fontSize: 12, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn,
              borderRadius: BorderRadius.circular(50),
            ),
            child: Text('View',
                style: GoogleFonts.zain(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}