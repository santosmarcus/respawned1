import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/adoption_fit_assessment.dart';
import 'package:respawnd1/core/models/adoption/adoption_response_sections.dart';
import 'package:respawnd1/core/services/adoption_fit_assessment_service.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/core/widgets/photo_thumbnail_strip.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/adoption/widgets/adoption_rejection_sheet.dart';
import 'package:respawnd1/features/admin/adoption/widgets/interview_reschedule_sheet.dart';
import 'package:respawnd1/features/admin/adoption/post_adoption_details_page.dart';
import 'package:respawnd1/features/admin/adoption/release_details_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

String _fmtDate(DateTime? d) => d == null ? kNotProvided : '${d.month}/${d.day}/${d.year}';
String _fmtDateTime(DateTime? d) =>
    d == null ? kNotProvided : '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class AdoptionApplicationDetailPage extends ConsumerStatefulWidget {
  final String applicationId;
  const AdoptionApplicationDetailPage({super.key, required this.applicationId});

  @override
  ConsumerState<AdoptionApplicationDetailPage> createState() => _AdoptionApplicationDetailPageState();
}

class _AdoptionApplicationDetailPageState extends ConsumerState<AdoptionApplicationDetailPage> {
  bool _responsesExpanded = false;
  bool _historyExpanded = false;
  bool _fitAssessmentExpanded = false;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.redAccent));
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
  }

  Future<void> _saveNote(AdoptionApplication app) async {
    final text = _noteController.text.trim();
    if (text.isEmpty) return;
    await _run(() => ref
        .read(adoptionApplicationRepositoryProvider)
        .addNote(applicationId: app.id, text: text, actorUid: _actorUid, actorName: _actorName));
    _noteController.clear();
  }

  Future<void> _accept(AdoptionApplication app) async {
    final confirmed =
        await showConfirmActionDialog(context, title: 'Accept Application?', message: 'This moves the application to Approved.', confirmLabel: 'Accept');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).accept(applicationId: app.id, actorUid: _actorUid, actorName: _actorName));
  }

  Future<void> _reject(AdoptionApplication app) async {
    final result = await showAdoptionRejectionSheet(context);
    if (result == null) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).reject(
          applicationId: app.id,
          reasons: result.reasons,
          notes: result.notes,
          actorUid: _actorUid,
          actorName: _actorName,
        ));
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("This application predates linked animal records and can't be reserved automatically."),
          backgroundColor: Colors.redAccent));
      return;
    }
    final confirmed = await showConfirmActionDialog(context,
        title: 'Reserve ${app.animalName}?',
        message: 'This reserves the animal for ${app.adopterName} and prevents other reservations while it stays reserved.',
        confirmLabel: 'Reserve');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).reserve(applicationId: app.id, animalId: animalRecordId));
  }

  Future<void> _unreserve(AdoptionApplication app) async {
    final animalRecordId = app.animalRecordId;
    if (animalRecordId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("This application predates linked animal records and can't be unreserved automatically."),
          backgroundColor: Colors.redAccent));
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AnimalHeaderCard(app: app),
                  const SizedBox(height: 16),

                  _SectionCard(title: 'Details', child: Column(
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
                  _FitAssessmentCard(
                    app: app,
                    expanded: _fitAssessmentExpanded,
                    onToggle: () => setState(() => _fitAssessmentExpanded = !_fitAssessmentExpanded),
                  ),

                  const SizedBox(height: 12),
                  _ApplicantHistorySection(
                    app: app,
                    expanded: _historyExpanded,
                    onToggle: () => setState(() => _historyExpanded = !_historyExpanded),
                  ),

                  const SizedBox(height: 12),
                  _ResponsesSection(
                    app: app,
                    expanded: _responsesExpanded,
                    onToggle: () => setState(() => _responsesExpanded = !_responsesExpanded),
                  ),

                  const SizedBox(height: 12),
                  _DocumentsSection(app: app),

                  const SizedBox(height: 12),
                  _AppointmentSection(
                    app: app,
                    busy: _busy,
                    onCompleteInterview: () => _completeInterview(app),
                    onReschedule: () => _reschedule(app),
                  ),

                  const SizedBox(height: 12),
                  _AdoptionFeeCard(app: app),

                  const SizedBox(height: 12),
                  _NotesSection(app: app, controller: _noteController, busy: _busy, onSave: () => _saveNote(app)),

                  const SizedBox(height: 20),
                  _ActionsSection(
                    app: app,
                    busy: _busy,
                    onAccept: () => _accept(app),
                    onReject: () => _reject(app),
                    onReserve: () => _reserve(app),
                    onUnreserve: () => _unreserve(app),
                    onRelease: () => _release(app),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
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
                ? Image.network(photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _ph())
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

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  const _SectionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
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

class _FitAssessmentCard extends ConsumerWidget {
  final AdoptionApplication app;
  final bool expanded;
  final VoidCallback onToggle;
  const _FitAssessmentCard({required this.app, required this.expanded, required this.onToggle});

  Color _bandColor(FitAssessmentBand band) => switch (band) {
        FitAssessmentBand.strong => AppColors.greenrspwn,
        FitAssessmentBand.moderate => AppColors.yellowrspwn,
        FitAssessmentBand.needsReview => const Color(0xFFE0A353),
        FitAssessmentBand.significantConcerns => const Color(0xFFE05353),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // app.animalId is the legacy join key, never a real doc id.
    final animalRecordId = app.animalRecordId;
    final animal = animalRecordId == null ? null : ref.watch(animalRecordProvider(animalRecordId)).asData?.value;
    final assessment = animal == null ? null : calculateFitAssessment(application: app, animal: animal);

    return _SectionCard(
      title: 'Fit Assessment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            Text('Concerns to discuss', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFE05353))),
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

// ---- Responses (collapsible) --------------------------------------------

class _ResponsesSection extends StatelessWidget {
  final AdoptionApplication app;
  final bool expanded;
  final VoidCallback onToggle;
  const _ResponsesSection({required this.app, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final sections = buildAdoptionResponseSections(app.raw);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Responses', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
              ],
            ),
          ),
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

class _ApplicantHistorySection extends ConsumerWidget {
  final AdoptionApplication app;
  final bool expanded;
  final VoidCallback onToggle;
  const _ApplicantHistorySection({required this.app, required this.expanded, required this.onToggle});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
          InkWell(
            onTap: onToggle,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Application History', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
              ],
            ),
          ),
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

class _DocumentsSection extends StatelessWidget {
  final AdoptionApplication app;
  const _DocumentsSection({required this.app});

  bool _looksLikeUrl(String v) => v.startsWith('http://') || v.startsWith('https://');

  /// Accepts every shape a value under `uploads.*` has actually been
  /// written as: null, a single URL string, a list of URL strings, or (for
  /// older/legacy entries) a list of maps carrying the URL under a
  /// url/downloadUrl/imageUrl key. Never crashes on an unexpected shape —
  /// anything that isn't recognizably a URL is silently dropped rather than
  /// shown broken.
  List<String> _urlsFor(dynamic value) {
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
  Widget build(BuildContext context) {
    final uploads = (app.raw['uploads'] as Map?) ?? const {};
    final governmentId = _urlsFor(uploads['governmentId']);
    final proofOfAddress = _urlsFor(uploads['proofOfAddress']);
    // Never read from anything but uploads.homePhotos — never
    // applicationDocuments, treatmentMedia, receipts, or the Animal
    // Record's own images.
    final homePhotos = _urlsFor(uploads['homePhotos']);

    return _SectionCard(
      title: 'Required Documents',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                        errorBuilder: (_, __, ___) => const Center(
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
              onPressed: () => showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Download'),
                  content: SelectableText(urls.join('\n')),
                  actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
                ),
              ),
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
  const _AppointmentSection({
    required this.app,
    required this.busy,
    required this.onCompleteInterview,
    required this.onReschedule,
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

    return _SectionCard(
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
                if (app.interviewCompletedAt == null && app.noShowAt == null)
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
              ],
            ),
        ],
      ),
    );
  }
}

// ---- Adoption fee -------------------------------------------------------

class _AdoptionFeeCard extends StatelessWidget {
  final AdoptionApplication app;
  const _AdoptionFeeCard({required this.app});

  @override
  Widget build(BuildContext context) {
    final hasPaymentRecord = app.raw['payment'] != null;
    return _SectionCard(
      title: 'Adoption Fee',
      child: !hasPaymentRecord
          ? Text('Payment tracking is not configured yet.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
          : Row(
              children: [
                Text(app.feeStatus.label, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (app.paymentAmount != null) ...[
                  const SizedBox(width: 6),
                  Text('· ${formatPeso(app.paymentAmount!)}', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                ],
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

    return _SectionCard(
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
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
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
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onReserve;
  final VoidCallback onUnreserve;
  final VoidCallback onRelease;
  const _ActionsSection({
    required this.app,
    required this.busy,
    required this.onAccept,
    required this.onReject,
    required this.onReserve,
    required this.onUnreserve,
    required this.onRelease,
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
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
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
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.textPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text(isReservedForThis ? 'Unreserve Animal' : 'Reserve Animal',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: busy ? null : onRelease,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: Text('Release Animal', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        );
      case AdoptionStatus.pending:
      case AdoptionStatus.interview:
        final canAccept = app.status == AdoptionStatus.interview && app.interviewCompletedAt != null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!canAccept)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Accept becomes available once the interview is completed.',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
              ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : onReject,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE05353)),
                      foregroundColor: const Color(0xFFE05353),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: (busy || !canAccept) ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      disabledBackgroundColor: AppColors.slaterspwn,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        );
    }
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
