import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/adoption_response_sections.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/adoption/widgets/adoption_rejection_sheet.dart';
import 'package:respawnd1/features/admin/animals/animal_record_detail_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

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

  Future<void> _markNoShow(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Mark as No-show?',
        message: 'This records that the applicant did not attend. It does not reject the application automatically.',
        confirmLabel: 'Mark No-show');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).markNoShow(applicationId: app.id, actorName: _actorName));
  }

  void _showReschedulePlaceholder() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reschedule', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
          'Rescheduling is not available yet.\n\n'
          'TODO: admin-proposed schedules, applicant confirmation, notifications, and previous-schedule history.',
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _setFitAssessment(AdoptionApplication app, FitAssessmentValue value) async {
    await _run(() =>
        ref.read(adoptionApplicationRepositoryProvider).setManualFitAssessment(applicationId: app.id, value: value, actorName: _actorName));
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

  Future<void> _reserve(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Reserve ${app.animalName}?',
        message: 'This reserves the animal for ${app.adopterName} and prevents other reservations while it stays reserved.',
        confirmLabel: 'Reserve');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).reserve(applicationId: app.id, animalId: app.animalId));
  }

  Future<void> _unreserve(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Unreserve ${app.animalName}?',
        message: 'This clears the reservation and returns the animal to the adoptable list. The application stays Approved.',
        confirmLabel: 'Unreserve');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).unreserve(applicationId: app.id, animalId: app.animalId));
  }

  Future<void> _release(AdoptionApplication app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Release ${app.animalName}?', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Animal: ${app.animalName}', style: GoogleFonts.zain(fontSize: 13)),
            Text('Adopter: ${app.adopterName}', style: GoogleFonts.zain(fontSize: 13)),
            Text('Application: #${app.id.substring(0, app.id.length > 6 ? 6 : app.id.length)}', style: GoogleFonts.zain(fontSize: 13)),
            Text('Reservation: ${app.reservedAt != null ? 'Reserved' : 'Not reserved'}', style: GoogleFonts.zain(fontSize: 13)),
            Text('Adoption fee: ${app.feeStatus.label}', style: GoogleFonts.zain(fontSize: 13)),
            Text('Release date: ${_fmtDate(DateTime.now())}', style: GoogleFonts.zain(fontSize: 13)),
            const SizedBox(height: 8),
            Text('This finalizes the adoption — the animal is removed from public adoptable listings.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
            child: const Text('Confirm Release'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).release(applicationId: app.id, animalId: app.animalId, actorName: _actorName));
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
                  _FitAssessmentCard(app: app, onSelect: (v) => _setFitAssessment(app, v)),

                  const SizedBox(height: 12),
                  _ResponsesSection(
                    app: app,
                    expanded: _responsesExpanded,
                    onToggle: () => setState(() => _responsesExpanded = !_responsesExpanded),
                  ),

                  const SizedBox(height: 12),
                  _ApplicantHistorySection(
                    app: app,
                    expanded: _historyExpanded,
                    onToggle: () => setState(() => _historyExpanded = !_historyExpanded),
                  ),

                  const SizedBox(height: 12),
                  _DocumentsSection(app: app),

                  const SizedBox(height: 12),
                  _AppointmentSection(
                    app: app,
                    busy: _busy,
                    onCompleteInterview: () => _completeInterview(app),
                    onNoShow: () => _markNoShow(app),
                    onReschedule: _showReschedulePlaceholder,
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
    final animal = ref.watch(animalRecordProvider(app.animalId)).asData?.value;
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

class _FitAssessmentCard extends StatelessWidget {
  final AdoptionApplication app;
  final ValueChanged<FitAssessmentValue> onSelect;
  const _FitAssessmentCard({required this.app, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Fit Assessment',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Automated fit scoring is not configured yet.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          // TODO(fit-assessment): replace this manual-only selector with a
          // transparent, documented scoring rubric once one is designed —
          // never a hardcoded/implied percentage before that exists.
          const SizedBox(height: 8),
          Text('Manual assessment: ${app.fitAssessment.label}',
              style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (app.fitAssessedBy != null)
            Text('By ${app.fitAssessedBy} · ${_fmtDate(app.fitAssessedAt)}', style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final v in [FitAssessmentValue.goodCandidate, FitAssessmentValue.needsReview, FitAssessmentValue.notRecommended])
                ChoiceChip(
                  label: Text(v.label),
                  selected: app.fitAssessment == v,
                  selectedColor: AppColors.yellowrspwn,
                  onSelected: (_) => onSelect(v),
                ),
            ],
          ),
        ],
      ),
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
                Text('Applicant History', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text('Previous applications: ${all.length}', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          Text('Successful adoptions: $successful', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          Text('Rejected applications: $rejected', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          Text('Withdrawn applications: $withdrawn', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          Text('Active applications: $active', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          if (expanded) ...[
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
      ),
    );
  }
}

// ---- Documents ------------------------------------------------------------

class _DocumentsSection extends StatelessWidget {
  final AdoptionApplication app;
  const _DocumentsSection({required this.app});

  List<String> _urlsFor(dynamic value) {
    if (value == null) return const [];
    if (value is String) return value.isEmpty ? const [] : [value];
    if (value is List) return value.whereType<String>().toList();
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final uploads = (app.raw['uploads'] as Map?) ?? const {};
    final categories = <(String, List<String>)>[
      ('Government ID', _urlsFor(uploads['governmentId'])),
      ('Proof of Address', _urlsFor(uploads['proofOfAddress'])),
      ('Home Photos', _urlsFor(uploads['homePhotos'])),
    ];

    return _SectionCard(
      title: 'Required Documents',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final (label, urls) in categories) _DocumentRow(label: label, urls: urls)],
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
  final VoidCallback onNoShow;
  final VoidCallback onReschedule;
  const _AppointmentSection({
    required this.app,
    required this.busy,
    required this.onCompleteInterview,
    required this.onNoShow,
    required this.onReschedule,
  });

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
            Expanded(child: _InfoItem('Status', app.interviewCompletedAt != null
                ? 'Completed'
                : (app.noShowAt != null ? 'No-show' : (hasAppointment ? 'Scheduled' : 'Not scheduled')))),
          ]),
          if (app.interviewCompletedAt != null)
            _InfoItem('Interview Completed', '${_fmtDateTime(app.interviewCompletedAt)}${app.interviewCompletedBy != null ? ' · ${app.interviewCompletedBy}' : ''}'),
          if (app.noShowAt != null) _InfoItem('No-show recorded', _fmtDateTime(app.noShowAt)),
          const SizedBox(height: 8),
          if (hasAppointment && app.status != AdoptionStatus.rejected && app.status != AdoptionStatus.withdrawn)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (app.interviewCompletedAt == null)
                  OutlinedButton(onPressed: busy ? null : onCompleteInterview, child: const Text('Complete Interview')),
                if (app.interviewCompletedAt == null)
                  OutlinedButton(onPressed: busy ? null : onNoShow, child: const Text('Mark as No-show')),
                OutlinedButton(onPressed: onReschedule, child: const Text('Reschedule')),
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

    return _SectionCard(
      title: 'Interview Notes',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PostAdoptionMonitoringPage(adoptionId: app.id))),
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
        final animal = ref.watch(animalRecordProvider(app.animalId)).asData?.value;
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
