import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/currency.dart';

/// TODO(fundraiser-backend): there is no fundraiser feature anywhere in
/// this app yet (no model, no Firestore collection, no donation-page
/// linkage). This screen is a clearly-marked DRAFT that only previews what
/// a fundraiser would be prefilled with from a treatment case — it never
/// writes anything to Firestore and never creates a real/active fundraiser.
/// Wiring it up for real requires: a `fundraisers` collection, a donation
/// flow that can pay into a specific case's outstanding balance, and a way
/// for [FundingSource.fundraiser] expenses to actually reconcile against
/// funds raised here.
class CreateFundraiserDraftPage extends StatelessWidget {
  final RescueCase rescueCase;
  final double outstandingBalance;
  const CreateFundraiserDraftPage({
    super.key,
    required this.rescueCase,
    required this.outstandingBalance,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = rescueCase.photoUrls.isNotEmpty ? rescueCase.photoUrls.first : null;
    // A round, slightly-padded suggestion above the outstanding balance —
    // purely a starting point for whoever eventually builds the real
    // fundraiser form; not a computed recommendation of any real value.
    final suggestedGoal = (outstandingBalance * 1.1 / 500).ceil() * 500;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Create Fundraiser (Draft)',
            style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE0A353).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE0A353)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.construction_outlined, size: 18, color: Color(0xFF9C6B10)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Draft only — the fundraiser backend does not exist yet. '
                      'Nothing here is saved or published.',
                      style: GoogleFonts.zain(fontSize: 12, color: const Color(0xFF9C6B10)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            if (thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(thumbnail, height: 160, width: double.infinity, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),

            Text('#${rescueCase.shortCaseId}',
                style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(rescueCase.speciesSummary,
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            if ((rescueCase.vetClinicName ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(rescueCase.vetClinicName!,
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ],

            const SizedBox(height: 20),
            _DraftField('Outstanding Balance', formatPeso(outstandingBalance)),
            _DraftField('Suggested Goal Amount', formatPeso(suggestedGoal)),
            _DraftField(
              'Reason / Treatment Summary',
              rescueCase.condition?.isNotEmpty == true
                  ? rescueCase.condition!
                  : 'Ongoing treatment for ${rescueCase.speciesSummary} at '
                      '${rescueCase.vetClinicName ?? 'the assigned clinic'}.',
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: null, // draft only — intentionally disabled
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.slaterspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text('Publish Fundraiser (Not Available Yet)',
                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftField extends StatelessWidget {
  final String label;
  final String value;
  const _DraftField(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
