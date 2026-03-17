import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_fonts/google_fonts.dart';
import 'models.dart';
import 'addcard.dart';

final donationUserCardsProvider = ChangeNotifierProvider((ref) => DonationUserCardsNotifier());

class DonationUserCardsNotifier extends ChangeNotifier {
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

  DonationUserCardsNotifier()
      : _creditCards = List<CreditCard>.from(_initialCreditCards);

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

class DonationCreditCardScreen extends ConsumerWidget {
  const DonationCreditCardScreen({super.key});

  static const Color _primaryBackgroundColor = Color(0xFFF0EFE0);
  static const Color _darkTextColor = Color(0xFF5D4037);
  static const Color _yellowAccentColor = Color(0xFFFAE07A);
  static const Color _lightDarkTextColor = Color(0xFF8B7969);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsNotifier = ref.watch(donationUserCardsProvider);
    final int bottomNavIndex = cardsNotifier.bottomNavIndex;
    final List<CreditCard> displayedCreditCards = cardsNotifier.creditCards;
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
                      Navigator.of(context).pop();
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
                    child: DonationCreditCardWidget(
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
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (BuildContext context) => const DonationAddCardScreen(),
                      ),
                    );
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
        onTap: (int index) => cardsNotifier.setBottomNavIndex(index),
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

class DonationCreditCardWidget extends StatelessWidget {
  const DonationCreditCardWidget({
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
