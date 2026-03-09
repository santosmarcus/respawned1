import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/home/home_screen.dart';

class EnterPhoneScreen extends StatefulWidget {
  final String role;
  final String name;
  const EnterPhoneScreen({super.key, required this.role, required this.name});

  @override
  State<EnterPhoneScreen> createState() => _EnterPhoneScreenState();
}

class _EnterPhoneScreenState extends State<EnterPhoneScreen> {
  final _phoneController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleNext() async {
    if (_phoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your mobile number.');
      return;
    }

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Save name, role, and phone to Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({
        'name': widget.name,
        'role': widget.role,
        'phone': '+63${_phoneController.text.trim()}',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
              (route) => false,
        );
      }
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select User Type')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 80),

              Text('Enter your\nmobile number',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge),

              const SizedBox(height: 48),

              // Phone field with +63 prefix
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+63',
                      style: GoogleFonts.zain(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: InputDecoration(
                        hintText: '9XXXXXXXXX',
                        hintStyle: GoogleFonts.zain(
                            fontSize: 16,
                            color: AppColors.textSecondary),
                        filled: false,
                        counterText: '',
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.textSecondary, width: 1),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(
                              color: AppColors.textPrimary, width: 2),
                        ),
                        contentPadding:
                        const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(_errorMessage!,
                    style: GoogleFonts.zain(
                        fontSize: 13, color: Colors.red.shade700)),
              ],

              const Spacer(),

              // Next button
              Center(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    fixedSize:
                    Size(MediaQuery.of(context).size.width * 0.55, 50),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: AppColors.textPrimary))
                      : Text('Next',
                      style:
                      Theme.of(context).textTheme.headlineLarge),
                ),
              ),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}