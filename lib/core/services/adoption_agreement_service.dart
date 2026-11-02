import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_terms_page.dart';

/// The formal Adoption Agreement the terms page promises ("reviewed and
/// signed by both parties on the day of the adoption"), printed for wet
/// signatures at handover. Same pw.Document / Printing pattern as
/// AnimalRecordExportService; nothing is written to Firestore and the PDF
/// is never stored.
///
/// Contents: both parties, the animal, any continuing care the adopter is
/// taking on (medications, conditions, special needs — disclosed so the
/// adopter signs knowingly), the adopter's terms (the same list they
/// accepted in the app, via [adoptionTermsFor]), the organization's own
/// commitments, and signature blocks. Never includes the government ID,
/// proof of address, or household answers from the application.
class AdoptionAgreementService {
  final FirebaseFirestore _db;
  AdoptionAgreementService({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  static String _fmtDate(DateTime d) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September',
      'October', 'November', 'December'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  static String _orDash(String? v) => (v == null || v.trim().isEmpty) ? '—' : v.trim();

  /// Continuing-care items the adopter should know about before signing.
  static List<String> careDisclosures(AnimalRecord? animal) {
    if (animal == null) return const [];
    final h = animal.health;
    return [
      if ((h.currentMedications ?? '').trim().isNotEmpty) 'Current medications: ${h.currentMedications!.trim()}',
      if ((h.chronicConditions ?? '').trim().isNotEmpty) 'Ongoing conditions: ${h.chronicConditions!.trim()}',
      if ((h.allergies ?? '').trim().isNotEmpty) 'Allergies: ${h.allergies!.trim()}',
      if (animal.hasMeaningfulSpecialNeedsInfo)
        'Special needs: ${[
          ...animal.specialNeedsTypes,
          if ((animal.specialNeedsNotes ?? '').trim().isNotEmpty) animal.specialNeedsNotes!.trim(),
        ].join('; ')}',
      if (!(h.sterilized ?? animal.spayedNeutered)) 'Not yet spayed/neutered.',
    ];
  }

  Future<Uint8List> buildPdf({
    required AdoptionApplication app,
    required AnimalRecord? animal,
    required String organizationName,
    required DateTime adoptionDate,
  }) async {
    final doc = pw.Document();
    final animalName = (animal?.name.isNotEmpty ?? false) ? animal!.name : app.animalName;
    final address = app.raw['personal'] is Map ? (app.raw['personal'] as Map)['homeAddress'] as String? : null;
    final disclosures = careDisclosures(animal);
    final fee = app.paymentAmount != null && app.paymentAmount! > 0
        // The PDF's built-in Helvetica has no peso sign.
        ? '${formatPeso(app.paymentAmount!).replaceFirst('₱', 'PHP ')} (${app.feeStatus.label.toLowerCase()})'
        : 'None';

    const body = pw.TextStyle(fontSize: 10, lineSpacing: 2);
    pw.Widget heading(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(text, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
        );
    pw.Widget field(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.TextSpan(text: value, style: body),
            ]),
          ),
        );
    pw.Widget numbered(List<String> items) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < items.length; i++)
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.SizedBox(width: 18, child: pw.Text('${i + 1}.', style: body)),
                    pw.Expanded(child: pw.Text(items[i], style: body)),
                  ],
                ),
              ),
          ],
        );
    pw.Widget signature(String role, String name) => pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(height: 36),
              pw.Container(height: 0.8, color: PdfColors.black),
              pw.SizedBox(height: 3),
              pw.Text(name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              pw.Text('$role — signature over printed name', style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 14),
              pw.Text('Date: ______________________', style: body),
            ],
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text('Application #${app.id} · Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ),
        build: (context) => [
          pw.Center(child: pw.Text('ADOPTION AGREEMENT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 4),
          pw.Center(child: pw.Text(organizationName, style: const pw.TextStyle(fontSize: 11))),
          pw.SizedBox(height: 12),
          pw.Text(
            'This agreement is made on ${_fmtDate(adoptionDate)} between $organizationName (the "Organization") '
            'and ${_orDash(app.adopterName)} (the "Adopter") for the adoption of the animal described below.',
            style: body,
          ),

          heading('Adopter'),
          field('Name', _orDash(app.adopterName)),
          field('Address', _orDash(address ?? app.adopterCity)),
          field('Mobile number', _orDash(app.adopterPhone)),
          field('Email', _orDash(app.adopterEmail)),

          heading('Animal'),
          field('Name', _orDash(animalName)),
          field('Species', _orDash(animal?.species)),
          field('Breed', _orDash(animal?.breed)),
          field('Sex', _orDash(animal?.sex)),
          field('Approximate age', _orDash(animal?.age)),
          if (animal != null && animal.keyCharacteristics.isNotEmpty)
            field('Characteristics', animal.keyCharacteristics.join(', ')),
          field('Spayed/neutered',
              animal == null ? '—' : ((animal.health.sterilized ?? animal.spayedNeutered) ? 'Yes' : 'No')),
          field('Vaccinated', animal == null ? '—' : (animal.vaccinated ? 'Yes' : 'No')),
          field('Adoption fee', fee),

          heading('Continuing care'),
          if (disclosures.isEmpty)
            pw.Text('The Organization knows of no ongoing medical care the animal needs at the time of adoption.',
                style: body)
          else ...[
            pw.Text('The Adopter has been told about, and accepts responsibility for, the following:', style: body),
            pw.SizedBox(height: 4),
            numbered(disclosures),
          ],

          heading("Adopter's commitments"),
          numbered(adoptionTermsFor(animalName)),

          heading("Organization's commitments"),
          numbered([
            'The Organization has disclosed all health, behavior and care information it holds about the animal.',
            'The Organization will deliver the animal to the Adopter and cover the transportation cost.',
            'The Organization will conduct the agreed post-adoption follow-ups and remain available for advice.',
            'If the Adopter can no longer keep the animal, the Organization will take it back.',
          ]),

          pw.SizedBox(height: 18),
          pw.Text('Signed by both parties on the date written below their names.', style: body),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              signature('Adopter', _orDash(app.adopterName)),
              pw.SizedBox(width: 40),
              signature('For the Organization', organizationName),
            ],
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// The application's owning organization's display name, or a neutral
  /// fallback for legacy applications with no organizationId.
  Future<String> _organizationName(AdoptionApplication app) async {
    final orgId = app.raw['organizationId'] as String?;
    if (orgId == null || orgId.isEmpty) return 'The Organization';
    final snap = await _db.collection('organizations').doc(orgId).get();
    final name = (snap.data()?['name'] as String?)?.trim();
    return (name == null || name.isEmpty) ? 'The Organization' : name;
  }

  /// Opens the OS print/preview sheet, from which staff print or share it.
  Future<void> preview({
    required AdoptionApplication app,
    required AnimalRecord? animal,
    required DateTime adoptionDate,
  }) async {
    final bytes = await buildPdf(
      app: app,
      animal: animal,
      organizationName: await _organizationName(app),
      adoptionDate: adoptionDate,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'adoption_agreement_${app.id}.pdf');
  }
}
