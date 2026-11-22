import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

enum TimelineStepState { done, current, pending }

class TimelineStep {
  final String title;
  final String? subtitle;
  final TimelineStepState state;

  const TimelineStep(this.title, {this.subtitle, required this.state});
}

/// A vertical list of numbered steps — finished ones checked, the current
/// one highlighted ("Current step"), the rest greyed out. Used for the
/// reporter's rescue progress (Track Case) and the staff's intake
/// sequence, so both show where a case is without reading every section.
class ProgressTimeline extends StatelessWidget {
  final String title;
  final String? statusLabel;
  final List<TimelineStep> steps;

  const ProgressTimeline({
    super.key,
    required this.title,
    required this.steps,
    this.statusLabel,
  });

  /// Builds the step states from how many steps are finished: the first
  /// unfinished one is current. [finished] past the end marks all done.
  static List<TimelineStep> sequence(
    List<(String title, String? subtitle)> items,
    int finished,
  ) =>
      [
        for (var i = 0; i < items.length; i++)
          TimelineStep(
            items[i].$1,
            subtitle: items[i].$2,
            state: i < finished
                ? TimelineStepState.done
                : (i == finished ? TimelineStepState.current : TimelineStepState.pending),
          ),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDAD7CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              ),
              if (statusLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel!,
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++) _row(i, steps[i], last: i == steps.length - 1),
        ],
      ),
    );
  }

  Widget _row(int i, TimelineStep step, {required bool last}) {
    final done = step.state == TimelineStepState.done;
    final current = step.state == TimelineStepState.current;
    final dotColor = done
        ? AppColors.greenrspwn
        : current
            ? AppColors.yellowrspwn
            : const Color(0xFFE6E3D8);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                    border: current ? Border.all(color: AppColors.textPrimary, width: 1.5) : null,
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${i + 1}',
                          style: GoogleFonts.zain(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: current ? AppColors.textPrimary : AppColors.textSecondary)),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: done ? AppColors.greenrspwn.withValues(alpha: 0.6) : const Color(0xFFE6E3D8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 6 : 14, top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          step.title,
                          style: GoogleFonts.zain(
                            fontSize: 15,
                            fontWeight: current || done ? FontWeight.w800 : FontWeight.w600,
                            color: step.state == TimelineStepState.pending
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (current) ...[
                        const SizedBox(width: 8),
                        Text('Current step',
                            style: GoogleFonts.zain(
                                fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF9C6B10))),
                      ],
                    ],
                  ),
                  if (step.subtitle != null)
                    Text(step.subtitle!,
                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
