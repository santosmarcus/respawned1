import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import 'models.dart';
import 'donation_addcard.dart';
import 'donation_review.dart';

final donationUserCardsProvider = ChangeNotifierProvider((ref) => DonationUserCardsNotifier());

class DonationUserCardsNotifier extends ChangeNotifier {
  final List<CreditCard> _creditCards;

  static final List<CreditCard> _initialCreditCards = <CreditCard>[
    CreditCard(
      cardType: CardType.visa,
      cardNumberLastFour: '1234',
      cardHolderName: 'JOHN DOE',
      expiryDate: '12/25',
      backgroundColor: const Color(0xFF1E1E1E), // Premium Black
    ),
    CreditCard(
      cardType: CardType.mastercard,
      cardNumberLastFour: '5678',
      cardHolderName: 'JANE DOE',
      expiryDate: '08/24',
      backgroundColor: AppColors.greenrspwn,
    ),
    CreditCard(
      cardType: CardType.other,
      cardNumberLastFour: '9012',
      cardHolderName: 'CHRIS SMITH',
      expiryDate: '03/26',
      backgroundColor: AppColors.yellowrspwn,
    ),
  ];

  DonationUserCardsNotifier()
      : _creditCards = List<CreditCard>.from(_initialCreditCards);

  List<CreditCard> get creditCards => List<CreditCard>.unmodifiable(_creditCards);

  void addCreditCard(CreditCard newCard) {
    _creditCards.add(newCard);
    notifyListeners();
  }

  void removeCreditCard(CreditCard card) {
    _creditCards.remove(card);
    notifyListeners();
  }
}

class DonationCreditCardScreen extends ConsumerWidget {
  const DonationCreditCardScreen({
    super.key,
    required this.fundraiserId,
    required this.organizationName,
    required this.campaignName,
    required this.amount,
    required this.isAnonymous,
    this.pet,
    this.isSponsorship = false,
  });

  final String fundraiserId;
  final String organizationName;
  final String campaignName;
  final double amount;
  final bool isAnonymous;
  final SponsorPet? pet;
  final bool isSponsorship;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsNotifier = ref.watch(donationUserCardsProvider);
    final List<CreditCard> displayedCreditCards = cardsNotifier.creditCards;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Select Card',
          style: GoogleFonts.tiltWarp(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: SafeArea(
        child: displayedCreditCards.isEmpty
            ? _buildEmptyState(context)
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 15.0),
                itemCount: displayedCreditCards.length + 1,
                itemBuilder: (context, index) {
                  if (index == displayedCreditCards.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0, bottom: 20),
                      child: _buildAddCardButton(context),
                    );
                  }

                  final card = displayedCreditCards[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: GestureDetector(
                      onTap: () => _onCardSelected(context, card),
                      onLongPress: () => _showDeleteDialog(context, ref, card),
                      child: DonationCreditCardWidget(
                        creditCard: card,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.credit_card_off_outlined,
              size: 80, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'No cards saved yet',
            style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a card to proceed with your donation',
            style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: _buildAddCardButton(context),
          ),
        ],
      ),
    );
  }

  Widget _buildAddCardButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => const DonationAddCardScreen(),
            ),
          );
        },
        icon: const Icon(Icons.add_card),
        label: Text(
          'Add New Card',
          style: GoogleFonts.tiltWarp(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellowrspwn,
          foregroundColor: AppColors.textPrimary,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  void _onCardSelected(BuildContext context, CreditCard card) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DonationReviewScreen(
          params: DonationReviewParams(
            fundraiserId: fundraiserId,
            organizationName: organizationName,
            donationMethod: 'Credit Card (**** ${card.cardNumberLastFour})',
            item: DonationItem(
              description: campaignName,
              amount: amount,
            ),
            isAnonymous: isAnonymous,
            pet: pet,
            isSponsorship: isSponsorship,
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, CreditCard card) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Card', style: GoogleFonts.tiltWarp()),
        content: Text('Are you sure you want to remove this card ending in ${card.cardNumberLastFour}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              ref.read(donationUserCardsProvider).removeCreditCard(card);
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class DonationCreditCardWidget extends StatelessWidget {
  const DonationCreditCardWidget({
    required this.creditCard,
    super.key,
  });

  final CreditCard creditCard;

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
    final bool isDark = ThemeData.estimateBrightnessForColor(creditCard.backgroundColor) == Brightness.dark;
    final Color textColor = isDark ? Colors.white : AppColors.textPrimary;
    final Color secondaryTextColor = isDark ? Colors.white70 : AppColors.textSecondary;

    return Container(
      height: 190,
      decoration: BoxDecoration(
        color: creditCard.backgroundColor,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: creditCard.backgroundColor.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: Stack(
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
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
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _getCardTypeIcon(creditCard.cardType),
                            color: textColor,
                            size: 20,
                          ),
                        ],
                      ),
                      Icon(Icons.nfc, color: textColor.withValues(alpha: 0.5), size: 20),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '**** **** **** ${creditCard.cardNumberLastFour}',
                    style: GoogleFonts.zain(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                      letterSpacing: 2,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      _buildInfoColumn('Card Holder', creditCard.cardHolderName, textColor, secondaryTextColor),
                      _buildInfoColumn('Expires', creditCard.expiryDate, textColor, secondaryTextColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value, Color textColor, Color secondaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.zain(fontSize: 12, color: secondaryColor)),
        Text(
          value.toUpperCase(),
          style: GoogleFonts.zain(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
