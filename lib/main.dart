import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
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
import 'package:respawnd1/features/userauth/details_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/push_token_service.dart';
import 'package:respawnd1/features/organization/organization_member_pending_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  GoogleFonts.config.allowRuntimeFetching = false;

  /*if (kIsWeb) {
    await FacebookAuth.instance.webAndDesktopInitialize(
      appId: "YOUR_FACEBOOK_APP_ID",
      cookie: true,
      xfbml: true,
      version: "v19.0",
    );
  }*/


  runApp(const ProviderScope(child: ResPAWndApp()));
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class ResPAWndApp extends StatefulWidget {
  const ResPAWndApp({super.key});

  @override
  State<ResPAWndApp> createState() => _ResPAWndAppState();
}

class _ResPAWndAppState extends State<ResPAWndApp> {
  StreamSubscription<User?>? _authSub;
  String? _signedInUid;

  @override
  void initState() {
    super.initState();
    _signedInUid = FirebaseAuth.instance.currentUser?.uid;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      final previousUid = _signedInUid;
      _signedInUid = user?.uid;
      if (previousUid != null && previousUid != user?.uid) {
        appNavigatorKey.currentState?.pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const AuthWrapper(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
              (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResPAWnd',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      navigatorKey: appNavigatorKey,
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
          return const LoginScreen();
        }

        PushTokenService.register();

        final uid = snapshot.data!.uid;
        return _UserDocRouter(key: ValueKey(uid), uid: uid);
      },
    );
  }
}

class _UserDocRouter extends StatefulWidget {
  final String uid;
  const _UserDocRouter({super.key, required this.uid});

  @override
  State<_UserDocRouter> createState() => _UserDocRouterState();
}

class _UserDocRouterState extends State<_UserDocRouter> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userDoc = _subscribe();

  Stream<DocumentSnapshot<Map<String, dynamic>>> _subscribe() =>
      FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(includeMetadataChanges: true);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (context, userSnapshot) {
        // A failed read says nothing about whether this user finished
        // onboarding — don't send an existing user back through it.
        if (userSnapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Could not load your profile.'),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _userDoc = _subscribe()),
                    child: const Text('Retry'),
                  ),
                  TextButton(
                    onPressed: () => AuthService().signOut(),
                    child: const Text('Sign out'),
                  ),
                ],
              ),
            ),
          );
        }

        final doc = userSnapshot.data;
        // Waiting, or an offline cache miss: "no document in the local
        // cache" isn't "new user", so wait for the server's answer.
        if (doc == null || (!doc.exists && doc.metadata.isFromCache)) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = doc.data();
        final role = data?['role'] as String? ?? '';

        // Onboarding not finished yet (new user, or social sign-in with
        // no role) — only these users see the onboarding questions.
        if (!AuthService.hasCompletedOnboarding(data)) {
          if (doc.metadata.isFromCache || doc.metadata.hasPendingWrites) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
            );
          }
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
  }
}

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
        // Organization Invitations spec §3/§7 — an invited admin or member
        // joining an EXISTING organization must never be routed into the
        // owner's document-upload wizard just because that org hasn't
        // submitted verification yet. Only the org's own owner/creator
        // (the account `createOrUpdateDraft` set as `ownerId`) goes through
        // the draft upload step; everyone else lands straight in the admin
        // shell regardless of the shared org doc's verification progress.
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        final isOwner = currentUid != null && currentUid == data?['ownerId'];
        if (status == OrgVerificationStatus.draft && !isOwner) {
          return const AdminHomeScreen();
        }
        switch (status) {
          case OrgVerificationStatus.approved:
          case OrgVerificationStatus.pending:
            return const AdminHomeScreen();
          case OrgVerificationStatus.draft:
            return OrganizationVerificationScreen(organizationId: organizationId);
          case OrgVerificationStatus.rejected:
          case OrgVerificationStatus.requiresChanges:
            return OrganizationVerificationPendingPage(organizationId: organizationId);
        }
      },
    );
  }
}