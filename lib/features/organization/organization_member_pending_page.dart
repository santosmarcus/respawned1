import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/organization/staff_members_page.dart';
import 'package:respawnd1/main.dart';

/// Landing page for the "Organization Member" signup path (Organization
/// Invitations spec §7/§8) — a simplified account with no org-creation/
/// verification wizard at all, reached whenever
/// `users/{uid}.role == 'organization_member'` and no `organizationId` is
/// set yet. Deliberately never creates a placeholder/empty organization
/// document — just an honest "nothing yet" state plus the same Staff
/// Members / My Pending Invitations page every account uses to accept or
/// reject an invitation.
///
/// Reactive (a `StreamBuilder` over `users/{uid}`, not a one-shot read) so
/// accepting an invitation on Staff Members and returning here picks up the
/// new `organizationId` immediately — no app restart required. Once it
/// appears, this hands off to the SAME [OrganizationRoleRouter]
/// `main.dart`'s AuthWrapper already uses for the 'organization' (admin)
/// role, so a joined member reaches the exact same operational shell as
/// any other org account, with no role-based module restrictions added
/// (spec §1). `_navigated` guards this hand-off to fire exactly once, so a
/// rebuild from the same stream emission can never push a second route.
class OrganizationMemberPendingPage extends StatefulWidget {
  const OrganizationMemberPendingPage({super.key});

  @override
  State<OrganizationMemberPendingPage> createState() => _OrganizationMemberPendingPageState();
}

class _OrganizationMemberPendingPageState extends State<OrganizationMemberPendingPage> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snapshot) {
        final organizationId = snapshot.data?.data()?['organizationId'] as String?;
        if (organizationId != null && organizationId.isNotEmpty && !_navigated) {
          _navigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => OrganizationRoleRouter(organizationId: organizationId)),
            );
          });
        }
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            title: Text('Organization', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
            actions: [
              IconButton(
                icon: const Icon(Icons.people_outline, color: AppColors.background),
                tooltip: 'Staff Members',
                onPressed: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffMembersPage(organizationId: null))),
              ),
            ],
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.apartment_outlined, size: 40, color: AppColors.textSecondary),
                  const SizedBox(height: 16),
                  Text('No organization joined yet.', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(
                    'Accept an organization invitation to get started.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffMembersPage(organizationId: null))),
                    icon: const Icon(Icons.mail_outline),
                    label: const Text('View My Invitations'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
