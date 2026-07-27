import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Shared appointment date/time picker bottom sheet — promoted from what was
/// a private, adopter-only widget in post_adoption_page.dart
/// (`_PickupSchedulerSheet`) since it was the only reusable
/// appointment-scheduling pattern anywhere in the app. Used for the adopter
/// return-pickup flow and the admin Retrieval Schedule sheet alike.
typedef ScheduledDateTime = ({DateTime date, String time});

const List<String> kDefaultAppointmentTimeSlots = [
  '9:00 AM',
  '10:00 AM',
  '11:00 AM',
  '1:00 PM',
  '2:00 PM',
  '3:00 PM',
  '4:00 PM',
];

String formatScheduleDate(DateTime d) {
  const months = [
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
  ];
  return '${months[d.month]} ${d.day}, ${d.year}';
}

Future<ScheduledDateTime?> showDateTimePickerSheet(
  BuildContext context, {
  String title = 'Select Date & Time',
  DateTime? initialDate,
  String? initialTime,
  DateTime? firstDate,
  DateTime? lastDate,
  List<String> timeSlots = kDefaultAppointmentTimeSlots,
}) {
  return showModalBottomSheet<ScheduledDateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _DateTimePickerSheet(
      title: title,
      initialDate: initialDate,
      initialTime: initialTime,
      firstDate: firstDate ?? DateTime.now(),
      lastDate: lastDate ?? DateTime.now().add(const Duration(days: 90)),
      timeSlots: timeSlots,
    ),
  );
}

class _DateTimePickerSheet extends StatefulWidget {
  final String title;
  final DateTime? initialDate;
  final String? initialTime;
  final DateTime firstDate;
  final DateTime lastDate;
  final List<String> timeSlots;

  const _DateTimePickerSheet({
    required this.title,
    this.initialDate,
    this.initialTime,
    required this.firstDate,
    required this.lastDate,
    required this.timeSlots,
  });

  @override
  State<_DateTimePickerSheet> createState() => _DateTimePickerSheetState();
}

class _DateTimePickerSheetState extends State<_DateTimePickerSheet> {
  DateTime? _date;
  String? _time;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _time = widget.initialTime;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(4)),
              ),
            ),
            Text(widget.title, style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.greenrspwn, width: 1.2),
              ),
              child: CalendarDatePicker(
                initialDate: _date ?? widget.firstDate.add(const Duration(days: 2)),
                firstDate: widget.firstDate,
                lastDate: widget.lastDate,
                onDateChanged: (picked) => setState(() {
                  _date = picked;
                  _time = null;
                }),
              ),
            ),
            const SizedBox(height: 16),
            Text('Available times', style: GoogleFonts.tiltWarp(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if (_date == null)
              Text('Select a date above to see available times.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary))
            else
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.timeSlots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final slot = widget.timeSlots[i];
                    final selected = _time == slot;
                    return GestureDetector(
                      onTap: () => setState(() => _time = slot),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? AppColors.greenrspwn : AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: selected ? AppColors.greenrspwn : AppColors.slaterspwn, width: 1.2),
                        ),
                        child: Text(
                          slot,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (_date != null && _time != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.yellowrspwn.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    const Icon(Icons.event_available, color: AppColors.greenrspwn, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${formatScheduleDate(_date!)}  ·  $_time',
                        style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_date == null || _time == null) ? null : () => Navigator.pop(context, (date: _date!, time: _time!)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Confirm', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
