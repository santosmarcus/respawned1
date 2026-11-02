import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/vaccination_record.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';
import 'package:respawnd1/core/utils/case_id.dart';

/// "Export Record PDF" for a single Animal Record — modeled directly on
/// [TransferExportService] (same pw.Document/Printing/Share.shareXFiles
/// pattern, same Preview/Share/Save trio, same "never store PDF bytes in
/// Firestore" rule) rather than a second unrelated PDF pipeline. Kept as its
/// own service (not folded into TransferExportService) because the source
/// data is genuinely different — Vaccines/Special Needs/current Medical
/// Profile straight off one AnimalRecord, not a rescue case + treatment
/// logs + transfer-destination fields.
///
/// Privacy: reads only `animals/{id}`, its `vaccinations` subcollection, and
/// its `managementLogs` subcollection (for a short history summary) — never
/// `adoptions/{id}` or any applicant/payment/government-ID/proof-of-address
/// field, so private adoption paperwork can never end up in this PDF.
class AnimalRecordExportService {
  final AnimalRecordRepository _animalRepo;
  AnimalRecordExportService({AnimalRecordRepository? animalRepo}) : _animalRepo = animalRepo ?? AnimalRecordRepository();

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Not recorded';
    return '${d.month}/${d.day}/${d.year}';
  }

  String _fmtDateTime(DateTime d) =>
      '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _s(dynamic v, [String fallback = 'Not recorded']) {
    if (v == null) return fallback;
    if (v is String) return v.trim().isEmpty ? fallback : v;
    if (v is List) return v.isEmpty ? fallback : v.join(', ');
    if (v is bool) return v ? 'Yes' : 'No';
    return v.toString();
  }

  String _boolLabel(bool? v) {
    if (v == null) return 'Unknown';
    return v ? 'Yes' : 'No';
  }

  /// Best-effort only — a failed/slow fetch never blocks the export; the
  /// PDF simply proceeds without an embedded image (spec: "must handle ...
  /// no image").
  Future<pw.MemoryImage?> _tryFetchCoverImage(List<String> photoUrls) async {
    if (photoUrls.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(photoUrls.first)).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      return pw.MemoryImage(response.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  /// Builds the PDF document bytes only — no I/O beyond the best-effort
  /// cover-image fetch, no Firestore writes. Kept separate from the
  /// preview/share/save entry points so it stays independently testable.
  Future<Uint8List> buildPdf({
    required AnimalRecord animal,
    required List<VaccinationRecord> vaccinations,
    required List<Map<String, dynamic>> recentLogs,
    required String exportedByName,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final coverImage = await _tryFetchCoverImage(animal.photoUrls);

    pw.Widget sectionTitle(String text) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Text(text, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget field(String label, String value) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 3),
          child: pw.RichText(
            text: pw.TextSpan(children: [
              pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 10)),
            ]),
          ),
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text('Animal Record', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Divider(),

          sectionTitle('Header'),
          field('Organization', _s(animal.raw['organizationName'] ?? animal.rescuedBy, 'Respawnd')),
          field('Export date/time', _fmtDateTime(now)),
          field('Exported by', exportedByName),
          field('Animal Record ID', shortCaseId(animal.id)),
          field('Current status', animal.statusLabel),

          sectionTitle('Profile'),
          if (coverImage != null) ...[
            pw.Container(
              height: 160,
              alignment: pw.Alignment.centerLeft,
              child: pw.Image(coverImage, fit: pw.BoxFit.contain),
            ),
            pw.SizedBox(height: 8),
          ],
          field('Name', _s(animal.name, animal.species)),
          field('Species', _s(animal.species)),
          field('Breed', _s(animal.breed)),
          field('Sex', _s(animal.sex)),
          field('Size', _s(animal.size)),
          field('Age', _s(animal.age)),
          field('Color/markings', _s(animal.keyCharacteristics)),
          field('Description', _s(animal.description)),
          field('Temperament', _s(animal.keyCharacteristics)),

          sectionTitle('Medical Profile'),
          field('Spayed/Neutered', _boolLabel(animal.health.sterilized ?? (animal.spayedNeutered ? true : null))),
          field('Dewormed', _boolLabel(animal.health.dewormed ?? (animal.dewormed ? true : null))),
          field('Allergies', _s(animal.health.allergies)),
          field('Chronic conditions', _s(animal.health.chronicConditions)),
          field('Current medications', _s(animal.health.currentMedications)),
          field('Last veterinary checkup', _fmtDate(animal.health.lastVetCheckup)),
          field('Weight', animal.health.weightKg != null ? '${animal.health.weightKg} kg' : 'Not recorded'),
          field('Body condition', _s(animal.health.bodyCondition)),
          field('Identification tag status', _s(animal.health.microchipStatus)),

          sectionTitle('Vaccines'),
          if (vaccinations.isEmpty)
            pw.Text('No vaccine records on file.', style: const pw.TextStyle(fontSize: 10))
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final v in vaccinations) ...[
                  pw.SizedBox(height: 4),
                  field(
                    v.vaccineName,
                    'Given ${_fmtDate(v.dateAdministered)} · Next due ${_fmtDate(v.nextDueDate)}'
                    '${v.batchOrLotNumber != null ? ' · Batch/lot ${v.batchOrLotNumber}' : ''}'
                    '${v.clinicOrProvider != null ? ' · ${v.clinicOrProvider}' : ''}',
                  ),
                ],
              ],
            ),

          if (animal.hasMeaningfulSpecialNeedsInfo) ...[
            sectionTitle('Special Needs'),
            field('Selected needs', _s(animal.specialNeedsTypes)),
            if ((animal.specialNeedsNotes ?? '').trim().isNotEmpty) field('Notes', animal.specialNeedsNotes!.trim()),
          ],

          sectionTitle('History'),
          if (recentLogs.isEmpty)
            pw.Text('No recorded history yet.', style: const pw.TextStyle(fontSize: 10))
          else
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final log in recentLogs) ...[
                  pw.SizedBox(height: 3),
                  field(
                    _s(log['action'], 'Action'),
                    '${log['timestamp'] is Timestamp ? _fmtDate((log['timestamp'] as Timestamp).toDate()) : 'Undated'}'
                    '${(log['details'] as String?)?.isNotEmpty ?? false ? ' · ${log['details']}' : ''}',
                  ),
                ],
              ],
            ),
        ],
      ),
    );

    return doc.save();
  }

  Future<Uint8List> _bytesFor(AnimalRecord animal) async {
    final vaccinations = await _animalRepo.streamVaccinations(animal.id).first;
    final recentLogs = await _animalRepo.streamManagementLogs(animal.id).first;
    return buildPdf(
      animal: animal,
      vaccinations: vaccinations,
      recentLogs: recentLogs.take(10).toList(),
      exportedByName: 'Admin Staff',
    );
  }

  /// Opens the OS print/preview sheet — no Firestore write, matching
  /// TransferExportService.preview.
  Future<void> preview(AnimalRecord animal) async {
    final bytes = await _bytesFor(animal);
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'animal_record_${animal.id}.pdf');
  }

  /// Native share sheet, same as TransferExportService.exportAndShare's
  /// share step — no separate audit doc for this export (unlike the
  /// transfer packet, nothing in this spec asks for one, and this repo has
  /// no `transferExports`-equivalent collection for single-record exports).
  Future<void> share(AnimalRecord animal) async {
    final bytes = await _bytesFor(animal);
    await Printing.sharePdf(bytes: bytes, filename: 'animal_record_${animal.id}.pdf');
  }

  /// Writes to a temp file and hands it to the share sheet with a
  /// "save"-oriented intent, then deletes the temp file right after —
  /// same approach and same reasoning as TransferExportService.saveToDevice
  /// (there is no direct-to-disk API this app otherwise has permission for).
  Future<void> saveToDevice(AnimalRecord animal) async {
    final bytes = await _bytesFor(animal);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/animal_record_${animal.id}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes);
    try {
      await Share.shareXFiles([XFile(file.path)], text: 'Animal Record — ${animal.name.isNotEmpty ? animal.name : animal.species}');
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}
