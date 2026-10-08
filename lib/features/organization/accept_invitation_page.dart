import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_invitation_repository.dart';
import 'package:respawnd1/main.dart';

/// Development-only invitation acceptance (spec §12's explicit fallback):
/// there is no email-delivery or deep-link backend in this codebase, so
/// this screen is reached by manually entering/pasting the invitation ID
/// a Staff Members admin copied via "Copy Dev Link" — never presented as a
/// real accept-invitation email flow. Still enforces every real acceptance
/// rule server logic would (email match, pending + unexpired, single-use
/// transaction) — see OrganizationInvitationRepository.acceptInvitation.
class AcceptInvitationPage extends StatefulWidget {
  const AcceptInvitationPage({super.key});

  @override
  State<AcceptInvitationPage> createState() => _AcceptInvitationPageState();
}

class _AcceptInvitationPageState extends State<AcceptInvitationPage> {
  final _idController = TextEditingController();
  final _repo = OrganizationInvitationRepository();
  bool _submitting = false;

  @override
  void dispose() {
    _idController.dispose();
    super.dispose();
  }

  Future<void> _accept() async {
    if (_submitting) return;
    final invitationId = _idController.text.trim();
    if (invitationId.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in with an email/password or Google account first.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await _repo.acceptInvitation(invitationId: invitationId, uid: user!.uid, signedInEmail: user.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invitation accepted.')));
        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthWrapper()), (route) => false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not accept invitation: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        title: Text('Accept Invitation', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFE0A353).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
              child: Text(
                'Development-only: this app does not yet send invitation emails. Paste the invitation ID your organization admin shared with you.',
                style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFF9C6B10)),
              ),
            ),
            const SizedBox(height: 20),
            Text('Invitation ID', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(controller: _idController, decoration: const InputDecoration(hintText: 'Paste invitation ID')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _accept,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _submitting
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Accept Invitation', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
