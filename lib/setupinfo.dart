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
      home: Login(),
    );
  }
}

class Login extends StatefulWidget {
  const Login({super.key});

  @override
  State<Login> createState() => _LSState();
}

class _LSState extends State<Login> {
  final TextEditingController _numEditor = TextEditingController();
  String? _numErr;

  @override
  void dispose() {
    _numEditor.dispose();
    super.dispose();
  }

  String? _validateMobileNumber(String? text) {
    if (text == null || text.isEmpty || text.length != 10) {
      return 'This is not a valid mobile number';
    }
    return null;
  }

  void _validateAndContinue() {
    setState(() {
      _numErr = _validateMobileNumber(_numEditor.text);
    });

    if (_numErr == null) {
      // Placeholder for validation logic
      //print('Mobile Number entered: +63${_numEditor.text}');
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
                'We need to know your contact details',
                style: GoogleFonts.tiltWarp(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _numEditor,
                keyboardType: TextInputType.number,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: 'e.g., 9123456789',
                  errorText: _numErr,
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
                  prefixIcon: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Image.network(
                          'https://www.gstatic.com/flutter-onestack-prototype/genui/example_1.jpg', // Placeholder image, to be replaced with a PH flag
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                              const Icon(Icons.flag, size: 28, color: Colors.grey),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+63',
                          style: GoogleFonts.zain(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                  counterText: '',
                ),
                onChanged: (String text) {
                  setState(() {
                    _numErr = _validateMobileNumber(text);
                  });
                },
              ),
              const SizedBox(height: 15), // Adjusted spacing after removing email field
              Text(
                'Worry not, we will keep this information safe from bad actors.',
                style: GoogleFonts.zain(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25), // Space before button
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