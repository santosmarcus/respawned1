import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_screen.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';

/// Step 1 of the Organization signup flow (spec §2): collects the
/// organization's details. Nothing is saved here: Next carries them to the
/// verification step, and the organization is only written when its
/// documents are submitted, so an abandoned signup leaves no organization
/// behind. A draft left by a submit that failed part-way is reloaded here
/// and reused (OrganizationRepository.currentOrganizationFor), never
/// duplicated.
///
/// [kind] independent: the same steps for an independent rescuer (one person
/// or a small team). Null resumes whatever was started: the draft's kind,
/// else `users/{uid}.signupKind` (set when Independent Rescuer was picked).
class OrganizationAboutScreen extends StatefulWidget {
  const OrganizationAboutScreen({super.key, this.kind});

  final OrgKind? kind;

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
  // A draft from an earlier submit that failed part-way (null normally).
  String? _draftOrganizationId;
  // Map pin for the address (required). Saved as the shelter location.
  ClinicSearchResult? _pin;
  bool _showPinError = false;
  bool _submitting = false;
  List<OrgDuplicateMatch> _acknowledgedWarnings = const [];
  late OrgKind _kind = widget.kind ?? OrgKind.shelter;
  bool get _independent => _kind == OrgKind.independent;

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // Prefilling is a convenience: if it can't load (offline), show an
    // empty form rather than a spinner with no way out.
    if (uid != null) {
      DocumentSnapshot<Map<String, dynamic>>? existing;
      try {
        existing = await _repo.currentOrganizationFor(uid);
      } catch (e) {
        debugPrint('[OrganizationAbout] draft load failed: $e');
      }
      if (existing == null && widget.kind == null) {
        try {
          final user = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          _kind = OrgKind.fromName(user.data()?['signupKind'] as String?);
        } catch (_) {}
      }
      if (existing != null && mounted) {
        _draftOrganizationId = existing.id;
        final data = existing.data()!;
        _kind = OrgKind.fromName(data['kind'] as String?);
        if (_kind == OrgKind.independent) {
          try {
            final home = await _repo.homeLocation(existing.id);
            if (home != null) {
              _pin = ClinicSearchResult(placeId: '', name: home.name, address: home.name, lat: home.lat, lng: home.lng);
            }
          } catch (_) {}
        }
        _nameController.text = data['name'] as String? ?? '';
        _phoneController.text = (data['contactNumber'] as String?) ?? (data['phone'] as String?) ?? '';
        _addressController.text = data['location'] as String? ?? '';
        final lat = (data['shelterLat'] as num?)?.toDouble();
        final lng = (data['shelterLng'] as num?)?.toDouble();
        if (lat != null && lng != null) {
          _pin = ClinicSearchResult(
            placeId: data['shelterPlaceId'] as String? ?? '',
            name: data['shelterName'] as String? ?? '',
            address: data['shelterAddress'] as String? ?? _addressController.text,
            lat: lat,
            lng: lng,
          );
        }
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

  Future<void> _pickPin() async {
    final result = await Navigator.push<ClinicSearchResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ShelterLocationPickerPage.pick(
          title: _independent ? 'Pin Home / Foster Location' : 'Pin Organization Address',
          emptyHint: _independent
              ? 'Search for where you keep rescued animals. Only your team sees this.'
              : "Search for your organization's address.",
          initialName: _pin?.name,
          initialAddress: _pin?.address ?? _addressController.text,
          initialPlaceId: _pin?.placeId,
          initialLat: _pin?.lat,
          initialLng: _pin?.lng,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pin = result;
      _showPinError = false;
      // Fill the address from the pin when it's empty; keep what they typed.
      // Not for an independent rescuer: their address is a general area and
      // the pin stays private.
      if (!_independent && _addressController.text.trim().isEmpty) {
        _addressController.text = result.address.isNotEmpty ? result.address : result.name;
      }
    });
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState?.validate() ?? false;
    if (_pin == null) setState(() => _showPinError = true);
    if (_submitting || !formOk || _pin == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Your session expired. Please sign in again.', kind: AppMessageKind.error),
      );
      return;
    }

    final name = _normalizeWhitespace(_nameController.text);
    final phone = _normalizeWhitespace(_phoneController.text);
    final address = _normalizeWhitespace(_addressController.text);

    setState(() => _submitting = true);
    try {
      final duplicates = await _repo.findPossibleDuplicates(
        name: name,
        address: address,
        contactNumber: phone,
        excludeOrganizationId: _draftOrganizationId,
      );
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

      if (!mounted) return;
      setState(() => _submitting = false);
      // Pushed (not replaced) so Back returns here to edit the details.
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrganizationVerificationScreen.signup(
            details: OrganizationSignupDetails(
              name: name,
              contactNumber: phone,
              address: address,
              pin: _pin!,
              kind: _kind,
            ),
            draftOrganizationId: _draftOrganizationId,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not check your organization details: $e', kind: AppMessageKind.error),
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
    return showConfirmActionDialog(context, title: 'Possible existing organization', message: 'An organization with a similar name or address ("$similarName") already exists. If this isn\'t a duplicate, '
          'you can continue — our verification review will confirm this before approval.', confirmLabel: 'Continue Anyway', cancelLabel: 'Go Back');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        title: Text(_independent ? 'About You as a Rescuer' : 'About Your Organization', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
        iconTheme: const IconThemeData(color: AppColors.background),
        actions: const [SignupLogOutButton()],
      ),
      body: _loadingDraft
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(_independent ? 'Tell us about your rescue work' : 'Tell us about your organization',
                        style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Text(
                        _independent
                            ? 'Independent rescuers take nearby cases and referrals, keep animal records and can '
                                'transport rescues themselves. A system admin reviews this before you start.'
                            : 'This information is reviewed as part of verification.',
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 24),
                    _label(_independent ? 'Rescuer or Team Name' : 'Organization Name'),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(hintText: _independent ? "e.g. Ana's Cat Rescue" : 'e.g. PAWS Manila'),
                      validator: (v) => AppValidators.nonEmptyText(v, fieldName: _independent ? 'Name' : 'Organization name'),
                    ),
                    const SizedBox(height: 16),
                    _label(_independent ? 'Contact Number' : 'Official Contact Number'),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      inputFormatters: AppInputFormatters.phoneFlexible,
                      decoration: const InputDecoration(hintText: '09171234567'),
                      validator: (v) => AppValidators.phFlexiblePhone(v),
                    ),
                    const SizedBox(height: 16),
                    _label(_independent ? 'Area You Cover (shown on your profile)' : 'Organization Address'),
                    TextFormField(
                      controller: _addressController,
                      maxLines: _independent ? 1 : 2,
                      decoration: InputDecoration(hintText: _independent ? 'Barangay, City' : 'Street, Barangay, City'),
                      validator: (v) => AppValidators.nonEmptyText(v, fieldName: _independent ? 'Area' : 'Address'),
                    ),
                    const SizedBox(height: 10),
                    _pinTile(),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        style: AppButtons.primary,
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

  Widget _pinTile() {
    final pin = _pin;
    final borderColor = _showPinError ? Theme.of(context).colorScheme.error : AppColors.greenrspwn;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: _submitting ? null : _pickPin,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: Row(
              children: [
                Icon(pin == null ? Icons.add_location_alt_outlined : Icons.location_on, color: AppColors.textPrimary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          pin == null
                              ? (_independent ? 'Pin home / foster location (private)' : 'Pin address on map')
                              : (_independent ? 'Home pinned (only your team sees it)' : 'Location pinned'),
                          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      if (pin != null)
                        Text(
                          pin.address.isNotEmpty ? pin.address : pin.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                Text(pin == null ? 'Set' : 'Change',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
        if (_showPinError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(_independent ? 'Pin where you keep rescued animals.' : "Pin your organization's address on the map.",
                style: GoogleFonts.zain(fontSize: 12, color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );
}
