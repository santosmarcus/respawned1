import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:google_fonts/google_fonts.dart';

class Fundraiser {
  final String id;
  final String name;
  final String description;
  final String imageUrl;
  final double targetAmount;
  double currentAmount;
  final bool hasFacebook;
  final bool hasInstagram;
  final bool hasSpotify;
  final bool hasEmail;
  final int daysLeft;
  bool isFavorite;

  Fundraiser({
    required this.id,
    required this.name,
    required this.description,
    required this.targetAmount,
    required this.daysLeft,
    this.currentAmount = 0.0,
    this.imageUrl =
        'https://www.gstatic.com/flutter-onestack-prototype/genui/example_1.jpg',
    this.hasFacebook = true,
    this.hasInstagram = true,
    this.hasSpotify = true,
    this.hasEmail = true,
    this.isFavorite = false,
  });

  Fundraiser copyWith({
    bool? isFavorite,
    double? currentAmount,
    int? daysLeft,
  }) {
    return Fundraiser(
      id: id,
      name: name,
      description: description,
      targetAmount: targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      imageUrl: imageUrl,
      hasFacebook: hasFacebook,
      hasInstagram: hasInstagram,
      hasSpotify: hasSpotify,
      hasEmail: hasEmail,
      isFavorite: isFavorite ?? this.isFavorite,
      daysLeft: daysLeft ?? this.daysLeft,
    );
  }
}

class FirebaseMockService {
  final List<Fundraiser> _mockFundraisers = <Fundraiser>[
    Fundraiser(
      id: '1',
      name: 'Campaign 1',
      description: 'Description 1',
      targetAmount: 5000.0,
      currentAmount: 2000.0,
      isFavorite: true,
      hasSpotify: false,
      daysLeft: 10,
    ),
    Fundraiser(
      id: '2',
      name: 'Campaign 2',
      description: 'Description 2',
      targetAmount: 10000.0,
      currentAmount: 2000.0,
      isFavorite: false,
      hasFacebook: false,
      daysLeft: 30,
    ),
    Fundraiser(
      id: '3',
      name: 'Campaign 3',
      description: 'Description 3',
      targetAmount: 2500.0,
      currentAmount: 2500.0,
      isFavorite: true,
      hasEmail: false,
      daysLeft: 5,
    ),
    Fundraiser(
      id: '4',
      name: 'Campaign 4',
      description: 'Description 4',
      targetAmount: 1500.0,
      currentAmount: 0.0,
      isFavorite: false,
      hasInstagram: false,
      daysLeft: 7,
    ),
  ];

  Future<List<Fundraiser>> fetchFundraisers() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return _mockFundraisers;
  }
}

class FundraiserData extends ChangeNotifier {
  int _bottomNavIndex = 0;
  List<Fundraiser> _fundraisers = <Fundraiser>[];
  bool _isLoading = true;
  String _searchQuery = '';

  FundraiserData() {
    _loadFundraisers();
  }

  int get bottomNavIndex => _bottomNavIndex;
  List<Fundraiser> get fundraisers {
    if (_searchQuery.isEmpty) {
      return _fundraisers;
    }
    return _fundraisers.where((Fundraiser fundraiser) {
      return fundraiser.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          fundraiser.description.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
  }
  bool get isLoading => _isLoading;

  Future<void> _loadFundraisers() async {
    _isLoading = true;
    notifyListeners();

    try {
      _fundraisers = await FirebaseMockService().fetchFundraisers();
    } catch (e) {
      // Placeholder for error logging
      _fundraisers = <Fundraiser>[];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setBottomNavIndex(int index) {
    if (_bottomNavIndex != index) {
      _bottomNavIndex = index;
      notifyListeners();
    }
  }

  void toggleFavorite(String fundraiserId) {
    _fundraisers = _fundraisers.map<Fundraiser>((Fundraiser fr) {
      if (fr.id == fundraiserId) {
        return fr.copyWith(isFavorite: !fr.isFavorite);
      }
      return fr;
    }).toList();
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }
}

class FundraiserScreen extends StatelessWidget {
  const FundraiserScreen({super.key});

  static const Color _primaryBackgroundColor = Color(0xFFF0EFE0); // Light cream/beige
  static const Color _darkTextColor = Color(0xFF5D4037); // Dark brown
  static const Color _yellowAccentColor = Color(0xFFFAE07A); // Yellow for search bar, etc.
  static const Color _cardBackgroundColor1 = Color(0xFFE8E8D2); // Light cream card
  static const Color _cardBackgroundColor2 = Color(0xFFB5B3A5); // Light brown/grey card
  static const Color _lightDarkTextColor = Color(0xFF8B7969); // Slightly lighter dark text for "Php"

  @override
  Widget build(BuildContext context) {
    final FundraiserData fundraiserData = context.watch<FundraiserData>();
    final int bottomNavIndex = fundraiserData.bottomNavIndex;
    final bool isLoading = fundraiserData.isLoading;
    final List<Fundraiser> displayedFundraisers = fundraiserData.fundraisers;

    return Scaffold(
      backgroundColor: _primaryBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios,
                        color: _darkTextColor, size: 24),
                    onPressed: () {
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Org 1',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tiltWarp(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _darkTextColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.favorite_border,
                        color: _darkTextColor, size: 24),
                    onPressed: () {
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: Column(
                  children: <Widget>[
                    Text(
                      'Location: Place, Region',
                      style: GoogleFonts.zain(
                          fontSize: 14, color: _darkTextColor),
                    ),
                    Text(
                      'org@example.com',
                      style: GoogleFonts.zain(
                          fontSize: 14, color: _darkTextColor),
                    ),
                    Text(
                      'example.com',
                      style: GoogleFonts.zain(
                          fontSize: 14, color: _darkTextColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      decoration: BoxDecoration(
                        color: _yellowAccentColor,
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
                        onChanged: (String value) =>
                            fundraiserData.setSearchQuery(value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _yellowAccentColor,
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child:
                        const Icon(Icons.tune, color: _darkTextColor),
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
                      children:
                          List<Widget>.generate(displayedFundraisers.length, (int index) {
                        final Fundraiser fundraiser = displayedFundraisers[index];
                        final Color cardColor =
                            index % 2 == 0 ? _cardBackgroundColor1 : _cardBackgroundColor2;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: FundraiserCard(
                            fundraiser: fundraiser,
                            onToggleFavorite: (String frId) =>
                                fundraiserData.toggleFavorite(frId),
                            cardBackgroundColor: cardColor,
                            darkTextColor: _darkTextColor,
                            lightDarkTextColor: _lightDarkTextColor,
                            yellowAccentColor: _yellowAccentColor,
                          ),
                        );
                      }),
                    ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: bottomNavIndex,
        onTap: (int index) => fundraiserData.setBottomNavIndex(index),
        backgroundColor: _yellowAccentColor,
        selectedItemColor: _darkTextColor,
        unselectedItemColor: _darkTextColor.withOpacity(0.6),
        selectedLabelStyle: GoogleFonts.tiltWarp(fontWeight: FontWeight.bold),
        unselectedLabelStyle: GoogleFonts.tiltWarp(),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_none),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            label: 'My Profile',
          ),
        ],
      ),
    );
  }
}
class FundraiserCard extends StatelessWidget {
  const FundraiserCard({
    required this.fundraiser,
    required this.onToggleFavorite,
    required this.cardBackgroundColor,
    required this.darkTextColor,
    required this.lightDarkTextColor,
    required this.yellowAccentColor,
    super.key,
  });
  final Fundraiser fundraiser;
  final ValueChanged<String> onToggleFavorite;
  final Color cardBackgroundColor;
  final Color darkTextColor;
  final Color lightDarkTextColor;
  final Color yellowAccentColor;

  @override
  Widget build(BuildContext context) {
    final double percentage = (fundraiser.targetAmount > 0)
        ? (fundraiser.currentAmount / fundraiser.targetAmount) * 100
        : (fundraiser.currentAmount > 0 ? 100.0 : 0.0);
    final String percentageText = '${percentage.round()}%';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Stack(
            children: <Widget>[
              Container(
                height: 150,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cardBackgroundColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20.0),
                    bottom: Radius.circular(0),
                  ),
                ),
              ),
              Positioned(
                top: 15,
                right: 15,
                child: GestureDetector(
                  onTap: () => onToggleFavorite(fundraiser.id),
                  child: Icon(
                    fundraiser.isFavorite
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: darkTextColor,
                    size: 24,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  fundraiser.name,
                  style: GoogleFonts.tiltWarp(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: darkTextColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          children: <TextSpan>[
                            TextSpan(
                              text: 'Target: Php. ${fundraiser.targetAmount.toStringAsFixed(0)}',
                              style: GoogleFonts.zain(
                                fontSize: 14,
                                color: darkTextColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: ' | Collected: Php. ${fundraiser.currentAmount.toStringAsFixed(0)} | ${fundraiser.daysLeft} days left',
                              style: GoogleFonts.zain(
                                fontSize: 14,
                                color: darkTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: yellowAccentColor,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          percentageText,
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: darkTextColor,
                          ),
                        ),
                      ),
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

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Fundraiser App',
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
      home: ChangeNotifierProvider<FundraiserData>(
        create: (BuildContext context) => FundraiserData(),
        builder: (BuildContext context, Widget? child) =>
            const FundraiserScreen(),
      ),
    );
  }
}

void main() {
  runApp(const MyApp());
}
