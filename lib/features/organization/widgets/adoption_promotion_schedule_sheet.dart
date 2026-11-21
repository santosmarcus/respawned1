import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/adoption_promotion_schedule.dart';
import 'package:respawnd1/core/repos/facebook_integration_repository.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Admin sheet for the adoption post schedule: how often every member of
/// the organization is reminded to post animals open for adoption, and
/// whether the system may also suggest a post between slots. Saved through
/// facebookSaveAdoptionPromotion (Admin only on the server too).
Future<void> showAdoptionPromotionScheduleSheet(
    BuildContext context, {
      required String organizationId,
      required AdoptionPromotionSchedule current,
    }) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ScheduleSheet(organizationId: organizationId, current: current),
  );
}

class _ScheduleSheet extends ConsumerStatefulWidget {
  final String organizationId;
  final AdoptionPromotionSchedule current;
  const _ScheduleSheet({required this.organizationId, required this.current});

  @override
  ConsumerState<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends ConsumerState<_ScheduleSheet> {
  late AdoptionPromotionSchedule _draft = widget.current;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(facebookIntegrationRepositoryProvider).savePromotionSchedule(
        organizationId: widget.organizationId,
        schedule: _draft,
      );
      navigator.pop();
      messenger.showSnackBar(appSnackBar('Adoption post schedule saved.', kind: AppMessageKind.success));
    } on FacebookOperationException catch (e) {
      messenger.showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
    } catch (_) {
      messenger.showSnackBar(appSnackBar('Could not save the schedule.', kind: AppMessageKind.error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _draft;
    final label = GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    final help = GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Adoption post schedule', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Every member of the organization gets a reminder with suggested animals. '
                    'Nothing is posted until a member allowed to share to Facebook reviews it and taps Post.',
                style: help,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Scheduled reminders', style: label),
                subtitle: Text('A reminder at the same time each cycle.', style: help),
                value: d.enabled,
                onChanged: _saving ? null : (v) => setState(() => _draft = d.copyWith(enabled: v)),
              ),
              if (d.enabled) ...[
                _row(
                  'How often',
                  DropdownButton<int>(
                    value: d.intervalWeeks,
                    items: [
                      for (final w in AdoptionPromotionSchedule.intervalWeekOptions)
                        DropdownMenuItem(value: w, child: Text(AdoptionPromotionSchedule.intervalLabel(w))),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _draft = d.copyWith(intervalWeeks: v)),
                  ),
                ),
                _row(
                  'Day',
                  DropdownButton<int>(
                    value: d.dayOfWeek,
                    items: [
                      for (var day = 1; day <= 7; day++)
                        DropdownMenuItem(value: day, child: Text(AdoptionPromotionSchedule.weekdayLabel(day))),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _draft = d.copyWith(dayOfWeek: v)),
                  ),
                ),
              ],
              if (d.enabled || d.smartSuggestions)
                _row(
                  'Time (Philippine time)',
                  DropdownButton<int>(
                    value: d.hour,
                    items: [
                      for (var h = 0; h < 24; h++)
                        DropdownMenuItem(value: h, child: Text(AdoptionPromotionSchedule.hourLabel(h))),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _draft = d.copyWith(hour: v)),
                  ),
                ),
              if (d.enabled || d.smartSuggestions)
                _row(
                  'Animals per post',
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: _saving || d.animalsPerPost <= AdoptionPromotionSchedule.minAnimalsPerPost
                            ? null
                            : () => setState(() => _draft = d.copyWith(animalsPerPost: d.animalsPerPost - 1)),
                      ),
                      Text('${d.animalsPerPost}', style: label),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: _saving || d.animalsPerPost >= AdoptionPromotionSchedule.maxAnimalsPerPost
                            ? null
                            : () => setState(() => _draft = d.copyWith(animalsPerPost: d.animalsPerPost + 1)),
                      ),
                    ],
                  ),
                ),
              const Divider(height: 24),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Smart suggestions', style: label),
                subtitle: Text(
                  'Also suggest a post between reminders when an animal open for adoption has never been '
                      'shared, or several have waited weeks without applicants. At most every 3 days, at the time above.',
                  style: help,
                ),
                value: d.smartSuggestions,
                onChanged: _saving ? null : (v) => setState(() => _draft = d.copyWith(smartSuggestions: v)),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: AppButtons.primary,
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Save schedule'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String title, Widget control) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(title, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
          control,
        ],
      ),
    );
  }
}
