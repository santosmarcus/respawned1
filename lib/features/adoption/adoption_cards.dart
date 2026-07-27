import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../app_theme.dart';
import '../donation/models.dart';
import '../donation/donation_cards.dart';
import 'adoption_addcard.dart';

class AdoptionCreditCardScreen extends ConsumerWidget {
  const AdoptionCreditCardScreen({super.key});

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
                      onTap: () => Navigator.pop(context, card),
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
            'Add a card to proceed with your payment',
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
              builder: (BuildContext context) => const AdoptionAddCardScreen(),
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
