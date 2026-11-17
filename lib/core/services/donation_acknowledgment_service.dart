import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:respawnd1/core/models/donation/donation_model.dart';

/// Donation gap 8: a printable acknowledgment for a donation recorded
/// offline (cash, bank transfer, check). Offline donors often have no
/// account, so the in-app Certificate of Donation never reaches them. This
/// reuses the certificate's wording (recipient, contribution, "for the
/// benefit of", organization, reference) on one page staff can print, save
/// or share from the OS print sheet. Nothing is stored.
class DonationAcknowledgmentService {
  DonationAcknowledgmentService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _db;

  static String _peso(double v) {
    final cents = (v * 100).round();
    final whole = (cents ~/ 100).toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    return 'PHP $whole.${(cents % 100).toString().padLeft(2, '0')}';
  }

  Future<Uint8List> buildPdf(DonationHistoryRecord r, {required String organizationName}) async {
    final doc = pw.Document();
    final donor = r.isAnonymous ? 'Our Supporter' : (r.donorName.isEmpty ? 'Our Supporter' : r.donorName);
    final benefit = r.generalFund ? 'our rescues' : (r.campaignName.isEmpty ? 'our rescues' : r.campaignName);
    final number = r.acknowledgmentNumber ?? 'ACK-${r.id.substring(0, r.id.length < 8 ? r.id.length : 8).toUpperCase()}';
    final when = r.date.isNotEmpty ? r.date : (r.when?.toIso8601String().split('T').first ?? '');

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(48),
        build: (_) => pw.Container(
          padding: const pw.EdgeInsets.all(32),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey700, width: 2)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(organizationName, style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 24),
              pw.Text('ACKNOWLEDGMENT OF DONATION',
                  style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, letterSpacing: 1.5)),
              pw.SizedBox(height: 28),
              pw.Text('This acknowledges with gratitude the donation of', style: const pw.TextStyle(fontSize: 13)),
              pw.SizedBox(height: 10),
              pw.Text(donor, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 14),
              pw.Text('in the amount of', style: const pw.TextStyle(fontSize: 13)),
              pw.SizedBox(height: 8),
              pw.Text(_peso(r.amountValue), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 14),
              pw.Text('for the benefit of $benefit.', style: const pw.TextStyle(fontSize: 13)),
              pw.SizedBox(height: 32),
              pw.Table(
                columnWidths: const {0: pw.FixedColumnWidth(150), 1: pw.FlexColumnWidth()},
                children: [
                  for (final (k, v) in [
                    ('Acknowledgment no.', number),
                    ('Date received', when),
                    ('Payment method', r.method.isEmpty ? '-' : r.method),
                    ('Reference no.', r.refNumber.isEmpty ? '-' : r.refNumber),
                    ('Recorded by', r.recordedByName ?? '-'),
                  ])
                    pw.TableRow(children: [
                      pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          child: pw.Text(k, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700))),
                      pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 3),
                          child: pw.Text(v, style: const pw.TextStyle(fontSize: 11))),
                    ]),
                ],
              ),
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children: [
                  pw.Column(children: [
                    pw.Container(width: 200, height: 1, color: PdfColors.black),
                    pw.SizedBox(height: 4),
                    pw.Text('Authorized signature', style: const pw.TextStyle(fontSize: 10)),
                  ]),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Text('Thank you for supporting our animals.',
                  style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700)),
            ],
          ),
        ),
      ),
    );
    return doc.save();
  }

  Future<String> _organizationName(DonationHistoryRecord r) async {
    if (r.campaignId.isNotEmpty) {
      final c = await _db.collection('campaigns').doc(r.campaignId).get();
      final orgId = c.data()?['organizationId'] as String?;
      if (orgId != null && orgId.isNotEmpty) {
        final org = await _db.collection('organizations').doc(orgId).get();
        final name = (org.data()?['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) return name;
      }
    }
    return r.organizer.isNotEmpty ? r.organizer : 'Rescue Shelter';
  }

  /// Opens the OS print/preview sheet.
  Future<void> preview(DonationHistoryRecord r) async {
    final bytes = await buildPdf(r, organizationName: await _organizationName(r));
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'acknowledgment_${r.id}.pdf');
  }
}
