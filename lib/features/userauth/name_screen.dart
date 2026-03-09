import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/userauth/phone_screen.dart';

class EnterNameScreen extends StatefulWidget {
  final String role;
  const EnterNameScreen({super.key, required this.role});

  @override
  State<EnterNameScreen> createState() => _EnterNameScreenState();
}

class _EnterNameScreenState extends State<EnterNameScreen> {
  final _nameController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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

              Text('Enter your\nname',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayLarge),

              const SizedBox(height: 48),

              // Underline-style text field
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'Name',
                  hintStyle: GoogleFonts.zain(
                      fontSize: 16, color: AppColors.textSecondary),
                  filled: false,
                  enabledBorder: const UnderlineInputBorder(
                    borderSide:
                    BorderSide(color: AppColors.textSecondary, width: 1),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide:
                    BorderSide(color: AppColors.textPrimary, width: 2),
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(vertical: 8),
                ),
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
                  onPressed: () {
                    if (_nameController.text.trim().isEmpty) {
                      setState(
                              () => _errorMessage = 'Please enter your name.');
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EnterPhoneScreen(
                          role: widget.role,
                          name: _nameController.text.trim(),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    fixedSize:
                    Size(MediaQuery.of(context).size.width * 0.55, 50),
                  ),
                  child: Text('Next',
                      style: Theme.of(context).textTheme.headlineLarge),
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