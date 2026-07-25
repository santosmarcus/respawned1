import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/closure_reason.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';

typedef CloseCaseResult = ({
  ClosureReason reason,
  String details,
  String? lastKnownLocation,
  String? clinicUnavailableDetails,
});

/// Shared Close Case confirmation form (spec §2/§10) — every exception
/// path (owner found, aggressive animal, animal moved, clinic unavailable,
/// duplicate, ...) opens this SAME sheet with a pre-selected reason rather
/// than building its own; the actual close write is
/// RescueCaseRepository.closeCase, called by the caller with this
/// sheet's result, once. Returns null if dismissed without confirming.
Future<CloseCaseResult?> showCloseCaseSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  ClosureReason? initialReason,
}) {
  return showModalBottomSheet<CloseCaseResult>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _CloseCaseSheetBody(rescueCase: rescueCase, initialReason: initialReason),
  );
}

class _CloseCaseSheetBody extends StatefulWidget {
  final RescueCase rescueCase;
  final ClosureReason? initialReason;
  const _CloseCaseSheetBody({required this.rescueCase, this.initialReason});

  @override
  State<_CloseCaseSheetBody> createState() => _CloseCaseSheetBodyState();
}

class _CloseCaseSheetBodyState extends State<_CloseCaseSheetBody> {
  late ClosureReason? _reason = widget.initialReason;
  final _detailsController = TextEditingController();
  final _locationController = TextEditingController();
  final _clinicDetailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    _locationController.dispose();
    _clinicDetailsController.dispose();
    super.dispose();
  }

  bool get _canConfirm {
    if (_reason == null || _detailsController.text.trim().isEmpty) return false;
    if (_reason!.needsLastKnownLocation && _locationController.text.trim().isEmpty) return false;
    if (_reason!.needsClinicDetails && _clinicDetailsController.text.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.rescueCase;
    final hasActiveAssignment = c.assignedVolunteerName != null || (c.raw['currentAssignmentId'] as String?) != null;

    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Close Case', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            // Pre-close summary (spec §10).
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _summaryRow('Case ID', c.id),
                  _summaryRow('Current phase', c.status.label),
                  _summaryRow('Animals affected', '${c.animalCount}'),
                  _summaryRow('Active transporter', c.assignedVolunteerName ?? 'None'),
                  _summaryRow('Selected clinic', c.vetClinicName ?? 'None'),
                ],
              ),
            ),
            if (hasActiveAssignment) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFE0A353).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  'Closing will cancel the pending/active transporter assignment, current route, and clinic destination.',
                  style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFF9C6B10)),
                ),
              ),
            ],

            const SizedBox(height: 16),
            Text('Closure Reason', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            ...ClosureReason.values.map((reason) => RadioListTile<ClosureReason>(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: reason,
                  groupValue: _reason,
                  activeColor: AppColors.textPrimary,
                  title: Text(reason.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                  onChanged: (v) => setState(() => _reason = v),
                )),

            const SizedBox(height: 8),
            Text('Detailed Explanation', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: _detailsController,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(hintText: 'What happened, and why the case is being closed'),
            ),

            if (_reason?.needsLastKnownLocation ?? false) ...[
              const SizedBox(height: 12),
              Text('Last Known Location', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: _locationController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Where the animal was last seen'),
              ),
            ],

            if (_reason?.needsClinicDetails ?? false) ...[
              const SizedBox(height: 12),
              Text('Clinic Availability Issue / Attempts Made', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              TextField(
                controller: _clinicDetailsController,
                maxLines: 2,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'e.g. clinic closed, no answer, no alternative found because…'),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _canConfirm
                        ? () => Navigator.pop(
                              context,
                              (
                                reason: _reason!,
                                details: _detailsController.text.trim(),
                                lastKnownLocation:
                                    _reason!.needsLastKnownLocation ? _locationController.text.trim() : null,
                                clinicUnavailableDetails:
                                    _reason!.needsClinicDetails ? _clinicDetailsController.text.trim() : null,
                              ),
                            )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE05353),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.slaterspwn,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      elevation: 0,
                    ),
                    child: const Text('Close Case'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(width: 130, child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
            Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          ],
        ),
      );
}
