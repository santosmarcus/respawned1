import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

class FirebaseMockService {
  final List<Organization> _mockOrganizations = <Organization>[
    Organization(
      id: '1',
      name: 'Org 1',
      location: 'Place, Region',
      website: 'https://one.org/',
      isFavorite: true,
    ),
    Organization(
      id: '2',
      name: 'Org 2',
      location: 'Place, Region',
      website: 'https://two.com/',
      isFavorite: false,
      hasSpotify: false,
    ),
    Organization(
      id: '3',
      name: 'Org 3',
      location: 'Place, Region',
      website: 'https://three.ph/',
      isFavorite: false,
      hasFacebook: false,
      hasInstagram: false,
      hasSpotify: false,
    ),
    Organization(
      id: '4',
      name: 'Org 4',
      location: 'Place, Region',
      website: 'https://four.org/',
      isFavorite: true,
      hasEmail: false,
    ),
    Organization(
      id: '5',
      name: 'Org 5',
      location: 'Place, Region',
      website: 'https://five.net/',
      isFavorite: false,
      hasFacebook: false,
    ),
  ];
  Future<List<Organization>> fetchOrganizations() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return _mockOrganizations;
  }
}

enum BasicFilters { topRated, nearMe, favorites }

class Organization {
  final String id;
  final String name;
  final String location;
  final String website;
  final String imageUrl;
  final bool hasFacebook;
  final bool hasInstagram;
  final bool hasSpotify;
  final bool hasEmail;
  bool isFavorite;

  Organization({
    required this.id,
    required this.name,
    required this.location,
    required this.website,
    this.imageUrl =
        'https://www.gstatic.com/flutter-onestack-prototype/genui/example_1.jpg',
    this.hasFacebook = true,
    this.hasInstagram = true,
    this.hasSpotify = true,
    this.hasEmail = true,
    this.isFavorite = false,
  });

  Organization copyWith({bool? isFavorite}) {
    return Organization(
      id: id,
      name: name,
      location: location,
      website: website,
      imageUrl: imageUrl,
      hasFacebook: hasFacebook,
      hasInstagram: hasInstagram,
      hasSpotify: hasSpotify,
      hasEmail: hasEmail,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class DonationData extends ChangeNotifier {
  BasicFilters _selectedCategory = BasicFilters.topRated;
  int _bottomNavIndex = 0;
  List<Organization> _organizations = <Organization>[];
  bool _isLoading = true;

  DonationData() {
    _loadOrganizations();
  }

  BasicFilters get selectedCategory => _selectedCategory;
  int get bottomNavIndex => _bottomNavIndex;
  List<Organization> get organizations => _organizations;
  bool get isLoading => _isLoading;
  Future<void> _loadOrganizations() async {
    _isLoading = true;
    notifyListeners();

    try {
      _organizations = await FirebaseMockService().fetchOrganizations();
    } catch (e) {
      // Placeholder for error logging
      _organizations = <Organization>[];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setSelectedCategory(BasicFilters category) {
    if (_selectedCategory != category) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  void setBottomNavIndex(int index) {
    if (_bottomNavIndex != index) {
      _bottomNavIndex = index;
      notifyListeners();
    }
  }

  void toggleFavorite(String organizationId) {
    _organizations = _organizations.map<Organization>((Organization org) {
      if (org.id == organizationId) {
        return org.copyWith(isFavorite: !org.isFavorite);
      }
      return org;
    }).toList();
    notifyListeners();
  }
}

class DonationScreen extends StatelessWidget {
  const DonationScreen({super.key});

  static const Color _primaryBackgroundColor = Color(0xFFF5F0E1);
  static const Color _darkTextColor = Color(0xFF5D4037);
  static const Color _searchBarColor = Color(0xFFFFECB3);
  static const Color _buttonActiveColor = Color(0xFFAED581);
  static const Color _buttonNearMeColor = Color(0xFFC5CAE9);
  static const Color _buttonFavoritesColor = Color(0xFFF8BBD0);
  static const Color _cardBackgroundColor = Color(0xFF9CCC65);
  static const Color _cardImagePlaceholderColor = Color(0xFFDCE775);
  static const Color _bottomNavBarColor = Color(0xFFFFD54F);

  @override
  Widget build(BuildContext context) {
    final DonationData donationData = context.watch<DonationData>();
    final BasicFilters selectedCategory = donationData.selectedCategory;
    final int bottomNavIndex = donationData.bottomNavIndex;
    final bool isLoading = donationData.isLoading;
    final List<Organization> displayedOrganizations =
        donationData.organizations.where((Organization org) {
      if (selectedCategory == BasicFilters.favorites) {
        return org.isFavorite;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: _primaryBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Text(
                  'Donate/Sponsor',
                  style: GoogleFonts.tiltWarp(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _darkTextColor,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: _searchBarColor,
                        borderRadius: BorderRadius.circular(15.0),
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search',
                          hintStyle: GoogleFonts.zain(color: _darkTextColor),
                          border: InputBorder.none,
                          prefixIcon:
                              const Icon(Icons.search, color: _darkTextColor),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12.0),
                        ),
                        style: GoogleFonts.zain(color: _darkTextColor),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _searchBarColor,
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child: const Icon(Icons.filter_list, color: _darkTextColor),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: <Widget>[
                  _CategoryButton(
                    text: 'Top Rated',
                    category: BasicFilters.topRated,
                    isSelected: selectedCategory == BasicFilters.topRated,
                    selectedColor: _buttonActiveColor,
                    onSelected: (BasicFilters category) =>
                        donationData.setSelectedCategory(category),
                    darkTextColor: _darkTextColor,
                  ),
                  _CategoryButton(
                    text: 'Near Me',
                    category: BasicFilters.nearMe,
                    isSelected: selectedCategory == BasicFilters.nearMe,
                    selectedColor: _buttonNearMeColor,
                    onSelected: (BasicFilters category) =>
                        donationData.setSelectedCategory(category),
                    darkTextColor: _darkTextColor,
                  ),
                  _CategoryButton(
                    text: 'Favorites',
                    category: BasicFilters.favorites,
                    isSelected: selectedCategory == BasicFilters.favorites,
                    selectedColor: _buttonFavoritesColor,
                    onSelected: (BasicFilters category) =>
                        donationData.setSelectedCategory(category),
                    darkTextColor: _darkTextColor,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              isLoading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 40.0),
                        child: CircularProgressIndicator(
                          color: _darkTextColor,
                        ),
                      ),
                    )
                  : Column(
                      children: displayedOrganizations
                          .map<Widget>((Organization organization) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: OrganizationCard(
                            organization: organization,
                            onToggleFavorite: (String orgId) =>
                                donationData.toggleFavorite(orgId),
                            cardBackgroundColor: _cardBackgroundColor,
                            cardImagePlaceholderColor:
                                _cardImagePlaceholderColor,
                            darkTextColor: _darkTextColor,
                          ),
                        );
                      }).toList(),
                    ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: bottomNavIndex,
        onTap: (int index) => donationData.setBottomNavIndex(index),
        backgroundColor: _bottomNavBarColor,
        selectedItemColor: _darkTextColor,
        unselectedItemColor: _darkTextColor.withOpacity(0.6),
        selectedLabelStyle: GoogleFonts.tiltWarp(fontWeight: FontWeight.bold),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'My Profile',
          ),
        ],
      ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.text,
    required this.category,
    required this.isSelected,
    required this.selectedColor,
    required this.onSelected,
    required this.darkTextColor,
  });

  final String text;
  final BasicFilters category;
  final bool isSelected;
  final Color selectedColor;
  final ValueChanged<BasicFilters> onSelected;
  final Color darkTextColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelected(category),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5.0),
          padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 10.0),
          decoration: BoxDecoration(
            color: isSelected ? selectedColor : selectedColor.withOpacity(0.4),
            borderRadius: BorderRadius.circular(15.0),
            boxShadow: <BoxShadow>[
              if (isSelected)
                BoxShadow(
                  color: selectedColor.withOpacity(0.5),
                  spreadRadius: 1,
                  blurRadius: 5,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: isSelected
                ? GoogleFonts.tiltWarp(
                    color: darkTextColor,
                    fontWeight: FontWeight.bold,
                  )
                : GoogleFonts.zain(
                    color: darkTextColor,
                    fontWeight: FontWeight.normal,
                  ),
          ),
        ),
      ),
    );
  }
}

class OrganizationCard extends StatelessWidget {
  const OrganizationCard({
    required this.organization,
    required this.onToggleFavorite,
    required this.cardBackgroundColor,
    required this.cardImagePlaceholderColor,
    required this.darkTextColor,
    super.key,
  });

  final Organization organization;
  final ValueChanged<String> onToggleFavorite;
  final Color cardBackgroundColor;
  final Color cardImagePlaceholderColor;
  final Color darkTextColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(20.0),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 100,
            height: 100,
            margin: const EdgeInsets.all(15.0),
            decoration: BoxDecoration(
              color: cardImagePlaceholderColor,
              borderRadius: BorderRadius.circular(15.0),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.0),
              child: Image.network(
                organization.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (BuildContext context, Object error,
                    StackTrace? stackTrace) {
                  return const Center(
                    child: Icon(Icons.image_not_supported, color: Colors.grey),
                  );
                },
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 15.0, horizontal: 15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          organization.name,
                          style: GoogleFonts.tiltWarp(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: darkTextColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => onToggleFavorite(organization.id),
                        child: Icon(
                          organization.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: Colors.redAccent,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    organization.location,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: darkTextColor.withOpacity(0.8),
                    ),
                  ),
                  Text(
                    organization.website,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: darkTextColor.withOpacity(0.8),
                      decoration: TextDecoration.underline,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      if (organization.hasFacebook)
                        Icon(Icons.facebook, color: darkTextColor, size: 24),
                      if (organization.hasFacebook) const SizedBox(width: 8),
                      if (organization.hasInstagram)
                        Icon(Icons.camera_alt,
                            color: darkTextColor,
                            size: 24),
                      if (organization.hasInstagram) const SizedBox(width: 8),
                      if (organization.hasSpotify)
                        Icon(Icons.music_note, color: darkTextColor, size: 24),
                      if (organization.hasSpotify) const SizedBox(width: 8),
                      if (organization.hasEmail)
                        Icon(Icons.email, color: darkTextColor, size: 24),
                    ],
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Donation',
      theme: ThemeData(
        primarySwatch: Colors.brown,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        textTheme: GoogleFonts.zainTextTheme().copyWith(
          displayLarge:
              GoogleFonts.tiltWarp(fontSize: 57, fontWeight: FontWeight.bold),
          displayMedium:
              GoogleFonts.tiltWarp(fontSize: 45, fontWeight: FontWeight.bold),
          displaySmall:
              GoogleFonts.tiltWarp(fontSize: 36, fontWeight: FontWeight.bold),
          headlineLarge:
              GoogleFonts.tiltWarp(fontSize: 32, fontWeight: FontWeight.bold),
          headlineMedium:
              GoogleFonts.tiltWarp(fontSize: 28, fontWeight: FontWeight.bold),
          headlineSmall:
              GoogleFonts.tiltWarp(fontSize: 24, fontWeight: FontWeight.bold),
          titleLarge:
              GoogleFonts.tiltWarp(fontSize: 22, fontWeight: FontWeight.bold),
          titleMedium:
              GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold),
          titleSmall:
              GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold),
          labelLarge:
              GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold),
          labelMedium:
              GoogleFonts.tiltWarp(fontSize: 12, fontWeight: FontWeight.bold),
          labelSmall:
              GoogleFonts.tiltWarp(fontSize: 11, fontWeight: FontWeight.bold),
          bodyLarge: GoogleFonts.zain(fontSize: 16),
          bodyMedium: GoogleFonts.zain(fontSize: 14),
          bodySmall: GoogleFonts.zain(fontSize: 12),
        ),
      ),
      home: ChangeNotifierProvider<DonationData>(
        create: (BuildContext context) => DonationData(),
        builder: (BuildContext context, Widget? child) =>
            const DonationScreen(),
      ),
    );
  }
}
void main() {
  runApp(const MyApp());
}
