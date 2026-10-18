import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_screen.dart';

/// Step 1 of the Organization signup flow (spec §2): collects the fields
/// the draft `organizations/{orgId}` doc needs before verification uploads
/// can start. Reopening this screen (back navigation, app restart) resumes
/// the SAME draft doc via OrganizationRepository.currentOrganizationFor —
/// it is never possible to end up with two organization documents for one
/// account from this screen.
class OrganizationAboutScreen extends StatefulWidget {
  const OrganizationAboutScreen({super.key});

  @override
  State<OrganizationAboutScreen> createState() => _OrganizationAboutScreenState();
}

class _OrganizationAboutScreenState extends State<OrganizationAboutScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _repo = OrganizationRepository();

  bool _loadingDraft = true;
  bool _submitting = false;
  List<OrgDuplicateMatch> _acknowledgedWarnings = const [];

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final existing = await _repo.currentOrganizationFor(uid);
      if (existing != null && mounted) {
        final data = existing.data()!;
        _nameController.text = data['name'] as String? ?? '';
        _phoneController.text = (data['contactNumber'] as String?) ?? (data['phone'] as String?) ?? '';
        _addressController.text = data['location'] as String? ?? '';
      }
    }
    if (mounted) setState(() => _loadingDraft = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _normalizeWhitespace(String v) => v.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your session expired. Please sign in again.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    final name = _normalizeWhitespace(_nameController.text);
    final phone = _normalizeWhitespace(_phoneController.text);
    final address = _normalizeWhitespace(_addressController.text);

    setState(() => _submitting = true);
    try {
      final duplicates = await _repo.findPossibleDuplicates(name: name, address: address, contactNumber: phone);
      final exact = duplicates.where((d) => d.exact).toList();
      if (exact.isNotEmpty) {
        if (mounted) {
          setState(() => _submitting = false);
          _showDuplicateBlockedDialog(exact.first.name);
        }
        return;
      }
      final possible = duplicates.where((d) => !_acknowledgedWarnings.any((a) => a.organizationId == d.organizationId)).toList();
      if (possible.isNotEmpty) {
        if (mounted) setState(() => _submitting = false);
        final proceed = await _showPossibleDuplicateDialog(possible.first.name);
        if (proceed != true) return;
        _acknowledgedWarnings = duplicates;
        setState(() => _submitting = true);
      }

      final orgId = await _repo.createOrUpdateDraft(uid: uid, name: name, contactNumber: phone, address: address);
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => OrganizationVerificationScreen(organizationId: orgId)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save your organization: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  void _showDuplicateBlockedDialog(String existingName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Organization may already be registered', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
          'An organization matching this name, address, and contact number is already registered ("$existingName"). '
          'If this is your organization, contact support instead of creating a second account.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }

  Future<bool?> _showPossibleDuplicateDialog(String similarName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Possible existing organization', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
          'An organization with a similar name or address ("$similarName") already exists. If this isn\'t a duplicate, '
          'you can continue — our verification review will confirm this before approval.',
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Go Back')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
            child: const Text('Continue Anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        title: Text('About Your Organization', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: _loadingDraft
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('Tell us about your organization',
                        style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text('This information is reviewed as part of verification.',
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    _label('Organization Name'),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(hintText: 'e.g. PAWS Manila'),
                      validator: (v) => AppValidators.nonEmptyText(v, fieldName: 'Organization name'),
                    ),
                    const SizedBox(height: 16),
                    _label('Official Contact Number'),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: AppInputFormatters.phoneFlexible,
                      decoration: const InputDecoration(hintText: '09171234567'),
                      validator: (v) => AppValidators.phFlexiblePhone(v),
                    ),
                    const SizedBox(height: 16),
                    _label('Organization Address'),
                    TextFormField(
                      controller: _addressController,
                      maxLines: 2,
                      decoration: const InputDecoration(hintText: 'Street, Barangay, City'),
                      validator: (v) => AppValidators.nonEmptyText(v, fieldName: 'Address'),
                    ),
                    const SizedBox(height: 4),
                    Text('You can pin the exact location on a map later from Organization Profile.',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.yellowrspwn,
                          foregroundColor: AppColors.textPrimary,
                          disabledBackgroundColor: AppColors.slaterspwn,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: _submitting
                            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                            : Text('Next', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
