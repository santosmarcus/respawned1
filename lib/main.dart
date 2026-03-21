
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:respawnd1/features/pettransporter/service_screen.dart';
import 'package:respawnd1/firebase_options.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/userauth/login_screen.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/adminhome/adminhome_screen.dart';
import 'package:respawnd1/features/volunteerhome/volhome_screen.dart';
import 'package:respawnd1/features/userauth/details_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await FirebaseAuth.instance.signOut();
  runApp(const ResPAWndApp());
}

class ResPAWndApp extends StatelessWidget {
  const ResPAWndApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResPAWnd',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AuthWrapper(), // ← use this instead of LoginScreen directly
    );
  }
}

// Automatically routes user based on login state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

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

        // Logged in — check if they need onboarding
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(snapshot.data!.uid)
              .get(),
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


