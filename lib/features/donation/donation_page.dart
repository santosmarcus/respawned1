import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'donation_detail.dart';
import 'sponsorship_detail.dart';
import 'models.dart';
import 'package:intl/intl.dart';

// Categories
const _categories = ['All', 'Rescue', 'Medicine & Treatment', 'Food & Supplies', 'Shelter'];

class DonationPage extends StatefulWidget {
  const DonationPage({super.key});

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  bool _showEnded = false;
  
  Set<String> _donatedIds = {};
  Set<String> _favoriteIds = {};
  Set<String> _petFavoriteIds = {};
  Map<String, HistoryItem> _activeSponsorships = {};
  bool _userDataLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> _loadUserData() async {
    if (_uid.isEmpty) return;
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(_uid).collection('donated').get(),
        FirebaseFirestore.instance.collection('users').doc(_uid).collection('donationFavorites').get(),
        FirebaseFirestore.instance.collection('users').doc(_uid).collection('favorites').get(),
        FirebaseFirestore.instance.collection('donations')
            .where('userId', isEqualTo: _uid)
            .where('type', isEqualTo: 'sponsorship')
            .get(),
      ]);

      if (mounted) {
        final sponsorships = results[3].docs.map((doc) => HistoryItem.fromFirestore(doc)).toList();
        final Map<String, HistoryItem> activeMap = {};
        final now = DateTime.now();

        for (var s in sponsorships) {
          // A sponsorship is active if it's "active" OR if it's "inactive" but before next charge date
          final isActiveStatus = s.sponsorshipStatus == 'active';
          final isStillValid = isActiveStatus || (s.nextChargeDate != null && s.nextChargeDate!.isAfter(now));
          
          if (isStillValid && s.campaignId != null) {
            activeMap[s.campaignId!] = s;
          }
        }

        setState(() {
          _donatedIds = results[0].docs.map((d) => d.id).toSet();
          _favoriteIds = results[1].docs.map((d) => d.id).toSet();
          _petFavoriteIds = results[2].docs.map((d) => d.id).toSet();
          _activeSponsorships = activeMap;
          _userDataLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _userDataLoading = false);
    }
  }

  Future<void> _markDonated({
    required DonationListing donation,
    required double amount,
    required String paymentMethod,
    required bool isAnonymous,
  }) async {
    // This will be handled in Phase 4 via transactions in donation_review.dart
    // For now, let's keep the UI feedback logic
    setState(() => _donatedIds.add(donation.id));
  }

  Future<void> _toggleFavorite(DonationListing donation) async {
    final isFav = _favoriteIds.contains(donation.id);
    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('donationFavorites')
        .doc(donation.id);

    if (isFav) {
      await doc.delete();
      setState(() => _favoriteIds.remove(donation.id));
    } else {
      await doc.set({
        'donationId': donation.id,
        'title': donation.title,
        'savedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _favoriteIds.add(donation.id));
    }
  }

  Future<void> _toggleSponsorFavorite(SponsorPet pet) async {
    final isFav = _petFavoriteIds.contains(pet.id);
    final doc = FirebaseFirestore.instance
        .collection('users')
        .doc(_uid)
        .collection('favorites')
        .doc(pet.id);

    if (isFav) {
      await doc.delete();
      setState(() => _petFavoriteIds.remove(pet.id));
    } else {
      await doc.set({
        'petId': pet.id,
        'name': pet.name,
        'savedAt': FieldValue.serverTimestamp(),
      });
      setState(() => _petFavoriteIds.add(pet.id));
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
        centerTitle: true,
        title: Text(
          'Donate/Sponsor',
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
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), activeIcon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.notifications_outlined), activeIcon: Icon(Icons.notifications), label: 'Notifications'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'My Profile'),
        ],
        onTap: (index) {
          if (index == 0) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const HomeScreen()));
          else if (index == 1) Navigator.push(context, MaterialPageRoute(builder: (context) => const NotificationsScreen()));
          else if (index == 2) Navigator.push(context, MaterialPageRoute(builder: (context) => const UserProfile()));
        },
      ),
      body: _userDataLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  _buildSearchBar(),
                  const SizedBox(height: 16),
                  Text('Donations', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  _buildCategoryChips(),
                  const SizedBox(height: 14),
                  _buildDonationList(),
                  const SizedBox(height: 8),
                  Text('Sponsorship', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  _buildSponsorshipList(),
                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchBar() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _searchQuery = v),
              style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search',
                hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary.withValues(alpha: 0.6)),
                prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary, size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        PopupMenuButton<bool>(
          icon: Icon(
            _showEnded ? Icons.visibility : Icons.visibility_off,
            color: _showEnded ? AppColors.greenrspwn : AppColors.textPrimary,
            size: 20,
          ),
          onSelected: (val) => setState(() => _showEnded = val),
          itemBuilder: (context) => [
            const PopupMenuItem(value: false, child: Text('Hide Ended')),
            const PopupMenuItem(value: true, child: Text('Show Ended')),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final selected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(cat, style: GoogleFonts.zain(fontSize: 15, fontWeight: selected ? FontWeight.w700 : FontWeight.normal, color: AppColors.textPrimary)),
                if (selected) Container(margin: const EdgeInsets.only(top: 2), height: 2, width: 24, color: AppColors.textPrimary),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDonationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('campaigns').where('type', isEqualTo: 'donation').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No donations found.'));

        final donations = snapshot.data!.docs.map((doc) => DonationListing.fromFirestore(doc)).where((d) {
          final q = _searchQuery.toLowerCase();
          final matchesSearch = q.isEmpty || d.title.toLowerCase().contains(q) || d.organizer.toLowerCase().contains(q);
          
          if (!_showEnded && d.isEnded) return false;
          
          return matchesSearch;
        }).toList();

        final donatedList = donations.where((d) => _donatedIds.contains(d.id)).toList();
        final activeDonations = donations.where((d) => !_donatedIds.contains(d.id)).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (donatedList.isNotEmpty) ...[
              Text('Donated', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              ...donatedList.map((d) => _DonationListItem(d, _favoriteIds.contains(d.id), () => _toggleFavorite(d), () => _openDetail(d))),
            ],
            if (activeDonations.isNotEmpty)
              ...activeDonations.map((d) => _DonationListItem(d, _favoriteIds.contains(d.id), () => _toggleFavorite(d), () => _openDetail(d))),
          ],
        );
      },
    );
  }

  Widget _buildSponsorshipList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('campaigns').where('type', isEqualTo: 'sponsorship').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No sponsorships found.'));

        final campaigns = snapshot.data!.docs.map((doc) => DonationListing.fromFirestore(doc)).where((c) {
          if (!_showEnded && c.isEnded) return false;
          final q = _searchQuery.toLowerCase();
          return q.isEmpty || (c.animalName?.toLowerCase().contains(q) ?? false) || c.organizer.toLowerCase().contains(q);
        }).toList();

        return Column(
          children: campaigns.map((c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _SponsorPetCard(
              sponsorship: c,
              favorited: _favoriteIds.contains(c.id),
              isSponsored: _activeSponsorships.containsKey(c.id),
              onFavorite: () => _toggleFavorite(c),
              onTap: () => _openSponsorDetail(c),
            ),
          )).toList(),
        );
      },
    );
  }

  Widget _DonationListItem(DonationListing d, bool favorited, VoidCallback onFav, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _DonationCard(donation: d, favorited: favorited, onFavorite: onFav, onTap: onTap),
    );
  }

  void _openDetail(DonationListing donation) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DonationDetail(donation: donation, onFavorite: () => _toggleFavorite(donation), onDonate: _markDonated)));
  }

  void _openSponsorDetail(DonationListing sponsorship) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SponsorshipDetail(sponsorship: sponsorship, onFavorite: () => _toggleFavorite(sponsorship))));
  }
}

class _DonationCard extends StatelessWidget {
  final DonationListing donation;
  final bool favorited;
  final VoidCallback onFavorite;
  final VoidCallback onTap;
  const _DonationCard({required this.donation, required this.favorited, required this.onFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final days = donation.daysRemaining;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 140, width: double.infinity,
                decoration: BoxDecoration(color: donation.backgroundColor, borderRadius: BorderRadius.circular(16)),
                child: donation.imageUrl != null ? ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.network(donation.imageUrl!, fit: BoxFit.cover)) : null,
              ),
              Positioned(
                top: 10, right: 12,
                child: IconButton(icon: Icon(favorited ? Icons.favorite : Icons.favorite_border, color: favorited ? const Color(0xFFE05C5C) : AppColors.textPrimary), onPressed: onFavorite),
              ),
              if (donation.isEnded)
                Positioned(
                  top: 10, left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
                    child: Text('Ended', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(donation.title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      RichText(text: TextSpan(children: [
                        TextSpan(text: '₱ ${NumberFormat('#,##0').format(donation.target)}  ', style: GoogleFonts.zain(fontSize: 16, color: AppColors.greenrspwn, fontWeight: FontWeight.w800)),
                        TextSpan(text: 'Funds: ₱ ${NumberFormat('#,##0').format(donation.collected)}  |  ', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
                        TextSpan(text: '$days days left!', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
                      ])),
                    ],
                  ),
                ),
                _PercentCircle(percent: donation.percentage),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PercentCircle extends StatelessWidget {
  final int percent;
  const _PercentCircle({required this.percent});
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44, height: 44,
      child: Stack(alignment: Alignment.center, children: [
        CircularProgressIndicator(value: percent / 100, strokeWidth: 4, backgroundColor: AppColors.textPrimary.withValues(alpha: 0.1), valueColor: const AlwaysStoppedAnimation<Color>(AppColors.yellowrspwn)),
        Text('$percent%', style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
    );
  }
}

class _SponsorPetCard extends StatelessWidget {
  final DonationListing sponsorship;
  final bool favorited;
  final bool isSponsored;
  final VoidCallback onFavorite;
  final VoidCallback onTap;
  const _SponsorPetCard({required this.sponsorship, required this.favorited, required this.isSponsored, required this.onFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.05))),
        child: Row(
          children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: sponsorship.backgroundColor, borderRadius: BorderRadius.circular(12)),
              child: Stack(
                children: [
                  sponsorship.imageUrl != null 
                      ? ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(sponsorship.imageUrl!, fit: BoxFit.cover, width: 56, height: 56)) 
                      : const Center(child: Icon(Icons.pets, size: 28, color: AppColors.textPrimary)),
                  if (sponsorship.isEnded)
                    Container(
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
                      alignment: Alignment.center,
                      child: Text('Ended', style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: Text(sponsorship.animalName ?? 'Rescue Pet', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                      if (isSponsored) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.greenrspwn.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text('Sponsored', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.greenrspwn)),
                        ),
                      ],
                    ],
                  ),
                  Text('Rescue Pet • Young', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  Text(sponsorship.description, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary.withValues(alpha: 0.7)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            IconButton(icon: Icon(favorited ? Icons.favorite : Icons.favorite_border, color: favorited ? const Color(0xFFE05C5C) : AppColors.textPrimary), onPressed: onFavorite),
          ],
        ),
      ),
    );
  }
}
