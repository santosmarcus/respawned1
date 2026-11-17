import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_adoption.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Release to the adopter (Rescue gaps 6/10). Only for a case with a
/// confirmed adopter: the adopter filled in the adoption request from Track
/// Case (accepting the vet-fee, obligations and pickup-window agreements)
/// and staff confirmed it on Rescue Details.
///
/// This doesn't hand the animal over yet. It marks the discharged
/// animal(s) ready for pickup and starts the [kAdopterPickupWindow]: the
/// adopter is told where and by when. Staff confirm the actual pickup on
/// Rescue Details, which finishes the adoption on Release Details. Not
/// collected in time: the request is closed and the animal goes to the
/// shelter, or is flagged for referral if the shelter is full.
Future<bool> showReleaseAnimalSheet(
    BuildContext context, {
      required RescueCase rescueCase,
      List<int>? animalIndexes,
    }) async {
  final request = CaseAdoptionRequest.fromCase(rescueCase.raw);
  if (request == null || !request.isConfirmed) {
    ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
      request == null
          ? 'Release needs a confirmed adopter. The interested adopter applies from Track Case, then you confirm them on Rescue Details.'
          : 'The adoption request is "${request.status.label}". Confirm the adopter on Rescue Details first.',
      kind: AppMessageKind.error,
    ));
    return false;
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReleaseAnimalSheetBody(rescueCase: rescueCase, request: request, animalIndexes: animalIndexes),
  );
  return result ?? false;
}

class _ReleaseAnimalSheetBody extends ConsumerStatefulWidget {
  final RescueCase rescueCase;
  final CaseAdoptionRequest request;
  final List<int>? animalIndexes;
  const _ReleaseAnimalSheetBody({required this.rescueCase, required this.request, this.animalIndexes});

  @override
  ConsumerState<_ReleaseAnimalSheetBody> createState() => _ReleaseAnimalSheetBodyState();
}

class _ReleaseAnimalSheetBodyState extends ConsumerState<_ReleaseAnimalSheetBody> {
  late final _placeController = TextEditingController(
    text: widget.rescueCase.vetClinicName ?? (widget.rescueCase.raw['dropoffName'] as String?) ?? '',
  );
  bool _saving = false;

  @override
  void dispose() {
    _placeController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final place = _placeController.text.trim();
    if (place.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnackBar('Enter where the adopter collects the animal.', kind: AppMessageKind.error));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(rescueCaseRepositoryProvider).markReadyForAdopterPickup(
        caseId: widget.rescueCase.id,
        place: place,
        actorUid: 'admin',
        actorName: 'Admin Staff',
        animalIndexes: widget.animalIndexes,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(e is StateError ? e.message : 'Could not mark ready for pickup: $e', kind: AppMessageKind.error),
        );
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.rescueCase;
    final hours = kAdopterPickupWindow.inHours;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Release to Adopter', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            const _Label('Confirmed adopter'),
            Text(widget.request.adopterName,
                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text('Agreed to pay the vet fees, fulfil their obligations as an adopter and collect on time.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            const _Label('Case'),
            Text('#${c.shortCaseId} · ${c.speciesSummary}',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            const _Label('Pickup place'),
            TextField(
              controller: _placeController,
              decoration: const InputDecoration(
                hintText: 'Clinic or shelter name and address',
                isDense: true,
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              'The adopter is told the animal is ready and has $hours hours to collect it. Confirm the pickup on '
                  'Rescue Details when they arrive. If they don\'t come in time, the request is closed and the animal goes '
                  'to the shelter, or is flagged for referral if the shelter is full.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: AppButtons.outline,
                    child: Text('Cancel', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _confirm,
                    style: AppButtons.primary,
                    child: _saving
                        ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                        : Text('Ready for Pickup', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(text,
        style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
  );
}
