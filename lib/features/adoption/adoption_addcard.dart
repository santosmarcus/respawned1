import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_theme.dart';
import '../../core/config/paymongo_config.dart';
import '../donation/models.dart';
import '../donation/donation_cards.dart';
import '../donation/donation_addcard.dart';

class AdoptionAddCardScreen extends ConsumerWidget {
  const AdoptionAddCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditCardData = ref.watch(creditCardDataProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Add New Card',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              DropdownButtonFormField<CardType>(
                initialValue: creditCardData.cardType,
                decoration: _inputDecoration('Card Type', Icons.credit_card_sharp, null),
                dropdownColor: AppColors.background,
                items: CardType.values.map<DropdownMenuItem<CardType>>(
                  (CardType type) {
                    return DropdownMenuItem<CardType>(
                      value: type,
                      child: Text(
                        type.name.toUpperCase(),
                        style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                      ),
                    );
                  },
                ).toList(),
                onChanged: (CardType? newType) {
                  creditCardData.updateCardType(newType);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: creditCardData.cardNumberController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  CreditCardNumberInputFormatter(),
                ],
                decoration: _inputDecoration(
                  'Card Number',
                  Icons.credit_card,
                  creditCardData.cardNumberError,
                  hint: 'XXXX XXXX XXXX XXXX',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: creditCardData.expiryMonthController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: _inputDecoration(
                        'Month',
                        Icons.calendar_month,
                        creditCardData.expiryMonthError,
                        hint: 'MM',
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: creditCardData.expiryYearController,
                      keyboardType: TextInputType.number,
                      style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: _inputDecoration(
                        'Year',
                        Icons.event,
                        creditCardData.expiryYearError,
                        hint: 'YY',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: creditCardData.cvvController,
                keyboardType: TextInputType.number,
                style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: _inputDecoration(
                  'CVV',
                  Icons.lock,
                  creditCardData.cvvError,
                  hint: 'XXX',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: creditCardData.cardHolderNameController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.words,
                style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
                decoration: _inputDecoration(
                  'Cardholder Name',
                  Icons.person,
                  creditCardData.cardHolderNameError,
                  hint: 'e.g. Marcus Santos',
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    creditCardData.validateAll();
                    if (creditCardData.isValid) {
                      final String cardNumber = creditCardData.cardNumberController.text.replaceAll(' ', '');
                      final String lastFour = cardNumber.substring(cardNumber.length - 4);
                      
                      final newCard = CreditCard(
                        id: '',
                        cardType: creditCardData.cardType,
                        cardNumberLastFour: lastFour,
                        cardHolderName: creditCardData.cardHolderNameController.text.trim(),
                        expiryDate: '${creditCardData.expiryMonthController.text}/${creditCardData.expiryYearController.text}',
                        backgroundColor: AppColors.lavenderrspwn,
                      );

                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              AdoptionCardVerificationScreen(
                                newCard: newCard,
                                fullCardNumber: cardNumber,
                                cvv: creditCardData.cvvController.text.trim(),
                              ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Please fix the errors in the form.',
                            style: GoogleFonts.zain(fontSize: 16),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    elevation: 0,
                  ),
                  child: Text(
                    'Add Card',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon, String? errorText, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: errorText,
      labelStyle: GoogleFonts.zain(color: AppColors.textPrimary.withValues(alpha: 0.7)),
      hintStyle: GoogleFonts.zain(color: AppColors.textPrimary.withValues(alpha: 0.3)),
      errorStyle: GoogleFonts.zain(color: Colors.red, fontSize: 12),
      prefixIcon: Icon(icon, color: AppColors.textPrimary.withValues(alpha: 0.5), size: 20),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.yellowrspwn, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
    );
  }
}

class AdoptionCardVerificationScreen extends ConsumerStatefulWidget {
  final CreditCard newCard;
  final String fullCardNumber;
  final String cvv;
  const AdoptionCardVerificationScreen({
    super.key,
    required this.newCard,
    required this.fullCardNumber,
    required this.cvv,
  });

  @override
  ConsumerState<AdoptionCardVerificationScreen> createState() => _AdoptionCardVerificationScreenState();
}

class _AdoptionCardVerificationScreenState extends ConsumerState<AdoptionCardVerificationScreen> {
  @override
  void initState() {
    super.initState();
    _verifyAndAdd();
  }

  Future<void> _verifyAndAdd() async {
    final paymongo = ref.read(payMongoServiceProvider);
    
    try {
      final method = await paymongo.createPaymentMethod(
        type: 'card',
        details: {
          'card_number': widget.fullCardNumber,
          'exp_month': int.tryParse(widget.newCard.expiryDate.split('/')[0]) ?? 1,
          'exp_year': int.tryParse(widget.newCard.expiryDate.split('/')[1]) ?? 25,
          'cvc': widget.cvv,
        },
      );

      if (method == null) throw Exception("Verification failed");

      if (mounted) {
        final cardWithToken = CreditCard(
          id: '',
          cardType: widget.newCard.cardType,
          cardNumberLastFour: widget.newCard.cardNumberLastFour,
          cardHolderName: widget.newCard.cardHolderName,
          expiryDate: widget.newCard.expiryDate,
          backgroundColor: widget.newCard.backgroundColor,
          token: method['id'],
        );

        await ref.read(donationUserCardsProvider).addCreditCard(cardWithToken);
        
        if (mounted) {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Card successfully added!',
                style: GoogleFonts.zain(fontSize: 16),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to verify card. Please try again.',
              style: GoogleFonts.zain(fontSize: 16),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Card Verification',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const CircularProgressIndicator(
              color: AppColors.yellowrspwn,
            ),
            const SizedBox(height: 24),
            Text(
              'Your card is being verified',
              style: GoogleFonts.tiltWarp(
                fontSize: 20,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please wait a moment while we process your request',
              style: GoogleFonts.zain(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
