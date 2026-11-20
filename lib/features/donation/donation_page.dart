import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'donation_detail.dart';
import 'sponsorship_detail.dart';
import 'models.dart';
import 'package:intl/intl.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart' show kPurposeTags;

// Category chips — the same purpose tags staff pick when creating a
// campaign (kPurposeTags), so a chip actually filters campaigns.
const _categories = ['All', ...kPurposeTags];

class DonationPage extends StatefulWidget {
  const DonationPage({super.key});

  @override
  State<DonationPage> createState() => _DonationPageState();
}

class _DonationPageState extends State<DonationPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  Set<String> _donatedIds = {};
  Set<String> _favoriteIds = {};
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
        FirebaseFirestore.instance.collection('donations')
            .where('userId', isEqualTo: _uid)
            .where('type', isEqualTo: 'sponsorship')
            .get(),
      ]);

      if (mounted) {
        final sponsorships = results[2].docs.map((doc) => HistoryItem.fromFirestore(doc)).toList();
        final Map<String, HistoryItem> activeMap = {};
        final now = DateTime.now();

        for (var s in sponsorships) {
          // A sponsorship is active if it's "active" OR if it's "inactive" but before next charge date
          final isActiveStatus = s.sponsorshipStatus == 'active';
          // A refunded sponsorship (refund request flow) never counts.
          final isStillValid = s.sponsorshipStatus != 'refunded' &&
              (isActiveStatus || (s.nextChargeDate != null && s.nextChargeDate!.isAfter(now)));

          if (isStillValid && s.campaignId != null) {
            activeMap[s.campaignId!] = s;
          }
        }

        setState(() {
          _donatedIds = results[0].docs.map((d) => d.id).toSet();
          _favoriteIds = results[1].docs.map((d) => d.id).toSet();
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
          'Donations & Sponsorships',
          style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary),
        ),
      ),
      body: _userDataLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fund rescues, treatment and care, or sponsor an animal monthly.',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            _buildSearchBar(),
            const SizedBox(height: 20),
            const _SectionHeader(
              title: 'Campaigns',
              subtitle: 'Open fundraisers from rescue organizations.',
            ),
            const SizedBox(height: 10),
            _buildCategoryChips(),
            const SizedBox(height: 12),
            _buildDonationList(),
            const SizedBox(height: 12),
            const _SectionHeader(
              title: 'Sponsor a Pet',
              subtitle: "Cover one animal's care every month.",
            ),
            const SizedBox(height: 10),
            _buildSponsorshipList(),
            const SizedBox(height: 20),
            const _SectionHeader(
              title: 'Past Campaigns',
              subtitle: 'Finished campaigns stay here so you can see where the funds went.',
            ),
            const SizedBox(height: 10),
            _buildPastList(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.12)),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search campaigns, pets or organizations',
          hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
          prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary, size: 20),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final cat = _categories[i];
          final selected = _selectedCategory == cat;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.yellowrspwn.withValues(alpha: 0.35) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? AppColors.textPrimary : AppColors.textPrimary.withValues(alpha: 0.15),
                ),
              ),
              child: Text(
                cat,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _inSelectedCategory(DonationListing d) =>
      _selectedCategory == 'All' || d.purposeTags.contains(_selectedCategory);

  Widget _buildDonationList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('campaigns').where('type', isEqualTo: 'donation').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const _EmptyCard('No open campaigns right now.');

        final donations = snapshot.data!.docs.map((doc) => DonationListing.fromFirestore(doc)).where((d) {
          // Only campaigns still taking donations; finished ones (goal
          // reached, deadline passed, closed) are under Past Campaigns, and
          // drafts / archived listings are never shown.
          if (d.isEnded) return false;
          final q = _searchQuery.toLowerCase();
          final matchesSearch = q.isEmpty || d.title.toLowerCase().contains(q) || d.organizer.toLowerCase().contains(q);

          return matchesSearch && _inSelectedCategory(d);
        }).toList();

        final donatedList = donations.where((d) => _donatedIds.contains(d.id)).toList();
        final activeDonations = donations.where((d) => !_donatedIds.contains(d.id)).toList();

        if (donations.isEmpty) {
          return const _EmptyCard('No campaigns match your search or category.');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (donatedList.isNotEmpty) ...[
              Text('You donated',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              ...donatedList.map((d) => _donationListItem(d, _favoriteIds.contains(d.id), () => _toggleFavorite(d), () => _openDetail(d))),
            ],
            if (activeDonations.isNotEmpty)
              ...activeDonations.map((d) => _donationListItem(d, _favoriteIds.contains(d.id), () => _toggleFavorite(d), () => _openDetail(d))),
          ],
        );
      },
    );
  }

  /// Finished donation campaigns and sponsorships (not drafts, not archived):
  /// title + arrow only, opening the usual detail page with its Fund Tracking.
  Widget _buildPastList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('campaigns').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        final q = _searchQuery.toLowerCase();
        final past = (snapshot.data?.docs ?? const [])
            .map((doc) => DonationListing.fromFirestore(doc))
            .where((c) => c.isPast)
            .where((c) =>
        q.isEmpty ||
            c.title.toLowerCase().contains(q) ||
            (c.animalName?.toLowerCase().contains(q) ?? false) ||
            c.organizer.toLowerCase().contains(q))
            .toList()
          ..sort((a, b) => (b.endDate ?? b.createdAt ?? DateTime(0)).compareTo(a.endDate ?? a.createdAt ?? DateTime(0)));
        if (past.isEmpty) {
          return const _EmptyCard('No past campaigns yet.');
        }
        return Column(
          children: [
            for (final c in past)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _CardShell(
                  onTap: () => c.type == 'sponsorship' ? _openSponsorDetail(c) : _openDetail(c),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Icon(c.type == 'sponsorship' ? Icons.pets : Icons.volunteer_activism,
                          size: 20, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          c.type == 'sponsorship' ? (c.animalName ?? c.title) : c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                      ),
                      if (_donatedIds.contains(c.id) || _activeSponsorships.containsKey(c.id))
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text('Donated',
                              style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.greenrspwn)),
                        ),
                      const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                    ],
                  ),
                ),
              ),
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
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const _EmptyCard('No pets to sponsor right now.');

        final campaigns = snapshot.data!.docs.map((doc) => DonationListing.fromFirestore(doc)).where((c) {
          if (c.isEnded) return false; // drafts, archived and finished listings
          final q = _searchQuery.toLowerCase();
          return q.isEmpty || (c.animalName?.toLowerCase().contains(q) ?? false) || c.organizer.toLowerCase().contains(q);
        }).toList();
        if (campaigns.isEmpty) return const _EmptyCard('No pets match your search.');

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

  Widget _donationListItem(DonationListing d, bool favorited, VoidCallback onFav, VoidCallback onTap) {
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

/// White card with a subtle border — the one card style on this page.
class _CardShell extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  const _CardShell({required this.child, this.onTap, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1)),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(subtitle, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;
  const _EmptyCard(this.text);

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      child: Center(
        child: Text(text,
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  final bool favorited;
  final VoidCallback onPressed;
  const _FavoriteButton({required this.favorited, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: favorited ? 'Remove from favorites' : 'Save to favorites',
        icon: Icon(favorited ? Icons.favorite : Icons.favorite_border,
            size: 20, color: favorited ? AppColors.error : AppColors.textPrimary),
        onPressed: onPressed,
      ),
    );
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
    final money = NumberFormat('#,##0');
    return _CardShell(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  color: donation.backgroundColor,
                  child: donation.imageUrl != null
                      ? Image.network(donation.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.volunteer_activism, color: AppColors.textSecondary))
                      : const Icon(Icons.volunteer_activism, size: 36, color: AppColors.textSecondary),
                ),
              ),
              Positioned(top: 8, right: 8, child: _FavoriteButton(favorited: favorited, onPressed: onFavorite)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(donation.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                if (donation.organizer.isNotEmpty)
                  Text(donation.organizer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (donation.percentage / 100).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    backgroundColor: AppColors.textPrimary.withValues(alpha: 0.08),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.yellowrspwn),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(
                              text: '₱${money.format(donation.collected)}',
                              style: GoogleFonts.zain(
                                  fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.greenrspwn)),
                          TextSpan(
                              text: ' raised of ₱${money.format(donation.target)}',
                              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                        ]),
                      ),
                    ),
                    Text(
                      '${donation.percentage}% · ${days <= 0 ? 'Last day' : '$days days left'}',
                      style: GoogleFonts.zain(
                          fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
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
    final monthly = sponsorship.monthlyAmount;
    return _CardShell(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 64,
              height: 64,
              color: sponsorship.backgroundColor,
              child: sponsorship.imageUrl != null
                  ? Image.network(sponsorship.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.pets, color: AppColors.textPrimary))
                  : const Icon(Icons.pets, size: 28, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(sponsorship.animalName ?? 'Rescue Pet',
                          style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (isSponsored) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.greenrspwn.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text('Sponsored',
                            style: GoogleFonts.zain(
                                fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.greenrspwn)),
                      ),
                    ],
                  ],
                ),
                if (sponsorship.organizer.isNotEmpty)
                  Text(sponsorship.organizer,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                if (sponsorship.description.isNotEmpty)
                  Text(sponsorship.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary.withValues(alpha: 0.75))),
                if (monthly != null && monthly > 0)
                  Text('₱${NumberFormat('#,##0').format(monthly)} / month',
                      style: GoogleFonts.zain(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.greenrspwn)),
              ],
            ),
          ),
          IconButton(
            tooltip: favorited ? 'Remove from favorites' : 'Save to favorites',
            icon: Icon(favorited ? Icons.favorite : Icons.favorite_border,
                color: favorited ? AppColors.error : AppColors.textPrimary),
            onPressed: onFavorite,
          ),
        ],
      ),
    );
  }
}
