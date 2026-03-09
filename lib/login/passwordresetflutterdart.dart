import 'package:flutter/material.dart';
import 'dart:async';

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
  final TextEditingController _passEditor = TextEditingController();
  final TextEditingController _cpassEditor = TextEditingController();
  final TextEditingController _codeEditor = TextEditingController();
  String _passValue = "";
  String _cpassValue = "";
  String _codeValue = "";
  bool _passwordVisible = false;
  bool _codeCooldown = false;
  int _countdown = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _passEditor.dispose();
    _cpassEditor.dispose();
    _codeEditor.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _codeCooldown = false;
      _countdown = 60;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_countdown <= 0) {
        timer.cancel();
        setState(() {
          _codeCooldown = true;
        });
      } else {
        setState(() {
          _countdown--;
        });
      }
    });
  }

  void _onResendCodePressed() {
    // Placeholder for resend code logic
    _startResendTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0EADC),
      body: Align(
        alignment: const Alignment(0, 0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text('A code has been sent to your email.'),
              const SizedBox(height: 16),
              TextField(
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  hintText: 'Enter a password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                  ),
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
                ),
                controller: _passEditor,
                onChanged: (String text) {
                  setState(() => _passValue = text);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                obscureText: !_passwordVisible,
                decoration: InputDecoration(
                  labelText: 'Retype Password',
                  hintText: 'Enter your password again',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _passwordVisible = !_passwordVisible;
                      });
                    },
                  ),
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
                ),
                controller: _cpassEditor,
                onChanged: (String text) {
                  setState(() => _cpassValue = text);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                obscureText: false,
                decoration: InputDecoration(
                  labelText: 'Verification Code',
                  hintText: 'Enter your code',
                  prefixIcon: const Icon(Icons.vpn_key_rounded),
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
                ),
                controller: _codeEditor,
                onChanged: (String text) {
                  setState(() => _codeValue = text);
                },
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Placeholder for reset password logic
                  },
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    backgroundColor: const Color(0xFFFFD95E),
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: const Text('Reset Password'),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _codeCooldown ? _onResendCodePressed : null,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 15.0),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.0),
                    ),
                    backgroundColor: const Color(0xFFFFD95E),
                    foregroundColor: Colors.black,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  child: Text(
                    _codeCooldown
                        ? 'Resend Code'
                        : 'Resend Code in $_countdown',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
