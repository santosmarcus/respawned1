import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/features/adminhome/dashboard/adminhome_screen.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_screen.dart';

/// Step 3 of the Organization signup flow (spec §5) — a live status view
/// (StreamBuilder, not a one-time read) over the org doc's
/// `verificationStatus`. Approval itself happens outside this app (manual
/// Firestore/console review, per spec §5's own allowance — there is no
/// verification-admin interface in this codebase yet) — this page only
/// ever reflects whatever that external decision already wrote, and never
/// auto-navigates the instant status changes: even on `approved`, the
/// admin still presses "Continue" themselves, consistent with this app's
/// existing rule against reactive auto-navigation from a stream.
class OrganizationVerificationPendingPage extends StatelessWidget {
  final String organizationId;
  const OrganizationVerificationPendingPage({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        automaticallyImplyLeading: false,
        title: Text('Verification Status', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('organizations').doc(organizationId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !(snapshot.data?.exists ?? false)) {
            return Center(
              child: Text('Could not load organization verification status.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            );
          }
          final data = snapshot.data!.data()!;
          final status = OrgVerificationStatus.fromName(data['verificationStatus'] as String?);
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Center(child: _content(context, status, data)),
          );
        },
      ),
    );
  }

  Widget _content(BuildContext context, OrgVerificationStatus status, Map<String, dynamic> data) {
    switch (status) {
      case OrgVerificationStatus.pending:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hourglass_top_outlined, size: 56, color: AppColors.yellowrspwn),
            const SizedBox(height: 16),
            Text('Verification Pending', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text(
              'Submission successful. Your organization is being reviewed.\nYou will be notified once a decision is available.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            ),
          ],
        );
      case OrgVerificationStatus.approved:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 56, color: AppColors.greenrspwn),
            const SizedBox(height: 16),
            Text('Organization Approved', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text('Your organization has been verified.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                  context, MaterialPageRoute(builder: (_) => const AdminHomeScreen()), (route) => false),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Continue', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ],
        );
      case OrgVerificationStatus.rejected:
        final reason = data['verificationRejectionReason'] as String?;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_outlined, size: 56, color: Color(0xFFE05353)),
            const SizedBox(height: 16),
            Text('Verification Rejected', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text(reason?.isNotEmpty == true ? reason! : 'No reason was provided.',
                textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
          ],
        );
      case OrgVerificationStatus.requiresChanges:
        final note = data['verificationRejectionReason'] as String?;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.edit_note_outlined, size: 56, color: Color(0xFFE0A353)),
            const SizedBox(height: 16),
            Text('Changes Requested', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 10),
            Text(note?.isNotEmpty == true ? note! : 'The reviewer requested changes to your submitted documents.',
                textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => OrganizationVerificationScreen(organizationId: organizationId))),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Update Documents', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ],
        );
      case OrgVerificationStatus.draft:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined, size: 56, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text('Verification documents have not been submitted', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pushReplacement(
                  context, MaterialPageRoute(builder: (_) => OrganizationVerificationScreen(organizationId: organizationId))),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Continue Verification', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ],
        );
    }
  }
}
