// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_form_widgets.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_upload_widgets.dart';

/// Step 1 — fill out the adoption form, uploads and agreements.
class AdoptionIntroStep extends StatelessWidget {
  const AdoptionIntroStep({
    super.key,
    required this.form,
    required this.readOnly,
    required this.isSubmitting,
    required this.onAddHomePhotos,
    required this.onPickUploadFile,
    required this.onSubmit,
    required this.onChanged,
  });

  final AdoptionFormController form;

  /// True while reviewing a previous step (read only).
  final bool readOnly;
  final bool isSubmitting;
  final VoidCallback onAddHomePhotos;
  final Future<void> Function({required void Function(File) onPicked})
  onPickUploadFile;
  final VoidCallback onSubmit;
  final VoidCallback onChanged;

  /// Applies [fn] to the shared form state, then asks the page to rebuild —
  /// the same effect as the page's own `setState(fn)` before extraction.
  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fill out adoption form',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Ready to give a rescue a loving forever home?',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Fill out this quick form to help us match you with the right rescue and confirm eligibility for adoption.',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 24),

        Form(
          key: form.formKey,
          child: Column(
            children: [
              // Personal Information
              AdoptionSectionTitle('Personal Information'),
              const SizedBox(height: 12),
              AdoptionFormField(
                controller: form.nameCtrl,
                label: 'Name',
                hint: ' ',
              ),
              const SizedBox(height: 12),
              AdoptionFormField(
                controller: form.emailCtrl,
                label: 'Email',
                hint: 'Email@email.com',
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: AdoptionFormField(
                      controller: form.phoneCtrl,
                      label: 'Number',
                      hint: '+63 989 989 989',
                      keyboardType: TextInputType.phone,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AdoptionFormField(
                      controller: form.ageCtrl,
                      label: 'Age',
                      hint: ' ',
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AdoptionFormField(
                controller: form.homeAddressCtrl,
                label: 'Home Address',
                hint: 'Enter your complete home address',
                maxLines: 3,
              ),

              const SizedBox(height: 22),

              // Household & Living Information
              AdoptionSectionTitle('Household & Living Information'),
              const SizedBox(height: 8),
              AdoptionRadioGroup<String>(
                label: 'Residence Type',
                value: form.residenceType,
                options: const [
                  'House',
                  'Apartment',
                  'Condominium',
                  'Townhouse',
                  'Other',
                ],
                onChanged: (v) => _set(() => form.residenceType = v),
              ),
              if (form.residenceType == 'Other') ...[
                const SizedBox(height: 8),
                AdoptionFormField(
                  controller: form.residenceOtherCtrl,
                  label: 'Please specify',
                  hint: ' ',
                ),
              ],
              const SizedBox(height: 16),
              AdoptionRadioGroup<String>(
                label: 'Ownership Status',
                value: form.ownershipStatus,
                options: const [
                  'Owned',
                  'Renting (Allowed Pets)',
                  'Living with Parents',
                ],
                onChanged: (v) => _set(() => form.ownershipStatus = v),
              ),
              const SizedBox(height: 12),
              AdoptionCounterField(
                label: 'Number of Household Members',
                value: form.householdMembers,
                onChanged: (v) => _set(() => form.householdMembers = v),
              ),

              const SizedBox(height: 22),

              // Pet Experience
              AdoptionSectionTitle('Pet Experience'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Owned pets before?',
                  style: GoogleFonts.zain(fontSize: 14),
                ),
                value: form.hadPetsBefore,
                onChanged: (v) => _set(() => form.hadPetsBefore = v!),
              ),
              const SizedBox(height: 8),
              Text(
                'Current pets',
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              AdoptionCounterField(
                label: 'Dogs',
                value: form.currentDogs,
                onChanged: (v) => _set(() => form.currentDogs = v),
              ),
              AdoptionCounterField(
                label: 'Cats',
                value: form.currentCats,
                onChanged: (v) => _set(() => form.currentCats = v),
              ),
              AdoptionCounterField(
                label: 'Birds',
                value: form.currentBirds,
                onChanged: (v) => _set(() => form.currentBirds = v),
              ),
              AdoptionCounterField(
                label: 'Fish',
                value: form.currentFish,
                onChanged: (v) => _set(() => form.currentFish = v),
              ),
              AdoptionCounterField(
                label: 'Reptiles',
                value: form.currentReptiles,
                onChanged: (v) => _set(() => form.currentReptiles = v),
              ),
              AdoptionCounterField(
                label: 'Other',
                value: form.currentOther,
                onChanged: (v) => _set(() => form.currentOther = v),
              ),
              if (form.currentOther > 0) ...[
                const SizedBox(height: 8),
                AdoptionFormField(
                  controller: form.currentOtherTypeCtrl,
                  label: 'Specify other pet type',
                  hint: ' ',
                ),
              ],
              const SizedBox(height: 16),
              AdoptionRadioGroup<String>(
                label: 'Are all current pets vaccinated?',
                value: form.petsVaccinated,
                options: const ['Yes', 'Some', 'None', 'Not Applicable'],
                onChanged: (v) => _set(() => form.petsVaccinated = v),
              ),
              const SizedBox(height: 16),
              AdoptionRadioGroup<String>(
                label: 'Are all current pets spayed/neutered?',
                value: form.petsSpayedNeutered,
                options: const ['Yes', 'Some', 'None', 'Not Applicable'],
                onChanged: (v) => _set(() => form.petsSpayedNeutered = v),
              ),

              const SizedBox(height: 22),

              // Lifestyle & Care
              AdoptionSectionTitle('Lifestyle & Care'),
              const SizedBox(height: 8),
              AdoptionRadioGroup<String>(
                label: 'Hours animal will be left alone',
                value: form.hoursAlone,
                options: const [
                  'Less than 2 hours',
                  '2-4',
                  '5-8',
                  'More than 8 hours',
                ],
                onChanged: (v) => _set(() => form.hoursAlone = v),
              ),
              const SizedBox(height: 12),
              Text(
                'Primary Caregiver',
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<String>(
                initialValue: form.primaryCaregiver,
                hint: Text(
                  'Select',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
                style: GoogleFonts.zain(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
                items: kCaregiverOptions
                    .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                    .toList(),
                onChanged: (v) => _set(() => form.primaryCaregiver = v),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.yellowrspwn.withValues(alpha: 0.3),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AdoptionRadioGroup<String>(
                label: 'Where will pet stay?',
                value: form.petStayLocation,
                options: const ['Indoors', 'Outdoors', 'Mixed'],
                onChanged: (v) => _set(() => form.petStayLocation = v),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Can you afford? (check all that apply)',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const AdoptionInfoTooltip(
                    message:
                        'According to the McDuffy 2026 Guide, the starter budget for owning a pet in the Philippines is approximately ₱2,400 per month. This covers essential expenses such as food, veterinary care, grooming, supplies, treats, and emergency savings.\n\n'
                        'Estimated monthly costs:\n'
                        '• Food – ₱500\n'
                        '• Vaccines – ₱250\n'
                        '• Flea & Tick Prevention – ₱500\n'
                        '• Grooming – ₱250\n'
                        '• Supplies & Replacements – ₱300\n'
                        '• Treats – ₱200\n'
                        '• Emergency Fund – ₱250\n'
                        '• Miscellaneous – ₱150',
                  ),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Food'),
                value: form.canAffordFood,
                onChanged: (v) => _set(() => form.canAffordFood = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vaccinations'),
                value: form.canAffordVaccinations,
                onChanged: (v) => _set(() => form.canAffordVaccinations = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Vet Visits'),
                value: form.canAffordVetVisits,
                onChanged: (v) => _set(() => form.canAffordVetVisits = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Emergency Medical Care'),
                value: form.canAffordEmergencyCare,
                onChanged: (v) => _set(() => form.canAffordEmergencyCare = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Grooming'),
                value: form.canAffordGrooming,
                onChanged: (v) => _set(() => form.canAffordGrooming = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Care Supplies'),
                value: form.canAffordCareSupplies,
                onChanged: (v) => _set(() => form.canAffordCareSupplies = v!),
              ),
              const SizedBox(height: 12),

              AdoptionFormField(
                controller: form.reasonCtrl,
                label: 'Why do you want to adopt?',
                hint: 'Enter',
                maxLines: 4,
              ),

              const SizedBox(height: 22),

              // Required Uploads
              AdoptionSectionTitle('Required Uploads'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  AdoptionUploadBox(
                    label: 'Government ID',
                    file: form.governmentIdFile,
                    isUploading: form.isUploadingGovId,
                    onTap: () => onPickUploadFile(
                      onPicked: (f) => _set(() => form.governmentIdFile = f),
                    ),
                  ),
                  AdoptionUploadBox(
                    label: 'Proof of Address',
                    file: form.proofOfAddressFile,
                    isUploading: form.isUploadingProof,
                    onTap: () => onPickUploadFile(
                      onPicked: (f) => _set(() => form.proofOfAddressFile = f),
                    ),
                  ),
                  /*AdoptionUploadBox(
                    label: 'Digital Signature',
                    file: _digitalSignatureFile,
                    isUploading: form.isUploadingSignature,
                    onTap: () => onPickUploadFile(
                      onPicked: (f) => _set(() => _digitalSignatureFile = f),
                    ),
                  ),*/
                ],
              ),

              const SizedBox(height: 18),

              // Home Photos — multiple images, not a single fixed slot: add
              // more afterward, remove any one before submitting, every
              // selected photo is uploaded and its URL saved (never
              // overwritten by only the most recent pick).
              HomePhotosPicker(
                existingUrls: form.existingHomePhotoUrls,
                newFiles: form.homePhotosFiles,
                isUploading: form.isUploadingHomePhotos,
                onAdd: onAddHomePhotos,
                onRemoveExisting: (i) =>
                    _set(() => form.existingHomePhotoUrls.removeAt(i)),
                onRemoveNew: (i) =>
                    _set(() => form.homePhotosFiles.removeAt(i)),
              ),

              const SizedBox(height: 22),

              // Agreements
              AdoptionSectionTitle('Agreements'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I will provide proper care'),
                value: form.agreeCare,
                onChanged: (v) => _set(() => form.agreeCare = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I will not abandon the animal'),
                value: form.agreeNoAbandon,
                onChanged: (v) => _set(() => form.agreeNoAbandon = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I agree to post-adoption follow ups'),
                value: form.agreeFollowup,
                onChanged: (v) => _set(() => form.agreeFollowup = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Information provided is accurate'),
                value: form.agreeAccurate,
                onChanged: (v) => _set(() => form.agreeAccurate = v!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I understand approval is not guaranteed'),
                value: form.agreeNotGuaranteed,
                onChanged: (v) => _set(() => form.agreeNotGuaranteed = v!),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        if (!readOnly) ...[
          AdoptionPrimaryButton(
            label: isSubmitting ? 'Submitting...' : "Submit",
            onTap: isSubmitting ? null : onSubmit,
          ),
          const SizedBox(height: 10),
          AdoptionSecondaryButton(
            label: 'Cancel',
            onTap: isSubmitting ? null : () => Navigator.pop(context),
          ),
        ],

        const SizedBox(height: 24),
      ],
    );
  }
}
