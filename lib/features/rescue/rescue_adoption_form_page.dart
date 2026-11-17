import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_adoption.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Rescue gaps 6/10, step 1: the adoption request for a rescued animal, from
/// the reporter who said they want to adopt it or the user who registered
/// interest on Track Case. Saves `adoptions/{id}` with
/// `source: 'rescue_case'` and status pending; the organization confirms it
/// on Rescue Details. All three agreements (vet fees, adopter obligations,
/// pickup window) must be accepted.
class RescueAdoptionFormPage extends StatefulWidget {
  const RescueAdoptionFormPage({super.key, required this.caseId, required this.caseData});

  final String caseId;
  final Map<String, dynamic> caseData;

  @override
  State<RescueAdoptionFormPage> createState() => _RescueAdoptionFormPageState();
}

class _RescueAdoptionFormPageState extends State<RescueAdoptionFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _otherPets = TextEditingController();
  final _caretaker = TextEditingController();
  String? _homeType;
  bool _landlordAllowsPets = false;
  final Map<String, bool> _agreed = {for (final (k, _, _) in kRescueAdoptionAgreements) k: false};
  bool _saving = false;

  static const _homeTypes = ['Own house', 'Renting', 'Living with family', 'Other'];

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final u = (await FirebaseFirestore.instance.collection('users').doc(user.uid).get()).data() ?? const {};
    if (!mounted) return;
    setState(() {
      _name.text = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.trim();
      _phone.text = (u['phone'] ?? u['phoneNumber'] ?? '').toString();
      _email.text = user.email ?? (u['email'] ?? '').toString();
      _address.text = (u['address'] ?? '').toString();
    });
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address, _otherPets, _caretaker]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _allAgreed => _agreed.values.every((v) => v);

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_allAgreed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnackBar('Accept all three agreements to send your request.', kind: AppMessageKind.error));
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _saving = true);
    try {
      final c = widget.caseData;
      final orgId = (c['organizationId'] as String?) ?? '';
      final species = (c['animalType'] ?? (c['animals'] is List && (c['animals'] as List).isNotEmpty
          ? ((c['animals'] as List).first as Map)['species']
          : null) ??
          'Rescued animal')
          .toString();
      final now = Timestamp.now();
      await FirebaseFirestore.instance.collection('adoptions').add({
        'source': kRescueAdoptionSource,
        'caseId': widget.caseId,
        // Unowned report: stamped when an organization accepts the case
        // (stampRescueAdoptionOrganization in functions/rescue_adoption.js).
        if (orgId.isNotEmpty) 'organizationId': orgId,
        'status': 'pending',
        'personal': {
          'adopterId': uid,
          'adopterName': _name.text.trim(),
          'adopterPhone': _phone.text.trim(),
          'adopterEmail': _email.text.trim(),
          'animalName': 'Rescue #${widget.caseId.substring(0, 6)} ($species)',
        },
        'rescueApplication': {
          'address': _address.text.trim(),
          'homeType': _homeType,
          'landlordAllowsPets': _homeType == 'Renting' ? _landlordAllowsPets : null,
          'otherPets': _otherPets.text.trim(),
          'caretaker': _caretaker.text.trim(),
          'role': c['reporterId'] == uid ? 'reporter' : 'interested user',
        },
        'agreement': {
          for (final (k, _, _) in kRescueAdoptionAgreements) k: true,
          'acceptedAt': now,
          'pickupWindowHours': kAdopterPickupWindow.inHours,
        },
        'createdAt': FieldValue.serverTimestamp(),
        'statusHistory': [
          {'status': 'Adoption request sent for a rescued animal.', 'timestamp': now},
        ],
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          'Request sent. The organization will confirm it and tell you when the animal is ready for pickup.',
          kind: AppMessageKind.success));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnackBar('Could not send your request: $e', kind: AppMessageKind.error));
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
    isDense: true,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Adopt this rescue', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text(
              'The organization reviews your request and confirms you as the adopter. You will be told when the animal '
                  'is ready for pickup.',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _name, decoration: _dec('Full name'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            TextFormField(
              controller: _phone,
              decoration: _dec('Mobile number'),
              keyboardType: TextInputType.phone,
              validator: (v) => AppValidators.phFlexiblePhone(v, required: true),
            ),
            TextFormField(
              controller: _email,
              decoration: _dec('Email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => AppValidators.email(v, required: false),
            ),
            TextFormField(controller: _address, decoration: _dec('Home address'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _homeType,
              decoration: _dec('Home'),
              items: [for (final h in _homeTypes) DropdownMenuItem(value: h, child: Text(h))],
              onChanged: (v) => setState(() => _homeType = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            if (_homeType == 'Renting')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _landlordAllowsPets,
                onChanged: (v) => setState(() => _landlordAllowsPets = v),
                title: Text('My landlord allows pets', style: GoogleFonts.zain(fontSize: 14)),
              ),
            TextFormField(controller: _otherPets, decoration: _dec('Other pets at home (or "None")'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            TextFormField(controller: _caretaker, decoration: _dec('Who will mainly care for the animal'),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
            const SizedBox(height: 18),
            Text('Agreements', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            for (final (key, title, body) in kRescueAdoptionAgreements)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _agreed[key],
                onChanged: (v) => setState(() => _agreed[key] = v ?? false),
                title: Text(title, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
                subtitle: Text(body, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _saving || !_allAgreed ? null : _submit,
              style: AppButtons.primary,
              child: _saving
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text('Send adoption request', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}
