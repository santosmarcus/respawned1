import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/create_animal_record_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Drives one animal-record creation per entry in `case.animals[]` (or a
/// single legacy entry for older single-animal cases), reusing
/// CreateAnimalRecordPage unchanged — this is a thin controller, not a
/// second form. Progress is derived entirely from
/// completedAnimalRecordIndexesProvider's live Firestore state, so
/// navigating away and back (or reopening the case later) always resumes
/// at the correct next animal — nothing is tracked only in local widget
/// state that could be lost.
class AnimalRecordsFlowPage extends ConsumerWidget {
  final String caseId;
  final Map<String, dynamic> caseData;
  const AnimalRecordsFlowPage({super.key, required this.caseId, required this.caseData});

  List<Map<String, dynamic>> _animalEntries(RescueCase c) {
    if (c.animals.isNotEmpty) return c.animals;
    // Legacy single-animal case: one synthetic entry from the flat fields.
    return [
      {
        'species': c.animalType,
        'breed': c.raw['breed'],
        'sex': c.raw['sex'],
        'size': c.raw['size'],
        'colorMarkings': c.raw['colorMarkings'],
      },
    ];
  }

  Map<String, dynamic> _prefillFor(RescueCase c, Map<String, dynamic> animal) {
    return {
      'species': animal['species'] ?? c.animalType,
      'breed': animal['breed'],
      'sex': animal['sex'],
      'size': animal['size'],
      'colorMarkings': animal['colorMarkings'],
      'description': c.condition,
      'reporterName': c.reporterName,
      'vetClinicName': c.vetClinicName,
      'photoUrl': c.photoUrls.isNotEmpty ? c.photoUrls.first : null,
      'rescueDate': c.raw['createdAt'],
      'scannedTagId': c.scannedTagId,
      'rescuedBy': 'Loved by the Gapz',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = RescueCase.fromMap(caseId, caseData);
    final animals = _animalEntries(c);
    final completedAsync = ref.watch(completedAnimalRecordIndexesProvider(caseId));

    return completedAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Animal Records')),
        body: Center(child: Text('Could not load progress: $e')),
      ),
      data: (completed) {
        final nextIndex = List.generate(animals.length, (i) => i).cast<int?>().firstWhere(
              (i) => !completed.contains(i),
              orElse: () => null,
            );

        if (nextIndex == null) {
          return _RecordsForCaseView(caseId: caseId, totalAnimals: animals.length);
        }

        return CreateAnimalRecordPage(
          key: ValueKey('animal-record-$caseId-$nextIndex'),
          prefillData: _prefillFor(c, animals[nextIndex]),
          linkedCaseId: caseId,
          sourceAnimalIndex: nextIndex,
          stepCurrent: nextIndex + 1,
          stepTotal: animals.length,
          popOnSuccess: false,
        );
      },
    );
  }
}

/// Shown once every expected animal record has been created — replaces
/// what used to be a dead-end "N of N records created" text screen with
/// actual navigation into the created record(s), and reconciles Intake
/// completion (spec §6/§7) the moment the last record lands, rather than
/// waiting for the admin to navigate back to Intake Details.
class _RecordsForCaseView extends ConsumerStatefulWidget {
  final String caseId;
  final int totalAnimals;
  const _RecordsForCaseView({required this.caseId, required this.totalAnimals});

  @override
  ConsumerState<_RecordsForCaseView> createState() => _RecordsForCaseViewState();
}

class _RecordsForCaseViewState extends ConsumerState<_RecordsForCaseView> {
  bool _hasCheckedIntakeCompletion = false;
  bool _hasAutoNavigated = false;

  Future<void> _checkIntakeCompletion() async {
    if (_hasCheckedIntakeCompletion) return;
    _hasCheckedIntakeCompletion = true;
    try {
      final caseSnap = await FirebaseFirestore.instance.collection('cases').doc(widget.caseId).get();
      if (!caseSnap.exists) return;
      final c = RescueCase.fromFirestore(caseSnap);
      await ref.read(rescueCaseRepositoryProvider).checkAndCompleteIntakeIfDue(
            c,
            totalAnimalsExpected: widget.totalAnimals,
            completedCount: widget.totalAnimals,
          );
    } catch (_) {
      // Best-effort — IntakeDetailPage's own reactive post-frame check
      // (which drove this same repository method) remains the primary,
      // guaranteed-to-eventually-fire path if this one is ever skipped.
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkIntakeCompletion());
    final recordsAsync = ref.watch(recordsForCaseProvider(widget.caseId));

    return recordsAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Animal Records')),
        body: Center(
          child: Text('Could not load animal records: $e', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
      ),
      data: (records) {
        if (records.isEmpty) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              backgroundColor: AppColors.textPrimary,
              leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
              title: Text('Animal Records', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'These animal records could not be found — they may have been removed. '
                  'Please contact your organization admin if this is unexpected.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }

        if (records.length == 1) {
          final only = records.first;
          if (!_hasAutoNavigated) {
            _hasAutoNavigated = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => AnimalRecordDetailPage(animalId: only.id, data: only.raw)),
              );
            });
          }
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
            title: Text('Animal Records', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text('${records.length} of ${widget.totalAnimals} records created',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _RecordListTile(record: records[i]),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _RecordListTile extends StatelessWidget {
  final AnimalRecord record;
  const _RecordListTile({required this.record});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnimalRecordDetailPage(animalId: record.id, data: record.raw)),
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: record.photoUrls.isNotEmpty
                  ? Image.network(record.photoUrls.first, width: 64, height: 64, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph())
                  : _ph(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(record.name.isNotEmpty ? record.name : record.species,
                      style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  Text(record.species, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  Text('Record #${shortCaseId(record.id)} · ${record.status}',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _ph() => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );
}
