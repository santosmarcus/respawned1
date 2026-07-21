import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:respawnd1/features/pettransporter/service_screen.dart';
import 'package:respawnd1/features/pettransporter/transporter_verification_screen.dart';
import 'package:respawnd1/firebase_options.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/userauth/login_screen.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/adminhome/adminhome_screen.dart';
import 'package:respawnd1/features/volunteerhome/volhome_screen.dart';
import 'package:respawnd1/features/userauth/details_screen.dart';
import 'package:respawnd1/features/generalhome/push_token_service.dart';
import 'package:google_fonts/google_fonts.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  GoogleFonts.config.allowRuntimeFetching = false;

  // flutter_facebook_auth requires an explicit web init before login() can
  // be called on Flutter Web — otherwise the Facebook button fails silently.
  // Replace 'YOUR_FACEBOOK_APP_ID' with the app ID from developers.facebook.com.
  if (kIsWeb) {
    await FacebookAuth.instance.webAndDesktopInitialize(
      appId: "YOUR_FACEBOOK_APP_ID",
      cookie: true,
      xfbml: true,
      version: "v19.0",
    );
  }

  // NOTE: previously this force-signed-out the user on every cold start,
  // which meant email, phone, and Facebook logins never persisted between
  // app launches — every open of the app looked like login "wasn't
  // working" because it silently logged the user right back out.
  // Removed so Firebase's normal persisted-session behavior applies.

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

  // Reuses the same Future for the same uid. authStateChanges() can
  // legitimately emit more than once around a sign-in transition (e.g.
  // right after logging back in following a logout). Without this cache,
  // every one of those emissions would rebuild this widget and create a
  // BRAND NEW .get() call inline, resetting the inner FutureBuilder back
  // to "waiting" each time — which is what made the screen look stuck on
  // a loading animation even though sign-in had actually succeeded.
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
          // Clear the cache so the *next* sign-in (possibly a different
          // user) always fetches fresh data instead of reusing a stale
          // future from the previous session.
          _cachedUid = null;
          _userDocFuture = null;
          return const LoginScreen();
        }

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

            // Fire-and-forget: registers/refreshes this device's FCM token
            // now that we know the user is fully signed in with a role.
            PushTokenService.register();

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