import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/features/admin/animals/create_animal_record_page.dart';
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
          return _AllRecordsCreatedView(total: animals.length);
        }

        return CreateAnimalRecordPage(
          key: ValueKey('animal-record-$caseId-$nextIndex'),
          prefillData: _prefillFor(c, animals[nextIndex]),
          linkedCaseId: caseId,
          sourceAnimalIndex: nextIndex,
          stepCurrent: nextIndex + 1,
          stepTotal: animals.length,
        );
      },
    );
  }
}

class _AllRecordsCreatedView extends StatelessWidget {
  final int total;
  const _AllRecordsCreatedView({required this.total});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Animal Records', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, size: 48, color: AppColors.greenrspwn),
              const SizedBox(height: 12),
              Text('$total of $total records created',
                  style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Text('All animal records for this case are complete.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
