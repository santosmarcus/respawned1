import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';

enum CardType { visa, mastercard, other }

class CreditCard {
  final CardType cardType;
  final String cardNumberLastFour;
  final String cardHolderName;
  final String expiryDate;
  final Color backgroundColor;

  CreditCard({
    required this.cardType,
    required this.cardNumberLastFour,
    required this.cardHolderName,
    required this.expiryDate,
    required this.backgroundColor,
  });
}

class CreditCardData extends ChangeNotifier {
  int _bottomNavIndex = 0;
  final List<CreditCard> _creditCards;
  static const Color _uniformCardBackgroundColor = Colors.white;
  static final List<CreditCard> _initialCreditCards = <CreditCard>[
    CreditCard(
      cardType: CardType.visa,
      cardNumberLastFour: '1234',
      cardHolderName: 'JOHN DOE',
      expiryDate: '12/25',
      backgroundColor: _uniformCardBackgroundColor,
    ),
    CreditCard(
      cardType: CardType.mastercard,
      cardNumberLastFour: '5678',
      cardHolderName: 'JANE DOE',
      expiryDate: '08/24',
      backgroundColor: _uniformCardBackgroundColor,
    ),
    CreditCard(
      cardType: CardType.other,
      cardNumberLastFour: '9012',
      cardHolderName: 'CHRIS SMITH',
      expiryDate: '03/26',
      backgroundColor: _uniformCardBackgroundColor,
    ),
    CreditCard(
      cardType: CardType.visa,
      cardNumberLastFour: '3456',
      cardHolderName: 'ALEX JOHNSON',
      expiryDate: '06/27',
      backgroundColor: _uniformCardBackgroundColor,
    ),
  ];

  CreditCardData()
      : _creditCards = _initialCreditCards,
        super();

  int get bottomNavIndex => _bottomNavIndex;
  List<CreditCard> get creditCards => List<CreditCard>.from(_creditCards);

  void setBottomNavIndex(int index) {
    if (_bottomNavIndex != index) {
      _bottomNavIndex = index;
      notifyListeners();
    }
  }

  void addCreditCard(CreditCard newCard) {
    _creditCards.add(newCard);
    notifyListeners();
  }
}

class CreditCardScreen extends StatelessWidget {
  const CreditCardScreen({super.key});

  static const Color _primaryBackgroundColor = Color(0xFFF0EFE0);
  static const Color _darkTextColor = Color(0xFF5D4037);
  static const Color _yellowAccentColor = Color(0xFFFAE07A);
  static const Color _lightDarkTextColor = Color(0xFF8B7969);

  @override
  Widget build(BuildContext context) {
    final CreditCardData creditCardData = context.watch<CreditCardData>();
    final int bottomNavIndex = creditCardData.bottomNavIndex;
    final List<CreditCard> displayedCreditCards = creditCardData.creditCards;
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
                      // Placeholder for navigation
                    },
                  ),
                  Expanded(
                    child: Text(
                      'Select Card',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tiltWarp(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _darkTextColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
              const SizedBox(height: 20),
              Column(
                children: displayedCreditCards.map<Widget>((CreditCard card) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: CreditCardWidget(
                      creditCard: card,
                      darkTextColor: _darkTextColor,
                      lightDarkTextColor: _lightDarkTextColor,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Center(
                child: FilledButton.icon(
                  onPressed: () {
                    // Placeholder redirect
                    // Navigator.push(context, MaterialPageRoute(builder: (context) => page2()));
                  },
                  icon: const Icon(Icons.add_card, color: _darkTextColor),
                  label: Text(
                    'Add New Card',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _darkTextColor,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _yellowAccentColor,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: bottomNavIndex,
        onTap: (int index) => creditCardData.setBottomNavIndex(index),
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

class CreditCardWidget extends StatelessWidget {
  const CreditCardWidget({
    required this.creditCard,
    required this.darkTextColor,
    required this.lightDarkTextColor,
    super.key,
  });

  final CreditCard creditCard;
  final Color darkTextColor;
  final Color lightDarkTextColor;

  IconData _getCardTypeIcon(CardType type) {
    switch (type) {
      case CardType.visa:
        return Icons.credit_card;
      case CardType.mastercard:
        return Icons.payment;
      case CardType.other:
        return Icons.account_balance_wallet;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: creditCard.backgroundColor,
        borderRadius: BorderRadius.circular(15.0),
        border: Border.all(
          color: lightDarkTextColor,
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(15.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    creditCard.cardType.name.toUpperCase(),
                    style: GoogleFonts.tiltWarp(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: darkTextColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _getCardTypeIcon(creditCard.cardType),
                    color: darkTextColor,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '**** **** **** ${creditCard.cardNumberLastFour}',
            style: GoogleFonts.zain(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: darkTextColor,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Card Holder',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: lightDarkTextColor,
                    ),
                  ),
                  Text(
                    creditCard.cardHolderName,
                    style: GoogleFonts.zain(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: darkTextColor,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Expires',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: lightDarkTextColor,
                    ),
                  ),
                  Text(
                    creditCard.expiryDate,
                    style: GoogleFonts.zain(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: darkTextColor,
                    ),
                  ),
                ],
              ),
            ],
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
      title: 'Credit Card Manager',
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
      home: ChangeNotifierProvider<CreditCardData>(
        create: (BuildContext context) => CreditCardData(),
        builder: (BuildContext context, Widget? child) =>
            const CreditCardScreen(),
      ),
    );
  }
}

void main() {
  runApp(const MyApp());
}
