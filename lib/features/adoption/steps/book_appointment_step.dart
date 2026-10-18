// Extracted from adoption_process.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/adoption/adoption_formatting.dart';
import 'package:respawnd1/features/adoption/interview_scheduling.dart';
import 'package:respawnd1/features/adoption/widgets/adoption_buttons.dart';

/// Step 2 — book the interview appointment.
class BookAppointmentStep extends StatelessWidget {
  const BookAppointmentStep({
    super.key,
    required this.form,
    required this.readOnly,
    required this.isSubmitting,
    required this.onSaveAppointment,
    required this.onChanged,
  });

  final AdoptionFormController form;

  /// True while reviewing a previous step (read only).
  final bool readOnly;
  final bool isSubmitting;
  final VoidCallback onSaveAppointment;
  final VoidCallback onChanged;

  /// Applies [fn] to the shared form state, then asks the page to rebuild —
  /// the same effect as the page's own `setState(fn)` before extraction.
  void _set(VoidCallback fn) {
    fn();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final slots = form.slotsForDate;
    final isSunday =
        form.appointmentDate != null &&
        form.appointmentDate!.weekday == DateTime.sunday;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Book appointment',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Just a few steps more.',
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'As part of this process, we\'d like to schedule an interview with the organization to further assess suitability and answer any questions you may have.\n\nPlease choose a date that works best for you, and we\'ll confirm your appointment once your application has been reviewed.',
          style: GoogleFonts.zain(
            fontSize: 14,
            color: AppColors.textPrimary,
            height: 1.5,
          ),
        ),

        const SizedBox(height: 20),

        // visit type
        Row(
          children: kInterviewTypes.map((type) {
            final selected = form.appointmentType == type;
            return GestureDetector(
              onTap: () => _set(() => form.appointmentType = type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.greenrspwn
                      : AppColors.lavenderrspwn,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  type,
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 20),

        // calendar
        Container(
          decoration: BoxDecoration(
            color: AppColors.yellowrspwn.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.greenrspwn, width: 1.2),
          ),
          child: Builder(
            builder: (context) {
              final firstDate = DateTime.now().add(const Duration(days: 1));
              final lastDate = DateTime.now().add(const Duration(days: 90));
              var initialDate = form.appointmentDate ?? firstDate;
              if (initialDate.isBefore(firstDate)) initialDate = firstDate;
              if (initialDate.isAfter(lastDate)) initialDate = lastDate;
              // initialDate must itself be selectable — nudge off a Sunday
              // rather than let CalendarDatePicker's own assertion fail.
              if (isInterviewClosedDay(initialDate)) {
                initialDate = initialDate.add(const Duration(days: 1));
              }

              return CalendarDatePicker(
                initialDate: initialDate,
                firstDate: firstDate,
                lastDate: lastDate,
                // Sundays aren't just shown as unavailable — they can't be
                // tapped at all.
                selectableDayPredicate: (date) => !isInterviewClosedDay(date),
                onDateChanged: (picked) {
                  _set(() {
                    form.appointmentDate = picked;
                    form.appointmentTime = null;
                  });
                },
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        // time slot selection
        Text(
          'Available times',
          style: GoogleFonts.tiltWarp(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),

        if (form.appointmentDate == null)
          Text(
            'Select a date above to see available times.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
          )
        else if (isSunday || slots.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.slaterspwn.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              isSunday
                  ? 'Closed on Sundays — please pick another day.'
                  : 'No slots available for this date.',
              style: GoogleFonts.zain(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: slots.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final slot = slots[i];
                final selected = form.appointmentTime == slot;
                return GestureDetector(
                  onTap: () => _set(() => form.appointmentTime = slot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.greenrspwn
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? AppColors.greenrspwn
                            : AppColors.slaterspwn,
                        width: 1.2,
                      ),
                    ),
                    child: Text(
                      slot,
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // summary
        if (form.appointmentDate != null && form.appointmentTime != null) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.yellowrspwn.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.event_available,
                  color: AppColors.greenrspwn,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$form.appointmentType  ·  ${formatAdoptionDate(form.appointmentDate!)}  ·  $form.appointmentTime',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        if (!readOnly)
          AdoptionPrimaryButton(
            label: isSubmitting ? 'Booking...' : 'Book',
            onTap:
                (form.appointmentDate == null ||
                    form.appointmentTime == null ||
                    isSubmitting)
                ? null
                : onSaveAppointment,
          ),

        const SizedBox(height: 24),
      ],
    );
  }
}
