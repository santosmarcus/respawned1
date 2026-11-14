import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/repos/rescue_case/case_verification_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/live_capture.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';

/// Shown to the reporter on Track Case while the rescue team is waiting for
/// a fresh photo or video of the animal. The camera opens directly (no
/// gallery), and the proof is sent with the time and the phone's location.
class LiveProofRequestCard extends StatefulWidget {
  const LiveProofRequestCard({super.key, required this.caseId, required this.data});

  final String caseId;
  final Map<String, dynamic> data;

  @override
  State<LiveProofRequestCard> createState() => _LiveProofRequestCardState();
}

class _LiveProofRequestCardState extends State<LiveProofRequestCard> {
  bool _sending = false;

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await captureWithCamera(context, title: 'Show the animal as it is now');
    if (picked == null || !mounted) return;
    setState(() => _sending = true);
    try {
      final position = await currentPositionOrNull();
      final media = await uploadMedia(
        picked,
        folder: 'cases/${widget.caseId}',
        name: 'proof_${DateTime.now().millisecondsSinceEpoch}',
      );
      await CaseVerificationRepository(RescueCaseStore(FirebaseFirestore.instance)).submitLiveProof(
        caseId: widget.caseId,
        media: [media],
        lat: position?.latitude,
        lng: position?.longitude,
        accuracyM: position?.accuracy,
      );
      messenger.showSnackBar(appSnackBar(
        position == null
            ? 'Sent. Your location was not available, so the team may ask again.'
            : 'Sent to the rescue team. Thank you!',
        kind: AppMessageKind.success,
      ));
    } catch (e) {
      messenger.showSnackBar(appSnackBar('Could not send it: $e', kind: AppMessageKind.error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = CaseVerificationState.fromCase(widget.data);
    final status = RescueStatus.fromFirestoreValue(widget.data['status'] as String?);
    if (!state.proofPending || !CaseVerificationRepository.canVerify(status)) {
      return const SizedBox.shrink();
    }
    final note = state.request?.note;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.yellowrspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera_outlined, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The rescue team needs a new photo',
                  style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Take a photo or short video of the animal where it is right now. '
            'It helps the team confirm your report before sending someone.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
          ),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text('They asked: $note', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _send,
              style: AppButtons.primary,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_camera, size: 18),
              label: Text(_sending ? 'Sending…' : 'Take a photo now'),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Your phone\'s location is sent with it. If you can no longer see the animal, '
            'tell the team in the messages below.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
