import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'donation_detail.dart';
import 'package:intl/intl.dart';



//Data Model

class DonationListing {
  final int id;
  final String title;
  final int target;
  final int collected;
  final int percentage;
  final int dateleft;
  final String organizer;
  final String date;
  final String time;
  final String description;
  final int numdonated;
  bool favorited;
  bool donated;

  DonationListing({
    required this.id,
    required this.title,
    required this.target,
    required this.collected,
    required this.percentage,
    required this.dateleft,
    required this.organizer,
    required this.date,
    required this.time,
    required this.description,
    required this.numdonated,
    this.favorited = false,
    this.donated = false,
  });
}

// Sample sponsorship pet model
class SponsorPet {
  final int id;
  final String name;
  final String breed;
  final int age;
  final String description;
  final List<String> tags;
  bool favorited;

  SponsorPet({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    required this.description,
    required this.tags,
    this.favorited = false,
  });
}

// Static Data

final List<DonationListing> _allDonations = [
  DonationListing(
    id: 1,
    title: 'Help Mickey battle Parvovirus!',
    target: 5000,
    collected: 2000,
    percentage: 40,
    dateleft: 10,
    organizer: 'Loved by the Gapz',
    date: 'Saturday, March 21, 2026',
    time: '9:00 AM - 10:30 AM',
    description:
    'Join our Volunteer Stray Dog Walking Event and help give rescued dogs '
        'the care, exercise, and attention they need. Spend time walking and '
        'bonding with friendly dogs while supporting local animal welfare efforts. '
        'No experience needed—just bring comfortable clothes and a love for dogs!',
    numdonated: 15,
  ),
  DonationListing(
    id: 2,
    title: 'Help Lola walk again!',
    target: 10000,
    collected: 2000,
    percentage: 20,
    dateleft: 1,
    organizer: 'Loved by the Gapz',
    date: 'Saturday, March 21, 2026',
    time: '9:00 AM - 10:30 AM',
    description:
    'Join our Volunteer Stray Dog Walking Event and help give rescued dogs '
        'the care, exercise, and attention they need. Spend time walking and '
        'bonding with friendly dogs while supporting local animal welfare efforts. '
        'No experience needed—just bring comfortable clothes and a love for dogs!',
    numdonated: 15,
  ),
];

final List<SponsorPet> _allSponsorPets = [
  SponsorPet(
    id: 1,
    name: 'Winnie',
    breed: 'Aspin',
    age: 3,
    description: 'Playful white dog',
    tags: ['Vaccinated'],
  ),
  SponsorPet(
    id: 2,
    name: 'Kiko',
    breed: 'Puspin',
    age: 2,
    description: 'Friendly orange tabby',
    tags: ['Neutered', 'Vaccinated'],
  ),
];

// Categories

const _categories = ['All', 'Rescue', 'Medicine & Treatment', 'Food & Supplies', 'Shelter'];

// Donation Page

class DonationPage extends StatefulWidget {
  const DonationPage({super.key});

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';
  late List<DonationListing> _donations;
  late List<SponsorPet> _sponsorPets;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _donations = _allDonations
        .map((e) => DonationListing(
      id: e.id,
      title: e.title,
      target: e.target,
      collected: e.collected,
      percentage: e.percentage,
      dateleft: e.dateleft,
      organizer: e.organizer,
      date: e.date,
      time: e.time,
      description: e.description,
      numdonated: e.numdonated,
    ))
        .toList();
    _sponsorPets = List.from(_allSponsorPets);
    _loadFromFirestore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Firestore refs
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _donatedRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('donated');

  CollectionReference<Map<String, dynamic>> get _favoritesRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('donationFavorites');

  CollectionReference<Map<String, dynamic>> _globalDonatedRef(int donationId) =>
      FirebaseFirestore.instance
          .collection('donations')
          .doc(donationId.toString())
          .collection('donors');

  // Load from Firestore
  Future<void> _loadFromFirestore() async {
    try {
      final results = await Future.wait([
        _donatedRef.get(),
        _favoritesRef.get(),
      ]);

      final donatedIds = results[0].docs.map((d) => int.parse(d.id)).toSet();
      final favIds = results[1].docs.map((d) => int.parse(d.id)).toSet();

      if (mounted) {
        setState(() {
          for (final d in _donations) {
            d.donated = donatedIds.contains(d.id);
            d.favorited = favIds.contains(d.id);
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Mark donated
  Future<void> _markDonated({
    required DonationListing donation,
    required double amount,
    required String paymentMethod,
    required bool isAnonymous,
  }) async {
    final now = FieldValue.serverTimestamp();
    final uid = _uid;

    await _donatedRef.doc(donation.id.toString()).set({
      'donationId': donation.id,
      'title': donation.title,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'isAnonymous': isAnonymous,
      'donatedAt': now,
    });

    await _globalDonatedRef(donation.id).doc(uid).set({
      'uid': uid,
      'donationId': donation.id,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'isAnonymous': isAnonymous,
      'donatedAt': now,
    });

    if (mounted) setState(() => donation.donated = true);
  }

  // Favorite toggle
  Future<void> _toggleFavorite(DonationListing donation) async {
    final newVal = !donation.favorited;
    setState(() => donation.favorited = newVal);

    final doc = _favoritesRef.doc(donation.id.toString());
    if (newVal) {
      await doc.set({
        'donationId': donation.id,
        'title': donation.title,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.delete();
    }
  }

  // Sponsor pet favorite toggle
  void _toggleSponsorFavorite(SponsorPet pet) {
    setState(() => pet.favorited = !pet.favorited);
  }

  // Filtered donations
  List<DonationListing> get _filteredDonations => _donations.where((d) {
    final q = _searchQuery.toLowerCase();
    final matchesSearch = q.isEmpty ||
        d.title.toLowerCase().contains(q) ||
        d.organizer.toLowerCase().contains(q);
    // Category filtering — extend as needed
    return matchesSearch;
  }).toList();

  List<DonationListing> get _donatedList =>
      _filteredDonations.where((d) => d.donated).toList();

  List<DonationListing> get _activeDonations =>
      _filteredDonations.where((d) => !d.donated).toList();

  // Build
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
          }
          else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserProfile()),
            );
          }
        },
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Search bar
            Row(
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
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.zain(
                          fontSize: 15, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: GoogleFonts.zain(
                            fontSize: 15,
                            color: AppColors.textPrimary.withValues(alpha: 0.6)),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textPrimary, size: 20),
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
                  alignment: Alignment.center,
                  child: const Icon(Icons.tune,
                      color: AppColors.textPrimary, size: 20),
                ),
              ],
            ),

            const SizedBox(height: 16),

            //Section label + category tabs
            Text('Donations',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            // Category chips
            SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final cat = _categories[i];
                  final selected = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          cat,
                          style: GoogleFonts.zain(
                            fontSize: 15,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (selected)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            height: 2,
                            width: 24,
                            color: AppColors.textPrimary,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            //Donated list (if any)
            if (_donatedList.isNotEmpty) ...[
              Text('Donated',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              ..._donatedList.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DonationCard(
                  donation: d,
                  onFavorite: () => _toggleFavorite(d),
                  onTap: () => _openDetail(d),
                ),
              )),
              const SizedBox(height: 8),
            ],

            // Active donations
            if (_activeDonations.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('No donations found.',
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textSecondary)),
                ),
              )
            else
              ..._activeDonations.map((d) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _DonationCard(
                  donation: d,
                  onFavorite: () => _toggleFavorite(d),
                  onTap: () => _openDetail(d),
                ),
              )),

            const SizedBox(height: 8),

            // Sponsorship section
            Text('Sponsorship',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            ..._sponsorPets.map((pet) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SponsorPetCard(
                pet: pet,
                onFavorite: () => _toggleSponsorFavorite(pet),
              ),
            )),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _openDetail(DonationListing donation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DonationDetail(
          donation: donation,
          onFavorite: () => _toggleFavorite(donation),
          onDonate: _markDonated,
        ),
      ),
    ).then((_) => setState(() {}));
  }
}

// Donation Card

class _DonationCard extends StatelessWidget {
  final DonationListing donation;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const _DonationCard({
    required this.donation,
    required this.onFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool urgent = donation.dateleft <= 1;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image area
          Stack(
            children: [
              Container(
                height: 140,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.tearspwn,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Positioned(
                top: 10,
                right: 12,
                child: GestureDetector(
                  onTap: onFavorite,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    donation.favorited ? Icons.favorite : Icons.favorite_border,
                    size: 22,
                    color: donation.favorited
                        ? const Color(0xFFE05C5C)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          // Info row
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        donation.title,
                        style: GoogleFonts.tiltWarp(
                            fontSize: 16, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '₱ ${_fmt(donation.target)}  ',
                              style: GoogleFonts.zain(
                                  fontSize: 16,
                                  color: AppColors.greenrspwn,
                                  fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text:
                              'Funds collected: ₱ ${_fmt(donation.collected)}  |  ',
                              style: GoogleFonts.zain(
                                  fontSize: 16,
                                  color: AppColors.textPrimary),
                            ),
                            TextSpan(
                              text: urgent
                                  ? '30 days left!'
                                  : '${donation.dateleft} days left!',
                              style: GoogleFonts.zain(
                                  fontSize: 16,
                                  color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Percentage circle
                _PercentCircle(percent: donation.percentage),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(num value) {
    return NumberFormat('#,##0').format(value);
  }
}

// Percent Circle

class _PercentCircle extends StatelessWidget {
  final int percent;
  const _PercentCircle({required this.percent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent / 100,
            strokeWidth: 4,
            backgroundColor: AppColors.textPrimary,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.yellowrspwn),
          ),
          Text(
            '$percent%',
            style: GoogleFonts.zain(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// Sponsor Pet Card

class _SponsorPetCard extends StatelessWidget {
  final SponsorPet pet;
  final VoidCallback onFavorite;

  const _SponsorPetCard({required this.pet, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
      ),
      child: Row(
        children: [
          // Pet avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.tearspwn,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.pets, size: 28, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pet.name,
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16, color: AppColors.textPrimary)),
                Text(pet.breed,
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary)),
                Text('${pet.age} year old',
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary)),
                Text(pet.description,
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: pet.tags
                      .map((tag) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.yellowrspwn.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(tag,
                        style: GoogleFonts.zain(
                            fontSize: 10,
                            color: AppColors.textPrimary)),
                  ))
                      .toList(),
                ),
              ],
            ),
          ),

          // Favorite
          GestureDetector(
            onTap: onFavorite,
            child: Icon(
              pet.favorited ? Icons.favorite : Icons.favorite_border,
              size: 22,
              color: pet.favorited
                  ? const Color(0xFFE05C5C)
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}