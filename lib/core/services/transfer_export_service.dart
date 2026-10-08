import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/treatment_log_entry.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';

/// Transfer/export spec — builds a shareable PDF "transfer packet" out of
/// selected animals' Rescue Report + Treatment + Animal Record information,
/// for sending to another clinic/organization/authorized volunteer during a
/// transfer. This is the ONE shared export implementation — every entry
/// point (Rescue Details, Treatment Details, Animal Record Details,
/// transfer confirmation) should call this same service rather than
/// building its own PDF.
///
/// Privacy: only ever reads from `cases/{id}`, `cases/{id}/treatmentLogs`,
/// and `animals/{id}` — never touches `adoptions/{id}` or any applicant/
/// payment/document field, so private adoption data can never end up in a
/// transfer packet. Reporter contact info is included but clearly labeled
/// as sensitive. Callers are responsible for only offering this action to
/// authenticated organization staff (the existing admin-only routes this
/// is wired into already require that).
class TransferExportService {
  final RescueCaseRepository _caseRepo;
  final AnimalRecordRepository _animalRepo;

  TransferExportService({RescueCaseRepository? caseRepo, AnimalRecordRepository? animalRepo})
      : _caseRepo = caseRepo ?? RescueCaseRepository(),
        _animalRepo = animalRepo ?? AnimalRecordRepository();

  String _fmtDate(DateTime? d) {
    if (d == null) return 'Not recorded';
    return '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _s(dynamic v, [String fallback = 'Not recorded']) {
    if (v == null) return fallback;
    if (v is String) return v.trim().isEmpty ? fallback : v;
    if (v is List) return v.isEmpty ? fallback : v.join(', ');
    return v.toString();
  }

  Map<String, dynamic> _animalMap(RescueCase rescueCase, int index) {
    if (index < 0 || index >= rescueCase.animals.length) return const {};
    return rescueCase.animals[index];
  }

  /// Builds the PDF document bytes only — no I/O, no Firestore writes. Kept
  /// separate from [exportAndShare] so it stays independently testable.
  Future<Uint8List> buildPdf({
    required RescueCase rescueCase,
    required List<int> animalIndexes,
    required List<TreatmentLogEntry> treatmentLogs,
    required List<AnimalRecord> animalRecords,
    required String destinationType,
    required String destinationName,
    required String transferredByName,
    required String sourceOrganization,
  }) async {
    final doc = pw.Document();
    final now = DateTime.now();
    final animalNames = animalIndexes
        .map((i) => _s(_animalMap(rescueCase, i)['species'], 'Animal ${i + 1}'))
        .join(', ');

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
          pw.Text('Animal Transfer Packet', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Divider(),

          sectionTitle('Transfer Header'),
          field('Case ID', rescueCase.id),
          field('Export date/time', _fmtDate(now)),
          field('Source organization', sourceOrganization),
          field('Destination type', destinationType),
          field('Destination name', destinationName),
          field('Transferred by', transferredByName),
          field('Selected animals', animalNames),

          sectionTitle('Rescue Report Information'),
          field('Original report date', _fmtDate(rescueCase.createdAt)),
          field('Rescue type', _s(rescueCase.raw['rescueType'])),
          field('Urgency', _s(rescueCase.urgency)),
          // Sensitive contact info — clearly labeled, never left unmarked.
          field('Reporter (sensitive contact info)',
              '${_s(rescueCase.reporterName, 'Not provided')} · ${_s(rescueCase.reporterPhone, 'No phone on file')}'),
          field('Original location', _s(rescueCase.address)),
          field('Description', _s(rescueCase.condition)),
          field('Bite risk (case-level)', _s(rescueCase.biteRisk)),
          field('Escape risk (case-level)', _s(rescueCase.escapeRisk)),

          for (final index in animalIndexes) ...[
            pw.SizedBox(height: 10),
            pw.Divider(),
            sectionTitle('Animal ${index + 1}'),
            () {
              final a = _animalMap(rescueCase, index);
              return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                field('Species', _s(a['species'])),
                field('Breed', _s(a['breed'])),
                field('Sex', _s(a['sex'])),
                field('Size', _s(a['size'])),
                field('Color/markings', _s(a['colorMarkings'])),
                field('Bite risk', _s(a['biteRisk'])),
                field('Escape risk', _s(a['escapeRisk'])),
                field('Body condition', _s(a['bodyCondition'])),
                field('Mobility', _s(a['mobility'])),
                field('Alertness', _s(a['alertness'])),
                field('Eyes/nose/mouth', _s(a['eyesNoseMouth'])),
                field('Skin and coat', _s(a['skinAndCoat'])),
                field('Appetite and hydration', _s(a['appetiteHydration'])),
                field('Behavior', _s(a['behavior'])),
                field('Environment and safety', _s(a['environmentSafety'])),
              ]);
            }(),
            pw.SizedBox(height: 6),
            pw.Text('Treatment', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            () {
              final logsForAnimal = treatmentLogs.where((l) => l.appliesToAnimal(index)).toList()
                ..sort((a, b) => (a.displayDate ?? DateTime(0)).compareTo(b.displayDate ?? DateTime(0)));
              if (logsForAnimal.isEmpty) {
                return pw.Text('No treatment logs recorded.', style: const pw.TextStyle(fontSize: 10));
              }
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (final log in logsForAnimal) ...[
                    pw.SizedBox(height: 4),
                    field('${log.type} (${_fmtDate(log.displayDate)})', log.notes.isEmpty ? 'No notes' : log.notes),
                    if (log.condition != null) field('  Condition', log.condition!),
                    if (log.medicationName != null) field('  Medication', '${log.medicationName} ${log.medicationDose ?? ''}'),
                    if (log.procedurePerformed != null) field('  Procedure', log.procedurePerformed!),
                    if (log.vaccineName != null) field('  Vaccination', '${log.vaccineName} ${log.vaccineDose ?? ''}'),
                    if (log.dischargeNotes != null) field('  Discharge notes', log.dischargeNotes!),
                    if (log.finalCondition != null) field('  Discharge condition', log.finalCondition!),
                    if (log.postTreatmentInstructions != null) field('  Special instructions', log.postTreatmentInstructions!),
                  ],
                ],
              );
            }(),
            pw.SizedBox(height: 6),
            pw.Text('Animal Record', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            () {
              final record = animalRecords.where((r) => r.sourceAnimalIndex == index).cast<AnimalRecord?>().firstWhere(
                    (r) => true,
                    orElse: () => null,
                  );
              if (record == null) {
                return pw.Text('No Animal Record created yet for this animal.', style: const pw.TextStyle(fontSize: 10));
              }
              return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                field('Name/label', record.name),
                field('Animal Record ID', record.id),
                field('Species', record.species),
                field('Breed', record.breed),
                field('Sex', record.sex),
                field('Size', record.size),
                field('Estimated age', record.age),
                field('Weight', record.health.weightKg != null ? '${record.health.weightKg} kg' : 'Not recorded'),
                field('Temperament', _s(record.keyCharacteristics)),
                field('Vaccination history', record.vaccinated ? 'Vaccinated' : 'Not recorded/confirmed'),
                field('Known conditions', _s(record.health.chronicConditions)),
                field('Allergies', _s(record.health.allergies)),
                field('Sterilization status', record.spayedNeutered ? 'Sterilized' : 'Not sterilized/unknown'),
              ]);
            }(),
          ],
        ],
      ),
    );

    return doc.save();
  }

  /// Full flow: fetches treatment logs + animal records for the case,
  /// builds the PDF, writes the lightweight audit record (never the PDF
  /// bytes themselves — see transferExports/{exportId} spec), and hands the
  /// bytes to the native share sheet via `printing` (Preview + Share both
  /// come from the same OS-native flow `Printing.sharePdf` opens).
  Future<void> exportAndShare({
    required RescueCase rescueCase,
    required List<int> animalIndexes,
    required String destinationType,
    required String destinationName,
    required String transferredByUid,
    required String transferredByName,
    String sourceOrganization = 'Respawnd',
  }) async {
    final treatmentLogs = await _caseRepo.streamTreatmentLogs(rescueCase.id).first;
    final animalRecords = await _animalRepo.streamRecordsForCase(rescueCase.id).first;

    final bytes = await buildPdf(
      rescueCase: rescueCase,
      animalIndexes: animalIndexes,
      treatmentLogs: treatmentLogs,
      animalRecords: animalRecords,
      destinationType: destinationType,
      destinationName: destinationName,
      transferredByName: transferredByName,
      sourceOrganization: sourceOrganization,
    );

    final exportRef = FirebaseFirestore.instance.collection('transferExports').doc();
    await exportRef.set({
      'caseId': rescueCase.id,
      'animalIndexes': animalIndexes,
      'animalRecordIds': animalRecords
          .where((r) => animalIndexes.contains(r.sourceAnimalIndex))
          .map((r) => r.id)
          .toList(),
      'organizationId': rescueCase.organizationId,
      'destinationType': destinationType,
      'destinationId': destinationName,
      'createdBy': transferredByUid,
      'createdAt': FieldValue.serverTimestamp(),
      'sectionsIncluded': const ['rescueReport', 'treatment', 'animalRecord'],
    });

    await Printing.sharePdf(bytes: bytes, filename: 'transfer_${rescueCase.id}.pdf');
  }

  /// Opens the OS print/preview sheet (spec's "Preview") for the same PDF,
  /// without writing a new audit record — used by a "Preview" action
  /// distinct from "Share".
  Future<void> preview({
    required RescueCase rescueCase,
    required List<int> animalIndexes,
    required String destinationType,
    required String destinationName,
    required String transferredByName,
    String sourceOrganization = 'Respawnd',
  }) async {
    final treatmentLogs = await _caseRepo.streamTreatmentLogs(rescueCase.id).first;
    final animalRecords = await _animalRepo.streamRecordsForCase(rescueCase.id).first;
    final bytes = await buildPdf(
      rescueCase: rescueCase,
      animalIndexes: animalIndexes,
      treatmentLogs: treatmentLogs,
      animalRecords: animalRecords,
      destinationType: destinationType,
      destinationName: destinationName,
      transferredByName: transferredByName,
      sourceOrganization: sourceOrganization,
    );
    await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'transfer_${rescueCase.id}.pdf');
  }

  /// Saves the PDF to a temporary app-scoped file and hands it to the
  /// share sheet with "save"-oriented intent (same underlying share sheet —
  /// Android/iOS both let the user pick "Save to Files/Drive" from it,
  /// there is no separate direct-to-disk API without broad storage
  /// permissions this app doesn't otherwise request). The temp file is
  /// deleted right after handing off, per the privacy spec's "delete
  /// temporary local/export files when appropriate".
  Future<void> saveToDevice({
    required RescueCase rescueCase,
    required List<int> animalIndexes,
    required String destinationType,
    required String destinationName,
    required String transferredByName,
    String sourceOrganization = 'Respawnd',
  }) async {
    final treatmentLogs = await _caseRepo.streamTreatmentLogs(rescueCase.id).first;
    final animalRecords = await _animalRepo.streamRecordsForCase(rescueCase.id).first;
    final bytes = await buildPdf(
      rescueCase: rescueCase,
      animalIndexes: animalIndexes,
      treatmentLogs: treatmentLogs,
      animalRecords: animalRecords,
      destinationType: destinationType,
      destinationName: destinationName,
      transferredByName: transferredByName,
      sourceOrganization: sourceOrganization,
    );
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/transfer_${rescueCase.id}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes);
    try {
      await Share.shareXFiles([XFile(file.path)], text: 'Transfer packet — Case ${rescueCase.id}');
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}
