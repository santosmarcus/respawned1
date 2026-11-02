import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/pettransporter/transporter_success_screen.dart';

class _VehicleTypeOption {
  final String type;
  final String description;
  const _VehicleTypeOption(this.type, this.description);
}

const _vehicleTypeOptions = [
  _VehicleTypeOption('Motorcycle', 'Less than 5 kg breeds'),
  _VehicleTypeOption('Sedan', 'Small to medium sized breeds'),
  _VehicleTypeOption('SUV', 'Medium sized breeds'),
  _VehicleTypeOption('Cargo Van/L300', 'Medium to large sized breeds'),
];

class TransporterVerificationScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String phone; // already collected earlier, e.g. "+639XXXXXXXXX"

  const TransporterVerificationScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.phone,
  });

  @override
  State<TransporterVerificationScreen> createState() =>
      _TransporterVerificationScreenState();
}

class _TransporterVerificationScreenState
    extends State<TransporterVerificationScreen> {
  // Identity
  late final TextEditingController _nameCtrl;
  late final TextEditingController _mobileCtrl;
  File? _licenseFront;
  File? _licenseBack;

  // Vehicle & documents
  File? _portrait;
  String? _vehicleType;
  final _licensePlateCtrl = TextEditingController();
  File? _antiRabiesRecord;

  bool _submitting = false;
  String? _errorMessage;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
        text: '${widget.firstName} ${widget.lastName}'.trim());
    _mobileCtrl =
        TextEditingController(text: widget.phone.replaceFirst('+63', ''));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _mobileCtrl.dispose();
    _licensePlateCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ValueChanged<File> onPicked,
      {ImageSource source = ImageSource.gallery}) async {
    final xf = await _picker.pickImage(source: source, imageQuality: 80);
    if (xf != null) setState(() => onPicked(File(xf.path)));
  }

  Future<String?> _uploadImage(File file, String uid, String filename) async {
    try {
      final ref = FirebaseStorage.instance
          .ref('transporter_verifications/$uid/$filename');
      await ref.putFile(file);
      return await ref.getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    setState(() => _errorMessage = null);

    if (_nameCtrl.text.trim().isEmpty || _mobileCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please fill in all fields.');
      return;
    }
    if (_licenseFront == null || _licenseBack == null) {
      setState(() =>
      _errorMessage = "Please upload both sides of your driver's license.");
      return;
    }
    if (_portrait == null) {
      setState(() => _errorMessage = 'Please upload a portrait of yourself.');
      return;
    }
    if (_vehicleType == null) {
      setState(() => _errorMessage = 'Please select a vehicle type.');
      return;
    }
    if (_licensePlateCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your license plate number.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final licenseFrontUrl =
      await _uploadImage(_licenseFront!, uid, 'license_front.jpg');
      final licenseBackUrl =
      await _uploadImage(_licenseBack!, uid, 'license_back.jpg');
      final portraitUrl = await _uploadImage(_portrait!, uid, 'portrait.jpg');
      final antiRabiesUrl = _antiRabiesRecord != null
          ? await _uploadImage(_antiRabiesRecord!, uid, 'anti_rabies.jpg')
          : null;

      final verificationData = {
        'name': _nameCtrl.text.trim(),
        'mobileNumber': _mobileCtrl.text.trim(),
        'licenseFrontUrl': licenseFrontUrl,
        'licenseBackUrl': licenseBackUrl,
        'portraitUrl': portraitUrl,
        'vehicleType': _vehicleType,
        'licensePlate': _licensePlateCtrl.text.trim(),
        'antiRabiesUrl': antiRabiesUrl,
        'status': 'pending',
        'submittedAt': FieldValue.serverTimestamp(),
      };

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'transporterVerification': verificationData,
        'transporterVerificationStatus': 'pending',
      }, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('transporterApplications')
          .doc(uid)
          .set({
        ...verificationData,
        'uid': uid,
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const TransporterSuccessScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Something went wrong submitting your application. '
              'Please try again.';
          _submitting = false;
        });
      }
    }
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Sign Out?'),
        content: const Text(
            "You'll need to sign back in to finish identity verification later."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign Out')),
        ],
      ),
    );
    if (confirmed == true) {
      await AuthService().signOut();
      // AuthWrapper (main.dart) rebuilds off the auth-state stream and
      // routes to LoginScreen on its own — nothing to navigate to here.
    }
  }

  @override
  Widget build(BuildContext context) {
    // AuthWrapper (main.dart) makes this screen the app's root/home
    // whenever verification is incomplete, so on a fresh launch there is
    // nothing behind it to pop to. The old unconditional
    // Navigator.pop(context) was a no-op at best and, in profile/release
    // builds where assertion failures don't render the red debug screen,
    // could show as a blank/black frame instead. Only offer a real "back"
    // when there's somewhere to go back to (e.g. reached via push right
    // after onboarding in the same session); otherwise offer Sign Out as
    // the actual way out of an incomplete verification.
    final canGoBack = Navigator.canPop(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: Icon(canGoBack ? Icons.chevron_left : Icons.logout,
              color: AppColors.textPrimary, size: canGoBack ? 28 : 22),
          tooltip: canGoBack ? 'Back' : 'Sign Out',
          onPressed: _submitting
              ? null
              : (canGoBack ? () => Navigator.pop(context) : _confirmSignOut),
        ),
        centerTitle: true,
        title: Text('Identity Verification',
            style: GoogleFonts.tiltWarp(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              _fieldLabel('Name'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(hintText: 'Full name'),
              ),

              const SizedBox(height: 20),

              _fieldLabel('Mobile Number'),
              const SizedBox(height: 6),
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
                      controller: _mobileCtrl,
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

              const SizedBox(height: 20),

              _uploadBox(
                label: 'Portrait of Self',
                file: _portrait,
                onTap: () => _pickImage((f) => _portrait = f,
                    source: ImageSource.camera),
              ),

              const SizedBox(height: 20),

              _uploadBox(
                label: "Driver's License Front",
                file: _licenseFront,
                onTap: () => _pickImage((f) => _licenseFront = f),
              ),

              const SizedBox(height: 20),

              _uploadBox(
                label: "Driver's License Back",
                file: _licenseBack,
                onTap: () => _pickImage((f) => _licenseBack = f),
              ),

              const SizedBox(height: 20),

              _fieldLabel('Vehicle Type'),
              const SizedBox(height: 6),
              _VehicleTypeDropdown(
                value: _vehicleType,
                onChanged: (v) => setState(() => _vehicleType = v),
              ),

              const SizedBox(height: 20),

              _fieldLabel('License Plate Entry'),
              const SizedBox(height: 6),
              TextFormField(
                controller: _licensePlateCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'e.g. ABC 1234'),
              ),

              const SizedBox(height: 20),

              _uploadBox(
                label: 'Anti-Rabies Vaccination Record (Optional)',
                file: _antiRabiesRecord,
                onTap: () => _pickImage((f) => _antiRabiesRecord = f),
              ),
              const SizedBox(height: 8),
              Text(
                'Optional: You may upload your anti-rabies vaccination '
                    'record. While not required, we strongly recommend that '
                    'all pet transporters have a valid anti-rabies '
                    'vaccination, as transporting animals may involve '
                    'unexpected bites or scratches that could expose them '
                    'to rabies. Being vaccinated helps protect both you and '
                    'the animals during transport.',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary),
              ),

              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
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
                                fontSize: 13, color: Colors.red.shade700)),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              Center(
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    fixedSize:
                    Size(MediaQuery.of(context).size.width * 0.55, 50),
                  ),
                  child: _submitting
                      ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.textPrimary))
                      : Text('Submit',
                      style: Theme.of(context).textTheme.headlineLarge),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _VehicleTypeDropdown extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const _VehicleTypeDropdown({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: const InputDecoration(
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(vertical: 14),
          ),
          hint: Text('Select vehicle type',
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textSecondary)),
          items: _vehicleTypeOptions
              .map((opt) => DropdownMenuItem<String>(
            value: opt.type,
            child: Row(
              children: [
                Text(opt.type,
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const Spacer(),
                Flexible(
                  child: Text(opt.description,
                      textAlign: TextAlign.right,
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ),
              ],
            ),
          ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

Widget _fieldLabel(String text) => Text(
  text,
  style: GoogleFonts.tiltWarp(
      fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
);

Widget _uploadBox({
  required String label,
  required File? file,
  required VoidCallback onTap,
}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _fieldLabel(label),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          height: 130,
          decoration: BoxDecoration(
            color: AppColors.slaterspwn.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.4)),
          ),
          child: file != null
              ? ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(file, fit: BoxFit.cover),
          )
              : const Center(
            child: Icon(Icons.add_a_photo_outlined,
                size: 28, color: AppColors.textSecondary),
          ),
        ),
      ),
    ],
  );
}