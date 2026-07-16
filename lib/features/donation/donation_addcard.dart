import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../app_theme.dart';
import 'models.dart';
import 'donation_cards.dart';

final creditCardDataProvider = ChangeNotifierProvider.autoDispose<CreditCardData>((ref) => CreditCardData());

class CreditCardData with ChangeNotifier {
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _expiryMonthController = TextEditingController();
  final TextEditingController _expiryYearController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  final TextEditingController _cardHolderNameController =
      TextEditingController();

  String? _cardNumberError;
  String? _expiryMonthError;
  String? _expiryYearError;
  String? _cvvError;
  String? _cardHolderNameError;
  CardType _cardType = CardType.other;

  TextEditingController get cardNumberController => _cardNumberController;
  TextEditingController get expiryMonthController => _expiryMonthController;
  TextEditingController get expiryYearController => _expiryYearController;
  TextEditingController get cvvController => _cvvController;
  TextEditingController get cardHolderNameController =>
      _cardHolderNameController;

  String? get cardNumberError => _cardNumberError;
  String? get expiryMonthError => _expiryMonthError;
  String? get expiryYearError => _expiryYearError;
  String? get cvvError => _cvvError;
  String? get cardHolderNameError => _cardHolderNameError;
  CardType get cardType => _cardType;

  CreditCardData() {
    _cardNumberController
        .addListener(() => updateCardNumber(_cardNumberController.text));
    _expiryMonthController
        .addListener(() => updateExpiryMonth(_expiryMonthController.text));
    _expiryYearController
        .addListener(() => updateExpiryYear(_expiryYearController.text));
    _cvvController.addListener(() => updateCvv(_cvvController.text));
    _cardHolderNameController
        .addListener(() => updateCardHolderName(_cardHolderNameController.text));
  }

  String? _validateCardNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a card number';
    }
    final String digitsOnly = value.replaceAll(' ', '');
    if (digitsOnly.length != 16) {
      return 'This is not a valid card number';
    }
    return null;
  }

  String? _validateExpiryMonth(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a month';
    }
    if (value.length != 2) {
      return 'This is not a valid month';
    }
    final int? month = int.tryParse(value);
    if (month == null || month < 1 || month > 12) {
      return 'This is not a valid month';
    }
    return null;
  }

  String? _validateExpiryYear(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a year';
    }
    if (value.length != 2) {
      return 'This is not a valid year';
    }
    final int? year = int.tryParse(value);
    if (year == null) {
      return 'This is not a valid year';
    }

    return null;
  }

  String? _validateCvv(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your CVV';
    }
    if (value.length < 3 || value.length > 4) {
      return 'This is not a valid CVV';
    }
    return null;
  }

  String? _validateCardHolderName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter the name of the cardholder';
    }
    return null;
  }

  void updateCardNumber(String value) {
    _cardNumberError = _validateCardNumber(value);
    notifyListeners();
  }

  void updateExpiryMonth(String value) {
    _expiryMonthError = _validateExpiryMonth(value);
    notifyListeners();
  }

  void updateExpiryYear(String value) {
    _expiryYearError = _validateExpiryYear(value);
    notifyListeners();
  }

  void updateCvv(String value) {
    _cvvError = _validateCvv(value);
    notifyListeners();
  }

  void updateCardHolderName(String value) {
    _cardHolderNameError = _validateCardHolderName(value);
    notifyListeners();
  }

  void updateCardType(CardType? newType) {
    if (newType != null) {
      _cardType = newType;
      notifyListeners();
    }
  }

  bool get isValid {
    _cardNumberError = _validateCardNumber(_cardNumberController.text);
    _cvvError = _validateCvv(_cvvController.text);
    _cardHolderNameError =
        _validateCardHolderName(_cardHolderNameController.text);

    _expiryMonthError = _validateExpiryMonth(_expiryMonthController.text);
    _expiryYearError = _validateExpiryYear(_expiryYearController.text);

    if (_expiryMonthError == null && _expiryYearError == null) {
      final int? month = int.tryParse(_expiryMonthController.text);
      final int? year = int.tryParse(_expiryYearController.text);

      if (month != null && year != null) {
        final int currentYearFull = DateTime.now().year;
        final int currentMonth = DateTime.now().month;

        // Convert two-digit year to full year
        final int fullYear = (currentYearFull ~/ 100) * 100 + year;

        if (fullYear < currentYearFull) {
          _expiryYearError = 'This card is expired';
        } else if (fullYear == currentYearFull && month < currentMonth) {
          _expiryMonthError = 'This card is expired';
        }
      }
    }

    return _cardNumberError == null &&
        _expiryMonthError == null &&
        _expiryYearError == null &&
        _cvvError == null &&
        _cardHolderNameError == null;
  }

  void validateAll() {
    notifyListeners();
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryMonthController.dispose();
    _expiryYearController.dispose();
    _cvvController.dispose();
    _cardHolderNameController.dispose();
    super.dispose();
  }
}

class CreditCardNumberInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    String text = newValue.text.replaceAll(RegExp(r'\s+'), '');
    if (text.length > 16) {
      return oldValue;
    }

    final StringBuffer newText = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      newText.write(text[i]);
      if ((i + 1) % 4 == 0 && i != text.length - 1) {
        newText.write(' ');
      }
    }

    return TextEditingValue(
      text: newText.toString(),
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class DonationAddCardScreen extends ConsumerWidget {
  const DonationAddCardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final CreditCardData creditCardData = ref.watch(creditCardDataProvider);

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
        scrolledUnderElevation: 0,
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
                        cardType: creditCardData.cardType,
                        cardNumberLastFour: lastFour,
                        cardHolderName: creditCardData.cardHolderNameController.text.trim(),
                        expiryDate: '${creditCardData.expiryMonthController.text}/${creditCardData.expiryYearController.text}',
                        backgroundColor: AppColors.lavenderrspwn, // Default color for new cards
                      );

                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              DonationCardVerificationScreen(newCard: newCard),
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

class DonationCardVerificationScreen extends ConsumerStatefulWidget {
  final CreditCard newCard;
  const DonationCardVerificationScreen({super.key, required this.newCard});

  @override
  ConsumerState<DonationCardVerificationScreen> createState() => _DonationCardVerificationScreenState();
}

class _DonationCardVerificationScreenState extends ConsumerState<DonationCardVerificationScreen> {
  @override
  void initState() {
    super.initState();
    _verifyAndAdd();
  }

  Future<void> _verifyAndAdd() async {
    // Simulate verification delay
    await Future.delayed(const Duration(seconds: 2));
    
    if (mounted) {
      // Add the card to the provider
      ref.read(donationUserCardsProvider).addCreditCard(widget.newCard);
      
      // Go back to the card list (pop verification and add card screens)
      Navigator.of(context).pop(); // Pop Verification
      Navigator.of(context).pop(); // Pop Add Card
      
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
        automaticallyImplyLeading: false, // Prevent going back during verification
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
