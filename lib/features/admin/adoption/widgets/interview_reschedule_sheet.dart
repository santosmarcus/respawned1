import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/interview_scheduling.dart';

typedef RescheduledInterview = ({DateTime date, String time, String type});

/// Admin's interview Reschedule sheet — edits the exact same appointment
/// the user booked (same visit types + day-of-week time slots, from the
/// shared interview_scheduling.dart), initialized from the application's
/// current appointment. Never a second/parallel scheduling concept.
Future<RescheduledInterview?> showInterviewRescheduleSheet(
  BuildContext context, {
  DateTime? initialDate,
  String? initialTime,
  String? initialType,
}) {
  return showModalBottomSheet<RescheduledInterview>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _InterviewRescheduleSheet(
      initialDate: initialDate,
      initialTime: initialTime,
      initialType: initialType,
    ),
  );
}

class _InterviewRescheduleSheet extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialTime;
  final String? initialType;

  const _InterviewRescheduleSheet({this.initialDate, this.initialTime, this.initialType});

  @override
  State<_InterviewRescheduleSheet> createState() => _InterviewRescheduleSheetState();
}

class _InterviewRescheduleSheetState extends State<_InterviewRescheduleSheet> {
  DateTime? _date;
  String? _time;
  late String _type;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _time = widget.initialTime;
    _type = (widget.initialType != null && kInterviewTypes.contains(widget.initialType)) ? widget.initialType! : kInterviewTypes.first;
  }

  @override
  Widget build(BuildContext context) {
    final slots = _date == null ? const <String>[] : interviewSlotsForDate(_date!);
    final isClosed = _date != null && isInterviewClosedDay(_date!);
    final firstDate = DateTime.now().add(const Duration(days: 1));
    final lastDate = DateTime.now().add(const Duration(days: 90));
    var initialCalendarDate = _date ?? firstDate;
    if (initialCalendarDate.isBefore(firstDate)) initialCalendarDate = firstDate;
    if (initialCalendarDate.isAfter(lastDate)) initialCalendarDate = lastDate;
    // initialDate must itself be selectable — nudge off a Sunday (e.g. a
    // legacy appointment set before Sundays were blocked) rather than let
    // CalendarDatePicker's own assertion fail.
    if (isInterviewClosedDay(initialCalendarDate)) initialCalendarDate = initialCalendarDate.add(const Duration(days: 1));

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
            Text('Reschedule Interview', style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Row(
              children: kInterviewTypes.map((type) {
                final selected = _type == type;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _type = type),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.greenrspwn : AppColors.lavenderrspwn,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(type, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.greenrspwn, width: 1.2),
              ),
              child: CalendarDatePicker(
                initialDate: initialCalendarDate,
                firstDate: firstDate,
                lastDate: lastDate,
                // Sundays aren't just shown as unavailable — they can't be
                // tapped at all, same as the user-side booking calendar.
                selectableDayPredicate: (date) => !isInterviewClosedDay(date),
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
            else if (isClosed || slots.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(color: AppColors.slaterspwn.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(10)),
                child: Text(
                  isClosed ? 'Closed on Sundays — please pick another day.' : 'No slots available for this date.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
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
                              fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.textPrimary),
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
                      child: Text('$_type  ·  ${_date!.month}/${_date!.day}/${_date!.year}  ·  $_time',
                          style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_date == null || _time == null)
                    ? null
                    : () => Navigator.pop(context, (date: _date!, time: _time!, type: _type)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Save Reschedule', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
