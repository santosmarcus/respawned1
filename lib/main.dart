import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
//import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
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
import 'package:respawnd1/features/systemadmin/system_admin_home_screen.dart';
import 'package:respawnd1/features/systemadmin/user_directory.dart' show kSystemAdminRole;
import 'package:respawnd1/features/adminhome/dashboard/adminhome_screen.dart';
import 'package:respawnd1/features/carer/carer_home_screen.dart';
import 'package:respawnd1/features/userauth/details_screen.dart';
import 'package:respawnd1/features/userauth/verify_email_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/services/notification_service.dart';
import 'package:respawnd1/core/services/geofence_service.dart';
import 'package:respawnd1/features/generalhome/push_token_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  GoogleFonts.config.allowRuntimeFetching = false;

  // Foreground push display + notification tap routing (geofence alerts).
  await NotificationService.init(appNavigatorKey);

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

/// The account Firebase restored from disk when the app launched, until it
/// signs out. A restored session that never finished onboarding is signed
/// out so the app opens on the login screen instead of "Your Details"; an
/// account that signs in during this run continues onboarding as usual.
String? _restoredUnfinishedUid = FirebaseAuth.instance.currentUser?.uid;

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
          _restoredUnfinishedUid = null;
          return const LoginScreen();
        }

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

class _UserDocRouterState extends State<_UserDocRouter> with WidgetsBindingObserver {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _userDoc = _subscribe();
  bool _signedInServicesStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Refresh the saved location + nearby case geofences whenever the app
  // comes back to the foreground (throttled inside GeofenceService).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _signedInServicesStarted) {
      GeofenceService.sync();
    }
  }

  /// Runs once per sign-in, after onboarding is complete: saves this
  /// device's push token (users/{uid}.fcmToken — every Cloud Function
  /// notification depends on it), starts geofencing, and lets a tapped
  /// notification open its screen.
  void _startSignedInServices() {
    if (_signedInServicesStarted) return;
    _signedInServicesStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PushTokenService.register();
      GeofenceService.start(widget.uid);
      NotificationService.markRouterReady();
    });
  }
  Stream<DocumentSnapshot<Map<String, dynamic>>> _subscribe() =>
      FirebaseFirestore.instance.collection('users').doc(widget.uid).snapshots(includeMetadataChanges: true);

  @override
  Widget build(BuildContext context) {
    // Unverified email/password accounts confirm their address before
    // anything else (onboarding included).
    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null && AuthService.needsEmailVerification(authUser)) {
      return VerifyEmailScreen(onVerified: () => setState(() {}));
    }

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
          // Reopening the app with a half-finished signup: start from the
          // login screen; signing in again resumes onboarding here.
          if (_restoredUnfinishedUid == widget.uid) {
            _restoredUnfinishedUid = null;
            WidgetsBinding.instance.addPostFrameCallback((_) => AuthService().signOut());
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const EnterDetailsScreen();
        }

        _restoredUnfinishedUid = null;
        _startSignedInServices();

        // Existing user with role — route based on role
        switch (role) {
          // Set in the Firebase console only: approvals and the user
          // directory, nothing else (system_admin_home_screen.dart).
          case kSystemAdminRole:
            return const SystemAdminHomeScreen();
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
          case 'general':
          default:
            return const HomeScreen();
        }
      },
    );
  }
}

/// Routes an organization account by its organization's verification
/// status. Public so OrganizationMemberPendingPage can hand off to it once a
/// member joins.
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
            return _ApprovedOrgHome(organizationId: organizationId);
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

/// An approved organization's member: daily-care-only Staff (and legacy
/// carers) get the care-tasks screen, Staff with no permissions a short
/// "ask an Admin" page, everyone else the admin shell. Live, so a change an
/// Admin makes applies without signing out.
class _ApprovedOrgHome extends StatelessWidget {
  final String organizationId;
  const _ApprovedOrgHome({required this.organizationId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const AdminHomeScreen();
    return StreamBuilder<OrganizationCapabilities>(
      stream: OrgMembershipService().streamCapabilities(uid),
      builder: (context, snapshot) {
        final caps = snapshot.data;
        if (caps == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return switch (orgHomeFor(caps)) {
          OrgHome.care => CarerHomeScreen(organizationId: organizationId),
          OrgHome.noAccess => const _NoOrgAccessScreen(),
          OrgHome.admin => const AdminHomeScreen(),
        };
      },
    );
  }
}

class _NoOrgAccessScreen extends StatelessWidget {
  const _NoOrgAccessScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 48),
                const SizedBox(height: 12),
                const Text('No access yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text(
                  "Your organization's Admin hasn't given your account any permissions yet. "
                  'Ask them to choose what you can do from Staff Members.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => authService.value.signOut(),
                  child: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
