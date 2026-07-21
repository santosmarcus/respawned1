import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/adoption/widgets/retrieval_schedule_sheet.dart';
import 'package:respawnd1/features/admin/rescue/intake_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

String _fmtDate(DateTime? d) => d == null ? 'Not set' : '${d.month}/${d.day}/${d.year}';
String _fmtDateTime(DateTime? d) =>
    d == null ? 'Not set' : '${d.month}/${d.day}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// Admin Return Details screen (spec §15-21) — every field shown comes
/// straight from the existing adopter-side AdoptionReturnForm's
/// `returnRequest` map (post_adoption_page.dart) plus the admin-review
/// fields this module adds on top (see core/models/adoption/
/// return_request.dart). Drives the return status flow via
/// AdoptionApplicationRepository's approveReturn/declineReturn/
/// setRetrievalSchedule/confirmAnimalRetrieved/proceedToIntake.
class ReturnDetailsPage extends ConsumerStatefulWidget {
  final String applicationId;
  const ReturnDetailsPage({super.key, required this.applicationId});

  @override
  ConsumerState<ReturnDetailsPage> createState() => _ReturnDetailsPageState();
}

class _ReturnDetailsPageState extends ConsumerState<ReturnDetailsPage> {
  bool _busy = false;

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
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

  Future<void> _approve() async {
    final confirmed = await showConfirmActionDialog(context, title: 'Approve Return?', message: 'You can set the retrieval schedule next.', confirmLabel: 'Approve Return');
    if (!confirmed) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).approveReturn(applicationId: widget.applicationId, actorName: _actorName));
  }

  Future<void> _decline() async {
    final reason = await _promptText(title: 'Decline Return', label: 'Reason (required)', required: true);
    if (reason == null || reason.isEmpty) return;
    await _run(() =>
        ref.read(adoptionApplicationRepositoryProvider).declineReturn(applicationId: widget.applicationId, actorName: _actorName, reason: reason));
  }

  Future<void> _setSchedule(ReturnRequest? existing) async {
    final result = await showRetrievalScheduleSheet(
      context,
      initialDateTime: existing?.retrievalDateTime,
      initialAddress: existing?.retrievalAddress,
      initialNotes: existing?.retrievalNotes,
    );
    if (result == null) return;
    await _run(() => ref.read(adoptionApplicationRepositoryProvider).setRetrievalSchedule(
          applicationId: widget.applicationId,
          dateTime: result.dateTime,
          address: result.address,
          notes: result.notes,
          actorName: _actorName,
        ));
  }

  Future<void> _confirmRetrieved(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Confirm Animal Retrieved?', message: '${app.animalName} will be marked as physically retrieved from the adopter.', confirmLabel: 'Confirm Retrieved');
    if (!confirmed) return;
    await _run(() => ref
        .read(adoptionApplicationRepositoryProvider)
        .confirmAnimalRetrieved(applicationId: widget.applicationId, animalId: app.animalId, actorName: _actorName));
  }

  Future<void> _proceedToIntake(AdoptionApplication app) async {
    final confirmed = await showConfirmActionDialog(context,
        title: 'Proceed to Intake?', message: '${app.animalName} will enter Intake as an Adoption Return using its existing animal record.', confirmLabel: 'Proceed to Intake');
    if (!confirmed) return;

    await _run(() async {
      final uid = _actorUid;
      final membership = uid.isEmpty ? null : await OrgMembershipService().getMembership(uid);
      final orgId = membership?.organizationId;
      final orgRepo = ref.read(organizationDirectoryRepositoryProvider);
      var destination = await orgRepo.resolveShelterLocation(orgId);
      destination ??= await orgRepo.resolveUserShelterLocation(uid);
      if (destination == null || destination.lat == null || destination.lng == null) {
        throw StateError('Set a shelter location for your organization before proceeding to Intake.');
      }

      final caseId = await ref.read(adoptionApplicationRepositoryProvider).proceedToIntake(
            applicationId: widget.applicationId,
            animalId: app.animalId,
            actorUid: uid,
            actorName: _actorName,
            shelterLat: destination.lat!,
            shelterLng: destination.lng!,
            shelterAddress: destination.address,
          );

      final caseSnap = await FirebaseFirestore.instance.collection('cases').doc(caseId).get();
      if (mounted && caseSnap.exists) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => IntakeDetailPage(caseId: caseId, data: caseSnap.data()!)),
        );
      }
    });
  }

  Future<String?> _promptText({required String title, required String label, bool required = false}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final appAsync = ref.watch(adoptionApplicationProvider(widget.applicationId));
    final app = appAsync.asData?.value;
    final r = app?.returnRequest;
    final followUpsAsync = ref.watch(followUpsForAdoptionProvider(widget.applicationId));
    final followUps = followUpsAsync.asData?.value ?? const [];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
        title: Text('Return Details', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: (app == null || r == null)
          ? Center(
              child: Text(app == null ? '' : 'No return request on this adoption.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(app.animalName, style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        _row('Adopter', app.adopterName),
                        _row('Contact', '${app.adopterPhone}  ·  ${app.adopterEmail}'),
                        _row('Adoption Date', _fmtDate(app.releasedAt ?? app.adoptedAt)),
                        _row('Status', r.status.label),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Return Request',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _row('Requested', _fmtDate(r.requestedAt)),
                        _row('Reason', r.reason + (r.reasonOther != null && r.reasonOther!.isNotEmpty ? ' — ${r.reasonOther}' : '')),
                        _row('Desired timeframe', r.urgency),
                        const SizedBox(height: 8),
                        Text('Detailed Explanation', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(r.explanation.isEmpty ? 'Not provided' : r.explanation, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                        if (r.images.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text('Photos (${r.images.length})', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          SizedBox(
                            height: 90,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: r.images.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 8),
                              itemBuilder: (context, i) => ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(r.images[i], width: 90, height: 90, fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(width: 90, height: 90, color: AppColors.tearspwn)),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SectionCard(
                    title: 'Post-Adoption History',
                    child: Text(
                      followUps.isEmpty
                          ? 'No follow-ups were recorded for this adoption.'
                          : '${followUps.where((f) => f.status.name == 'completed').length} of ${followUps.length} follow-ups completed before this return.',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (r.status == ReturnRequestStatus.declined)
                    _closedBanner('Return Declined', 'Reason: ${r.declineReason ?? 'Not provided'}'),
                  if (r.status == ReturnRequestStatus.pendingReview)
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _decline,
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFE05353)), foregroundColor: const Color(0xFFE05353)),
                          child: const Text('Decline'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _busy ? null : _approve,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                          child: const Text('Approve Return'),
                        ),
                      ),
                    ]),
                  if (r.status.isApprovedAwaitingSchedule)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : () => _setSchedule(r),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Set Retrieval Schedule'),
                      ),
                    ),
                  if (r.status == ReturnRequestStatus.retrievalScheduled) ...[
                    SectionCard(
                      title: 'Retrieval Schedule',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _row('When', _fmtDateTime(r.retrievalDateTime)),
                          _row('Address', r.retrievalAddress ?? 'Not set'),
                          if (r.retrievalNotes != null && r.retrievalNotes!.isNotEmpty) _row('Notes', r.retrievalNotes!),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: OutlinedButton(onPressed: _busy ? null : () => _setSchedule(r), child: const Text('Reschedule'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _busy ? null : () => _confirmRetrieved(app),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                          child: const Text('Confirm Animal Retrieved'),
                        ),
                      ),
                    ]),
                  ],
                  if (r.status == ReturnRequestStatus.retrieved)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _busy ? null : () => _proceedToIntake(app),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary, padding: const EdgeInsets.symmetric(vertical: 14)),
                        child: const Text('Proceed to Intake'),
                      ),
                    ),
                  if (r.status == ReturnRequestStatus.intake)
                    _closedBanner('Proceeded to Intake', 'Case #${r.intakeCaseId ?? '—'} · ${_fmtDate(r.proceededToIntakeAt)}'),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
            Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          ],
        ),
      );

  Widget _closedBanner(String title, String subtitle) => Container(
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
