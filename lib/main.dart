import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/features/organization/organization_member_pending_page.dart';
import 'package:respawnd1/features/organization/signup/organization_about_screen.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_pending_page.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_screen.dart';
import 'package:respawnd1/features/pettransporter/service_screen.dart';
import 'package:respawnd1/features/pettransporter/transporter_verification_screen.dart';
import 'package:respawnd1/firebase_options.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/userauth/login_screen.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/adminhome/adminhome_screen.dart';
import 'package:respawnd1/features/volunteerhome/volhome_screen.dart';
import 'package:respawnd1/features/userauth/details_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/push_token_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  GoogleFonts.config.allowRuntimeFetching = false;

  runApp(const ProviderScope(child: ResPAWndApp()));
}

class ResPAWndApp extends StatelessWidget {
  const ResPAWndApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResPAWnd',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(), // use this instead of LoginScreen directly
    );
  }
}

// Automatically routes user based on login state
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _cachedUid;
  Future<DocumentSnapshot>? _userDocFuture;

  Future<DocumentSnapshot> _userDocFor(String uid) {
    if (_cachedUid != uid || _userDocFuture == null) {
      _cachedUid = uid;
      _userDocFuture =
          FirebaseFirestore.instance.collection('users').doc(uid).get();
    }
    return _userDocFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Still loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Not logged in
        if (!snapshot.hasData) {
          _cachedUid = null;
          _userDocFuture = null;
          return const LoginScreen();
        }


        PushTokenService.register();

        // Logged in — check if they need onboarding
        return FutureBuilder<DocumentSnapshot>(
          future: _userDocFor(snapshot.data!.uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final data = userSnapshot.data?.data() as Map<String, dynamic>?;
            final role = data?['role'] ?? '';

            // New user or social sign-in with no role yet
            if (role.isEmpty) {
              return const EnterDetailsScreen();
            }

            // Existing user with role — route based on role
            switch (role) {
              case 'ngo_staff':
              case 'admin':
                return const AdminHomeScreen();
              case 'pet_transporter':
                final verificationStatus =
                    data?['transporterVerificationStatus'] as String? ?? '';
                if (verificationStatus.isEmpty) {
                  return TransporterVerificationScreen(
                    firstName: data?['firstName'] as String? ?? '',
                    lastName: data?['lastName'] as String? ?? '',
                    phone: data?['phone'] as String? ?? '',
                  );
                }
                return const ServiceScreen();
              case 'rescue_volunteer':
                return const ServiceScreen();
              case 'organization':
                final organizationId = data?['organizationId'] as String?;
                if (organizationId == null || organizationId.isEmpty) {
                  // Role was saved but the draft org doc never got created
                  // (interrupted session) — About Your Organization always
                  // resumes an existing draft rather than creating a new
                  // one, so this is safe to send them back to.
                  return const OrganizationAboutScreen();
                }
                return OrganizationRoleRouter(organizationId: organizationId);
              // Organization Invitations spec §7 — a simplified "Organization
              // Member" account: no org-creation/verification wizard at all.
              // Once linked to an organization (by accepting an invitation)
              // it hands off to the SAME OrganizationRoleRouter the
              // 'organization' (admin/creator) role above uses, so a member
              // reaches the exact same operational shell as any other org
              // account — no role-based module restrictions added yet
              // (spec §1).
              case 'organization_member':
                final organizationId = data?['organizationId'] as String?;
                if (organizationId == null || organizationId.isEmpty) {
                  return const OrganizationMemberPendingPage();
                }
                return OrganizationRoleRouter(organizationId: organizationId);
              case 'general':
              default:
                return const HomeScreen();
            }
          },
        );
      },
    );
  }
}

/// Second-level routing for role == 'organization' — reads the org doc's
/// verificationStatus and picks the right step of the signup pipeline
/// (draft still needs documents uploaded; pending/rejected/requires_changes
/// show the status page; approved reaches the admin shell), mirroring the
/// existing pet_transporter case's use of transporterVerificationStatus
/// just one Firestore hop further (organization, not the user doc itself).
class OrganizationRoleRouter extends StatelessWidget {
  final String organizationId;
  const OrganizationRoleRouter({super.key, required this.organizationId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('organizations').doc(organizationId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final status = OrgVerificationStatus.fromName(data?['verificationStatus'] as String?);
        switch (status) {
          case OrgVerificationStatus.approved:
            return const AdminHomeScreen();
          case OrgVerificationStatus.draft:
            return OrganizationVerificationScreen(organizationId: organizationId);
          case OrgVerificationStatus.pending:
          case OrgVerificationStatus.rejected:
          case OrgVerificationStatus.requiresChanges:
            return OrganizationVerificationPendingPage(organizationId: organizationId);
        }
      },
    );
  }
}