// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/widgets/found_animal_card.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/rescue/widgets/owner_toggle.dart';

/// Lost Pet report: owner/finder toggle, then that side's fields.
class LostPetFields extends StatelessWidget {
  const LostPetFields({
    super.key,
    required this.form,
    required this.pinnedAddress,
    required this.onChanged,
  });

  final RescueFormController form;

  /// The map pin's resolved address (shown as last-seen / found location).
  final String pinnedAddress;
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
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Are you the owner?',
                style: GoogleFonts.zain(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              '*',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        OwnerToggle(
          label: 'Yes, I am the owner.',
          value: true,
          selected: form.isOwner,
          onSelected: (v) => _set(() => form.isOwner = v),
        ),
        const SizedBox(height: 4),
        OwnerToggle(
          label: 'No, I am a rescuer reporting a suspected lost pet.',
          value: false,
          selected: form.isOwner,
          onSelected: (v) => _set(() => form.isOwner = v),
        ),

        if (form.scannedTagId != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.greenrspwn.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.verified_outlined,
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A registered ID tag was found on scan — the owner will be '
                    'notified directly instead of a manual match.',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (form.isOwner == true)
          OwnerFields(
            form: form,
            pinnedAddress: pinnedAddress,
            onChanged: onChanged,
          ),
        if (form.isOwner == false)
          FinderFields(
            form: form,
            pinnedAddress: pinnedAddress,
            onChanged: onChanged,
          ),
      ],
    );
  }
}

/// Owner side: reporting their own lost pet.
class OwnerFields extends StatelessWidget {
  const OwnerFields({
    super.key,
    required this.form,
    required this.pinnedAddress,
    required this.onChanged,
  });

  final RescueFormController form;

  /// The map pin's resolved address (shown as last-seen / found location).
  final String pinnedAddress;
  final VoidCallback onChanged;

  /// Applies [fn] to the shared form state, then asks the page to rebuild —
  /// the same effect as the page's own `setState(fn)` before extraction.
  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  Future<void> _pickLastSeenDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: form.lastSeenDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.yellowrspwn,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) _set(() => form.lastSeenDate = picked);
  }

  Future<void> _pickLastSeenTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: form.lastSeenTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.yellowrspwn,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) _set(() => form.lastSeenTime = picked);
  }

  String _formatDate(DateTime d) =>
      '${_monthName(d.month)} ${d.day}, ${d.year}';

  String _monthName(int m) => const [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ][m];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        RescueFieldLabel('Pet Name', required: true),
        const SizedBox(height: 6),
        RescueTextField(
          form.petNameController,
          'Enter pet name',
          inputFormatters: [AppInputFormatters.nameOnly],
        ),
        const SizedBox(height: 20),
        RescueFieldLabel('Species', required: true),
        const SizedBox(height: 6),
        SpeciesDropdown(
          value: form.selectedAnimalType,
          onChanged: (v) => _set(() {
            form.selectedAnimalType = v;
            form.lostBreed = null;
          }),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RescueFieldLabel('Breed', required: false),
                  const SizedBox(height: 6),
                  BreedDropdown(
                    species: form.selectedAnimalType,
                    breedValue: form.lostBreed,
                    onChanged: (v) => _set(() => form.lostBreed = v),
                    otherController: form.lostBreedOtherController,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RescueFieldLabel('Sex', required: false),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: form.lostSex,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.textPrimary),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Male', child: Text('Male')),
                      DropdownMenuItem(value: 'Female', child: Text('Female')),
                    ],
                    onChanged: (v) => _set(() => form.lostSex = v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        RescueFieldLabel('Color / Distinguishing markings', required: true),
        const SizedBox(height: 6),
        RescueTextField(
          form.lostColorController,
          'e.g. Brown and white, torn left ear',
        ),
        const SizedBox(height: 20),
        RescueFieldLabel('Last seen location', required: true),
        const SizedBox(height: 6),
        Text(
          pinnedAddress,
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          'Uses the pin on the map above — adjust it if this isn\'t right.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RescueFieldLabel('Date last seen', required: true),
                  const SizedBox(height: 6),
                  RescuePickerField(
                    label: form.lastSeenDate != null
                        ? _formatDate(form.lastSeenDate!)
                        : 'Select date',
                    onTap: () => _pickLastSeenDate(context),
                    icon: Icons.calendar_today_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RescueFieldLabel('Time last seen', required: false),
                  const SizedBox(height: 6),
                  RescuePickerField(
                    label: form.lastSeenTime != null
                        ? form.lastSeenTime!.format(context)
                        : 'Select time',
                    onTap: () => _pickLastSeenTime(context),
                    icon: Icons.access_time,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        RescueFieldLabel('Temperament', required: false),
        const SizedBox(height: 8),
        RescueRadioOption(
          'Friendly, approachable',
          form.temperament,
          (val) => _set(() => form.temperament = val),
        ),
        RescueRadioOption(
          'Nervous, may run',
          form.temperament,
          (val) => _set(() => form.temperament = val),
        ),
        RescueRadioOption(
          'Can be defensive / bite risk',
          form.temperament,
          (val) => _set(() => form.temperament = val),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Offer a reward',
              style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Switch(
              value: form.offerReward,
              activeThumbColor: AppColors.textPrimary,
              onChanged: (v) => _set(() => form.offerReward = v),
            ),
          ],
        ),
        if (form.offerReward) ...[
          const SizedBox(height: 6),
          RescueTextField(
            form.rewardAmountController,
            'Enter amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [AppInputFormatters.decimal],
          ),
        ],
        const SizedBox(height: 20),
        RescueFieldLabel('Contact Number', required: true),
        const SizedBox(height: 6),
        RescueTextField(
          form.ownerContactController,
          'Mobile number',
          keyboardType: TextInputType.phone,
          inputFormatters: AppInputFormatters.phoneFlexible,
        ),
        const SizedBox(height: 6),
        Text(
          'Only revealed to a finder once you confirm a match.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Finder side: someone reporting a stray they suspect is lost.
class FinderFields extends StatelessWidget {
  const FinderFields({
    super.key,
    required this.form,
    required this.pinnedAddress,
    required this.onChanged,
  });

  final RescueFormController form;

  /// The map pin's resolved address (shown as last-seen / found location).
  final String pinnedAddress;
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
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        RescueFieldLabel('Location Found', required: true),
        const SizedBox(height: 6),
        Text(
          pinnedAddress,
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 20),
        RescueFieldLabel('Animal(s) found', required: true),
        const SizedBox(height: 4),
        Text(
          'Found more than one? Add each animal below — they will be tracked '
          'together as one case.',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 10),
        FoundAnimalList(animals: form.foundAnimals, onChanged: onChanged),
        const SizedBox(height: 12),
        RescueFieldLabel('Describe Condition', required: true),
        const SizedBox(height: 6),
        RescueTextField(form.conditionController, 'Calm, scared, injured…'),
        const SizedBox(height: 20),
        RescueFieldLabel('Right now, the animal is', required: true),
        const SizedBox(height: 8),
        RescueRadioOption(
          'With me, I can hold it for now',
          form.animalStatus,
          (val) => _set(() => form.animalStatus = val),
        ),
        RescueRadioOption(
          "Still roaming, can't approach it",
          form.animalStatus,
          (val) => _set(() => form.animalStatus = val),
        ),
        RescueRadioOption(
          'Already brought to a vet/shelter',
          form.animalStatus,
          (val) => _set(() => form.animalStatus = val),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.pinkrspwn.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'This animal needs pickup or medical help',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Switch(
                value: form.finderNeedsRescue,
                activeThumbColor: AppColors.textPrimary,
                onChanged: (v) => _set(() => form.finderNeedsRescue = v),
              ),
            ],
          ),
        ),
        if (form.finderNeedsRescue) ...[
          const SizedBox(height: 16),
          RescueFieldLabel('Select Urgency', required: true),
          const SizedBox(height: 8),
          RescueRadioOption(
            'Low',
            form.selectedUrgency,
            (val) => _set(() => form.selectedUrgency = val),
          ),
          RescueRadioOption(
            'Medium',
            form.selectedUrgency,
            (val) => _set(() => form.selectedUrgency = val),
          ),
          RescueRadioOption(
            'Critical',
            form.selectedUrgency,
            (val) => _set(() => form.selectedUrgency = val),
          ),
        ],
        const SizedBox(height: 20),
        RescueFieldLabel('Contact Number', required: true),
        const SizedBox(height: 6),
        RescueTextField(
          form.finderContactController,
          'Mobile number',
          keyboardType: TextInputType.phone,
          inputFormatters: AppInputFormatters.phoneFlexible,
        ),
        const SizedBox(height: 6),
        Text(
          "We'll check this against open lost pet alerts nearby.",
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
