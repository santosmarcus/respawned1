import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';
import 'package:respawnd1/features/collartag/animal_tag_scan.dart' show isStaffOfOrganization;

/// The route for a link that opens the app on an animal
/// (`respawnd://open/animal/ID`, from the "Open in the app" button on the
/// animal's public web page), or null when [settings] isn't one.
Route<void>? animalLinkRoute(RouteSettings settings) {
  final id = AppLinks.animalIdFromLink(settings.name);
  if (id == null) return null;
  return MaterialPageRoute(settings: settings, builder: (_) => AnimalLinkPage(animalId: id));
}

/// Any other link into the app: says so, with a way back.
Route<void> unknownLinkRoute(RouteSettings settings) => MaterialPageRoute(
      settings: settings,
      builder: (_) => const _Message(
        icon: Icons.link_off,
        title: 'Link not recognized',
        body: "This link doesn't open anything in ResPAWnd.",
        actionLabel: 'Close',
      ),
    );

/// Shows the animal a link points at: the full record for staff of the
/// owning organization, the public profile for everyone else (as scanning
/// the animal's QR tag does). Asks to sign in first when nobody is.
class AnimalLinkPage extends StatelessWidget {
  const AnimalLinkPage({super.key, required this.animalId});

  final String animalId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snap) {
        final user = snap.data;
        if (user == null) {
          return _Message(
            icon: Icons.lock_outline,
            title: 'Sign in to see this animal',
            body: 'Sign in or create an account, then open the link again.',
            actionLabel: 'Sign in',
          );
        }
        return _ResolvedAnimal(key: ValueKey(user.uid), animalId: animalId);
      },
    );
  }
}

class _ResolvedAnimal extends StatefulWidget {
  const _ResolvedAnimal({super.key, required this.animalId});
  final String animalId;

  @override
  State<_ResolvedAnimal> createState() => _ResolvedAnimalState();
}

class _ResolvedAnimalState extends State<_ResolvedAnimal> {
  late final Future<Widget?> _page = _resolve();

  Future<Widget?> _resolve() async {
    final db = FirebaseFirestore.instance;
    // Staff of the owning organization can read the full record (hidden
    // ones included); for everyone else the rules refuse it.
    try {
      final own = await db.collection('animals').doc(widget.animalId).get();
      final data = own.data();
      if (own.exists && data != null && await isStaffOfOrganization(data['organizationId'] as String?)) {
        return AnimalRecordDetailPage(animalId: own.id, data: data);
      }
    } on FirebaseException {
      // Not staff there.
    }
    final public = await db.collection('publicAnimals').doc(widget.animalId).get();
    if (!public.exists) return null;
    final record = AnimalRecord.fromFirestore(public);
    return AnimalPage(animal: animalRecordToCard(record, 0), onFavoriteToggle: () {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget?>(
      future: _page,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return const _Message(
            icon: Icons.wifi_off,
            title: 'Could not open this animal',
            body: 'Check your connection and open the link again.',
            actionLabel: 'Close',
          );
        }
        return snap.data ??
            const _Message(
              icon: Icons.pets,
              title: 'Profile not available',
              body: "This animal's profile was removed or isn't public any more.",
              actionLabel: 'Close',
            );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.title, required this.body, required this.actionLabel});

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(backgroundColor: AppColors.background, foregroundColor: AppColors.textPrimary, elevation: 0),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColors.textSecondary),
              const SizedBox(height: 12),
              Text(title,
                  textAlign: TextAlign.center, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(body,
                  textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              ElevatedButton(
                style: AppButtons.primary,
                onPressed: () => Navigator.maybePop(context),
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
