import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/widgets/date_time_picker_sheet.dart' as picker;
import 'package:respawnd1/features/admin/adoption/return_details_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

String _fmtDate(DateTime? d) => d == null ? 'Not set' : '${d.month}/${d.day}/${d.year}';
String _fmtDateTime(DateTime? d) =>
    d == null ? 'Not set' : '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Admin-facing Post-Adoption Details (spec §7-14) — the screen the admin
/// adoption-detail page's "View Post-Adoption" button now opens, replacing
/// the adopter-facing PostAdoptionMonitoringPage it used to (mis)point at.
class PostAdoptionDetailsPage extends ConsumerStatefulWidget {
  final String applicationId;
  const PostAdoptionDetailsPage({super.key, required this.applicationId});

  @override
  ConsumerState<PostAdoptionDetailsPage> createState() => _PostAdoptionDetailsPageState();
}

class _PostAdoptionDetailsPageState extends ConsumerState<PostAdoptionDetailsPage> {
  bool _busy = false;
  final Set<String> _expanded = {};

  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.redAccent));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptText({required String title, required String label, bool required = false}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          backgroundColor: AppColors.background,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          content: TextField(controller: controller, maxLines: 3, autofocus: true, decoration: InputDecoration(labelText: label)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final text = controller.text.trim();
                if (required && text.isEmpty) return;
                Navigator.pop(ctx, text);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
              child: const Text('Continue'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendReminder(FollowUpRecord f) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Send Reminder?',
      message: 'Notifies the adopter that follow-up #${f.sequenceNumber} (due ${_fmtDate(f.scheduledDate)}) needs a response.',
      confirmLabel: 'Send Reminder',
    );
    if (!confirmed) return;
    await _run(() =>
        ref.read(adoptionApplicationRepositoryProvider).sendFollowUpReminder(applicationId: widget.applicationId, followUpId: f.id, actorName: _actorName));
  }

  Future<void> _confirmReceipt(FollowUpRecord f) async {
    final notes = await _promptText(title: 'Confirm Receipt', label: 'Organization notes (optional, never shown to adopter)');
    if (notes == null) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).confirmFollowUpReceipt(
          applicationId: widget.applicationId,
          followUpId: f.id,
          actorName: _actorName,
          notes: notes.isEmpty ? null : notes,
        ));
  }

  Future<void> _completeFollowUp(FollowUpRecord f) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Mark Follow-up Complete?', message: 'This closes follow-up #${f.sequenceNumber}.', confirmLabel: 'Mark Complete');
    if (!confirmed) return;
    await _run(
        () => ref.read(adoptionApplicationRepositoryProvider).completeFollowUp(applicationId: widget.applicationId, followUpId: f.id, actorName: _actorName));
  }

  Future<void> _manualComplete(FollowUpRecord f) async {
    final reason = await _promptText(title: 'Close Without a Response?', label: 'Reason (required)', required: true);
    if (reason == null || reason.isEmpty) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Confirm Manual Completion',
      message: 'Follow-up #${f.sequenceNumber} will be closed without an adopter response. This is recorded in the audit trail.',
      confirmLabel: 'Close Follow-up',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).completeFollowUp(
          applicationId: widget.applicationId,
          followUpId: f.id,
          actorName: _actorName,
          manualOverride: true,
          reason: reason,
        ));
  }

  Future<void> _reschedule(FollowUpRecord f) async {
    final result = await picker.showDateTimePickerSheet(
      context,
      title: 'Reschedule Follow-up #${f.sequenceNumber}',
      initialDate: f.scheduledDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (result == null) return;
    final reason = await _promptText(title: 'Reason (optional)', label: 'Why is this being rescheduled?');
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).rescheduleFollowUp(
          applicationId: widget.applicationId,
          followUpId: f.id,
          newDate: result.date,
          actorName: _actorName,
          reason: (reason == null || reason.isEmpty) ? null : reason,
        ));
  }

  Future<void> _markPostAdoptionComplete() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Mark Post-Adoption Complete?',
      message: 'This closes post-adoption monitoring for this adoption. All schedules, submissions, and notes stay in history.',
      confirmLabel: 'Mark Complete',
    );
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).markPostAdoptionComplete(applicationId: widget.applicationId, actorName: _actorName));
  }

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(adoptionApplicationProvider(widget.applicationId));
    final app = appAsync.asData?.value;
    final followUpsAsync = ref.watch(followUpsForAdoptionProvider(widget.applicationId));
    final followUps = [...followUpsAsync.asData?.value ?? const <FollowUpRecord>[]]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
        title: Text('Post-Adoption Details', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: app == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(app: app, followUps: followUps),
                  const SizedBox(height: 12),
                  if (app.returnRequest != null) ...[
                    _ReturnBanner(app: app),
                    const SizedBox(height: 12),
                  ],
                  if (app.noFollowUpsPlanned)
                    SectionCard(
                      child: Text('No post-adoption follow-ups were scheduled for this adoption.',
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    )
                  else if (followUps.isEmpty)
                    SectionCard(
                      child: Text('Follow-ups will appear here once generated.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                    )
                  else
                    for (final f in followUps) ...[
                      _FollowUpCard(
                        applicationId: widget.applicationId,
                        followUp: f,
                        expanded: _expanded.contains(f.id),
                        busy: _busy,
                        onToggle: () => setState(() => _expanded.contains(f.id) ? _expanded.remove(f.id) : _expanded.add(f.id)),
                        onSendReminder: () => _sendReminder(f),
                        onConfirmReceipt: () => _confirmReceipt(f),
                        onComplete: () => _completeFollowUp(f),
                        onManualComplete: () => _manualComplete(f),
                        onReschedule: () => _reschedule(f),
                      ),
                      const SizedBox(height: 10),
                    ],
                  const SizedBox(height: 14),
                  if (!app.noFollowUpsPlanned) _CompleteMonitoringButton(app: app, followUps: followUps, busy: _busy, onTap: _markPostAdoptionComplete),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}

class _Header extends StatelessWidget {
  final AdoptionApplication app;
  final List<FollowUpRecord> followUps;
  const _Header({required this.app, required this.followUps});

  @override
  Widget build(BuildContext context) {
    final completed = followUps.where((f) => f.status == FollowUpStatus.completed).length;
    final nextDue = followUps.where((f) => !f.isTerminal).fold<DateTime?>(null, (acc, f) {
      if (acc == null) return f.scheduledDate;
      return f.scheduledDate.isBefore(acc) ? f.scheduledDate : acc;
    });

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(app.animalName, style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          _row('Adopter', app.adopterName),
          _row('Adoption Date', _fmtDate(app.releasedAt ?? app.adoptedAt)),
          if (!app.noFollowUpsPlanned) _row('Next Due', nextDue == null ? 'None remaining' : _fmtDate(nextDue)),
          if (!app.noFollowUpsPlanned) _row('Follow-ups', '$completed of ${followUps.length} completed'),
          _row(
            'Monitoring Status',
            app.postAdoptionStatus == 'completed'
                ? 'Completed${app.postAdoptionCompletedAt != null ? ' — ${_fmtDate(app.postAdoptionCompletedAt)}' : ''}'
                : 'In Progress',
          ),
          if (!app.noFollowUpsPlanned && followUps.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: completed / followUps.length,
                  minHeight: 8,
                  backgroundColor: AppColors.slaterspwn.withValues(alpha: 0.3),
                  valueColor: const AlwaysStoppedAnimation(AppColors.greenrspwn),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            SizedBox(width: 110, child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
            Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          ],
        ),
      );
}

class _ReturnBanner extends StatelessWidget {
  final AdoptionApplication app;
  const _ReturnBanner({required this.app});

  @override
  Widget build(BuildContext context) {
    final r = app.returnRequest!;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ReturnDetailsPage(applicationId: app.id))),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.pinkrspwn.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(14)),
        child: Row(
          children: [
            const Icon(Icons.assignment_return_outlined, color: AppColors.textPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text('A return request is in progress — ${r.status.label}. Tap to review.',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }
}

class _CompleteMonitoringButton extends StatelessWidget {
  final AdoptionApplication app;
  final List<FollowUpRecord> followUps;
  final bool busy;
  final VoidCallback onTap;
  const _CompleteMonitoringButton({required this.app, required this.followUps, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    if (app.postAdoptionStatus == 'completed') {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.greenrspwn.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(14)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: AppColors.greenrspwn),
            const SizedBox(width: 8),
            Text('Post-adoption monitoring completed', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      );
    }

    final completed = followUps.where((f) => f.status == FollowUpStatus.completed || f.status == FollowUpStatus.cancelled).length;
    final allDone = followUps.isNotEmpty && completed == followUps.length;

    return Column(
      children: [
        if (!allDone)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('$completed of ${followUps.length} follow-ups completed', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: (busy || !allDone) ? null : onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              disabledBackgroundColor: AppColors.slaterspwn,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('Mark Post-Adoption Complete', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  final String applicationId;
  final FollowUpRecord followUp;
  final bool expanded;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onSendReminder;
  final VoidCallback onConfirmReceipt;
  final VoidCallback onComplete;
  final VoidCallback onManualComplete;
  final VoidCallback onReschedule;

  const _FollowUpCard({
    required this.applicationId,
    required this.followUp,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onSendReminder,
    required this.onConfirmReceipt,
    required this.onComplete,
    required this.onManualComplete,
    required this.onReschedule,
  });

  Color _statusColor(String label) => switch (label) {
        'Overdue' => Colors.redAccent,
        'Completed' => AppColors.greenrspwn,
        'Confirmed' => AppColors.greenrspwn,
        'Cancelled' => AppColors.slaterspwn,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    final displayStatus = followUp.displayStatus(DateTime.now());
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
      ]),
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Follow-up ${followUp.sequenceNumber}',
                            style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text(_fmtDate(followUp.scheduledDate), style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration:
                        BoxDecoration(color: _statusColor(displayStatus).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                    child: Text(displayStatus, style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor(displayStatus))),
                  ),
                  Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  _detail('Scheduled date', _fmtDate(followUp.scheduledDate)),
                  if (followUp.originalScheduledDate != null) _detail('Original date', _fmtDate(followUp.originalScheduledDate)),
                  _detail('Reminder', followUp.reminderSentAt == null ? 'Not sent' : '${_fmtDateTime(followUp.reminderSentAt)} (x${followUp.reminderCount})'),
                  _detail('Submitted', followUp.submittedAt == null ? 'Not yet' : _fmtDateTime(followUp.submittedAt)),
                  _detail('Confirmed', followUp.confirmedAt == null ? 'Not yet' : '${_fmtDateTime(followUp.confirmedAt)} by ${followUp.confirmedBy ?? '—'}'),
                  if (followUp.confirmationNotes != null && followUp.confirmationNotes!.isNotEmpty)
                    _detail('Organization notes', followUp.confirmationNotes!),
                  if (followUp.manualCompletionReason != null) _detail('Manually closed — reason', followUp.manualCompletionReason!),
                  if (followUp.rescheduledAt != null)
                    _detail('Rescheduled', '${_fmtDateTime(followUp.rescheduledAt)} by ${followUp.rescheduledBy ?? '—'}${followUp.rescheduleReason != null ? ' — ${followUp.rescheduleReason}' : ''}'),
                  const SizedBox(height: 8),
                  Text('Adopter Responses', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 6),
                  _AdopterResponseViewer(applicationId: applicationId, followUpId: followUp.id, submitted: followUp.submittedAt != null),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!followUp.isTerminal)
                              ElevatedButton(
                                onPressed: busy ? null : onSendReminder,
                                style:
                                    ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                                child: const Text('Send Reminder'),
                              ),
                            if (followUp.status == FollowUpStatus.submitted)
                              ElevatedButton(
                                onPressed: busy ? null : onConfirmReceipt,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.greenrspwn, foregroundColor: Colors.white),
                                child: const Text('Confirm Receipt'),
                              ),
                            if (followUp.status == FollowUpStatus.confirmed)
                              ElevatedButton(
                                onPressed: busy ? null : onComplete,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                                child: const Text('Mark as Complete'),
                              ),
                            if (!followUp.isTerminal && followUp.status != FollowUpStatus.confirmed)
                              ElevatedButton(
                                onPressed: busy ? null : onManualComplete,
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                                child: const Text('Close without response'),
                              ),
                          ],
                        ),
                      ),
                      // Reschedule moved off the main action row and into a
                      // secondary overflow menu — it was cluttering the row
                      // as a same-weight button next to the actual primary
                      // actions above; functionality is unchanged.
                      if (!followUp.isTerminal)
                        PopupMenuButton<void>(
                          icon: const Icon(Icons.more_vert, color: AppColors.textSecondary),
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              onTap: busy ? null : onReschedule,
                              child: const Text('Reschedule'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
            children: [
              TextSpan(text: '$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: value),
            ],
          ),
        ),
      );
}

/// Reads the SAME `checkins/{followUpId}` doc the existing adopter-side
/// PostAdoptionCheckinForm already writes (post_adoption_page.dart) — every
/// field rendered here is one that form actually collects, nothing
/// invented.
class _AdopterResponseViewer extends StatelessWidget {
  final String applicationId;
  final String followUpId;
  final bool submitted;
  const _AdopterResponseViewer({required this.applicationId, required this.followUpId, required this.submitted});

  @override
  Widget build(BuildContext context) {
    if (!submitted) {
      return Text('No response submitted yet.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
    }
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('adoptions').doc(applicationId).collection('checkins').doc(followUpId).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data();
        if (data == null) return Text('Loading response…', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
        final healthConcerns = List<String>.from(data['healthConcerns'] ?? const []);
        final images = List<String>.from(data['images'] ?? const []);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _qa('How is the pet doing?', data['howIsPetDoing'] as String?),
            _qa('Health concerns', healthConcerns.isEmpty ? null : healthConcerns.join(', ') + (data['healthConcernsOther'] != null && (data['healthConcernsOther'] as String).isNotEmpty ? ' (${data['healthConcernsOther']})' : '')),
            _qa('Vaccinations', data['vaccinated'] as String?),
            _qa('Additional notes', data['notes'] as String?),
            if (images.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Photos (${images.length})', style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              const SizedBox(height: 6),
              SizedBox(
                height: 84,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(images[i], width: 84, height: 84, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(width: 84, height: 84, color: AppColors.tearspwn)),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _qa(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
