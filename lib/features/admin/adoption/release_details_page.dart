import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_schedule.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/post_adoption_details_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/adoption/widgets/schedule_rule_editor.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

String _fmtDate(DateTime d) => '${d.month}/${d.day}/${d.year}';

/// Release Details screen (spec §1/§2/§6) — the admin sets the official
/// release/adoption date and configures the post-adoption follow-up
/// schedule before releasing the animal. Reuses AdoptionApplication,
/// AnimalRecord, and AdoptionApplicationRepository directly; the only new
/// state is the draft schedule kept in this screen until Mark as Released.
class ReleaseDetailsPage extends ConsumerStatefulWidget {
  final String applicationId;
  const ReleaseDetailsPage({super.key, required this.applicationId});

  @override
  ConsumerState<ReleaseDetailsPage> createState() => _ReleaseDetailsPageState();
}

class _ReleaseDetailsPageState extends ConsumerState<ReleaseDetailsPage> {
  bool _initialized = false;
  bool _busy = false;
  DateTime _releaseDate = DateTime.now();
  List<FollowUpScheduleRule> _rules = [];
  bool _noFollowUpsPlanned = false;

  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  void _initFromRemote(AdoptionApplication app) {
    if (_initialized) return;
    _initialized = true;
    final raw = app.raw;
    final scheduledReleaseDate = raw['scheduledReleaseDate'];
    if (scheduledReleaseDate != null) {
      // Timestamp -> DateTime, guarded so a bad value never crashes init.
      try {
        _releaseDate = (scheduledReleaseDate as dynamic).toDate() as DateTime;
      } catch (_) {}
    }
    final savedRules = (raw['followUpSchedules'] as List?) ?? const [];
    _rules = savedRules.whereType<Map>().map((m) => FollowUpScheduleRule.fromMap(Map<String, dynamic>.from(m))).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    _noFollowUpsPlanned = raw['noFollowUpsPlanned'] as bool? ?? false;
  }

  Future<void> _persistDraft() async {
    await ref.read(adoptionApplicationRepositoryProvider).saveFollowUpScheduleDraft(
          applicationId: widget.applicationId,
          rules: _rules,
          noFollowUpsPlanned: _noFollowUpsPlanned,
        );
  }

  Future<void> _pickReleaseDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _releaseDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _releaseDate = picked);
    await ref.read(adoptionApplicationRepositoryProvider).setScheduledReleaseDate(applicationId: widget.applicationId, date: picked);
    await _persistDraft(); // release date shifts every "on release date"/"after previous rule" anchor
  }

  Future<void> _addRule() async {
    final rule = await showScheduleRuleEditorSheet(
      context,
      order: _rules.length,
      releaseDate: _releaseDate,
      earlierRules: _rules,
      actorName: _actorName,
    );
    if (rule == null) return;
    setState(() => _rules = [..._rules, rule]);
    await _persistDraft();
  }

  Future<void> _editRule(int index) async {
    final rule = await showScheduleRuleEditorSheet(
      context,
      existing: _rules[index],
      order: index,
      releaseDate: _releaseDate,
      earlierRules: _rules.sublist(0, index),
      actorName: _actorName,
    );
    if (rule == null) return;
    setState(() => _rules[index] = rule);
    await _persistDraft();
  }

  Future<void> _removeRule(int index) async {
    final removedId = _rules[index].ruleId;
    setState(() {
      _rules.removeAt(index);
      // Any later rule chained off the removed one falls back to the
      // release date rather than pointing at a rule that no longer exists.
      _rules = [
        for (var i = 0; i < _rules.length; i++)
          _rules[i].copyWith(
            order: i,
            startMode: _rules[i].previousRuleId == removedId ? StartMode.releaseDate : null,
            clearPreviousRuleId: _rules[i].previousRuleId == removedId,
          ),
      ];
    });
    await _persistDraft();
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _rules.removeAt(oldIndex);
      _rules.insert(newIndex, item);
      _rules = [for (var i = 0; i < _rules.length; i++) _rules[i].copyWith(order: i)];
    });
    await _persistDraft();
  }

  Future<void> _toggleNoFollowUps(bool value) async {
    setState(() => _noFollowUpsPlanned = value);
    await _persistDraft();
  }

  List<DateTime> get _combinedPreview => generateFollowUpDates(_rules, _releaseDate).map((g) => g.date).toList();

  ({bool canRelease, String? reason}) _releaseGuard(AdoptionApplication app, AnimalRecord? animal) {
    if (app.status != AdoptionStatus.approved) return (canRelease: false, reason: 'Only an approved application can be released.');
    if (animal == null) return (canRelease: false, reason: 'Animal record not found.');
    if (animal.adoptionStatus == 'adopted') return (canRelease: false, reason: 'This animal has already been adopted.');
    if (animal.adoptionStatus == 'reserved' && animal.reservedApplicationId != widget.applicationId) {
      return (canRelease: false, reason: 'This animal is reserved for a different applicant.');
    }
    if (!_noFollowUpsPlanned && _rules.isEmpty) {
      return (canRelease: false, reason: 'Add at least one follow-up schedule, or turn on "No follow-ups needed".');
    }
    if (!_noFollowUpsPlanned && _combinedPreview.isEmpty) {
      return (canRelease: false, reason: 'This follow-up schedule produced no dates — check each rule.');
    }
    return (canRelease: true, reason: null);
  }

  Future<void> _markReleased(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Mark ${app.animalName} as Released?',
      message: 'This finalizes the adoption on ${_fmtDate(_releaseDate)}${_noFollowUpsPlanned ? '' : ' and schedules ${_combinedPreview.length} follow-up${_combinedPreview.length == 1 ? '' : 's'}'}. The animal will be removed from public adoptable listings.',
      confirmLabel: 'Mark as Released',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await ref.read(adoptionApplicationRepositoryProvider).releaseWithFollowUps(
            applicationId: widget.applicationId,
            animalId: app.animalId,
            actorName: _actorName,
            releaseDate: _releaseDate,
            rules: _rules,
            noFollowUpsPlanned: _noFollowUpsPlanned,
          );
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PostAdoptionDetailsPage(applicationId: widget.applicationId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not release: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(adoptionApplicationProvider(widget.applicationId));
    final app = appAsync.asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
        title: Text('Release Details', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: app == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              _initFromRemote(app);
              final animalAsync = ref.watch(animalRecordProvider(app.animalId));
              final animal = animalAsync.asData?.value;
              final guard = _releaseGuard(app, animal);

              return SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionCard(
                      title: 'Summary',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row('Animal', app.animalName),
                          _row('Adopter', app.adopterName),
                          _row('Application', '#${app.id.substring(0, app.id.length > 6 ? 6 : app.id.length)}'),
                          _row('Adoption fee', app.feeStatus.label + (app.paymentAmount != null ? ' · ${formatPeso(app.paymentAmount!)}' : '')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    SectionCard(
                      title: 'Release / Adoption Date',
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(_fmtDate(_releaseDate), style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ),
                          OutlinedButton.icon(onPressed: _pickReleaseDate, icon: const Icon(Icons.edit_calendar, size: 16), label: const Text('Change')),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    SectionCard(
                      title: 'Post-Adoption Follow-up Schedule',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('No post-adoption follow-ups needed', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                            value: _noFollowUpsPlanned,
                            activeThumbColor: AppColors.greenrspwn,
                            onChanged: _toggleNoFollowUps,
                          ),
                          if (!_noFollowUpsPlanned) ...[
                            if (_rules.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                child: Text('No schedules yet — add at least one.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                              )
                            else
                              ReorderableListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _rules.length,
                                onReorder: (o, n) => _reorder(o, n),
                                itemBuilder: (context, i) {
                                  final r = _rules[i];
                                  return Container(
                                    key: ValueKey(r.ruleId),
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(10)),
                                    child: Row(
                                      children: [
                                        Text('${i + 1}.', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('${r.frequencyLabel} ${r.durationLabel}',
                                                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                              Text(r.startLabel, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                                            ],
                                          ),
                                        ),
                                        IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () => _editRule(i)),
                                        IconButton(icon: const Icon(Icons.delete_outline, size: 18), onPressed: () => _removeRule(i)),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 6),
                            OutlinedButton.icon(onPressed: _addRule, icon: const Icon(Icons.add), label: const Text('Add Schedule')),
                            const SizedBox(height: 14),
                            Text('Combined Preview', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            const SizedBox(height: 6),
                            if (_combinedPreview.isEmpty)
                              Text('No dates yet.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
                            else
                              Wrap(
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  for (final d in _combinedPreview)
                                    Chip(
                                      label: Text(_fmtDate(d), style: GoogleFonts.zain(fontSize: 11)),
                                      backgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.4),
                                    ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (!guard.canRelease)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(guard.reason ?? '', style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (_busy || !guard.canRelease) ? null : () => _markReleased(app),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.yellowrspwn,
                              disabledBackgroundColor: AppColors.slaterspwn,
                              foregroundColor: AppColors.textPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text('Mark as Released', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            }),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 90, child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
            Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          ],
        ),
      );
}
