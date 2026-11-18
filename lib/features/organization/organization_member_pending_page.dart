import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/organization/staff_members_page.dart';
import 'package:respawnd1/main.dart';
import 'package:respawnd1/core/widgets/delete_account.dart';

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
/// appears, the navigation stack is reset to AuthWrapper, which routes an
/// 'organization_member' with an organization to [OrganizationRoleRouter] —
/// the same operational shell as any other org account (spec §1).
/// `_navigated` guards this hand-off to fire exactly once.
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
          // Reset the whole stack to AuthWrapper, which now routes this
          // member to their organization. Replacing only the top route left
          // the invitations screens underneath (swiping back returned there).
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            appNavigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const AuthWrapper()),
              (route) => false,
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
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: AppColors.background),
                onSelected: (_) => showDeleteAccountFlow(context),
                itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Delete account'))],
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: AppColors.background),
                tooltip: 'Log out',
                onPressed: () async {
                  await AuthService().signOut();
                  appNavigatorKey.currentState?.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const AuthWrapper()),
                    (route) => false,
                  );
                },
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
                    style: AppButtons.primary,
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
