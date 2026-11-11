import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/transporter_application.dart';
import 'package:respawnd1/core/repos/transporter_application_repository.dart';
import 'package:respawnd1/core/utils/transporter_trip_stats.dart';
import 'package:respawnd1/features/admin/volunteers/transporter_applications_page.dart';
import 'package:respawnd1/features/admin/volunteers/volunteers_page.dart';

/// Admin view of one pet transporter: contact, vehicle, verification,
/// availability, trip counts and their submitted application documents.
/// Opened from the Transporters directory (VolunteersPage(transporters: true)).
class TransporterDetailPage extends StatelessWidget {
  const TransporterDetailPage({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: AppColors.background),
        title: Text('Transporter', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: db.collection('users').doc(uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return _message('Could not load this transporter.');
          if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
          if (!snap.data!.exists) return _message('This account no longer exists.');
          final t = PetTransporter.fromFirestore(snap.data!);
          final data = snap.data!.data() ?? const <String, dynamic>{};
          final email = (data['email'] as String?)?.trim();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              _Header(transporter: t),
              const SizedBox(height: 20),
              _TripStats(uid: uid),
              const SizedBox(height: 20),
              _Section(title: 'Contact', children: [
                _row(Icons.phone_outlined, 'Phone', t.phone,
                    onTap: (t.phone ?? '').isEmpty ? null : () => launchUrl(Uri(scheme: 'tel', path: t.phone))),
                _row(Icons.email_outlined, 'Email', email),
              ]),
              _Section(title: 'Vehicle', children: [
                _row(Icons.local_shipping_outlined, 'Vehicle type', t.vehicleType),
                _row(Icons.confirmation_number_outlined, 'License plate', t.licensePlate),
              ]),
              _Section(title: 'Availability', children: [
                _row(Icons.circle, 'Status', t.isOnline ? 'Online now' : 'Offline',
                    iconColor: t.isOnline ? AppColors.greenrspwn : AppColors.slaterspwn),
                _row(Icons.schedule, 'Last seen',
                    t.lastSeenAt == null ? null : DateFormat('MMM d, y · h:mm a').format(t.lastSeenAt!)),
              ]),
              Text('Application', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              StreamBuilder<TransporterApplication?>(
                stream: TransporterApplicationRepository().watch(uid),
                builder: (context, appSnap) {
                  if (appSnap.hasError) {
                    return Text('Could not load the application.',
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
                  }
                  if (!appSnap.hasData && appSnap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
                    );
                  }
                  final app = appSnap.data;
                  if (app == null) {
                    return Text('No verification application submitted yet.',
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TransporterApplicationCard(app: app),
                      if (app.status == TransporterApplicationStatus.pending)
                        TextButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const TransporterApplicationsPage()),
                          ),
                          icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                          label: const Text('Review in Transporter applications'),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );

  static Widget _row(IconData icon, String label, String? value, {VoidCallback? onTap, Color? iconColor}) {
    final shown = (value == null || value.trim().isEmpty) ? '—' : value.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: icon == Icons.circle ? 12 : 18, color: iconColor ?? AppColors.textSecondary),
            const SizedBox(width: 10),
            Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(shown,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      decoration: onTap != null ? TextDecoration.underline : null)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.transporter});

  final PetTransporter transporter;

  @override
  Widget build(BuildContext context) {
    final photo = transporter.photoUrl;
    return Column(
      children: [
        CircleAvatar(
          radius: 44,
          backgroundColor: AppColors.tearspwn,
          backgroundImage: (photo != null && photo.isNotEmpty) ? NetworkImage(photo) : null,
          child: (photo == null || photo.isEmpty)
              ? const Icon(Icons.person_outline, size: 40, color: AppColors.textSecondary)
              : null,
        ),
        const SizedBox(height: 10),
        Text(transporter.name,
            textAlign: TextAlign.center, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        transporterVerificationPill(transporter),
      ],
    );
  }
}

class _TripStats extends StatelessWidget {
  const _TripStats({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('cases').where('assignedVolunteerId', isEqualTo: uid).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        final completed = docs.where((d) => isCompletedTransit(d.data())).length;
        final ongoing = docs.where((d) => isOngoingTransit(d.data())).length;
        String value(int n) => snap.hasData ? '$n' : '–';
        return Row(
          children: [
            Expanded(child: _stat('Completed trips', value(completed), Icons.check_circle_outline)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Ongoing', value(ongoing), Icons.local_shipping_outlined)),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value, IconData icon) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
