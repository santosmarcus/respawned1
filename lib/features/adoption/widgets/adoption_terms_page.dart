// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

// Terms and Conditions page (Adoption Day)
class AdoptionTermsAndConditionsPage extends StatelessWidget {
  final String animalName;

  const AdoptionTermsAndConditionsPage({super.key, required this.animalName});

  List<String> get _terms => [
    'I am over eighteen (18) years of age and can legally adopt.',
    '$animalName, hereinafter referred to as the pet, is being transferred '
        'to the adopting owner with the understanding that the adopter is '
        'taking possession of the pet to treat and be responsible for it as '
        'their own pet.',
    'The pet will be treated as a family member with loving care and '
        'affection. I/we will do my/our best to ensure the pet\'s safety and '
        'well-being.',
    'I/we will feed the pet at least twice a day and provide a fresh water '
        'supply at all times.',
    'I will not leave the pet outside my home and will not let it be '
        'isolated from the family. I will walk my pet on a leash or '
        'accompanied lead whenever I take my pet out, and will never keep it '
        'chained or tied up in a yard, garage, patio, balcony, or pen, or '
        'leave the pet outdoors, even in a fenced yard.',
    'I will not have the pet attack-trained, and will not use it for any '
        'purpose other than companionship. I will not have the pet\'s ears '
        'cropped, nor will I have its tail docked. I will never allow any '
        'physical, mental, or emotional abuse of the pet.',
    'I will take the pet to a licensed veterinarian when shots are due, but '
        'in no event later than one year after its last vet visit. I will '
        'ensure required and/or needed veterinary care, including rabies '
        'shots as required every one to three years, yearly booster shots '
        '(e.g. 5-in-1, 6-in-1 vaccines), and prompt treatment by a licensed '
        'veterinarian for any illness or injury.',
    'I/we affirm that no member of my household is allergic to or objects '
        'to keeping the pet, and that all household members have agreed to '
        'welcome the pet into the home.',
    'I/we agree to allow the organization to conduct reasonable post-'
        'adoption home visits or follow-up check-ins to ensure the pet\'s '
        'continued well-being.',
    'I/we understand that if, for any reason, I/we are no longer able to '
        'care for the pet, I/we will first return the pet to the '
        'organization rather than rehoming, abandoning, or surrendering it '
        'to another shelter or individual.',
    'I/we agree that a formal Adoption Agreement containing these terms '
        'will be reviewed and signed by both parties on the day of the '
        'adoption, and that this signed agreement will govern the adoption.',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(
                  Icons.chevron_left,
                  size: 30,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Terms and Conditions',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Please read and agree to the following terms and '
                      'conditions before you continue. A formal Adoption '
                      'Agreement containing these terms will be reviewed '
                      'and signed by both parties on the day of the '
                      'adoption.',
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'I hereby confirm the following terms and conditions '
                      'that:',
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...List.generate(_terms.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 22,
                              child: Text(
                                '${i + 1}.',
                                style: GoogleFonts.zain(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                _terms[i],
                                style: GoogleFonts.zain(
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
