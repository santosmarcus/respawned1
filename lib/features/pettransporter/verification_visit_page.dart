import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/repos/rescue_case/case_verification_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/live_capture.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';

CaseVerificationRepository _repository() =>
    CaseVerificationRepository(RescueCaseStore(FirebaseFirestore.instance));

/// Location checks an organization asked this rider to do: go to a reported
/// location and say whether the animal is there. Shown on the rider's home
/// screen whether they are online or not, because staff assigned it to them
/// by name. Nothing is drawn when there are none.
class VerificationVisitsBanner extends StatelessWidget {
  const VerificationVisitsBanner({super.key, required this.riderUid});

  final String riderUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<RescueCase>>(
      stream: _repository().streamVerificationVisits(riderUid),
      builder: (context, snap) {
        final visits = snap.data ?? const <RescueCase>[];
        if (visits.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              for (final c in visits)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: AppColors.lavenderrspwn.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => VerificationVisitPage(caseId: c.id)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.travel_explore, color: AppColors.textPrimary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Check a location: ${c.speciesSummary}',
                                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    c.address ?? 'Open to see the location',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The rider's visit: where to go, what was reported, and the form for what
/// they found. The photo is taken with the camera on the spot and sent with
/// the phone's location.
class VerificationVisitPage extends StatefulWidget {
  const VerificationVisitPage({super.key, required this.caseId});

  final String caseId;

  @override
  State<VerificationVisitPage> createState() => _VerificationVisitPageState();
}

class _VerificationVisitPageState extends State<VerificationVisitPage> {
  final _selected = <RiderOutcome>[];
  final _unused = TextEditingController();
  final _note = TextEditingController();
  final _photos = <PickedMedia>[];
  bool _sending = false;

  @override
  void dispose() {
    _unused.dispose();
    _note.dispose();
    super.dispose();
  }

  RiderOutcome? get _outcome => _selected.isEmpty ? null : _selected.first;

  /// "Found" needs a photo of the animal; "not found" needs a note or a
  /// photo of the empty spot.
  bool get _canSend {
    final outcome = _outcome;
    if (outcome == null || _sending) return false;
    if (outcome == RiderOutcome.found) return _photos.isNotEmpty;
    return _photos.isNotEmpty || _note.text.trim().isNotEmpty;
  }

  Future<void> _addPhoto() async {
    final picked = await captureWithCamera(context, title: 'Photo from the location');
    if (picked != null && mounted) setState(() => _photos.add(picked));
  }

  Future<void> _openMaps(RescueCase c) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${c.lat},${c.lng}');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) showAppError(context, 'Could not open Maps.');
  }

  Future<void> _send() async {
    final outcome = _outcome;
    final user = FirebaseAuth.instance.currentUser;
    if (outcome == null || user == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _sending = true);
    try {
      final position = await currentPositionOrNull();
      final profile = (await FirebaseFirestore.instance.collection('users').doc(user.uid).get()).data();
      final name = '${profile?['firstName'] ?? ''} ${profile?['lastName'] ?? ''}'.trim();
      final media = await uploadAllMedia(
        _photos,
        folder: 'cases/${widget.caseId}',
        prefix: 'verify_${DateTime.now().millisecondsSinceEpoch}',
      );
      final note = _note.text.trim();
      await _repository().recordRiderOutcome(
        caseId: widget.caseId,
        outcome: outcome,
        note: note.isEmpty ? null : note,
        media: media,
        lat: position?.latitude,
        lng: position?.longitude,
        actorUid: user.uid,
        actorName: name.isEmpty ? 'Rider' : name,
      );
      messenger.showSnackBar(appSnackBar('Result sent to the organization.', kind: AppMessageKind.success));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(appSnackBar('Could not send the result: $e', kind: AppMessageKind.error));
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Check a location', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('cases').doc(widget.caseId).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: AppErrorBanner('Could not load this visit. Check your connection and reopen it.'),
            ));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final c = RescueCase.fromFirestore(snap.data!);
          final verification = CaseVerification.fromMap(c.raw['verification']);
          final open = c.status == RescueStatus.verifying && (verification?.awaitingRider ?? false);
          final text = GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary);
          final media = [
            for (final url in c.photoUrls) MediaRef(url),
            for (final url in c.videoUrls) MediaRef(url, isVideo: true),
          ];
          final access = (c.raw['accessInstructions'] as String?)?.trim() ?? '';

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(c.speciesSummary, style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
              Text('Case ${c.shortCaseId}', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 10),
              Text(
                'The organization has not accepted this report yet. Go to the location and tell them '
                'whether the animal is there. You are not picking it up on this visit.',
                style: text,
              ),
              const SizedBox(height: 14),
              Text('Where', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              Text(c.address ?? 'No address given', style: text),
              if (access.isNotEmpty) Text('Access: $access', style: text),
              if (c.lat != null && c.lng != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _openMaps(c),
                  style: AppButtons.outline,
                  icon: const Icon(Icons.directions, size: 18),
                  label: const Text('Directions'),
                ),
              ],
              const SizedBox(height: 14),
              Text('What was reported', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
              Text((c.condition ?? '').isEmpty ? 'No description.' : c.condition!, style: text),
              if (media.isNotEmpty) ...[
                const SizedBox(height: 8),
                MediaThumbStrip(media: media, size: 72),
              ],
              const Divider(height: 32, color: AppColors.slaterspwn),
              if (!open)
                Text(
                  verification?.riderOutcome != null
                      ? 'Result already recorded: ${verification!.riderOutcome!.label}.'
                      : 'This visit is no longer needed.',
                  style: text,
                )
              else ...[
                Text('What did you find?', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                ReasonChoiceList<RiderOutcome>(
                  options: [for (final o in RiderOutcome.values) ReasonOption(o, '${o.label}: ${o.help}')],
                  selected: _selected,
                  otherController: _unused,
                  onChanged: (values) => setState(() => _selected
                    ..clear()
                    ..addAll(values)),
                ),
                const SizedBox(height: 8),
                ReasonTextField(
                  controller: _note,
                  label: _outcome == RiderOutcome.notFound ? 'What you saw (or add a photo)' : 'Note (optional)',
                  hint: 'e.g. neighbours say it left this morning',
                  maxLines: 3,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (var i = 0; i < _photos.length; i++)
                      InputChip(
                        avatar: Icon(_photos[i].isVideo ? Icons.videocam_outlined : Icons.photo_outlined, size: 18),
                        label: Text(_photos[i].isVideo ? 'Video ${i + 1}' : 'Photo ${i + 1}'),
                        onDeleted: _sending ? null : () => setState(() => _photos.removeAt(i)),
                      ),
                    if (_photos.length < 3)
                      OutlinedButton.icon(
                        onPressed: _sending ? null : _addPhoto,
                        style: AppButtons.outline,
                        icon: const Icon(Icons.photo_camera_outlined, size: 18),
                        label: Text(_photos.isEmpty
                            ? (_outcome == RiderOutcome.notFound ? 'Photo of the spot' : 'Photo of the animal')
                            : 'Add another'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Photos are taken with the camera here, and your location is sent with the result.',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _canSend ? _send : null,
                    style: AppButtons.primary,
                    child: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Send result'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
