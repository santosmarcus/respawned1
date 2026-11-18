import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';

/// Who may take a transit. Mirrors isVerifiedResponder() in firestore.rules:
/// a pet transporter staff verified (users/{uid}.isVerified, set when their
/// application is approved), or a rescue volunteer whose volunteer
/// application was approved.

const String kTransporterPendingMessage =
    'Your transporter application is still being reviewed. You can take transits once it is approved.';
const String kTransporterRejectedMessage =
    'Your transporter application was not approved, so you can\'t take transits.';
const String kVolunteerNotApprovedMessage =
    'Your volunteer application has not been approved yet. You can take transits once it is.';
const String kNotATransporterMessage = 'Only verified pet transporters can take transits.';

/// Why a pet transporter with this users/{uid} data may not take transits,
/// or null when they may.
String? petTransporterBlockReason(Map<String, dynamic>? user) {
  if (user?['isVerified'] == true) return null;
  final status = user?['transporterVerificationStatus'] as String? ?? '';
  return status == 'rejected' ? kTransporterRejectedMessage : kTransporterPendingMessage;
}

/// Why the signed-in account may not take a transit, or null when it may.
Future<String?> transitBlockReason() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return kNotATransporterMessage;
  final db = FirebaseFirestore.instance;
  final user = (await db.collection('users').doc(uid).get()).data();

  switch (user?['role'] as String?) {
    case 'pet_transporter':
      return petTransporterBlockReason(user);
    case 'rescue_volunteer':
      final app = await db.collection('volunteerApplications').doc(uid).get();
      return app.data()?['status'] == 'approved' ? null : kVolunteerNotApprovedMessage;
    default:
      return kNotATransporterMessage;
  }
}

/// Banner on the transporter's job board while their account isn't verified,
/// so they know why they can't take transits. Updates live when approved.
class TransporterVerificationBanner extends StatelessWidget {
  const TransporterVerificationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final user = snap.data?.data();
        // Rescue volunteers are checked when they accept (transitBlockReason).
        if (user == null || user['role'] != 'pet_transporter') return const SizedBox.shrink();
        final reason = petTransporterBlockReason(user);
        if (reason == null) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: Colors.orange.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reason,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
