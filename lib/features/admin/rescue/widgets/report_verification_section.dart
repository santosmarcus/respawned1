import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/rescue_case/case_verification_repository.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

/// The desk check on Rescue Details: what backs the report up, the live
/// proof asked of the reporter, and the recorded result (confirmed
/// remotely, rider sent, could not confirm, and what the rider found).
///
/// Shown with its actions while the report is in review or being verified;
/// afterwards it stays as a read-only record if anything was recorded.
class ReportVerificationSection extends ConsumerStatefulWidget {
  const ReportVerificationSection({
    super.key,
    required this.rescueCase,
    required this.actorUid,
    required this.actorName,
  });

  final RescueCase rescueCase;
  final String actorUid;
  final String actorName;

  @override
  ConsumerState<ReportVerificationSection> createState() => _ReportVerificationSectionState();
}

class _ReportVerificationSectionState extends ConsumerState<ReportVerificationSection> {
  bool _busy = false;
  Future<ReporterTrackRecord?>? _trackRecord;
  Future<int?>? _nearbyReports;

  RescueCase get _case => widget.rescueCase;
  CaseVerificationRepository get _repo => ref.read(rescueCaseRepositoryProvider).verification;

  @override
  void initState() {
    super.initState();
    if (CaseVerificationRepository.canVerify(_case.status)) _loadChecks();
  }

  /// The two checks that need a query. A failed lookup shows as "could not
  /// check" rather than hiding the rest of the panel.
  void _loadChecks() {
    final c = _case;
    final repo = ref.read(rescueCaseRepositoryProvider);
    final reporterId = c.reporterId;
    _trackRecord = reporterId == null || reporterId.isEmpty
        ? Future.value(null)
        : repo.verification
            .reporterTrackRecord(reporterId, excludeCaseId: c.id)
            .then<ReporterTrackRecord?>((r) => r)
            .catchError((_) => null);
    _nearbyReports = repo
        .findPossibleDuplicates(c)
        .then<int?>((cases) => cases.where((o) => o.reporterId != c.reporterId).length)
        .catchError((_) => null);
  }

  Future<void> _run(Future<void> Function() action, {required String failure, String? success}) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) messenger.showSnackBar(appSnackBar(success, kind: AppMessageKind.success));
    } on StateError catch (e) {
      messenger.showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
    } catch (e) {
      messenger.showSnackBar(appSnackBar('$failure: $e', kind: AppMessageKind.error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestProof() async {
    final note = await showTextInputDialog(
      context,
      title: 'Ask for live proof',
      message: 'The reporter is asked for a photo or short video taken now, in the app. '
          'It arrives here with the time and where their phone was.',
      label: 'Anything specific to show? (optional)',
      hint: 'e.g. the whole animal, the street sign',
      confirmLabel: 'Send request',
    );
    if (note == null || !mounted) return;
    await _run(
      () => _repo.requestLiveProof(
        caseId: _case.id,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
        note: note.isEmpty ? null : note,
      ),
      failure: 'Could not send the request',
      success: 'Request sent to the reporter.',
    );
  }

  Future<void> _recordDeskResult() async {
    final result = await showReasonSheet<_DeskResult>(context, builder: (_) => const _DeskResultSheet());
    if (result == null || !mounted) return;
    await _run(
      () async {
        final organizationId = await ref.read(currentOrganizationIdProvider.future);
        await _repo.recordDeskOutcome(
          caseId: _case.id,
          outcome: result.outcome,
          note: result.note,
          actorUid: widget.actorUid,
          actorName: widget.actorName,
          organizationId: organizationId,
          riderId: result.riderId,
          riderName: result.riderName,
        );
      },
      failure: 'Could not save the result',
      success: result.outcome == DeskOutcome.needsRider ? 'Rider assigned to check the location.' : 'Result saved.',
    );
  }

  Future<void> _recordRiderResult() async {
    final result = await showReasonSheet<_RiderResult>(context, builder: (_) => const _RiderResultSheet());
    if (result == null || !mounted) return;
    await _run(
      () async {
        final media = await uploadAllMedia(
          result.media,
          folder: 'cases/${_case.id}',
          prefix: 'verify_${DateTime.now().millisecondsSinceEpoch}',
        );
        await _repo.recordRiderOutcome(
          caseId: _case.id,
          outcome: result.outcome,
          note: result.note,
          media: media,
          actorUid: widget.actorUid,
          actorName: widget.actorName,
        );
      },
      failure: 'Could not save the rider\'s result',
      success: 'Rider\'s result saved.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _case;
    final state = CaseVerificationState.fromCase(c.raw);
    final active = CaseVerificationRepository.canVerify(c.status);
    if (!active && !state.hasRecord) return const SizedBox.shrink();
    if (active && _trackRecord == null) _loadChecks();

    final verification = state.verification;
    final sightings = ref.watch(caseCommunityReportsProvider(c.id)).asData?.value ?? const [];
    final byOthers = sightings.where((r) => r.reporterId != c.reporterId);
    final seen = byOthers.where((r) => r.type == 'still_here' || r.type == 'moved').length;
    final notThere = byOthers.where((r) => r.type == 'no_animal' || r.type == 'rescued').length;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SectionCard(
        title: 'Report verification',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (verification != null && (verification.deskOutcome != null || verification.riderOutcome != null)) ...[
              _ResultBox(verification: verification, pinLat: c.lat, pinLng: c.lng),
              const SizedBox(height: 10),
            ],
            if (active) ...[
              for (final flag in evidenceFlags(state.evidence, pinLat: c.lat, pinLng: c.lng)) _FlagRow(flag),
              _FutureFlag<ReporterTrackRecord?>(
                future: _trackRecord,
                checking: 'Checking the reporter\'s earlier reports…',
                failed: 'Could not check the reporter\'s earlier reports',
                toFlag: (record) => record?.flag,
              ),
              _FutureFlag<int?>(
                future: _nearbyReports,
                checking: 'Looking for other reports nearby…',
                failed: 'Could not look for other reports nearby',
                toFlag: (nearby) => nearby == null
                    ? null
                    : corroborationFlag(
                        otherReports: nearby + c.mergedCaseIds.length,
                        sightings: seen,
                        notThere: notThere,
                      ),
              ),
            ],
            if (state.request != null || state.proof != null) ...[
              const SizedBox(height: 6),
              _LiveProofBlock(state: state, pinLat: c.lat, pinLng: c.lng),
            ],
            if (active) ...[
              const SizedBox(height: 12),
              if (verification?.awaitingRider ?? false) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _recordRiderResult,
                    style: AppButtons.primary,
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: const Text('Record rider\'s result'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _requestProof,
                      style: AppButtons.outline,
                      child: Text(state.request == null ? 'Ask for live proof' : 'Ask again', textAlign: TextAlign.center),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _recordDeskResult,
                      style: AppButtons.outline,
                      child: Text(
                        verification?.deskOutcome == null ? 'Record result' : 'Change result',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

TextStyle _body({Color color = AppColors.textPrimary, FontWeight? weight}) =>
    GoogleFonts.zain(fontSize: 13, color: color, fontWeight: weight);

TextStyle _small() => GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary);

({IconData icon, Color color}) _look(EvidenceLevel level) => switch (level) {
      EvidenceLevel.supports => (icon: Icons.check_circle, color: AppColors.success),
      EvidenceLevel.caution => (icon: Icons.error_outline, color: AppColors.warning),
      EvidenceLevel.concern => (icon: Icons.warning_amber_rounded, color: AppColors.error),
      EvidenceLevel.unknown => (icon: Icons.help_outline, color: AppColors.textSecondary),
    };

/// One check: an icon that also says how to read it, the finding, and a
/// line of detail.
class _FlagRow extends StatelessWidget {
  const _FlagRow(this.flag);

  final EvidenceFlag flag;

  @override
  Widget build(BuildContext context) {
    final look = _look(flag.level);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(look.icon, size: 18, color: look.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(flag.label, style: _body(weight: FontWeight.w700)),
                if (flag.detail != null) Text(flag.detail!, style: _small()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A check that waits on a lookup.
class _FutureFlag<T> extends StatelessWidget {
  const _FutureFlag({required this.future, required this.checking, required this.failed, required this.toFlag});

  final Future<T>? future;
  final String checking;
  final String failed;

  /// Null means the lookup had nothing to say (or failed).
  final EvidenceFlag? Function(T value) toFlag;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _FlagRow(EvidenceFlag(EvidenceLevel.unknown, checking));
        }
        final flag = snap.hasData ? toFlag(snap.data as T) : null;
        return _FlagRow(flag ?? EvidenceFlag(EvidenceLevel.unknown, failed));
      },
    );
  }
}

/// The request and the reporter's answer.
class _LiveProofBlock extends StatelessWidget {
  const _LiveProofBlock({required this.state, this.pinLat, this.pinLng});

  final CaseVerificationState state;
  final double? pinLat;
  final double? pinLng;

  @override
  Widget build(BuildContext context) {
    final request = state.request;
    final proof = state.proof;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.proofPending)
          _FlagRow(EvidenceFlag(
            EvidenceLevel.unknown,
            'Waiting for the reporter\'s live proof',
            'Asked ${formatDateTimeOr(request?.requestedAt, 'just now')}'
                '${request?.requestedByName == null ? '' : ' by ${request!.requestedByName}'}.',
          )),
        if (proof != null && proof.media.isNotEmpty) ...[
          _FlagRow(proof.flagAgainst(pinLat: pinLat, pinLng: pinLng)),
          MediaThumbStrip(media: proof.media),
          const SizedBox(height: 4),
          Text(
            '${state.proofPending ? 'Earlier proof sent' : 'Sent'} ${formatDateTimeOr(proof.submittedAt, 'just now')}',
            style: _small(),
          ),
        ],
      ],
    );
  }
}

/// The recorded result: the desk decision, then the rider and what they
/// found.
class _ResultBox extends StatelessWidget {
  const _ResultBox({required this.verification, this.pinLat, this.pinLng});

  final CaseVerification verification;
  final double? pinLat;
  final double? pinLng;

  @override
  Widget build(BuildContext context) {
    final v = verification;
    final level = v.isConfirmed
        ? EvidenceLevel.supports
        : (v.riderOutcome == RiderOutcome.notFound || v.deskOutcome == DeskOutcome.couldNotConfirm)
            ? EvidenceLevel.concern
            : EvidenceLevel.caution;
    final look = _look(level);
    final riderDistance = metresBetween(v.riderLat, v.riderLng, pinLat, pinLng);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: look.color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: look.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (v.deskOutcome != null) ...[
            Row(
              children: [
                Icon(look.icon, size: 18, color: look.color),
                const SizedBox(width: 6),
                Expanded(child: Text(v.deskOutcome!.label, style: _body(weight: FontWeight.w700))),
              ],
            ),
            Text(
              'Desk check${v.deskByName == null ? '' : ' by ${v.deskByName}'}'
              '${v.deskAt == null ? '' : ' · ${formatDateTime(v.deskAt!)}'}',
              style: _small(),
            ),
            if (v.deskNote != null) Text(v.deskNote!, style: _body()),
          ],
          if (v.hasRider) ...[
            if (v.deskOutcome != null) const SizedBox(height: 8),
            Text(
              'Rider: ${v.riderName ?? 'Unnamed'}'
              '${v.riderId == null ? ' (no app account, staff record the result)' : ''}',
              style: _body(weight: FontWeight.w700),
            ),
            if (v.riderOutcome == null)
              Text(
                'Sent ${formatDateTimeOr(v.riderAssignedAt, 'just now')}. No result yet.',
                style: _small(),
              )
            else ...[
              Text(v.riderOutcome!.label, style: _body()),
              Text(
                'Recorded${v.riderRecordedByName == null ? '' : ' by ${v.riderRecordedByName}'}'
                '${v.riderRecordedAt == null ? '' : ' · ${formatDateTime(v.riderRecordedAt!)}'}'
                '${riderDistance == null ? '' : ' · ${formatDistance(riderDistance)} from the pin'}',
                style: _small(),
              ),
              if (v.riderNote != null) Text(v.riderNote!, style: _body()),
              if (v.riderMedia.isNotEmpty) ...[
                const SizedBox(height: 6),
                MediaThumbStrip(media: v.riderMedia),
              ],
            ],
          ],
        ],
      ),
    );
  }
}

// ---- Sheets ----------------------------------------------------------------

class _DeskResult {
  const _DeskResult({required this.outcome, this.note, this.riderId, this.riderName});

  final DeskOutcome outcome;
  final String? note;
  final String? riderId;
  final String? riderName;
}

/// Not a transporter account: staff type the rider's name and record the
/// result for them.
const _someoneElse = '__someone_else__';

class _DeskResultSheet extends ConsumerStatefulWidget {
  const _DeskResultSheet();

  @override
  ConsumerState<_DeskResultSheet> createState() => _DeskResultSheetState();
}

class _DeskResultSheetState extends ConsumerState<_DeskResultSheet> {
  final _selected = <DeskOutcome>[];
  final _unused = TextEditingController();
  final _note = TextEditingController();
  final _riderName = TextEditingController();
  String? _riderChoice;

  @override
  void dispose() {
    _unused.dispose();
    _note.dispose();
    _riderName.dispose();
    super.dispose();
  }

  DeskOutcome? get _outcome => _selected.isEmpty ? null : _selected.first;

  List<PetTransporter> get _riders {
    final all = [
      ...ref.watch(petTransportersProvider).asData?.value ?? const <PetTransporter>[],
      ...ref.watch(rescueVolunteersProvider).asData?.value ?? const <PetTransporter>[],
    ].where((r) => r.isVerified).toList();
    // Online riders first, then by name.
    all.sort((a, b) {
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return all;
  }

  bool get _riderChosen =>
      _riderChoice != null && (_riderChoice != _someoneElse || _riderName.text.trim().isNotEmpty);

  bool get _canSave {
    final outcome = _outcome;
    if (outcome == null) return false;
    if (outcome == DeskOutcome.needsRider) return _riderChosen;
    // "Could not confirm" has to say what was tried.
    return outcome != DeskOutcome.couldNotConfirm || _note.text.trim().isNotEmpty;
  }

  void _save(List<PetTransporter> riders) {
    final outcome = _outcome!;
    final note = _note.text.trim();
    String? riderId;
    String? riderName;
    if (outcome == DeskOutcome.needsRider) {
      if (_riderChoice == _someoneElse) {
        riderName = _riderName.text.trim();
      } else {
        final rider = riders.firstWhere((r) => r.uid == _riderChoice);
        riderId = rider.uid;
        riderName = rider.name;
      }
    }
    Navigator.pop(
      context,
      _DeskResult(outcome: outcome, note: note.isEmpty ? null : note, riderId: riderId, riderName: riderName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final riders = _riders;
    final outcome = _outcome;
    return ReasonSheetFrame(
      title: 'Verification result',
      subtitle: 'What did the desk check show? Accept and Reject stay separate decisions.',
      confirmLabel: outcome == DeskOutcome.needsRider ? 'Send rider' : 'Save result',
      destructive: false,
      onConfirm: _canSave ? () => _save(riders) : null,
      children: [
        ReasonChoiceList<DeskOutcome>(
          options: [for (final o in DeskOutcome.values) ReasonOption(o, '${o.label}: ${o.help}')],
          selected: _selected,
          otherController: _unused,
          onChanged: (values) => setState(() => _selected
            ..clear()
            ..addAll(values)),
        ),
        if (outcome == DeskOutcome.needsRider) ...[
          const ReasonSectionLabel(
            'Who is going?',
            help: 'A verified transporter sees the visit in their app and records what they find.',
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(_riderChoice),
            initialValue: _riderChoice,
            isExpanded: true,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface,
              hintText: 'Choose a rider',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            items: [
              for (final r in riders)
                DropdownMenuItem(
                  value: r.uid,
                  child: Text(
                    '${r.name}${r.isOnline ? ' (online)' : ''}',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                  ),
                ),
              DropdownMenuItem(
                value: _someoneElse,
                child: Text('Someone else (type a name)',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              ),
            ],
            onChanged: (v) => setState(() => _riderChoice = v),
          ),
          if (_riderChoice == _someoneElse) ...[
            const SizedBox(height: 8),
            ReasonTextField(
              controller: _riderName,
              label: 'Rider\'s name',
              hint: 'You record the result for them afterwards',
              onChanged: () => setState(() {}),
            ),
          ],
        ],
        const SizedBox(height: 12),
        ReasonTextField(
          controller: _note,
          label: outcome == DeskOutcome.couldNotConfirm ? 'What was tried' : 'Note (optional)',
          hint: 'e.g. called the reporter, matched the photo to the street',
          maxLines: 3,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }
}

class _RiderResult {
  const _RiderResult({required this.outcome, this.note, this.media = const []});

  final RiderOutcome outcome;
  final String? note;
  final List<PickedMedia> media;
}

/// Staff recording what a rider reported back.
class _RiderResultSheet extends StatefulWidget {
  const _RiderResultSheet();

  @override
  State<_RiderResultSheet> createState() => _RiderResultSheetState();
}

class _RiderResultSheetState extends State<_RiderResultSheet> {
  final _selected = <RiderOutcome>[];
  final _unused = TextEditingController();
  final _note = TextEditingController();
  List<PickedMedia> _media = const [];

  @override
  void dispose() {
    _unused.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ReasonSheetFrame(
      title: 'Rider\'s result',
      subtitle: 'What did the rider find at the reported location?',
      confirmLabel: 'Save result',
      destructive: false,
      onConfirm: _selected.isEmpty
          ? null
          : () {
              final note = _note.text.trim();
              Navigator.pop(
                context,
                _RiderResult(outcome: _selected.first, note: note.isEmpty ? null : note, media: _media),
              );
            },
      children: [
        ReasonChoiceList<RiderOutcome>(
          options: [for (final o in RiderOutcome.values) ReasonOption(o, '${o.label}: ${o.help}')],
          selected: _selected,
          otherController: _unused,
          onChanged: (values) => setState(() => _selected
            ..clear()
            ..addAll(values)),
        ),
        const SizedBox(height: 12),
        ReasonTextField(controller: _note, label: 'Note (optional)', maxLines: 3),
        const SizedBox(height: 12),
        AttachmentPicker(
          items: _media,
          onChanged: (items) => setState(() => _media = items),
          label: 'Add the rider\'s photo',
          max: 3,
          allowDocument: false,
        ),
      ],
    );
  }
}
