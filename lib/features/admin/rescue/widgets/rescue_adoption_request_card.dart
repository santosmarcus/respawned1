import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_response_sections.dart';
import 'package:respawnd1/core/models/rescue/rescue_adoption.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/adoption/release_details_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

/// Rescue gaps 6/10 on Rescue Details: the adoption request from the
/// interested adopter, the organization's confirmation, the pickup window
/// and what happened when it was missed.
class RescueAdoptionRequestCard extends ConsumerStatefulWidget {
  const RescueAdoptionRequestCard({
    super.key,
    required this.rescueCase,
    required this.actorUid,
    required this.actorName,
    required this.onRefer,
  });

  final RescueCase rescueCase;
  final String actorUid;
  final String actorName;

  /// Opens the existing Refer flow (missed pickup with a full shelter).
  final VoidCallback onRefer;

  @override
  ConsumerState<RescueAdoptionRequestCard> createState() => _RescueAdoptionRequestCardState();
}

class _RescueAdoptionRequestCardState extends ConsumerState<RescueAdoptionRequestCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(done, kind: AppMessageKind.success));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            appSnackBar(e is StateError ? e.message : 'Could not update: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(CaseAdoptionRequest r) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Confirm ${r.adopterName} as the adopter?',
      message: 'They agreed to pay the vet fees, fulfil their obligations as an adopter and collect the animal within '
          '${kAdopterPickupWindow.inHours} hours of being told it is ready. If the transporter has not reached the '
          'clinic yet, their trip will end there and the adopter collects the animal from the clinic.',
      confirmLabel: 'Confirm Adopter',
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await ref.read(adoptionApplicationRepositoryProvider).accept(
        applicationId: r.applicationId,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      // The animal already went to the shelter and has a record: reserve it
      // for the adopter, so the usual Release Details flow finishes the
      // adoption from there.
      final records = await FirebaseFirestore.instance
          .collection('animals')
          .where('linkedCaseId', isEqualTo: widget.rescueCase.id)
          .where('organizationId', isEqualTo: widget.rescueCase.raw['organizationId'])
          .get();
      final available = records.docs.where((d) => !['adopted', 'reserved', 'deceased'].contains(d.data()['adoptionStatus']));
      if (available.isNotEmpty) {
        final animalId = available.first.id;
        await FirebaseFirestore.instance.collection('adoptions').doc(r.applicationId).update({
          'personal.animalRecordId': animalId,
          'personal.animalId': animalId,
        });
        await ref.read(adoptionApplicationRepositoryProvider).reserve(
          applicationId: r.applicationId,
          animalId: animalId,
          actorId: widget.actorUid,
          actorName: widget.actorName,
        );
      }
    }, 'Adopter confirmed. They have been notified.');
  }

  Future<void> _decline(CaseAdoptionRequest r) async {
    final reason = await showTextInputDialog(context,
        title: 'Decline adoption request',
        message: '${r.adopterName} is told the request was not approved.',
        label: 'Reason',
        confirmLabel: 'Decline',
        destructive: true,
        required: true);
    if (reason == null || !mounted) return;
    await _run(
          () => ref.read(adoptionApplicationRepositoryProvider).reject(
        applicationId: r.applicationId,
        reasons: const ['Not approved for this rescue'],
        notes: reason,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      ),
      'Request declined.',
    );
  }

  Future<void> _confirmPickup() async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Confirm pickup',
      message: 'Confirm the adopter collected the animal. You then finish the adoption on Release Details: '
          'print the agreement for signing and set the post-adoption check-ins.',
      confirmLabel: 'Confirm Pickup',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final applicationId = await ref.read(rescueCaseRepositoryProvider).confirmAdopterPickup(
        caseId: widget.rescueCase.id,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ReleaseDetailsPage(applicationId: applicationId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            appSnackBar(e is StateError ? e.message : 'Could not confirm pickup: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.rescueCase.raw;
    final request = CaseAdoptionRequest.fromCase(data);
    final pickup = AdopterPickup.fromCase(data);
    if (request == null && pickup == null) return const SizedBox.shrink();
    final owned = ((data['organizationId'] as String?) ?? '').isNotEmpty;

    Widget line(String text, {Color? color, FontWeight? weight}) => Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(text,
          style: GoogleFonts.zain(fontSize: 13, color: color ?? AppColors.textPrimary, fontWeight: weight)),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SectionCard(
        title: 'Adoption request',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (request != null) ...[
              line('${request.adopterName} · ${request.status.label}', weight: FontWeight.w700),
              if (request.closedReason != null) line(request.closedReason!, color: AppColors.textSecondary),
              _RequestDetails(applicationId: request.applicationId),
              if (request.status == RescueAdoptionStatus.pending) ...[
                if (!owned)
                  line('Accept the case first; the request is confirmed by the organization that owns it.',
                      color: AppColors.textSecondary),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy || !owned ? null : () => _decline(request),
                      style: AppButtons.dangerOutline,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy || !owned ? null : () => _confirm(request),
                      style: AppButtons.primary,
                      child: const Text('Confirm Adopter'),
                    ),
                  ),
                ]),
              ],
              if (request.isConfirmed && pickup == null)
                line('Once the animal is discharged, use Release on Treatment Details to tell the adopter it is ready '
                    'for pickup.', color: AppColors.textSecondary),
            ],
            if (pickup != null) ...[
              const Divider(height: 20),
              if (pickup.isWaiting) ...[
                line('Ready for pickup at ${pickup.place}', weight: FontWeight.w700),
                if (pickup.deadline != null)
                  line(
                    'Collect by ${formatDateTime(pickup.deadline!)}'
                        '${pickup.deadline!.isBefore(DateTime.now()) ? ' (window passed, being moved)' : ''}',
                    color: pickup.deadline!.isBefore(DateTime.now()) ? AppColors.error : AppColors.textSecondary,
                  ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _busy ? null : _confirmPickup,
                    style: AppButtons.primary,
                    child: const Text('Confirm Pickup'),
                  ),
                ),
              ] else if (pickup.collectedAt != null)
                line('Collected on ${formatDateTime(pickup.collectedAt!)}.', weight: FontWeight.w700)
              else if (pickup.missedAt != null) ...[
                  line(
                    pickup.missedOutcome == 'refer'
                        ? 'Not collected in time and the shelter is full: refer this animal to another organization.'
                        : 'Not collected in time: the animal goes to the shelter. Continue on Intake Details.',
                    color: AppColors.error,
                    weight: FontWeight.w700,
                  ),
                  if (pickup.missedOutcome == 'refer' && data['status'] != 'referred') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(onPressed: widget.onRefer, style: AppButtons.outline, child: const Text('Refer')),
                    ),
                  ],
                ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The adopter's answers and accepted agreements.
class _RequestDetails extends StatelessWidget {
  const _RequestDetails({required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('adoptions').doc(applicationId).snapshots(),
      builder: (context, snap) {
        final d = snap.data?.data();
        if (d == null) return const SizedBox.shrink();
        final personal = (d['personal'] as Map?) ?? const {};
        final answers = (d['rescueApplication'] as Map?) ?? const {};
        final agreement = (d['agreement'] as Map?) ?? const {};
        // Pet Experience and Lifestyle & Care, read the same way as on
        // Adoption Details. Requests sent before these were asked have none.
        const added = {'Pet Experience', 'Lifestyle & Care'};
        final sections = d['petExperience'] is Map
            ? buildAdoptionResponseSections(d).where((s) => added.contains(s.title)).toList()
            : const <ResponseSection>[];
        final governmentId = ((d['uploads'] as Map?) ?? const {})['governmentId'] as String?;
        Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text(t, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w800)),
        );
        Widget row(String k, Object? v) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
                width: 120,
                child: Text(k, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
            Expanded(
                child: Text('${v ?? '-'}', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary))),
          ]),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            row('Phone', personal['adopterPhone']),
            row('Email', personal['adopterEmail']),
            row('Address', answers['address']),
            row('Home', answers['homeType']),
            if (answers['homeType'] == 'Renting') row('Landlord allows pets', answers['landlordAllowsPets'] == true ? 'Yes' : 'No'),
            row('Other pets', answers['otherPets']),
            row('Main caretaker', answers['caretaker']),
            for (final s in sections) ...[
              heading(s.title),
              for (final item in s.items) row(item.label, item.answer),
            ],
            if (governmentId != null && governmentId.isNotEmpty) ...[
              heading('Government ID'),
              GestureDetector(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(governmentId))),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(governmentId,
                      width: 120,
                      height: 90,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.insert_drive_file_outlined)),
                ),
              ),
            ],
            const SizedBox(height: 6),
            // Only the agreements this request was sent with (older
            // requests had three).
            for (final (key, title, _) in kRescueAdoptionAgreements)
              if (agreement.containsKey(key))
                Row(children: [
                  Icon(agreement[key] == true ? Icons.check_circle : Icons.cancel_outlined,
                      size: 16, color: agreement[key] == true ? AppColors.success : AppColors.error),
                  const SizedBox(width: 6),
                  Expanded(child: Text(title, style: GoogleFonts.zain(fontSize: 12))),
                ]),
          ],
        );
      },
    );
  }
}
