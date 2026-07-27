import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/features/donation/donation_summary.dart';
import 'package:respawnd1/features/donation/donation_summary_inkind.dart';
import 'package:respawnd1/features/donation/sponsorship_summary.dart' as sponsorship;

enum CertificateCategory { adoption, rescue, donation, sponsorship, volunteer }

class CertificatesPage extends StatefulWidget {
  const CertificatesPage({super.key});

  @override
  State<CertificatesPage> createState() => _CertificatesPageState();
}

class _CertificatesPageState extends State<CertificatesPage> {
  CertificateCategory _selectedCategory = CertificateCategory.donation;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String get _searchHint {
    switch (_selectedCategory) {
      case CertificateCategory.donation:
        return 'Search by campaign name';
      case CertificateCategory.sponsorship:
      case CertificateCategory.adoption:
      case CertificateCategory.rescue:
        return 'Search by pet name';
      case CertificateCategory.volunteer:
        return 'Search by event name';
    }
  }

  final Map<String, Map<String, dynamic>> _campaignCache = {};

  Stream<List<HistoryItem>> _getCertificatesStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    return FirebaseFirestore.instance
        .collection('donations')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .asyncMap((snapshot) async {
      final List<HistoryItem> items = [];
      
      for (final doc in snapshot.docs) {
        final item = HistoryItem.fromFirestore(doc);
        
        // Category filtering
        if (_selectedCategory == CertificateCategory.donation) {
          if (!(item.type == HistoryType.donation || item.type == HistoryType.inKindDonation)) continue;
        } else if (_selectedCategory == CertificateCategory.sponsorship) {
          if (item.type != HistoryType.sponsorship) continue;
        } else {
          continue; // Adoption, Rescue, Volunteer not implemented yet
        }

        // Completion status check
        if (item.type == HistoryType.inKindDonation && item.status != InKindStatus.complete) {
          continue;
        }

        // Cross-reference campaign name and pet name from campaigns database
        HistoryItem enrichedItem = item;
        if (item.campaignId != null) {
          Map<String, dynamic>? campaignData;
          if (_campaignCache.containsKey(item.campaignId)) {
            campaignData = _campaignCache[item.campaignId];
          } else {
            final campaignDoc = await FirebaseFirestore.instance
                .collection('campaigns')
                .doc(item.campaignId)
                .get();
            if (campaignDoc.exists) {
              campaignData = campaignDoc.data();
              _campaignCache[item.campaignId!] = campaignData!;
            }
          }

          if (campaignData != null) {
            enrichedItem = item.copyWith(
              campaignName: campaignData['title'] ?? item.campaignName,
              pet: item.type == HistoryType.sponsorship 
                  ? SponsorPet(
                      id: campaignData['animalId'] ?? '',
                      name: campaignData['animalName'] ?? (item.pet?.name ?? 'Pet Name'),
                      breed: '', age: '', description: '', tags: []
                    ) 
                  : item.pet,
            );
          }
        }

        // Search filtering
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          bool matches = false;
          if (_selectedCategory == CertificateCategory.donation) {
            final campaign = enrichedItem.campaignName?.toLowerCase() ?? '';
            final organizer = enrichedItem.organizer.toLowerCase();
            matches = campaign.contains(query) || organizer.contains(query);
          } else if (_selectedCategory == CertificateCategory.sponsorship) {
            final petName = enrichedItem.pet?.name.toLowerCase() ?? '';
            matches = petName.contains(query);
          }
          if (!matches) continue;
        }

        items.add(enrichedItem);
      }
      
      // Sort by date descending
      items.sort((a, b) => b.dateTime.compareTo(a.dateTime));
      return items;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
          } else if (index == 2) {
             Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const UserProfile()),
            );
          }
        },
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 30),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        'Certificates',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => setState(() => _searchQuery = val),
                decoration: InputDecoration(
                  hintText: _searchHint,
                  hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 16),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.yellowrspwn.withOpacity(0.8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                ),
              ),
            ),
            const SizedBox(height: 15),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _CategoryChip(
                    label: 'Adoption',
                    isSelected: _selectedCategory == CertificateCategory.adoption,
                    onTap: () => setState(() => _selectedCategory = CertificateCategory.adoption),
                  ),
                  _CategoryChip(
                    label: 'Rescue',
                    isSelected: _selectedCategory == CertificateCategory.rescue,
                    onTap: () => setState(() => _selectedCategory = CertificateCategory.rescue),
                  ),
                  _CategoryChip(
                    label: 'Donations',
                    isSelected: _selectedCategory == CertificateCategory.donation,
                    onTap: () => setState(() => _selectedCategory = CertificateCategory.donation),
                  ),
                  _CategoryChip(
                    label: 'Sponsorships',
                    isSelected: _selectedCategory == CertificateCategory.sponsorship,
                    onTap: () => setState(() => _selectedCategory = CertificateCategory.sponsorship),
                  ),
                  _CategoryChip(
                    label: 'Volunteers',
                    isSelected: _selectedCategory == CertificateCategory.volunteer,
                    onTap: () => setState(() => _selectedCategory = CertificateCategory.volunteer),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: StreamBuilder<List<HistoryItem>>(
                stream: _getCertificatesStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Failed to load certificates', style: GoogleFonts.zain()));
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    String message = 'No completed contributions found.';
                    if (_selectedCategory == CertificateCategory.adoption ||
                        _selectedCategory == CertificateCategory.rescue ||
                        _selectedCategory == CertificateCategory.volunteer) {
                      message = 'Place Holder ${_selectedCategory.name}.';
                    }
                    return Center(
                      child: Text(
                        message,
                        style: GoogleFonts.zain(fontSize: 18, color: AppColors.textSecondary),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 15),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _CertificateCard(item: item);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: GoogleFonts.zain(
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.black : AppColors.textSecondary,
        )),
        selected: isSelected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.yellowrspwn,
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: isSelected ? AppColors.yellowrspwn : Colors.grey.shade300),
        ),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final HistoryItem item;

  const _CertificateCard({required this.item});

  String get _typeLabel {
    switch (item.type) {
      case HistoryType.donation:
        return 'Donation';
      case HistoryType.inKindDonation:
        return 'In-Kind Donation';
      case HistoryType.sponsorship:
        return 'Sponsorship';
    }
  }

  String get _displayTitle {
    if (item.type == HistoryType.sponsorship) {
      final name = item.pet?.name;
      return (name != null && name.isNotEmpty && name != 'Pet Name') ? name : 'Sponsored Pet';
    } else {
      final name = item.campaignName ?? item.organizer;
      if (name.isEmpty || name == 'Rescue Shelter') {
        return 'General Donation';
      }
      return name;
    }
  }

  void _onTap(BuildContext context) {
    if (item.type == HistoryType.inKindDonation) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => InKindDonationSummaryScreen(
            params: InKindDonationSummaryParams(
              charityName: item.organizer,
              category: item.category ?? 'General',
              clarification: item.clarification ?? 'No additional details',
              isAnonymous: item.isAnonymous ?? false,
              referenceNumber: item.refNumber,
              timestamp: item.dateTime,
              address: item.address ?? 'Rescue Center',
              status: item.status,
            ),
          ),
        ),
      );
    } else if (item.type == HistoryType.sponsorship) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => sponsorship.DonationSummaryScreen(
            params: sponsorship.DonationSummaryParams(
              charityName: item.organizer,
              donationMethod: item.donationMethod ?? 'GCash',
              item: DonationItem(
                description: item.itemDescription ?? 'Sponsorship',
                amount: item.amount ?? 0.0,
              ),
              referenceNumber: item.refNumber,
              timestamp: item.dateTime,
              historyItem: item,
            ),
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DonationSummaryScreen(
            params: DonationSummaryParams(
              charityName: item.organizer,
              donationMethod: item.donationMethod ?? 'GCash',
              item: DonationItem(
                description: item.itemDescription ?? 'Donation',
                amount: item.amount ?? 0.0,
              ),
              referenceNumber: item.refNumber,
              timestamp: item.dateTime,
              historyItem: item,
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MM/dd/yyyy \'at\' HH:mm:ss');
    
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateFormat.format(item.dateTime),
              style: GoogleFonts.zain(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _typeLabel,
              style: GoogleFonts.tiltWarp(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            Text(
              _displayTitle,
              style: GoogleFonts.zain(
                fontSize: 20,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
