import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/certificate_view.dart';

/// Profile → Certificates: every Certificate of Donation the user received,
/// newest first (`users/{uid}/certificates`, written by the backend).
class CertificatesPage extends StatefulWidget {
  const CertificatesPage({super.key});

  @override
  State<CertificatesPage> createState() => _CertificatesPageState();
}

class _CertificatesPageState extends State<CertificatesPage> {
  static const _filters = {'All': null, 'Donations': 'donation', 'Sponsorships': 'sponsorship', 'In-Kind': 'inkind'};
  String _filter = 'All';
  String _query = '';

  Stream<QuerySnapshot<Map<String, dynamic>>>? _stream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('certificates')
        .orderBy('issuedAt', descending: true)
        .snapshots();
  }

  @override
  Widget build(BuildContext context) {
    final stream = _stream();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text('Certificates', style: GoogleFonts.tiltWarp(fontSize: 24, color: AppColors.textPrimary)),
      ),
      body: stream == null
          ? Center(child: Text('Please sign in to see your certificates.', style: GoogleFonts.zain(fontSize: 16)))
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              height: 44,
              decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(12)),
              child: TextField(
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search by campaign or pet name',
                  hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary.withValues(alpha: 0.6)),
                  prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in _filters.keys)
                  Padding(
                    padding: const EdgeInsets.only(right: 18),
                    child: InkWell(
                      onTap: () => setState(() => _filter = f),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(f,
                              style: GoogleFonts.zain(
                                  fontSize: 15,
                                  fontWeight: f == _filter ? FontWeight.w700 : FontWeight.normal,
                                  color: AppColors.textPrimary)),
                          if (f == _filter)
                            Container(margin: const EdgeInsets.only(top: 2), height: 2, width: 24, color: AppColors.textPrimary),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
                }
                if (snap.hasError) {
                  return Center(child: Text('Could not load certificates.', style: GoogleFonts.zain(fontSize: 16)));
                }
                final type = _filters[_filter];
                final certs = (snap.data?.docs ?? const [])
                    .map(DonationCertificate.fromFirestore)
                    .where((c) => type == null || c.type == type)
                    .where((c) =>
                _query.isEmpty ||
                    c.benefit.toLowerCase().contains(_query) ||
                    (c.campaignTitle ?? '').toLowerCase().contains(_query))
                    .toList();
                if (certs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'No certificates yet. You\'ll receive one after each successful donation.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: certs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _CertificateTile(cert: certs[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CertificateTile extends StatelessWidget {
  final DonationCertificate cert;
  const _CertificateTile({required this.cert});

  @override
  Widget build(BuildContext context) {
    final label = switch (cert.type) {
      'sponsorship' => 'Sponsorship',
      'inkind' => 'In-Kind Donation',
      _ => 'Donation',
    };
    return Material(
      color: AppColors.tearspwn.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => CertificateScreen(certificateId: cert.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium_outlined, color: AppColors.textPrimary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cert.campaignTitle ?? cert.benefit,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                    Text('$label · ${cert.contribution}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    Text(cert.dateText, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.textPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
