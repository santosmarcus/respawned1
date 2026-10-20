import 'dart:io';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_theme.dart';

/// A Certificate of Donation, stored by the backend at
/// `users/{uid}/certificates/{id}` (id = payment id, or donation id for
/// in-kind). Issued after a verified payment / confirmed in-kind receipt.
class DonationCertificate {
  final String id;
  final String type; // 'donation' | 'sponsorship' | 'inkind'
  final String recipientName;
  final String organizationName;
  final String contribution;
  final String benefit;
  final String dateText;
  final String? campaignTitle;
  final String? refNumber;
  final DateTime? issuedAt;

  const DonationCertificate({
    required this.id,
    required this.type,
    required this.recipientName,
    required this.organizationName,
    required this.contribution,
    required this.benefit,
    required this.dateText,
    this.campaignTitle,
    this.refNumber,
    this.issuedAt,
  });

  factory DonationCertificate.fromFirestore(DocumentSnapshot doc) {
    final d = (doc.data() as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return DonationCertificate(
      id: doc.id,
      type: d['type'] as String? ?? 'donation',
      recipientName: d['recipientName'] as String? ?? '',
      organizationName: d['organizationName'] as String? ?? 'Rescue Shelter',
      contribution: d['contribution'] as String? ?? '',
      benefit: d['benefit'] as String? ?? 'our rescues',
      dateText: d['dateText'] as String? ?? '',
      campaignTitle: d['campaignTitle'] as String?,
      refNumber: d['refNumber'] as String?,
      issuedAt: d['issuedAt'] is Timestamp ? (d['issuedAt'] as Timestamp).toDate() : null,
    );
  }

  static DocumentReference<Map<String, dynamic>>? ref(String id) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid).collection('certificates').doc(id);
  }
}

/// The certificate artwork (Figma "Certificate of Donation").
class CertificateCard extends StatelessWidget {
  final DonationCertificate certificate;
  const CertificateCard({super.key, required this.certificate});

  @override
  Widget build(BuildContext context) {
    final c = certificate;
    TextStyle body({double size = 16, FontWeight weight = FontWeight.w700}) =>
        GoogleFonts.zain(fontSize: size, fontWeight: weight, height: 1.15, color: AppColors.textPrimary);
    Widget line() => const Divider(height: 1, thickness: 1, color: AppColors.slaterspwn);

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CERTIFICATE OF\nDONATION',
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(fontSize: 30, height: 1.1, color: AppColors.textPrimary)),
          const SizedBox(height: 20),
          Text('${c.organizationName} expresses our gratitude to', textAlign: TextAlign.center, style: body()),
          const SizedBox(height: 22),
          Text(c.recipientName, textAlign: TextAlign.center, style: body(size: 18)),
          const SizedBox(height: 10),
          line(),
          const SizedBox(height: 22),
          Text('For the generous donation of', textAlign: TextAlign.center, style: body()),
          const SizedBox(height: 22),
          Text(c.contribution, textAlign: TextAlign.center, style: body(size: 18)),
          const SizedBox(height: 10),
          line(),
          const SizedBox(height: 22),
          Text('For the benefit of ${c.benefit}', textAlign: TextAlign.center, style: body()),
          const SizedBox(height: 18),
          Text('Given this day of ${c.dateText}',
              textAlign: TextAlign.center, style: body(weight: FontWeight.w400)),
          const SizedBox(height: 44),
          Text('Thank you for your unwavering support\nfor our rescues!', textAlign: TextAlign.center, style: body()),
          const SizedBox(height: 16),
          const Icon(Icons.pets, size: 56, color: AppColors.textPrimary),
        ],
      ),
    );
  }
}

/// Full-screen certificate with a Share button. Streams the doc, so it shows
/// up as soon as the backend issues it (same transaction as the payment).
class CertificateScreen extends StatefulWidget {
  final String certificateId;
  const CertificateScreen({super.key, required this.certificateId});

  @override
  State<CertificateScreen> createState() => _CertificateScreenState();
}

class _CertificateScreenState extends State<CertificateScreen> {
  final _boundaryKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share(DonationCertificate c) async {
    setState(() => _sharing = true);
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Certificate is not ready yet.');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) throw Exception('Could not render the certificate.');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/certificate_${c.id}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path)],
        text: 'My Certificate of Donation from ${c.organizationName}',
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not share: $e')));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = DonationCertificate.ref(widget.certificateId);
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
        title: Text('Certificate', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
        centerTitle: true,
      ),
      body: ref == null
          ? Center(child: Text('Please sign in to view certificates.', style: GoogleFonts.zain(fontSize: 16)))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
          }
          if (snap.hasError) {
            return Center(child: Text('Could not load the certificate.', style: GoogleFonts.zain(fontSize: 16)));
          }
          if (!(snap.data?.exists ?? false)) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No certificate yet. Certificates are issued once a payment is confirmed or an in-kind '
                      'donation is received (donations made before certificates were introduced don\'t have one).',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final cert = DonationCertificate.fromFirestore(snap.data!);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slaterspwn),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
                ),
                child: RepaintBoundary(key: _boundaryKey, child: CertificateCard(certificate: cert)),
              ),
              const SizedBox(height: 20),
              Center(
                child: ElevatedButton.icon(
                  onPressed: _sharing ? null : () => _share(cert),
                  icon: _sharing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.share_outlined),
                  label: Text('Share / Save', style: GoogleFonts.tiltWarp(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
