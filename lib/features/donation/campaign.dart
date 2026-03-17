import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'amount.dart';

final donationCampaignProvider = ChangeNotifierProvider.autoDispose.family<DonationCampaignNotifier, Fundraiser>((ref, fundraiser) {
  return DonationCampaignNotifier(fundraiser: fundraiser);
});

class DonationCampaignNotifier extends ChangeNotifier {
  final Fundraiser fundraiser;

  DonationCampaignNotifier({
    required this.fundraiser,
  });

  void toggleFavorite() {
    fundraiser.isFavorite = !fundraiser.isFavorite;
    notifyListeners();
  }
}

class DonationCampaignScreen extends ConsumerStatefulWidget {
  const DonationCampaignScreen({
    super.key,
    required this.fundraiser,
    required this.organizationName,
  });

  final Fundraiser fundraiser;
  final String organizationName;

  @override
  ConsumerState<DonationCampaignScreen> createState() => _DonationCampaignScreenState();
}

class _DonationCampaignScreenState extends ConsumerState<DonationCampaignScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final fundraiser = widget.fundraiser;
    final campaignNotifier = ref.watch(donationCampaignProvider(fundraiser));
    
    final double screenHeight = MediaQuery.of(context).size.height;
    final double statusBarHeight = MediaQuery.of(context).padding.top;
    const Color kPrimaryColor = Color(0xFFF9D142);
    const Color kProgressFilledColor = Color(0xFFB1B2DE);
    const Color kProgressEmptyColor = Color(0xFFE0E0E0);
    const Color kTextColor = Color(0xFF333333);
    const Color kSubtitleColor = Color(0xFF666666);
    const Color kIconColor = Color(0xFF333333);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: screenHeight * 0.6,
            child: _DonationImageCarousel(fundraiser.imageUrl),
          ),
          Positioned(
            top: statusBarHeight + 16,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      fundraiser.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: fundraiser.isFavorite ? Colors.red : Colors.white,
                    ),
                    onPressed: () {
                      campaignNotifier.toggleFavorite();
                    },
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            top: screenHeight * 0.5,
            left: 0,
            right: 0,
            bottom: 0,
            child: _DonationCampaignDetailsCard(
              fundraiser: fundraiser,
              organizationName: widget.organizationName,
              kPrimaryColor: kPrimaryColor,
              kProgressFilledColor: kProgressFilledColor,
              kProgressEmptyColor: kProgressEmptyColor,
              kTextColor: kTextColor,
              kSubtitleColor: kSubtitleColor,
              kIconColor: kIconColor,
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: kPrimaryColor,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black12,
              blurRadius: 10,
              offset: Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: kPrimaryColor,
          selectedItemColor: kTextColor,
          unselectedItemColor: kTextColor.withOpacity(0.6),
          currentIndex: _selectedIndex,
          onTap: _onItemTapped,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          items: <BottomNavigationBarItem>[
            BottomNavigationBarItem(
              icon: Icon(Icons.home, color: _selectedIndex == 0 ? kTextColor : kTextColor.withOpacity(0.6)),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.lightbulb_outline,
                  color: _selectedIndex == 1 ? kTextColor : kTextColor.withOpacity(0.6)),
              label: 'Notifications',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person, color: _selectedIndex == 2 ? kTextColor : kTextColor.withOpacity(0.6)),
              label: 'My Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationImageCarousel extends StatelessWidget {
  final String imageUrl;

  const _DonationImageCarousel(this.imageUrl);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? loadingProgress) {
        if (loadingProgress == null) return child;
        return Center(
          child: CircularProgressIndicator(
            value: loadingProgress.expectedTotalBytes != null
                ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                : null,
          ),
        );
      },
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Center(
        child: Icon(Icons.broken_image, size: 50, color: Colors.grey),
      ),
    );
  }
}

class _DonationCampaignDetailsCard extends StatelessWidget {
  final Fundraiser fundraiser;
  final String organizationName;
  final Color kPrimaryColor;
  final Color kProgressFilledColor;
  final Color kProgressEmptyColor;
  final Color kTextColor;
  final Color kSubtitleColor;
  final Color kIconColor;

  const _DonationCampaignDetailsCard({
    required this.fundraiser,
    required this.organizationName,
    required this.kPrimaryColor,
    required this.kProgressFilledColor,
    required this.kProgressEmptyColor,
    required this.kTextColor,
    required this.kSubtitleColor,
    required this.kIconColor,
  });

  @override
  Widget build(BuildContext context) {
    final double progress = fundraiser.targetAmount > 0 ? fundraiser.currentAmount / fundraiser.targetAmount : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Expanded(
                  child: Text(
                    fundraiser.name,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: kTextColor,
                      fontFamily: GoogleFonts.tiltWarp().fontFamily,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.share, color: kIconColor),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Active Campaign',
              style: TextStyle(
                fontSize: 12,
                color: kSubtitleColor,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              fundraiser.description,
              style: TextStyle(
                fontSize: 14,
                color: kSubtitleColor,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Expanded(
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: kProgressEmptyColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: progress.clamp(0.0, 1.0),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: kProgressFilledColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '₱${fundraiser.currentAmount.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kTextColor,
                    fontFamily: GoogleFonts.tiltWarp().fontFamily,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                _DonationStatItem(
                  label: 'Funds received',
                  value: '${(progress * 100).toStringAsFixed(0)}%',
                  valueColor: kTextColor,
                  labelColor: kSubtitleColor,
                ),
                _DonationStatItem(
                  label: 'Target funds',
                  value: '₱${fundraiser.targetAmount.toStringAsFixed(0)}',
                  valueColor: kTextColor,
                  labelColor: kSubtitleColor,
                ),
                _DonationStatItem(
                  label: 'Days left',
                  value: fundraiser.daysLeft.toString(),
                  valueColor: kTextColor,
                  labelColor: kSubtitleColor,
                ),
              ],
            ),
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => DonationAmountScreen(
                        organizationName: organizationName,
                        campaignName: fundraiser.name,
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
                  elevation: 5,
                ),
                child: Text(
                  'Donate',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: kTextColor,
                    fontFamily: GoogleFonts.tiltWarp().fontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DonationStatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color labelColor;

  const _DonationStatItem({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: valueColor,
            fontFamily: GoogleFonts.tiltWarp().fontFamily,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}
