import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';
import 'package:respawnd1/core/utils/adoption_lifecycle.dart';
import 'package:respawnd1/core/widgets/animal_record_header_image.dart';
import 'package:respawnd1/core/widgets/date_time_picker_sheet.dart' as picker;
import 'package:respawnd1/features/admin/adoption/return_details_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

const List<String> kPostAdoptionWarningCategories = [
  'Missed follow-up',
  'Animal welfare concern',
  'Incomplete information',
  'Unable to contact adopter',
  'Agreement concern',
  'Other',
];

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

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';

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

  // No separate "Confirm Receipt" step anymore — Mark as Complete is the
  // only completion action for an individual follow-up (spec: "Do not
  // require a separate Confirm Receipt step"). completeFollowUp itself
  // never required the prior confirmed status at the repository level
  // (see its own doc comment), so this was purely a UI gate to relax.
  Future<void> _completeFollowUp(FollowUpRecord f) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Mark Follow-up Complete?', message: 'This closes follow-up #${f.sequenceNumber}.', confirmLabel: 'Mark Complete');
    if (!confirmed) return;
    await _run(
        () => ref.read(adoptionApplicationRepositoryProvider).completeFollowUp(applicationId: widget.applicationId, followUpId: f.id, actorName: _actorName));
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

  Future<void> _addNote() async {
    final text = await _promptText(title: 'Add Note', label: 'Private organization note (never shown to the adopter)', required: true);
    if (text == null || text.isEmpty) return;
    await _run(() =>
        ref.read(adoptionApplicationRepositoryProvider).addPrivateNote(applicationId: widget.applicationId, text: text, actorUid: _actorUid, actorName: _actorName));
  }

  Future<void> _sendWarning() async {
    final result = await showModalBottomSheet<_WarningDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _SendWarningSheet(),
    );
    if (result == null) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).sendWarning(
          applicationId: widget.applicationId,
          category: result.category,
          message: result.message,
          requiredAction: result.requiredAction,
          responseDeadline: result.responseDeadline,
          actorUid: _actorUid,
          actorName: _actorName,
        ));
  }

  Future<void> _resolveWarning(String warningId) async {
    final confirmed = await showConfirmActionDialog(context, title: 'Mark Warning Resolved?', message: 'This does not notify the adopter.', confirmLabel: 'Mark Resolved');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).resolveWarning(applicationId: widget.applicationId, warningId: warningId, actorName: _actorName));
  }

  Future<void> _initiateReturn() async {
    final result = await showModalBottomSheet<_InitiateReturnDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _InitiateReturnSheet(),
    );
    if (result == null) return;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Initiate Return?',
      message: 'This starts the same return workflow an adopter-requested return uses. The adopter will see a return banner stating '
          'the organization initiated this.',
      confirmLabel: 'Initiate Return',
    );
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).adminInitiateReturn(
          applicationId: widget.applicationId,
          reason: result.reason,
          explanation: result.explanation,
          urgency: result.urgency,
          proposedRetrievalDateTime: result.proposedRetrievalDateTime,
          internalNotes: result.internalNotes,
          actorUid: _actorUid,
          actorName: _actorName,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(adoptionApplicationProvider(widget.applicationId));
    final app = appAsync.asData?.value;
    final followUpsAsync = ref.watch(followUpsForAdoptionProvider(widget.applicationId));
    final followUps = [...followUpsAsync.asData?.value ?? const <FollowUpRecord>[]]..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));

    // Action visibility by state (spec §4): a return in progress hides
    // Add Note/Send Warning/Initiate Return (View Return / Schedule /
    // Confirm Retrieved already live on ReturnDetailsPage, one tap away
    // via the return banner below — not duplicated here); Completed shows
    // only Initiate Return.
    final returnRequest = app?.returnRequest;
    final returnActive = isReturnActive(returnRequest);
    final monitoringCompleted = app?.postAdoptionStatus == 'completed';
    final activeMonitoring = !returnActive && !monitoringCompleted;

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
                  _OrgActionsSection(
                    activeMonitoring: activeMonitoring,
                    monitoringCompleted: monitoringCompleted,
                    busy: _busy,
                    onAddNote: _addNote,
                    onSendWarning: _sendWarning,
                    onInitiateReturn: _initiateReturn,
                  ),
                  const SizedBox(height: 12),
                  // Post-Adoption Notes spec §5 — surfaces the SAME
                  // notesLog/addPrivateNote history the "Add General
                  // Post-Adoption Note" button above already writes to,
                  // which previously had no display anywhere on this
                  // screen at all (only visible, mislabeled "Interview
                  // Notes", on the separate application-review page).
                  _GeneralNotesSection(applicationId: widget.applicationId),
                  const SizedBox(height: 12),
                  _WarningsSection(applicationId: widget.applicationId, busy: _busy, onResolve: _resolveWarning),
                  const SizedBox(height: 12),
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
                        onComplete: () => _completeFollowUp(f),
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AnimalRecordHeaderImage(animalRecordId: app.animalRecordId, height: 110),
          ),
          const SizedBox(height: 10),
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
              child: Text(
                  r.isOrgInitiated
                      ? 'The organization has initiated a return — ${r.status.label}. Tap to review.'
                      : 'A return request is in progress — ${r.status.label}. Tap to review.',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }
}

/// Add Note / Send Warning / Initiate Return (spec §4) — visibility keyed
/// off the same active-monitoring/return-active/completed state the
/// return banner and Mark Complete button already derive, so these never
/// disagree about what phase the adoption is in.
class _OrgActionsSection extends StatelessWidget {
  final bool activeMonitoring;
  final bool monitoringCompleted;
  final bool busy;
  final VoidCallback onAddNote;
  final VoidCallback onSendWarning;
  final VoidCallback onInitiateReturn;

  const _OrgActionsSection({
    required this.activeMonitoring,
    required this.monitoringCompleted,
    required this.busy,
    required this.onAddNote,
    required this.onSendWarning,
    required this.onInitiateReturn,
  });

  @override
  Widget build(BuildContext context) {
    // Return-active: nothing here — View Return / Schedule / Confirm
    // Retrieved already live on ReturnDetailsPage via the banner above.
    if (!activeMonitoring && !monitoringCompleted) return const SizedBox.shrink();

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Organization Actions', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (activeMonitoring) ...[
                OutlinedButton(
                  onPressed: busy ? null : onAddNote,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.textPrimary, side: const BorderSide(color: AppColors.textPrimary)),
                  // Post-Adoption Notes spec §5 — explicitly scoped as the
                  // adoption-wide note, distinct from each follow-up's own
                  // admin note below (_FollowUpCard's "Admin Note" field).
                  child: const Text('Add General Post-Adoption Note'),
                ),
                OutlinedButton(
                  onPressed: busy ? null : onSendWarning,
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF9C6B10), side: const BorderSide(color: Color(0xFFE0A353))),
                  child: const Text('Send Warning'),
                ),
              ],
              ElevatedButton(
                onPressed: busy ? null : onInitiateReturn,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE05353), foregroundColor: Colors.white),
                child: const Text('Initiate Return'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Persistent warning history — this, not just the notification feed, is
/// what makes a sent warning reliably visible on the admin side and (via
/// the equivalent user-side section in post_adoption_page.dart) the
/// adopter side.
class _WarningsSection extends StatelessWidget {
  final String applicationId;
  final bool busy;
  final ValueChanged<String> onResolve;
  const _WarningsSection({required this.applicationId, required this.busy, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('adoptions').doc(applicationId).collection('warnings').orderBy('sentAt', descending: true).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Warnings', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              for (final doc in docs) _WarningRow(id: doc.id, data: doc.data(), busy: busy, onResolve: () => onResolve(doc.id)),
            ],
          ),
        );
      },
    );
  }
}

class _WarningRow extends StatelessWidget {
  final String id;
  final Map<String, dynamic> data;
  final bool busy;
  final VoidCallback onResolve;
  const _WarningRow({required this.id, required this.data, required this.busy, required this.onResolve});

  @override
  Widget build(BuildContext context) {
    final resolved = data['resolved'] as bool? ?? false;
    final sentAt = data['sentAt'];
    final sentAtStr = sentAt is Timestamp ? _fmtDateTime(sentAt.toDate()) : 'Not set';
    final deadline = data['responseDeadline'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: resolved ? AppColors.tearspwn.withValues(alpha: 0.3) : const Color(0xFFE0A353).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(data['category'] as String? ?? 'Other',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              Text(resolved ? 'Resolved' : 'Open', style: GoogleFonts.zain(fontSize: 11, color: resolved ? AppColors.greenrspwn : const Color(0xFF9C6B10))),
            ],
          ),
          const SizedBox(height: 4),
          Text(data['message'] as String? ?? '', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          if ((data['requiredAction'] as String?)?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Required action: ${data['requiredAction']}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            ),
          if (deadline is Timestamp)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('Response due: ${_fmtDate(deadline.toDate())}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Sent $sentAtStr by ${data['sentBy'] ?? '—'}', style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
          ),
          if (!resolved) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onResolve,
                child: Text('Mark Resolved', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// General Post-Adoption Note history (Post-Adoption Notes spec §5) — the
/// SAME `adoptions/{id}/notesLog` subcollection AdoptionApplicationRepository.
/// addPrivateNote already writes to; this widget only reads it. Deliberately
/// labeled to make the scope unambiguous against each follow-up's own
/// separate Admin Note field below.
class _GeneralNotesSection extends StatelessWidget {
  final String applicationId;
  const _GeneralNotesSection({required this.applicationId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adoptions')
          .doc(applicationId)
          .collection('notesLog')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('General Post-Adoption Note — History', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              for (final doc in docs) _GeneralNoteRow(data: doc.data()),
            ],
          ),
        );
      },
    );
  }
}

class _GeneralNoteRow extends StatelessWidget {
  final Map<String, dynamic> data;
  const _GeneralNoteRow({required this.data});

  @override
  Widget build(BuildContext context) {
    final createdAt = data['createdAt'];
    final createdAtStr = createdAt is Timestamp ? _fmtDateTime(createdAt.toDate()) : 'Not set';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.tearspwn.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(data['text'] as String? ?? '', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('$createdAtStr by ${data['createdBy'] ?? '—'}', style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

typedef _WarningDraft = ({String category, String message, String? requiredAction, DateTime? responseDeadline});

class _SendWarningSheet extends StatefulWidget {
  const _SendWarningSheet();
  @override
  State<_SendWarningSheet> createState() => _SendWarningSheetState();
}

class _SendWarningSheetState extends State<_SendWarningSheet> {
  String _category = kPostAdoptionWarningCategories.first;
  final _messageController = TextEditingController();
  final _actionController = TextEditingController();
  DateTime? _deadline;

  @override
  void dispose() {
    _messageController.dispose();
    _actionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Send Warning', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),
            Text('Warning Category', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kPostAdoptionWarningCategories)
                  ChoiceChip(
                    label: Text(c),
                    selected: _category == c,
                    selectedColor: AppColors.yellowrspwn,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Message', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(controller: _messageController, maxLines: 3, decoration: const InputDecoration(hintText: 'Describe the concern')),
            const SizedBox(height: 14),
            Text('Required Corrective Action (optional)', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(controller: _actionController, decoration: const InputDecoration(hintText: 'What should the adopter do?')),
            const SizedBox(height: 14),
            Text('Response Deadline (optional)', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 7)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                if (picked != null) setState(() => _deadline = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_deadline == null ? 'None set' : _fmtDate(_deadline), style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _messageController.text.trim().isEmpty
                    ? null
                    : () => Navigator.pop(context, (
                          category: _category,
                          message: _messageController.text.trim(),
                          requiredAction: _actionController.text.trim().isEmpty ? null : _actionController.text.trim(),
                          responseDeadline: _deadline,
                        )),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                child: const Text('Send Warning'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

typedef _InitiateReturnDraft = ({
  String reason,
  String explanation,
  String urgency,
  DateTime? proposedRetrievalDateTime,
  String? internalNotes,
});

const List<String> kAdminReturnUrgencyOptions = ['Low', 'Medium', 'High'];

class _InitiateReturnSheet extends StatefulWidget {
  const _InitiateReturnSheet();
  @override
  State<_InitiateReturnSheet> createState() => _InitiateReturnSheetState();
}

class _InitiateReturnSheetState extends State<_InitiateReturnSheet> {
  final _reasonController = TextEditingController();
  final _explanationController = TextEditingController();
  final _notesController = TextEditingController();
  String _urgency = 'Medium';
  DateTime? _proposedDate;

  @override
  void dispose() {
    _reasonController.dispose();
    _explanationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _reasonController.text.trim().isNotEmpty && _explanationController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Initiate Return', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Starts the same return workflow an adopter-requested return uses.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Text('Reason', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(controller: _reasonController, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'e.g. Welfare concern, agreement violation')),
            const SizedBox(height: 14),
            Text('Detailed Explanation', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: _explanationController,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Explain why the organization is initiating this return'),
            ),
            const SizedBox(height: 14),
            Text('Urgency', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final u in kAdminReturnUrgencyOptions)
                  ChoiceChip(label: Text(u), selected: _urgency == u, selectedColor: AppColors.yellowrspwn, onSelected: (_) => setState(() => _urgency = u)),
              ],
            ),
            const SizedBox(height: 14),
            Text('Proposed Retrieval Schedule (optional)', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now().add(const Duration(days: 3)),
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 90)),
                );
                if (picked != null) setState(() => _proposedDate = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_proposedDate == null ? 'Not proposed yet' : _fmtDate(_proposedDate), style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Internal Notes (optional, never shown to adopter)', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(controller: _notesController, maxLines: 2, decoration: const InputDecoration(hintText: 'Internal notes')),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: !_canSubmit
                    ? null
                    : () => Navigator.pop(context, (
                          reason: _reasonController.text.trim(),
                          explanation: _explanationController.text.trim(),
                          urgency: _urgency,
                          proposedRetrievalDateTime: _proposedDate,
                          internalNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
                        )),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE05353),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.slaterspwn,
                ),
                child: const Text('Continue'),
              ),
            ),
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

/// Per-follow-up Admin Note editor (Post-Adoption Notes spec §4). Kept
/// read-only once the follow-up reaches a terminal state (completed/
/// cancelled) — this codebase's existing convention for other per-item
/// notes (e.g. Interview Notes becoming read-only once an application is
/// adopted) is to freeze history rather than keep it editable forever;
/// flagged here as a deliberate policy choice, not an oversight, in case
/// the org actually wants completed items to stay editable.
class _FollowUpAdminNoteField extends StatefulWidget {
  final String applicationId;
  final FollowUpRecord followUp;
  const _FollowUpAdminNoteField({required this.applicationId, required this.followUp});

  @override
  State<_FollowUpAdminNoteField> createState() => _FollowUpAdminNoteFieldState();
}

enum _NoteSaveState { idle, saving, saved, error }

class _FollowUpAdminNoteFieldState extends State<_FollowUpAdminNoteField> {
  late final TextEditingController _controller;
  _NoteSaveState _saveState = _NoteSaveState.idle;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.followUp.adminNote ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  Future<void> _save() async {
    setState(() => _saveState = _NoteSaveState.saving);
    try {
      await AdoptionApplicationRepository().setFollowUpAdminNote(
        applicationId: widget.applicationId,
        followUpId: widget.followUp.id,
        note: _controller.text.trim(),
        actorName: _actorName,
      );
      if (!mounted) return;
      setState(() {
        _saveState = _NoteSaveState.saved;
        _editing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveState = _NoteSaveState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.followUp.isTerminal && !_editing;
    final hasNote = (widget.followUp.adminNote ?? '').trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Admin Note', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const Spacer(),
              if (_saveState == _NoteSaveState.saving)
                const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
              else if (_saveState == _NoteSaveState.saved)
                Text('Saved', style: GoogleFonts.zain(fontSize: 11, color: AppColors.greenrspwn))
              else if (_saveState == _NoteSaveState.error)
                Text('Could not save', style: GoogleFonts.zain(fontSize: 11, color: Colors.redAccent)),
            ],
          ),
          const SizedBox(height: 6),
          if (readOnly)
            Text(hasNote ? widget.followUp.adminNote! : 'No note for this follow-up.',
                style: GoogleFonts.zain(fontSize: 12, color: hasNote ? AppColors.textPrimary : AppColors.textSecondary))
          else
            TextField(
              controller: _controller,
              maxLines: 3,
              onChanged: (_) => setState(() => _saveState = _NoteSaveState.idle),
              decoration: InputDecoration(
                hintText: 'Private note for this follow-up (never shown to the adopter)',
                hintStyle: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                isDense: true,
                contentPadding: const EdgeInsets.all(8),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.slaterspwn)),
              ),
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
            ),
          if (widget.followUp.adminNoteUpdatedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Last updated ${_fmtDateTime(widget.followUp.adminNoteUpdatedAt)} by ${widget.followUp.adminNoteUpdatedBy ?? '—'}',
                style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary),
              ),
            ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: widget.followUp.isTerminal && !_editing
                ? TextButton(
                    onPressed: () => setState(() => _editing = true),
                    child: Text('Edit anyway', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  )
                : TextButton(
                    onPressed: _saveState == _NoteSaveState.saving ? null : _save,
                    child: Text('Save Note', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
          ),
        ],
      ),
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
  final VoidCallback onComplete;
  final VoidCallback onReschedule;

  const _FollowUpCard({
    required this.applicationId,
    required this.followUp,
    required this.expanded,
    required this.busy,
    required this.onToggle,
    required this.onSendReminder,
    required this.onComplete,
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
                  const SizedBox(height: 10),
                  // Post-Adoption Notes spec §4 — belongs to THIS follow-up
                  // only (never the adopter's confirmationNotes above, never
                  // the adoption-wide General Post-Adoption Note), placed
                  // before the communication/action row below.
                  _FollowUpAdminNoteField(applicationId: applicationId, followUp: followUp),
                  const SizedBox(height: 10),
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
                            // No separate Confirm Receipt step — Mark as
                            // Complete is reachable directly once a
                            // response is submitted (or immediately, for
                            // any already-confirmed legacy follow-up).
                            if (followUp.status == FollowUpStatus.submitted ||
                                followUp.status == FollowUpStatus.confirmed)
                              ElevatedButton(
                                onPressed: busy ? null : onComplete,
                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                                child: const Text('Mark as Complete'),
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


