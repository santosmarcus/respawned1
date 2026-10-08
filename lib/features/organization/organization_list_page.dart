import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';

import 'organization_model.dart';
import 'organization_profile_page.dart';

class OrganizationsListPage extends StatefulWidget {
  const OrganizationsListPage({super.key});

  @override
  State<OrganizationsListPage> createState() => _OrganizationsListPageState();
}

class _OrganizationsListPageState extends State<OrganizationsListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Set<String> _favoriteIds = {};
  bool _loadingFavorites = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _favoritesRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('favoriteOrganizations');

  Future<void> _loadFavorites() async {
    try {
      final snapshot = await _favoritesRef.get();
      if (mounted) {
        setState(() {
          _favoriteIds = snapshot.docs.map((d) => d.id).toSet();
          _loadingFavorites = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingFavorites = false);
    }
  }

  Future<void> _toggleFavorite(Organization org) async {
    final isFav = _favoriteIds.contains(org.id);
    setState(() {
      if (isFav) {
        _favoriteIds.remove(org.id);
      } else {
        _favoriteIds.add(org.id);
      }
    });

    final doc = _favoritesRef.doc(org.id);
    if (isFav) {
      await doc.delete();
    } else {
      await doc.set({
        'organizationId': org.id,
        'name': org.name,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: true,
        centerTitle: false,
        title: Text(
          'Organizations',
          style: GoogleFonts.tiltWarp(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
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
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => const NotificationsScreen()),
            );
          } else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserProfile()),
            );
          }
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: GoogleFonts.zain(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: GoogleFonts.zain(
                          fontSize: 15,
                          color: AppColors.textPrimary.withOpacity(0.6),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.tune,
                    color: AppColors.textPrimary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Organization list
          Expanded(
            child: _loadingFavorites
                ? const Center(
                child:
                CircularProgressIndicator(color: AppColors.greenrspwn))
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('organizations')
                  .orderBy('name')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Something went wrong.',
                      style: GoogleFonts.zain(
                          color: AppColors.textSecondary),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.greenrspwn),
                  );
                }

                final q = _searchQuery.toLowerCase();
                final orgs = snapshot.data!.docs
                    .map((doc) => Organization.fromFirestore(
                  doc,
                  favorited: _favoriteIds.contains(doc.id),
                ))
                    .where((org) =>
                q.isEmpty ||
                    org.name.toLowerCase().contains(q) ||
                    org.location.toLowerCase().contains(q))
                    .toList();

                if (orgs.isEmpty) {
                  return Center(
                    child: Text(
                      'No organizations found.',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textSecondary),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  itemCount: orgs.length,
                  separatorBuilder: (_, __) =>
                  const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final org = orgs[index];
                    return _OrganizationCard(
                      organization: org,
                      onFavorite: () => _toggleFavorite(org),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                OrganizationProfilePage(
                                    organizationId: org.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OrganizationCard extends StatelessWidget {
  final Organization organization;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const _OrganizationCard({
    required this.organization,
    required this.onFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 130,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.tearspwn,
                  borderRadius: BorderRadius.circular(16),
                  image: organization.avatarUrl != null &&
                      organization.avatarUrl!.isNotEmpty
                      ? DecorationImage(
                    image: NetworkImage(organization.avatarUrl!),
                    fit: BoxFit.cover,
                  )
                      : null,
                ),
                child: organization.avatarUrl == null ||
                    organization.avatarUrl!.isEmpty
                    ? const Center(
                  child: Icon(Icons.corporate_fare,
                      size: 36, color: AppColors.textSecondary),
                )
                    : null,
              ),
              Positioned(
                top: 10,
                right: 12,
                child: GestureDetector(
                  onTap: onFavorite,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    organization.favorited
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 22,
                    color: organization.favorited
                        ? const Color(0xFFE05C5C)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            organization.name,
            style: GoogleFonts.tiltWarp(
                fontSize: 15, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              const Icon(Icons.location_on_outlined,
                  size: 13, color: AppColors.textSecondary),
              const SizedBox(width: 3),
              Text(
                organization.location,
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}