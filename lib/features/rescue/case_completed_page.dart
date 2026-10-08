import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/case_summary_page.dart';

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
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.pets,
                              size: 48,
                              color: AppColors.textPrimary),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Text(
                      _isRejected
                          ? 'Report Reviewed'
                          : (_isClosed ? 'Case Closed' : 'Case Completed!'),
                      style: GoogleFonts.tiltWarp(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),

                    const SizedBox(height: 12),

                    Text(
                      _isRejected
                          ? 'Thank you for reporting this. Our team reviewed it and determined it doesn\'t require rescue intervention at this time.'
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
                      _isRejected
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  fixedSize:
                  Size(MediaQuery.of(context).size.width * 0.55, 50),
                ),
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