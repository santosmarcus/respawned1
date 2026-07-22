import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/follow_up_schedule.dart';

/// Add/edit sheet for one follow-up schedule rule (spec §2/§3) — used from
/// ReleaseDetailsPage's schedule builder. Returns the saved rule, or null if
/// cancelled.
Future<FollowUpScheduleRule?> showScheduleRuleEditorSheet(
  BuildContext context, {
  FollowUpScheduleRule? existing,
  required int order,
  required DateTime releaseDate,
  required List<FollowUpScheduleRule> earlierRules,
  required String actorName,
}) {
  return showModalBottomSheet<FollowUpScheduleRule>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _ScheduleRuleEditorSheet(
      existing: existing,
      order: order,
      releaseDate: releaseDate,
      earlierRules: earlierRules,
      actorName: actorName,
    ),
  );
}

class _ScheduleRuleEditorSheet extends StatefulWidget {
  final FollowUpScheduleRule? existing;
  final int order;
  final DateTime releaseDate;
  final List<FollowUpScheduleRule> earlierRules;
  final String actorName;

  const _ScheduleRuleEditorSheet({
    this.existing,
    required this.order,
    required this.releaseDate,
    required this.earlierRules,
    required this.actorName,
  });

  @override
  State<_ScheduleRuleEditorSheet> createState() => _ScheduleRuleEditorSheetState();
}

class _ScheduleRuleEditorSheetState extends State<_ScheduleRuleEditorSheet> {
  late int _intervalValue;
  late IntervalUnit _intervalUnit;
  late int _durationValue;
  late DurationUnit _durationUnit;
  late StartMode _startMode;
  DateTime? _customStartDate;
  String? _previousRuleId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _intervalValue = e?.intervalValue ?? 1;
    _intervalUnit = e?.intervalUnit ?? IntervalUnit.week;
    _durationValue = e?.durationValue ?? 1;
    _durationUnit = e?.durationUnit ?? DurationUnit.month;
    _startMode = e?.startMode ?? (widget.earlierRules.isEmpty ? StartMode.releaseDate : StartMode.afterPreviousRule);
    _customStartDate = e?.customStartDate;
    _previousRuleId = e?.previousRuleId ?? (widget.earlierRules.isNotEmpty ? widget.earlierRules.last.ruleId : null);
  }

  FollowUpScheduleRule get _draft => FollowUpScheduleRule(
        ruleId: widget.existing?.ruleId ?? 'rule_${DateTime.now().microsecondsSinceEpoch}',
        order: widget.order,
        intervalValue: _intervalValue,
        intervalUnit: _intervalUnit,
        durationValue: _durationValue,
        durationUnit: _durationUnit,
        startMode: _startMode,
        customStartDate: _startMode == StartMode.customDate ? _customStartDate : null,
        previousRuleId: _startMode == StartMode.afterPreviousRule ? _previousRuleId : null,
        createdAt: widget.existing?.createdAt ?? DateTime.now(),
        createdBy: widget.existing?.createdBy ?? widget.actorName,
      );

  List<DateTime> get _previewDates {
    final rule = _draft;
    if (rule.startMode == StartMode.afterPreviousRule && widget.earlierRules.isNotEmpty) {
      // Approximate preview: chain against the earlier rules actually passed
      // in — the combined, authoritative preview lives on the parent screen.
      final combined = generateFollowUpDates([...widget.earlierRules, rule], widget.releaseDate);
      return combined.where((g) => g.ruleId == rule.ruleId).map((g) => g.date).toList();
    }
    return generateFollowUpDates([rule], widget.releaseDate).map((g) => g.date).toList();
  }

  Future<void> _pickCustomDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? widget.releaseDate,
      firstDate: DateTime(widget.releaseDate.year - 1),
      lastDate: DateTime(widget.releaseDate.year + 5),
    );
    if (picked != null) setState(() => _customStartDate = picked);
  }

  Widget _stepperField({required String label, required int value, required ValueChanged<int> onChanged, int min = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: value > min ? () => onChanged(value - 1) : null,
            ),
            Text('$value', style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () => onChanged(value + 1)),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _previewDates;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.existing == null ? 'Add Follow-up Schedule' : 'Edit Follow-up Schedule',
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            Text('Frequency', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _stepperField(label: 'Every', value: _intervalValue, onChanged: (v) => setState(() => _intervalValue = v))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<IntervalUnit>(
                    initialValue: _intervalUnit,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: IntervalUnit.values.map((u) => DropdownMenuItem(value: u, child: Text('${u.label}(s)'))).toList(),
                    onChanged: (v) => setState(() => _intervalUnit = v ?? _intervalUnit),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            Text('Duration', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _stepperField(label: 'For', value: _durationValue, onChanged: (v) => setState(() => _durationValue = v))),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<DurationUnit>(
                    initialValue: _durationUnit,
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                    items: DurationUnit.values.map((u) => DropdownMenuItem(value: u, child: Text('${u.label}(s)'))).toList(),
                    onChanged: (v) => setState(() => _durationUnit = v ?? _durationUnit),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),
            Text('Starts', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<StartMode>(
              initialValue: _startMode,
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: StartMode.releaseDate, child: Text('On release date')),
                const DropdownMenuItem(value: StartMode.afterRelease, child: Text('After release')),
                if (widget.earlierRules.isNotEmpty)
                  const DropdownMenuItem(value: StartMode.afterPreviousRule, child: Text('After previous schedule')),
                const DropdownMenuItem(value: StartMode.customDate, child: Text('Custom date')),
              ],
              onChanged: (v) => setState(() => _startMode = v ?? _startMode),
            ),
            if (_startMode == StartMode.afterPreviousRule && widget.earlierRules.isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _previousRuleId ?? widget.earlierRules.last.ruleId,
                decoration: const InputDecoration(isDense: true, labelText: 'After which schedule?', border: OutlineInputBorder()),
                items: [
                  for (final r in widget.earlierRules)
                    DropdownMenuItem(value: r.ruleId, child: Text('${r.frequencyLabel} ${r.durationLabel}')),
                ],
                onChanged: (v) => setState(() => _previousRuleId = v),
              ),
            ],
            if (_startMode == StartMode.customDate) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickCustomDate,
                icon: const Icon(Icons.event),
                label: Text(_customStartDate == null ? 'Choose a date' : formatScheduleDateForPreview(_customStartDate!)),
              ),
            ],

            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(12)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Preview', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  if (preview.isEmpty)
                    Text('No dates generated — check the interval and duration.',
                        style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent))
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        for (final d in preview)
                          Text(formatScheduleDateForPreview(d), style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
                      ],
                    ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: preview.isEmpty && _startMode != StartMode.afterPreviousRule
                        ? null
                        : () => Navigator.pop(context, _draft),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                    child: const Text('Save Schedule'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String formatScheduleDateForPreview(DateTime d) {
  const months = [
    '',
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[d.month]} ${d.day}, ${d.year}';
}
