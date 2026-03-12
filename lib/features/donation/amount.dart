import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: DonationAmountInput(),
    );
  }
}

class DonationAmountInput extends StatefulWidget {
  const DonationAmountInput({super.key});

  @override
  State<DonationAmountInput> createState() => _DonationAmountInputState();
}

class _DonationAmountInputState extends State<DonationAmountInput> {
  final TextEditingController _amountEditor = TextEditingController();
  String? _amountErr;

  @override
  void dispose() {
    _amountEditor.dispose();
    super.dispose();
  }

  String? _validateDonationAmount(String? text) {
    if (text == null || text.isEmpty) {
      return 'Please enter a donation amount';
    }
    final double? amount = double.tryParse(text);
    if (amount == null) {
      return 'Please enter a valid number';
    }
    if (amount <= 0) {
      return 'Donation must be greater than zero';
    }
    return null;
  }

  void _validateAndContinue() {
    setState(() {
      _amountErr = _validateDonationAmount(_amountEditor.text);
    });

    if (_amountErr == null) {
      // Placeholder for validation logic
      //print('Donation Amount entered: PHP ${_amountEditor.text}');
      // Placeholder for redirect logic
      // Navigator.push(
      //   context,
      //   MaterialPageRoute(builder: (context) => const page2()),
      // );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EADC),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                'How much are you donating?',
                style: GoogleFonts.tiltWarp(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _amountEditor,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                decoration: InputDecoration(
                  labelText: 'Donation Amount',
                  hintText: 'Enter a value',
                  errorText: _amountErr,
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
                  prefixText: 'PHP ',
                  prefixStyle: GoogleFonts.zain(
                    fontSize: 16,
                    color: Colors.black,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onChanged: (String text) {
                  setState(() {
                    _amountErr = _validateDonationAmount(text);
                  });
                },
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _validateAndContinue,
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
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
