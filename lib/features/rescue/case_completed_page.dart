import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';

class CaseCompletedPage extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> caseData;

  const CaseCompletedPage({
    super.key,
    required this.caseId,
    required this.caseData,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Case Completed',
            style: Theme.of(context).textTheme.displaySmall),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Success icon
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
              child: const Icon(Icons.pets,
                  size: 48, color: AppColors.textPrimary),
            ),

            const SizedBox(height: 20),

            Text(
              'Case Completed!',
              style: GoogleFonts.tiltWarp(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),

            const SizedBox(height: 12),

            Text(
              'The animal is now in treatment and in the care of our partner organization. Thank you for your compassion and for helping make this rescue possible.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),

            const SizedBox(height: 8),

            Text(
              'Please stand by for the progress of this animal or contact the organization if you\'re interested in adopting or sponsoring this animal.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary),
            ),

            const SizedBox(height: 32),

            // Summary section
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Summary',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary)),
            ),

            const SizedBox(height: 12),

            // Case media
            Text('Case Media',
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Row(
              children: [
                _MediaBox(),
                const SizedBox(width: 12),
                _MediaBox(),
              ],
            ),

            const SizedBox(height: 16),

            // Case details
            _DetailRow('Reporter Name', caseData['reporterName']),
            _DetailRow('Reporter Mobile Number', caseData['reporterPhone']),
            _DetailRow('Pet Transporter Name',
                caseData['transporterName'] ?? '-'),
            _DetailRow('Pet Transporter Mobile Number',
                caseData['transporterPhone'] ?? '-'),
            _DetailRow('Address', caseData['address']),
            _DetailRow('Vet Clinic Address',
                caseData['vetClinicAddress'] ?? '-'),
            _DetailRow('Description', caseData['condition']),
            _DetailRow('Type of Animal', caseData['animalType']),
            _DetailRow('Urgency', caseData['urgency']),
            _DetailRow('Coordination', caseData['coordinateWithShelter']),
            if (caseData['coordinateWithShelter'] == 'no') ...[
              _DetailRow('Witness Name', caseData['witnessName']),
              _DetailRow(
                  'Witness Mobile Number', caseData['witnessPhone']),
            ],
            _DetailRow(
                'Interest to adopt', caseData['interestedToAdopt']),

            const SizedBox(height: 32),

            // Next button
            ElevatedButton(
              onPressed: () => Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const HomeScreen()),
                    (route) => false,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                fixedSize:
                Size(MediaQuery.of(context).size.width * 0.55, 50),
              ),
              child: Text('Next',
                  style: Theme.of(context).textTheme.headlineLarge),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _MediaBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.slaterspwn,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textSecondary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          Text(value ?? '-',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}