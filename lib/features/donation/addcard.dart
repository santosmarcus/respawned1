import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

enum CardType { visa, mastercard, other }

extension CardTypeExtension on CardType {
  String get name {
    switch (this) {
      case CardType.visa:
        return 'Visa';
      case CardType.mastercard:
        return 'Mastercard';
      case CardType.other:
        return 'Other';
    }
  }
}
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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<CreditCardData>(
      create: (BuildContext context) => CreditCardData(),
      builder: (BuildContext context, Widget? child) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: const BorderSide(
                color: Colors.blueAccent,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: const BorderSide(
                color: Colors.red,
                width: 2,
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12.0),
              borderSide: const BorderSide(
                color: Colors.redAccent,
                width: 2,
              ),
            ),
            labelStyle: GoogleFonts.zain(fontSize: 16, color: Colors.black),
            hintStyle: GoogleFonts.zain(fontSize: 16, color: Colors.grey[400]),
            errorStyle: GoogleFonts.zain(fontSize: 12, color: Colors.red),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10.0, horizontal: 12.0),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
              ),
              backgroundColor: const Color(0xFFFFD95E),
              foregroundColor: Colors.black,
              textStyle: GoogleFonts.tiltWarp(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          textSelectionTheme: const TextSelectionThemeData(
            cursorColor: Colors.blueAccent,
            selectionColor: Colors.blueAccent,
            selectionHandleColor: Colors.blueAccent,
          ),
        ),
        home: const AddCreditCardScreen(),
      ),
    );
  }
}

class AddCreditCardScreen extends StatelessWidget {
  const AddCreditCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final CreditCardData creditCardData = context.watch<CreditCardData>();
    const Color scaffoldBackgroundColor = Color(0xFFF0EADC);

    return Scaffold(
      backgroundColor: scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              debugPrint('Cannot pop: This is the first screen.');
            }
          },
        ),
        title: Text(
          'Add New Card',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        backgroundColor: scaffoldBackgroundColor,
        iconTheme: const IconThemeData(color: Colors.black),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 15),
              DropdownButtonFormField<CardType>(
                value: creditCardData.cardType,
                decoration: InputDecoration(
                  labelText: 'Card Type',
                  prefixIcon:
                      const Icon(Icons.credit_card_sharp, color: Colors.grey),
                ),
                items: CardType.values.map<DropdownMenuItem<CardType>>(
                  (CardType type) {
                    return DropdownMenuItem<CardType>(
                      value: type,
                      child: Text(type.name),
                    );
                  },
                ).toList(),
                onChanged: (CardType? newType) {
                  creditCardData.updateCardType(newType);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: creditCardData.cardNumberController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  CreditCardNumberInputFormatter(),
                ],
                decoration: InputDecoration(
                  labelText: 'Card Number (16 digits)',
                  hintText: 'XXXX XXXX XXXX XXXX',
                  errorText: creditCardData.cardNumberError,
                  prefixIcon: const Icon(Icons.credit_card, color: Colors.grey),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: creditCardData.expiryMonthController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: InputDecoration(
                  labelText: 'Month',
                  hintText: 'MM',
                  errorText: creditCardData.expiryMonthError,
                  prefixIcon:
                      const Icon(Icons.calendar_month, color: Colors.grey),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: creditCardData.expiryYearController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                decoration: InputDecoration(
                  labelText: 'Year',
                  hintText: 'YY',
                  errorText: creditCardData.expiryYearError,
                  prefixIcon: const Icon(Icons.event, color: Colors.grey),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: creditCardData.cvvController,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                decoration: InputDecoration(
                  labelText: 'CVV (3 or 4 digits)',
                  hintText: 'XXX',
                  errorText: creditCardData.cvvError,
                  prefixIcon: const Icon(Icons.lock, color: Colors.grey),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: creditCardData.cardHolderNameController,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Cardholder Name',
                  hintText: 'e.g. Marcus Santos',
                  errorText: creditCardData.cardHolderNameError,
                  prefixIcon: const Icon(Icons.person, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    creditCardData.validateAll();
                    if (creditCardData.isValid) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (BuildContext context) =>
                              const CardVerificationScreen(),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                              'There are invalid or missing inputs in the form.'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  },
                  child: const Text('Add Card'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CardVerificationScreen extends StatelessWidget {
  const CardVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Placeholder for external card verification script
    const Color scaffoldBackgroundColor = Color(0xFFF0EADC);

    return Scaffold(
      backgroundColor: scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Card Verification',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        centerTitle: true,
        backgroundColor: scaffoldBackgroundColor,
        iconTheme: const IconThemeData(color: Colors.black),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const CircularProgressIndicator(
              color: Color(0xFFFFD95E),
            ),
            const SizedBox(height: 20),
            Text(
              'Your card is being verified',
              style: GoogleFonts.zain(
                fontSize: 18,
                color: Colors.black,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              'Please follow any instructions when you see them',
              style: GoogleFonts.zain(
                fontSize: 16,
                color: Colors.grey[700],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
