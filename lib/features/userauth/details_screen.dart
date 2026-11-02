import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/userauth/onboard_screen.dart';

class EnterDetailsScreen extends StatefulWidget {
  //final String role;
  const EnterDetailsScreen({super.key});

  @override
  State<EnterDetailsScreen> createState() => _EnterDetailsScreenState();
}

class _EnterDetailsScreenState extends State<EnterDetailsScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController  = TextEditingController();
  final _phoneController     = TextEditingController();

  // ── TEMPLATE: Add extra fields here ──────────────────────────
  // final _addressController   = TextEditingController();
  // final _birthdateController = TextEditingController();
  // String? _selectedGender;
  // ─────────────────────────────────────────────────────────────

  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    // _addressController.dispose();
    // _birthdateController.dispose();
    super.dispose();
  }

  void _handleNext() {
    setState(() => _errorMessage = null);

    if (_firstNameController.text.trim().isEmpty ||
        _lastNameController.text.trim().isEmpty ||
        _phoneController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }

    if (_phoneController.text.trim().length < 10) {
      setState(() => _errorMessage = 'Please enter a valid phone number.');
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OnboardingRoleScreen(
          firstName: _firstNameController.text.trim(),
          lastName:  _lastNameController.text.trim(),
          phone:     '+63${_phoneController.text.trim()}',
          // pass extra fields here when added:
          // address: _addressController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Details')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),

              Text('Tell us about\nyourself',
                  style: Theme.of(context).textTheme.displayLarge),
              const SizedBox(height: 8),
              Text('This helps us personalize your experience.',
                  style: Theme.of(context).textTheme.bodyMedium),

              const SizedBox(height: 32),

              // First name
              _DetailField(
                controller: _firstNameController,
                hint: 'First Name',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 16),

              // Last name
              _DetailField(
                controller: _lastNameController,
                hint: 'Last Name',
                icon: Icons.person_outline,
              ),

              const SizedBox(height: 16),

              // Phone number
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.greenrspwn,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text('+63',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        hintText: '9XXXXXXXXX',
                        counterText: '',
                      ),
                    ),
                  ),
                ],
              ),

              // ── TEMPLATE: Extra fields ──────────────────────────────
              // Uncomment and add as needed:
              //
              // const SizedBox(height: 16),
              //
              // Address field:
              // _DetailField(
              //   controller: _addressController,
              //   hint: 'Home Address',
              //   icon: Icons.home_outlined,
              // ),
              //
              // Birthdate picker:
              // const SizedBox(height: 16),
              // GestureDetector(
              //   onTap: () async {
              //     final picked = await showDatePicker(
              //       context: context,
              //       initialDate: DateTime(2000),
              //       firstDate: DateTime(1900),
              //       lastDate: DateTime.now(),
              //     );
              //     if (picked != null) {
              //       _birthdateController.text =
              //           '${picked.day}/${picked.month}/${picked.year}';
              //     }
              //   },
              //   child: AbsorbPointer(
              //     child: _DetailField(
              //       controller: _birthdateController,
              //       hint: 'Date of Birth',
              //       icon: Icons.calendar_today_outlined,
              //     ),
              //   ),
              // ),
              //
              // Gender dropdown:
              // const SizedBox(height: 16),
              // DropdownButtonFormField<String>(
              //   value: _selectedGender,
              //   decoration: const InputDecoration(
              //     hintText: 'Gender',
              //     prefixIcon: Icon(Icons.wc_outlined),
              //   ),
              //   items: ['Male', 'Female', 'Prefer not to say']
              //       .map((g) => DropdownMenuItem(value: g, child: Text(g)))
              //       .toList(),
              //   onChanged: (val) => setState(() => _selectedGender = val),
              // ),
              // ───────────────────────────────────────────────────────

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Colors.red.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_errorMessage!,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: Colors.red.shade700)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 40),

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

// Reusable field widget for this screen
class _DetailField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;

  const _DetailField({
    required this.controller,
    required this.hint,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon),
      ),
    );
  }
}