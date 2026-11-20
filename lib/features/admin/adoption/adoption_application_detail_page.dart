import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/utils/current_org_kind.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/adoption_fit_assessment.dart';
import 'package:respawnd1/core/models/adoption/adoption_no_show_rules.dart';
import 'package:respawnd1/core/models/adoption/adoption_response_sections.dart';
import 'package:respawnd1/core/services/adoption_fit_assessment_service.dart';
import 'package:respawnd1/core/widgets/photo_thumbnail_strip.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/adoption/widgets/adoption_rejection_sheet.dart';
import 'package:respawnd1/features/admin/adoption/widgets/interview_reschedule_sheet.dart';
import 'package:respawnd1/features/admin/adoption/post_adoption_details_page.dart';
import 'package:respawnd1/features/admin/adoption/release_details_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

String _fmtDate(DateTime? d) => d == null ? kNotProvided : formatDate(d);
String _fmtDateTime(DateTime? d) =>
    d == null ? kNotProvided : formatDateTime(d);

class AdoptionApplicationDetailPage extends ConsumerStatefulWidget {
  final String applicationId;
  const AdoptionApplicationDetailPage({super.key, required this.applicationId});

  @override
  ConsumerState<AdoptionApplicationDetailPage> createState() => _AdoptionApplicationDetailPageState();
}

class _AdoptionApplicationDetailPageState extends ConsumerState<AdoptionApplicationDetailPage> {
  bool _busy = false;
  final _noteController = TextEditingController();

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Action failed: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeInterview(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Complete Interview?',
        message: 'This marks the interview step completed. The application stays in Interview until you Accept or Reject it.',
        confirmLabel: 'Complete Interview');
    if (!confirmed) return;
    await _run(() => ref
        .read(adoptionApplicationRepositoryProvider)
        .completeInterview(applicationId: app.id, actorUid: _actorUid, actorName: _actorName));
  }

  Future<void> _confirmInterview(AdoptionApplication app) async {
    final when = '${_fmtDate(app.appointmentDate)}${app.appointmentTime != null ? ' · ${app.appointmentTime}' : ''}';
    final confirmed = await showConfirmActionDialog(context,
        title: 'Confirm Interview?',
        message: 'This moves the application to Interview and tells ${app.adopterName} their interview on $when is confirmed.',
        confirmLabel: 'Confirm Interview');
    if (!confirmed) return;
    await _run(() => ref
        .read(adoptionApplicationRepositoryProvider)
        .confirmInterview(applicationId: app.id, actorUid: _actorUid, actorName: _actorName));
  }

  Future<void> _markNoShow(AdoptionApplication app) async {
    final closes = noShowOutcome(previousNoShows: app.noShowCount) == NoShowOutcome.close;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Mark as No-show?',
      message: closes
          ? 'This is ${app.adopterName}\'s second missed interview. The application will be closed '
              '("$kNoShowClosedReason") and they will be told.'
          : '${app.adopterName} will be told they missed the interview and can book one more. '
              'A second no-show closes the application.',
      confirmLabel: closes ? 'Close Application' : 'Mark No-show',
      destructive: closes,
    );
    if (!confirmed || !mounted) return;
    await _run(() => ref
        .read(adoptionApplicationRepositoryProvider)
        .markNoShow(applicationId: app.id, actorUid: _actorUid, actorName: _actorName));
    // The missed interview's online meeting is no longer needed.
    if (mounted && app.hasActiveZoomMeeting) await _cancelZoomMeeting(app.id);
  }

  Future<void> _reschedule(AdoptionApplication app) async {
    final result = await showInterviewRescheduleSheet(
      context,
      initialDate: app.appointmentDate,
      initialTime: app.appointmentTime,
      initialType: app.appointmentType,
    );
    if (result == null) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).rescheduleInterview(
          applicationId: app.id,
          date: result.date,
          time: result.time,
          type: result.type,
          actorName: _actorName,
        ));
    // Zoom interview spec — only ever created for an Online interview,
    // never for On-site (and never blocks the appointment save above,
    // which already completed either way). Deliberately outside _run so a
    // Zoom failure shows its own retry action without re-litigating
    // whether the appointment itself saved.
    if (mounted && result.type == 'Online') {
      await _setupZoomMeeting(app.id, result.date, result.time);
    }
  }

  /// appointmentRevision is derived from the date+time themselves (not a
  /// separate counter) — a duplicate save with the SAME date/time always
  /// produces the same key, so a Firestore listener rebuild, a reopened
  /// page, or a duplicate tap on Save never creates a second meeting; an
  /// actual reschedule changes date/time and therefore the key, which is
  /// exactly when a new/updated meeting is needed.
  Future<void> _setupZoomMeeting(String applicationId, DateTime date, String time) async {
    final revision = '${date.toIso8601String()}_$time';
    final startTime = DateTime(date.year, date.month, date.day);
    try {
      await FirebaseFunctions.instance.httpsCallable('createOrUpdateZoomMeeting').call(<String, dynamic>{
        'applicationId': applicationId,
        'appointmentRevision': revision,
        'topic': 'Adoption Interview',
        'startTimeIso': startTime.toIso8601String(),
        'durationMinutes': 30,
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final unavailable = e.code == 'failed-precondition';
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(unavailable
            ? 'Online meeting setup is unavailable for this organization.'
            : 'Could not set up the Zoom meeting.', kind: AppMessageKind.error, action: unavailable
            ? null
            : SnackBarAction(label: 'Retry', onPressed: () => _setupZoomMeeting(applicationId, date, time))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not set up the Zoom meeting.', kind: AppMessageKind.error, action: SnackBarAction(label: 'Retry', onPressed: () => _setupZoomMeeting(applicationId, date, time))));
    }
  }

  Future<void> _cancelZoomMeeting(String applicationId) async {
    try {
      await FirebaseFunctions.instance.httpsCallable('cancelZoomMeeting').call(<String, dynamic>{'applicationId': applicationId});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(appSnackBar('Could not cancel the Zoom meeting: $e', kind: AppMessageKind.error));
      }
    }
  }

  Future<void> _saveNote(AdoptionApplication app) async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    await _run(() => ref
        .read(adoptionApplicationRepositoryProvider)
        .addNote(applicationId: app.id, text: text, actorUid: _actorUid, actorName: _actorName));
    _noteController.clear();
  }

  /// The viewer's organization is an independent rescuer (interview
  /// optional). Loaded once.
  bool _interviewOptional = false;
  bool _kindLoaded = false;

  void _loadKindOnce() {
    if (_kindLoaded) return;
    _kindLoaded = true;
    currentOrgIsIndependent().then((v) {
      if (mounted && v) setState(() => _interviewOptional = true);
    });
  }

  Future<void> _accept(AdoptionApplication app) async {
    final confirmed =
        await showConfirmActionDialog(context, title: 'Accept Application?', message: 'This moves the application to Approved.', confirmLabel: 'Accept');
    if (!confirmed) return;
    await _run(() async {
      final fit = await _fitAssessmentNow(app);
      await ref
          .read(adoptionApplicationRepositoryProvider)
          .accept(applicationId: app.id, actorUid: _actorUid, actorName: _actorName, fitAssessment: fit);
    });
  }

  /// The rule-based Fit Assessment as it stands right now, saved with the
  /// decision. Null when the application has no linked animal record.
  Future<AdoptionFitAssessment?> _fitAssessmentNow(AdoptionApplication app) async {
    final animalRecordId = app.animalRecordId;
    if (animalRecordId == null) return null;
    final animal = await ref.read(animalRecordProvider(animalRecordId).future);
    return animal == null ? null : calculateFitAssessment(application: app, animal: animal);
  }

  Future<void> _reject(AdoptionApplication app) async {
    final result = await showAdoptionRejectionSheet(context);
    if (result == null) return;
    await _run(() async {
      final fit = await _fitAssessmentNow(app);
      await ref.read(adoptionApplicationRepositoryProvider).reject(
            applicationId: app.id,
            reasons: result.reasons,
            notes: result.notes,
            actorUid: _actorUid,
            actorName: _actorName,
            fitAssessment: fit,
          );
    });
    // Zoom interview spec — rejecting an application with a scheduled
    // online interview counts as cancelling that interview: the meeting is
    // invalidated so the old join link stops working, without deleting the
    // meeting's history.
    if (mounted && app.hasActiveZoomMeeting) {
      await _cancelZoomMeeting(app.id);
    }
  }

  // reserve/unreserve/release all take a real animals/{id} doc id for a
  // direct document lookup — app.animalId is the legacy hash/catalog-int
  // join key and would never resolve to the actual animal doc (see
  // AdoptionApplication's own doc comment). app.animalRecordId is the
  // reliable one; applications submitted before it existed can't be
  // reserved/released from here, so that's surfaced as a clear message
  // rather than a silent "Animal record not found" failure from _run.
  Future<void> _reserve(AdoptionApplication app) async {
    final animalRecordId = app.animalRecordId;
    if (animalRecordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar("This application predates linked animal records and can't be reserved automatically.", kind: AppMessageKind.error));
      return;
    }
    final confirmed = await showConfirmActionDialog(context,
        title: 'Reserve ${app.animalName}?',
        message: 'This reserves the animal for ${app.adopterName}. Every other open application for '
            '${app.animalName} will be closed as "Animal no longer available" and those applicants notified. '
            'Unreserving later does not reopen them.',
        confirmLabel: 'Reserve');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).reserve(
          applicationId: app.id,
          animalId: animalRecordId,
          actorId: FirebaseAuth.instance.currentUser?.uid,
          actorName: FirebaseAuth.instance.currentUser?.displayName,
          actorEmail: FirebaseAuth.instance.currentUser?.email,
        ));
  }

  Future<void> _unreserve(AdoptionApplication app) async {
    final animalRecordId = app.animalRecordId;
    if (animalRecordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar("This application predates linked animal records and can't be unreserved automatically.", kind: AppMessageKind.error));
      return;
    }
    final confirmed = await showConfirmActionDialog(context,
        title: 'Unreserve ${app.animalName}?',
        message: 'This clears the reservation and returns the animal to the adoptable list. The application stays Approved.',
        confirmLabel: 'Unreserve');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).unreserve(applicationId: app.id, animalId: animalRecordId));
  }

  // The admin now sets the release date and follow-up schedule on the
  // dedicated Release Details screen (spec §1/§2) instead of a bare confirm
  // dialog — that screen calls AdoptionApplicationRepository.
  // releaseWithFollowUps itself once "Mark as Released" is confirmed.
  void _release(AdoptionApplication app) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReleaseDetailsPage(applicationId: app.id)));
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
        title: Text('Adoption Details', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: app == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: _buildBody(app),
            ),
    );
  }

  /// One page for every phase: a stepper and a "current step" card holding
  /// what staff act on now, then the reference sections. The existing
  /// section widgets are each placed exactly once — inside the current-step
  /// card when they are this phase's work, otherwise further down.
  Widget _buildBody(AdoptionApplication app) {
    _loadKindOnce();
    final status = app.status;
    // While the application is still being reviewed, the review material
    // starts open; once it has moved on it is reference, so it starts
    // collapsed. Keys carry the status so a phase change (e.g. Accept)
    // resets each section to the new phase's default.
    final reviewing = status == AdoptionStatus.pending;
    final interviewIsCurrent = status == AdoptionStatus.interview;

    final appointment = _AppointmentSection(
      app: app,
      busy: _busy,
      onCompleteInterview: () => _completeInterview(app),
      onReschedule: () => _reschedule(app),
      onNoShow: () => _markNoShow(app),
    );
    final notes = _NotesSection(app: app, controller: _noteController, busy: _busy, onSave: () => _saveNote(app));
    final actions = _ActionsSection(
      app: app,
      busy: _busy,
      onConfirmInterview: () => _confirmInterview(app),
      onAccept: () => _accept(app),
      onReject: () => _reject(app),
      onReserve: () => _reserve(app),
      onUnreserve: () => _unreserve(app),
      onRelease: () => _release(app),
      interviewOptional: _interviewOptional,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AnimalHeaderCard(app: app),
        const SizedBox(height: 14),
        _PhaseStepper(status: status),
        const SizedBox(height: 14),

        _CurrentStepCard(
          app: app,
          children: [
            if (status == AdoptionStatus.pending) _PendingReviewChecklist(app: app),
            if (interviewIsCurrent) ...[appointment, notes],
            actions,
          ],
        ),

        const SizedBox(height: 16),
        SectionCard(title: 'Details', child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _InfoItem('Name', app.adopterName)),
              Expanded(child: _InfoItem('Location', app.adopterCity ?? kNotProvided)),
            ]),
            Row(children: [
              Expanded(child: _InfoItem('Email', app.adopterEmail)),
              Expanded(child: _InfoItem('Phone', app.adopterPhone)),
            ]),
          ],
        )),

        const SizedBox(height: 12),
        _FitAssessmentCard(key: ValueKey('fit-${status.name}'), app: app, initiallyExpanded: false),

        const SizedBox(height: 12),
        _ApplicantHistorySection(key: ValueKey('history-${status.name}'), app: app, initiallyExpanded: false),

        const SizedBox(height: 12),
        _ResponsesSection(key: ValueKey('responses-${status.name}'), app: app, initiallyExpanded: reviewing),

        const SizedBox(height: 12),
        _DocumentsSection(key: ValueKey('documents-${status.name}'), app: app, initiallyExpanded: reviewing),

        if (!interviewIsCurrent) ...[
          const SizedBox(height: 12),
          appointment,
          const SizedBox(height: 12),
          notes,
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---- Phase stepper + current step ----------------------------------------

const _kPhaseLabels = ['Pending', 'Interview', 'Release', 'Adopted'];

/// Index into [_kPhaseLabels]; null for a closed (rejected/withdrawn)
/// application, which sits outside the pipeline.
int? _phaseIndex(AdoptionStatus status) => switch (status) {
      AdoptionStatus.pending => 0,
      AdoptionStatus.interview => 1,
      AdoptionStatus.approved => 2,
      AdoptionStatus.adopted => 3,
      AdoptionStatus.rejected || AdoptionStatus.withdrawn => null,
    };

class _PhaseStepper extends StatelessWidget {
  final AdoptionStatus status;
  const _PhaseStepper({required this.status});

  @override
  Widget build(BuildContext context) {
    final current = _phaseIndex(status);
    final closed = current == null;
    return Opacity(
      opacity: closed ? 0.5 : 1,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < _kPhaseLabels.length; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: i == 0 ? const SizedBox() : _line(done: !closed && i <= current)),
                      _dot(i, current),
                      Expanded(child: i == _kPhaseLabels.length - 1 ? const SizedBox() : _line(done: !closed && i < current)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _kPhaseLabels[i],
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                      color: i == current ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _line({required bool done}) =>
      Container(height: 2, color: done ? AppColors.greenrspwn : AppColors.slaterspwn);

  Widget _dot(int i, int? current) {
    final done = current != null && i < current;
    final isCurrent = i == current;
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? AppColors.greenrspwn : (isCurrent ? AppColors.yellowrspwn : Colors.white),
        border: Border.all(color: done ? AppColors.greenrspwn : (isCurrent ? AppColors.textPrimary : AppColors.slaterspwn)),
      ),
      child: done
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : Text('${i + 1}', style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    );
  }
}

/// The highlighted block at the top of the page: what staff do in this
/// phase. It only frames the existing section widgets and actions passed
/// in as [children]; it adds no actions of its own.
class _CurrentStepCard extends StatelessWidget {
  final AdoptionApplication app;
  final List<Widget> children;
  const _CurrentStepCard({required this.app, required this.children});

  (String, String) get _copy => switch (app.status) {
        AdoptionStatus.pending => (
            'Review the application',
            'Review the responses and documents, then confirm the interview the applicant booked.',
          ),
        AdoptionStatus.interview => (
            'Hold the interview',
            'Complete the interview and record your notes, then Accept or Reject.',
          ),
        AdoptionStatus.approved => (
            'Release the animal',
            'Reserve the animal for this adopter, then set the release date and follow-ups.',
          ),
        AdoptionStatus.adopted => (
            'Post-adoption',
            'The animal is home. Follow-ups and returns are handled on the Post-Adoption page.',
          ),
        AdoptionStatus.rejected || AdoptionStatus.withdrawn => (
            'Closed',
            'This application is no longer active.',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (title, hint) = _copy;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.yellowrspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CURRENT STEP', style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textSecondary)),
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(hint, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          for (final child in children) ...[
            const SizedBox(height: 12),
            child,
          ],
        ],
      ),
    );
  }
}

/// Pending phase: a glance at what there is to review before deciding.
class _PendingReviewChecklist extends StatelessWidget {
  final AdoptionApplication app;
  const _PendingReviewChecklist({required this.app});

  @override
  Widget build(BuildContext context) {
    final uploads = (app.raw['uploads'] as Map?) ?? const {};
    final docsProvided = _DocumentsSection.providedCount(uploads);
    final booked = app.appointmentDate != null;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row(Icons.description_outlined, 'Responses', 'Application form completed', true),
          _row(Icons.folder_open_outlined, 'Documents', '$docsProvided of ${_DocumentsSection.kDocumentCount} provided',
              docsProvided == _DocumentsSection.kDocumentCount),
          _row(
            Icons.event_outlined,
            'Interview',
            booked
                ? 'Booked for ${_fmtDate(app.appointmentDate)}${app.appointmentTime != null ? ' · ${app.appointmentTime}' : ''}'
                : 'Not booked yet',
            booked,
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 16, color: ok ? AppColors.greenrspwn : AppColors.textSecondary),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: Text(label, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
            Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
          ],
        ),
      );
}

/// Header row shared by the collapsible sections: title + chevron.
class _CollapsibleHeader extends StatelessWidget {
  final String title;
  final bool expanded;
  final VoidCallback onToggle;
  final double fontSize;
  const _CollapsibleHeader({required this.title, required this.expanded, required this.onToggle, this.fontSize = 15});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onToggle,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: GoogleFonts.tiltWarp(fontSize: fontSize, color: AppColors.textPrimary)),
            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
          ],
        ),
      );
}

class _AnimalHeaderCard extends ConsumerWidget {
  final AdoptionApplication app;
  const _AnimalHeaderCard({required this.app});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // app.animalId is the legacy join key, never a real animals/{id} doc
    // id — see AdoptionApplication's own doc comment.
    final animalRecordId = app.animalRecordId;
    final animal = animalRecordId == null ? null : ref.watch(animalRecordProvider(animalRecordId)).asData?.value;
    final photoUrl = animal?.photoUrls.isNotEmpty == true ? animal!.photoUrls.first : null;

    return GestureDetector(
      onTap: animal == null
          ? null
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => AnimalRecordDetailPage(animalId: animal.id, data: animal.raw))),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: photoUrl != null
                ? Image.network(photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, _, _) => _ph())
                : _ph(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(app.animalName, style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                Text('Tap to open Animal Record', style: GoogleFonts.zain(fontSize: 11, color: AppColors.greenrspwn)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ph() => Container(
      width: 56, height: 56, decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.pets));
}

class _InfoItem extends StatelessWidget {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      );
}

// ---- Fit Assessment -----------------------------------------------------

/// Collapsed shows the score/band; expanded adds the breakdown.
class _FitAssessmentCard extends ConsumerStatefulWidget {
  final AdoptionApplication app;
  final bool initiallyExpanded;
  const _FitAssessmentCard({super.key, required this.app, this.initiallyExpanded = false});

  @override
  ConsumerState<_FitAssessmentCard> createState() => _FitAssessmentCardState();
}

class _FitAssessmentCardState extends ConsumerState<_FitAssessmentCard> {
  late bool expanded = widget.initiallyExpanded;

  AdoptionApplication get app => widget.app;
  void onToggle() => setState(() => expanded = !expanded);

  Color _bandColor(FitAssessmentBand band) => switch (band) {
        FitAssessmentBand.strong => AppColors.greenrspwn,
        FitAssessmentBand.moderate => AppColors.yellowrspwn,
        FitAssessmentBand.needsReview => AppColors.warning,
        FitAssessmentBand.significantConcerns => AppColors.error,
      };

  @override
  Widget build(BuildContext context) {
    // Once staff accepted or rejected the application, show the score they
    // saw then (saved with the decision), never a recalculated one.
    final saved = app.fitAtDecision;
    if (saved != null) {
      return SectionCard(
        title: 'Fit Assessment at decision time',
        child: _SavedFitAssessment(
          saved: saved,
          expanded: expanded,
          onToggle: onToggle,
          bandColor: saved.assessment == null ? AppColors.slaterspwn : _bandColor(saved.assessment!.band),
        ),
      );
    }

    // app.animalId is the legacy join key, never a real doc id.
    final animalRecordId = app.animalRecordId;
    final animal = animalRecordId == null ? null : ref.watch(animalRecordProvider(animalRecordId)).asData?.value;
    final assessment = animal == null ? null : calculateFitAssessment(application: app, animal: animal);

    return SectionCard(
      title: 'Fit Assessment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (app.status == AdoptionStatus.approved || app.status == AdoptionStatus.rejected)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('Decided before scores were saved; this is a fresh calculation.',
                  style: GoogleFonts.zain(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
            ),
          if (assessment == null)
            Text(
              animalRecordId == null
                  ? 'Fit assessment unavailable — this application predates linked animal records.'
                  : 'Loading fit assessment…',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            )
          else if (assessment.insufficientData)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fit assessment unavailable', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Not enough application or animal information was provided.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            )
          else
            _AssessmentSummary(assessment: assessment, expanded: expanded, onToggle: onToggle, bandColor: _bandColor(assessment.band)),
        ],
      ),
    );
  }
}

/// The computed side of the Fit Assessment card — collapsed shows just the
/// score/band/completeness; expanded adds the category breakdown and
/// plain-language strengths/concerns/not-assessed lists. Never shown with
/// approval/rejection styling — [bandColor] uses the same neutral palette
/// as other informational chips in this app, not a green-means-approved /
/// red-means-rejected scheme.
class _AssessmentSummary extends StatelessWidget {
  final AdoptionFitAssessment assessment;
  final bool expanded;
  final VoidCallback onToggle;
  final Color bandColor;
  const _AssessmentSummary({required this.assessment, required this.expanded, required this.onToggle, required this.bandColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text('${assessment.score} / 100', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: bandColor.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(20)),
                    child: Text(assessment.band.label, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ],
              ),
              Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text('Assessment completeness: ${assessment.completeness}%', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Text(
            'This assessment is a guide based on application and animal information. The organization must make '
            'the final decision after reviewing the full application, documents, and interview.',
            style: GoogleFonts.zain(fontSize: 11, fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
        if (expanded) ...[
          const SizedBox(height: 14),
          for (final c in assessment.categoryScores)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(c.label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                  Text('${c.score} / ${c.maxScore}', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
            ),
          if (assessment.strengths.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Positive indicators', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.greenrspwn)),
            for (final s in assessment.strengths)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('•  $s', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              ),
          ],
          if (assessment.concerns.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Concerns to discuss', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
            for (final c in assessment.concerns)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('•  $c', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              ),
          ],
          if (assessment.unassessedItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Not assessed', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            for (final u in assessment.unassessedItems)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('•  $u', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
          ],
        ],
      ],
    );
  }
}

/// The Fit Assessment saved when the application was accepted or rejected:
/// the score and breakdown under the rubric version of the day, the staff's
/// own fit value and the notes they had written.
class _SavedFitAssessment extends StatelessWidget {
  final FitAtDecision saved;
  final bool expanded;
  final VoidCallback onToggle;
  final Color bandColor;
  const _SavedFitAssessment({required this.saved, required this.expanded, required this.onToggle, required this.bandColor});

  @override
  Widget build(BuildContext context) {
    final muted = GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary);
    final verb = saved.decision == 'approved' ? 'accepted' : 'rejected';
    final when = saved.decidedAt == null ? '' : ' on ${_fmtDateTime(saved.decidedAt)}';
    final staffFit = saved.staffFitValue == null ? null : FitAssessmentValue.fromName(saved.staffFitValue);
    final a = saved.assessment;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Saved when ${saved.decidedBy ?? 'staff'} $verb this application$when'
            '${saved.rubricVersion == null ? '' : ' (rubric v${saved.rubricVersion})'}.', style: muted),
        const SizedBox(height: 8),
        if (a == null)
          Text('No score was calculated (no linked animal record).',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
        else if (a.insufficientData)
          Text('Not enough application or animal information for a score at the time.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
        else
          _AssessmentSummary(assessment: a, expanded: expanded, onToggle: onToggle, bandColor: bandColor),
        const SizedBox(height: 10),
        Text('Staff fit at decision: ${staffFit == null || staffFit == FitAssessmentValue.notReviewed ? 'not set' : staffFit.label}'
            '${saved.staffFitBy == null || staffFit == null ? '' : ' (by ${saved.staffFitBy})'}',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
        if (saved.staffNotes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Staff notes at decision', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          for (final n in saved.staffNotes)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('•  ${n.text}${n.by == null ? '' : ' (${n.by}${n.at == null ? '' : ', ${_fmtDate(n.at)}'})'}',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
            ),
        ],
      ],
    );
  }
}

// ---- Responses (collapsible) --------------------------------------------

class _ResponsesSection extends StatefulWidget {
  final AdoptionApplication app;
  final bool initiallyExpanded;
  const _ResponsesSection({super.key, required this.app, this.initiallyExpanded = false});

  @override
  State<_ResponsesSection> createState() => _ResponsesSectionState();
}

class _ResponsesSectionState extends State<_ResponsesSection> {
  late bool expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final sections = buildAdoptionResponseSections(widget.app.raw);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleHeader(title: 'Responses', expanded: expanded, onToggle: () => setState(() => expanded = !expanded)),
          if (!expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Application form completed', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ),
          if (expanded) ...[
            const SizedBox(height: 8),
            for (final section in sections) ...[
              Text(section.title, style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.greenrspwn)),
              const SizedBox(height: 4),
              for (final item in section.items) ...[
                Text(item.label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                Text(item.answer, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }
}

// ---- Applicant History ---------------------------------------------------

class _ApplicantHistorySection extends ConsumerStatefulWidget {
  final AdoptionApplication app;
  final bool initiallyExpanded;
  const _ApplicantHistorySection({super.key, required this.app, this.initiallyExpanded = false});

  @override
  ConsumerState<_ApplicantHistorySection> createState() => _ApplicantHistorySectionState();
}

class _ApplicantHistorySectionState extends ConsumerState<_ApplicantHistorySection> {
  late bool expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    if (app.adopterId.isEmpty) return const SizedBox.shrink();
    // Watched unconditionally (not gated on `expanded`) so Riverpod keeps
    // one cached subscription regardless of how many times the tile is
    // toggled — expanding never triggers a fresh Firestore query.
    final historyAsync = ref.watch(adoptionsForApplicantProvider(app.adopterId));
    final all = historyAsync.asData?.value ?? const <AdoptionApplication>[];
    final others = all.where((a) => a.id != app.id).toList();

    final successful = all.where((a) => a.status == AdoptionStatus.adopted).length;
    final rejected = all.where((a) => a.status == AdoptionStatus.rejected).length;
    final withdrawn = all.where((a) => a.status == AdoptionStatus.withdrawn).length;
    final active = all.where((a) => a.isOpen).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleHeader(
              title: 'Application History', expanded: expanded, onToggle: () => setState(() => expanded = !expanded)),
          if (expanded) ...[
            const SizedBox(height: 10),
            if (historyAsync.isLoading)
              const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
            else if (historyAsync.hasError)
              Text('Could not load application history.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
            else ...[
              Text('Previous applications: ${all.length}', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              Text('Successful adoptions: $successful', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              Text('Rejected applications: $rejected', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              Text('Withdrawn applications: $withdrawn', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              Text('Active applications: $active', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
              const Divider(height: 20),
              if (others.isEmpty)
                Text('No other applications from this applicant.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
              else
                for (final a in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${a.animalName} — ${a.status.label}', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
                      Text('Applied ${_fmtDate(a.createdAt)}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      if (a.status == AdoptionStatus.adopted && a.adoptedAt != null)
                        Text('Adopted ${_fmtDate(a.adoptedAt)}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      if (a.status == AdoptionStatus.rejected)
                        Text('Reason: ${a.rejectionReasons.isEmpty ? kNotProvided : a.rejectionReasons.join(', ')}',
                            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      if (a.status == AdoptionStatus.withdrawn)
                        Text('Reason: ${a.withdrawalReason ?? kNotProvided}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

// ---- Documents ------------------------------------------------------------

class _DocumentsSection extends StatefulWidget {
  final AdoptionApplication app;
  final bool initiallyExpanded;
  const _DocumentsSection({super.key, required this.app, this.initiallyExpanded = false});

  /// Government ID, Proof of Address, Home Photos.
  static const kDocumentCount = 3;

  /// How many of the [kDocumentCount] documents have at least one file.
  static int providedCount(Map uploads) => [
        _urlsFor(uploads['governmentId']),
        _urlsFor(uploads['proofOfAddress']),
        _urlsFor(uploads['homePhotos']),
      ].where((urls) => urls.isNotEmpty).length;

  static bool _looksLikeUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

  /// Accepts every shape a value under `uploads.*` has actually been
  /// written as: null, a single URL string, a list of URL strings, or (for
  /// older/legacy entries) a list of maps carrying the URL under a
  /// url/downloadUrl/imageUrl key. Never crashes on an unexpected shape —
  /// anything that isn't recognizably a URL is silently dropped rather than
  /// shown broken.
  static List<String> _urlsFor(dynamic value) {
    if (value == null) return const [];
    if (value is String) return _looksLikeUrl(value) ? [value] : const [];
    if (value is List) {
      final urls = <String>[];
      for (final item in value) {
        if (item is String && _looksLikeUrl(item)) {
          urls.add(item);
        } else if (item is Map) {
          final url = item['url'] ?? item['downloadUrl'] ?? item['imageUrl'];
          if (url is String && _looksLikeUrl(url)) urls.add(url);
        }
      }
      return urls;
    }
    if (value is Map) {
      final url = value['url'] ?? value['downloadUrl'] ?? value['imageUrl'];
      return (url is String && _looksLikeUrl(url)) ? [url] : const [];
    }
    return const [];
  }

  @override
  State<_DocumentsSection> createState() => _DocumentsSectionState();
}

class _DocumentsSectionState extends State<_DocumentsSection> {
  late bool expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final uploads = (widget.app.raw['uploads'] as Map?) ?? const {};
    final governmentId = _DocumentsSection._urlsFor(uploads['governmentId']);
    final proofOfAddress = _DocumentsSection._urlsFor(uploads['proofOfAddress']);
    // Never read from anything but uploads.homePhotos — never
    // applicationDocuments, treatmentMedia, receipts, or the Animal
    // Record's own images.
    final homePhotos = _DocumentsSection._urlsFor(uploads['homePhotos']);

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleHeader(
            title: 'Required Documents',
            fontSize: 14,
            expanded: expanded,
            onToggle: () => setState(() => expanded = !expanded),
          ),
          if (!expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('${_DocumentsSection.providedCount(uploads)} of ${_DocumentsSection.kDocumentCount} provided',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ),
          if (expanded) ...[
            const SizedBox(height: 8),
            _DocumentRow(label: 'Government ID', urls: governmentId),
            _DocumentRow(label: 'Proof of Address', urls: proofOfAddress),
            const SizedBox(height: 4),
            Text('Home Photos${homePhotos.length > 1 ? ' (${homePhotos.length})' : ''}',
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if (homePhotos.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(kNotProvided, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PhotoThumbnailStrip(photoUrls: homePhotos),
              ),
          ],
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  final String label;
  final List<String> urls;
  const _DocumentRow({required this.label, required this.urls});

  void _openGallery(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: AppColors.background,
        child: SizedBox(
          height: 420,
          child: PageView(
            children: [
              for (final url in urls)
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                        errorBuilder: (_, _, _) => const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [Icon(Icons.broken_image_outlined, size: 40), Text('Could not load this file.')],
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(url, maxLines: 1, style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text('$label${urls.length > 1 ? ' (${urls.length})' : ''}',
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          if (urls.isEmpty)
            Text(kNotProvided, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
          else ...[
            TextButton(onPressed: () => _openGallery(context), child: const Text('View')),
            IconButton(
              icon: const Icon(Icons.download_outlined, size: 18),
              tooltip: 'Open file URL to download',
              onPressed: () => showInfoDialog(context, title: 'Download', content: SelectableText(urls.join('\n'))),
            ),
          ],
        ],
      ),
    );
  }
}

// ---- Appointment ------------------------------------------------------

class _AppointmentSection extends StatelessWidget {
  final AdoptionApplication app;
  final bool busy;
  final VoidCallback onCompleteInterview;
  final VoidCallback onReschedule;
  final VoidCallback onNoShow;
  const _AppointmentSection({
    required this.app,
    required this.busy,
    required this.onCompleteInterview,
    required this.onReschedule,
    required this.onNoShow,
  });

  ButtonStyle _yellowButton({bool enabled = true}) => ElevatedButton.styleFrom(
        backgroundColor: enabled ? AppColors.yellowrspwn : AppColors.slaterspwn,
        foregroundColor: AppColors.textPrimary,
        disabledBackgroundColor: AppColors.slaterspwn,
        disabledForegroundColor: AppColors.textSecondary,
      );

  @override
  Widget build(BuildContext context) {
    final hasAppointment = app.appointmentDate != null;

    return SectionCard(
      title: 'Appointment Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: _InfoItem('Date', _fmtDate(app.appointmentDate))),
            Expanded(child: _InfoItem('Time', app.appointmentTime ?? kNotProvided)),
          ]),
          Row(children: [
            Expanded(child: _InfoItem('Type', app.appointmentType ?? kNotProvided)),
            Expanded(
              child: _InfoItem(
                  'Status',
                  app.interviewCompletedAt != null
                      ? 'Completed'
                      : (app.noShowAt != null
                          ? 'No-show'
                          : (hasAppointment ? 'Scheduled' : 'Not scheduled'))),
            ),
          ]),
          if (app.interviewCompletedAt != null)
            _InfoItem('Interview Completed', '${_fmtDateTime(app.interviewCompletedAt)}${app.interviewCompletedBy != null ? ' · ${app.interviewCompletedBy}' : ''}'),
          if (app.noShowAt != null) _InfoItem('No-show recorded', _fmtDateTime(app.noShowAt)),
          if (app.noShowCount > 0)
            _InfoItem('Missed interviews', '${app.noShowCount} of $kMaxInterviewNoShows allowed'
                '${app.noShowAt == null && app.lastNoShowAt != null ? ' · last ${_fmtDateTime(app.lastNoShowAt)}' : ''}'),
          // Zoom interview spec — only shown for an Online interview that
          // actually has a meeting on file; the host start URL is
          // deliberately never available here (server-side only).
          if (app.appointmentType == 'Online') ...[
            if (app.hasActiveZoomMeeting)
              _InfoItem('Zoom Meeting', app.zoom?['zoomJoinUrl'] as String? ?? kNotProvided)
            else if (app.zoom != null && app.zoom?['zoomMeetingStatus'] == 'cancelled')
              _InfoItem('Zoom Meeting', 'Cancelled')
            else
              _InfoItem('Zoom Meeting', 'Not yet created — reschedule to retry'),
          ],
          const SizedBox(height: 8),
          // Once adopted (release completed), the interview loop is over —
          // Complete/Reschedule/No-show no longer make sense and are
          // removed from the active action area entirely, not just
          // disabled. The Date/Time/Type/Status fields above stay visible
          // as read-only history. There is no separate "Confirm Interview"
          // step anymore — booking the appointment itself is what makes
          // these actions available (see adoption_process.dart's
          // _saveAppointment), and Complete Interview no longer waits for
          // the scheduled time to actually arrive.
          if (hasAppointment &&
              app.status != AdoptionStatus.rejected &&
              app.status != AdoptionStatus.withdrawn &&
              app.status != AdoptionStatus.adopted)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // Completing waits until staff confirmed the interview
                // (Pending → Interview via Confirm Interview).
                if (app.status == AdoptionStatus.interview && app.interviewCompletedAt == null && app.noShowAt == null)
                  ElevatedButton(
                    onPressed: busy ? null : onCompleteInterview,
                    style: _yellowButton(),
                    child: const Text('Complete Interview'),
                  ),
                ElevatedButton(
                  onPressed: busy ? null : onReschedule,
                  style: _yellowButton(),
                  child: const Text('Reschedule'),
                ),
                if (app.interviewCompletedAt == null &&
                    app.noShowAt == null &&
                    (app.status == AdoptionStatus.pending || app.status == AdoptionStatus.interview))
                  OutlinedButton(
                    onPressed: busy ? null : onNoShow,
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
                    child: const Text('Mark No-show'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

// ---- Notes ------------------------------------------------------------

class _NotesSection extends ConsumerWidget {
  final AdoptionApplication app;
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;
  const _NotesSection({required this.app, required this.controller, required this.busy, required this.onSave});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(adoptionNotesProvider(app.id));
    final notes = notesAsync.asData?.value ?? const <Map<String, dynamic>>[];
    // Once adopted, historical notes stay visible but read-only — adding
    // new interview notes no longer makes sense once the interview loop
    // is over.
    final canEditNotes = app.status != AdoptionStatus.adopted;

    return SectionCard(
      title: 'Interview Notes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canEditNotes) ...[
            Text('Private to your organization — never shown to the applicant.',
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'General observations, home/environment concerns, pet-care knowledge, '
                    'financial preparedness, compatibility, follow-up concerns, recommendation…',
                isDense: true,
              ),
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: busy ? null : onSave,
                style: AppButtons.primary,
                child: const Text('Save Note'),
              ),
            ),
          ] else if (notes.isEmpty)
            Text('No interview notes were recorded.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          if (notes.isNotEmpty) ...[
            const Divider(height: 20),
            Text('History', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            for (final n in notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n['text'] as String? ?? '', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                    Text('${n['createdBy'] ?? 'Admin'} · ${n['createdAt'] is Timestamp ? _fmtDateTime((n['createdAt'] as Timestamp).toDate()) : ''}',
                        style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ---- Actions ------------------------------------------------------------

class _ActionsSection extends ConsumerWidget {
  final AdoptionApplication app;
  final bool busy;
  final VoidCallback onConfirmInterview;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onReserve;
  final VoidCallback onUnreserve;
  final VoidCallback onRelease;

  /// An independent rescuer: the interview is optional, so a pending
  /// application can be accepted straight away.
  final bool interviewOptional;
  const _ActionsSection({
    required this.app,
    required this.busy,
    required this.onConfirmInterview,
    required this.onAccept,
    required this.onReject,
    required this.onReserve,
    required this.onUnreserve,
    required this.onRelease,
    this.interviewOptional = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (app.status) {
      case AdoptionStatus.rejected:
        return _ClosedBanner(
          title: 'Application Rejected',
          subtitle: 'Reasons: ${app.rejectionReasons.isEmpty ? kNotProvided : app.rejectionReasons.join(', ')}'
              '${app.rejectionNotes != null ? '\nNotes: ${app.rejectionNotes}' : ''}',
        );
      case AdoptionStatus.withdrawn:
        return _ClosedBanner(
          title: 'Application withdrawn by applicant',
          subtitle: 'Reason: ${app.withdrawalReason ?? kNotProvided}',
        );
      case AdoptionStatus.adopted:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostAdoptionDetailsPage(applicationId: app.id))),
            style: AppButtons.primary,
            child: Text('View Post-Adoption', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          ),
        );
      case AdoptionStatus.approved:
        // app.animalId is the legacy join key, never a real doc id.
        final approvedAnimalRecordId = app.animalRecordId;
        final animal =
            approvedAnimalRecordId == null ? null : ref.watch(animalRecordProvider(approvedAnimalRecordId)).asData?.value;
        final isReservedForThis = animal?.reservedApplicationId == app.id;
        return Column(
          children: [
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: busy ? null : (isReservedForThis ? onUnreserve : onReserve),
                style: AppButtons.outline,
                child: Text(isReservedForThis ? 'Unreserve Animal' : 'Reserve Animal',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: busy ? null : onRelease,
                style: AppButtons.primary,
                child: Text('Release Animal', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        );
      case AdoptionStatus.pending:
        // Pending → Interview: staff confirm the slot the applicant booked.
        final booked = app.appointmentDate != null;
        final row = _decisionRow(
          hint: booked
              ? null
              : interviewOptional
                  ? 'The interview is optional for rescue volunteers. Accept now, or wait for the applicant to book one.'
                  : 'Waiting for the applicant to book an interview.',
          primaryLabel: 'Confirm Interview',
          onPrimary: (busy || !booked) ? null : onConfirmInterview,
        );
        if (!interviewOptional) return row;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row,
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy ? null : onAccept,
              style: AppButtons.outline,
              child: const Text('Accept Without Interview'),
            ),
          ],
        );
      case AdoptionStatus.interview:
        final canAccept = app.interviewCompletedAt != null;
        return _decisionRow(
          hint: canAccept ? null : 'Accept becomes available once the interview is completed.',
          primaryLabel: 'Accept',
          onPrimary: (busy || !canAccept) ? null : onAccept,
        );
    }
  }

  /// Reject on the left, the phase's forward action on the right.
  Widget _decisionRow({required String? hint, required String primaryLabel, required VoidCallback? onPrimary}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hint != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(hint, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : onReject,
                style: AppButtons.dangerOutline,
                child: const Text('Reject'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: onPrimary,
                style: AppButtons.primary,
                child: Text(primaryLabel),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ClosedBanner extends StatelessWidget {
  final String title;
  final String subtitle;
  const _ClosedBanner({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.slaterspwn.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}
