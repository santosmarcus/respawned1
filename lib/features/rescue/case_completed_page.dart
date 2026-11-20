import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/features/rescue/case_summary_page.dart';

/// Every animal of a Community-Adoption-eligible report was adopted
/// (CommunityAdoptionRepository.adopt closes the case once all are
/// claimed). Its status is 'closed' like a case whose animal passed away,
/// so this is what tells the two apart.
bool isCommunityAdoptedCase(Map<String, dynamic> data) {
  final s = (data['status'] as String? ?? '').toLowerCase();
  if (s != 'closed') return false;
  final ids = data['communityAdoptionIds'];
  final claimed = data['claimedAnimalIndexes'];
  return (ids is List && ids.isNotEmpty) || (claimed is List && claimed.isNotEmpty);
}

/// A Pet Surrender the organization finished taking in.
bool isCompletedSurrenderCase(Map<String, dynamic> data) {
  final s = (data['status'] as String? ?? '').toLowerCase();
  return data['rescueType'] == 'Pet Surrender' && s.contains('completed');
}

/// The title the success page, the case summary and History use for a
/// finished report.
String finishedCaseTitle(Map<String, dynamic> data) {
  final s = (data['status'] as String? ?? '').toLowerCase();
  if (isCommunityAdoptedCase(data)) return 'Adopted';
  if (isCompletedSurrenderCase(data)) return 'Surrender Completed';
  if (s == 'rejected') return 'Report Reviewed';
  if (s == 'closed' || s.contains('ended')) return 'Case Closed';
  return 'Case Completed';
}

class CaseCompletedPage extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> caseData;

  const CaseCompletedPage({
    super.key,
    required this.caseId,
    required this.caseData,
  });

  bool get _isClosed {
    final s = (caseData['status'] as String? ?? '').toLowerCase();
    return s == 'closed' || s.contains('ended');
  }

  bool get _isRejected {
    final s = (caseData['status'] as String? ?? '').toLowerCase();
    return s == 'rejected';
  }

  bool get _isCommunityAdopted => isCommunityAdoptedCase(caseData);
  bool get _isSurrender => isCompletedSurrenderCase(caseData);

  String? get _rejectionReasonLabel {
    final name = caseData['rejectionReason'] as String?;
    if (name == null || name.isEmpty) return null;
    final reason = RejectionReason.fromName(name);
    if (reason == RejectionReason.other) {
      final other = caseData['rejectionReasonOther'] as String?;
      return (other?.trim().isNotEmpty ?? false) ? other!.trim() : 'Other';
    }
    return reason.label;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.lavenderrspwn,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: AppColors.textPrimary.withValues(alpha: 0.2),
                            width: 4),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Image.asset(
                          _isClosed
                              ? 'assets/icon/animalshelter.png'
                              : 'assets/icon/animalshelter.png',
                          color: AppColors.textPrimary,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                              Icons.pets,
                              size: 48,
                              color: AppColors.textPrimary),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      _isCommunityAdopted
                          ? 'Adopted!'
                          : _isSurrender
                          ? 'Surrender Completed!'
                          : _isRejected
                          ? 'Report Reviewed'
                          : (_isClosed ? 'Case Closed' : 'Case Completed!'),
                      style: GoogleFonts.tiltWarp(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _isCommunityAdopted
                          ? 'Every animal from your report found a home through Community Adoption. Thank you for caring for them and finding them a family!'
                          : _isSurrender
                          ? 'Your pet is now in the care of our partner organization. Thank you for trusting them and for choosing a safe, responsible surrender.'
                          : _isRejected
                          ? (_rejectionReasonLabel != null
                          ? 'Thank you for reporting this case! The team reviewd it and determined it does not require rescue intervention at this time. Reason: $_rejectionReasonLabel'
                          : 'No reason was provided for this rejection.')
                          : (_isClosed
                          ? 'With heavy hearts, we share that this animal passed away despite everyone\'s rescue efforts.'
                          : 'The animal is now in treatment and in the care of our partner organization. Thank you for your compassion and for helping make this rescue possible.'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _isCommunityAdopted
                          ? 'The adopters will share post-adoption updates for the first two weeks. You can find this report and the updates any time in your History.'
                          : _isSurrender
                          ? 'The organization will look after your pet and work on finding it a new home. You can find this report any time in your History.'
                          : _isRejected
                          ? 'You can review the reason and full details any time from your report history.'
                          : (_isClosed
                          ? 'We\'re grateful for your compassion and support, which gave this animal a chance at care, comfort, and dignity in its final moments. Thank you for helping make this rescue possible — we hope you\'ll continue supporting future efforts.'
                          : 'Please stand by for the progress of this animal or contact the organization if you\'re interested in adopting or sponsoring this animal.'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),

              ElevatedButton(
                onPressed: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CaseSummaryPage(
                      caseId: caseId,
                      caseData: caseData,
                      fromCompletionFlow: true,
                    ),
                  ),
                ),
                style: AppButtons.primary.copyWith(fixedSize: WidgetStatePropertyAll(Size(MediaQuery.of(context).size.width * 0.55, 50))),
                child: Text('Next',
                    style: Theme.of(context).textTheme.headlineLarge),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}