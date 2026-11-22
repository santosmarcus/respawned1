import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/community_report.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';

String _formatReportDateTime(DateTime? d) => formatDateTimeOr(d, '');

/// The one place staff see a case's community reports: the case's own
/// `cases/{caseId}/communityReports` (written by the user side's
/// CommunityReportSection) plus those filed on duplicates merged into it.
/// Always open — no expanding — with "Animal moved" reports waiting for
/// review at the top. Staff verify a move against the map (current pin vs
/// the reported pin) and confirming it moves the case's location, which
/// the transporter's pickup, the maps and the distances all follow.
/// Used on Rescue Details and on Track Case (whichever the case's status
/// opens), never twice on one screen.
class CommunityReportsSection extends ConsumerWidget {
  final String caseId;
  const CommunityReportsSection({super.key, required this.caseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(caseCommunityReportsProvider(caseId));
    final rescueCase = ref.watch(caseDetailProvider(caseId)).asData?.value;
    final reports = reportsAsync.asData?.value ?? const <CommunityReport>[];
    final pending = reports.where((r) => r.isPendingMove).toList();
    final others = reports.where((r) => !r.isPendingMove).toList();
    final currentPin = (rescueCase?.lat != null && rescueCase?.lng != null)
        ? LatLng(rescueCase!.lat!, rescueCase.lng!)
        : null;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Community Reports${reportsAsync.hasValue ? '  ${reports.length}' : ''}',
                  style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
              if (pending.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${pending.length} to verify',
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.warning),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          reportsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Text(
              'Could not load community reports.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
            data: (_) {
              if (reports.isEmpty) {
                return Text(
                  'No community reports submitted yet.',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in [...pending, ...others])
                    _CommunityReportTile(caseId: caseId, report: r, currentPin: currentPin),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Current case pin (red) and the reported new pin (orange), so staff can
/// check how far the animal moved before confirming.
class _MoveCheckMap extends StatelessWidget {
  final LatLng? current;
  final LatLng reported;
  const _MoveCheckMap({required this.current, required this.reported});

  @override
  Widget build(BuildContext context) {
    final cur = current;
    final meters = cur == null
        ? null
        : Geolocator.distanceBetween(cur.latitude, cur.longitude, reported.latitude, reported.longitude);
    final center = cur == null
        ? reported
        : LatLng((cur.latitude + reported.latitude) / 2, (cur.longitude + reported.longitude) / 2);
    final zoom = meters == null
        ? 16.0
        : meters < 300
            ? 16.0
            : meters < 1500
                ? 14.0
                : meters < 6000
                    ? 12.5
                    : 11.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 150,
            child: GoogleMap(
              gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer())},
              initialCameraPosition: CameraPosition(target: center, zoom: zoom),
              markers: {
                if (cur != null) Marker(markerId: const MarkerId('current'), position: cur),
                Marker(
                  markerId: const MarkerId('reported'),
                  position: reported,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
                ),
              },
              polylines: {
                if (cur != null)
                  Polyline(
                    polylineId: const PolylineId('move'),
                    points: [cur, reported],
                    width: 3,
                    color: AppColors.warning,
                    patterns: [PatternItem.dash(12), PatternItem.gap(8)],
                  ),
              },
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          meters == null
              ? 'Orange: reported location'
              : 'Red: current location · Orange: reported · ${meters >= 1000 ? '${(meters / 1000).toStringAsFixed(1)} km' : '${meters.round()} m'} apart',
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _CommunityReportTile extends ConsumerStatefulWidget {
  final String caseId;
  final CommunityReport report;
  final LatLng? currentPin;
  const _CommunityReportTile({required this.caseId, required this.report, this.currentPin});

  @override
  ConsumerState<_CommunityReportTile> createState() =>
      _CommunityReportTileState();
}

class _CommunityReportTileState extends ConsumerState<_CommunityReportTile> {
  bool _busy = false;

  String get _actorUid => FirebaseAuth.instance.currentUser?.uid ?? '';
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName;
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  /// Set when the report was filed on a duplicate merged into this case.
  String? get _reportCaseId {
    final id = widget.report.caseId;
    return (id == null || id == widget.caseId) ? null : id;
  }

  Future<void> _approve() async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Confirm the animal moved?',
      message: 'The case location changes to ${widget.report.newAddress?.trim().isNotEmpty == true ? '"${widget.report.newAddress}"' : 'the reported pin'}. '
          'The transporter, maps and distances follow the new location.',
      confirmLabel: 'Update location',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .approveLocationUpdate(
            caseId: widget.caseId,
            reportId: widget.report.id,
            reportCaseId: _reportCaseId,
            actorUid: _actorUid,
            actorName: _actorName,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not approve: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final reason = await showTextInputDialog(
      context,
      title: 'Reject Location Change',
      label: 'Reason',
      hint: 'Explain why this proposed location is being rejected',
      confirmLabel: 'Reject',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(rescueCaseRepositoryProvider)
          .rejectLocationUpdate(
            caseId: widget.caseId,
            reportId: widget.report.id,
            reportCaseId: _reportCaseId,
            actorUid: _actorUid,
            actorName: _actorName,
            reason: reason,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not reject: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Community Report Overflow spec §3 — the previous fixed Row of both
  // buttons overflowed by ~52px on narrow screens/at larger text scales
  // ("RIGHT OVERFLOWED BY 52 PIXELS"), since neither button had a bounded
  // width and their combined intrinsic width exceeded the card's content
  // area. LayoutBuilder switches to a stacked column (primary action
  // first, per spec) once the row genuinely doesn't have room for both
  // buttons at a reasonable size, instead of shrinking text or clipping.
  Widget _approvalActionButtons() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final rejectButton = OutlinedButton(
          onPressed: _busy ? null : _reject,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.error,
            side: const BorderSide(color: AppColors.error),
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: const Text(
            'Not Verified',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        );

        final approveButton = ElevatedButton(
          onPressed: _busy ? null : _approve,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.greenrspwn,
            foregroundColor: Colors.white,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
          child: _busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Confirm Move · Update Location',
                  style: TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
        );

        // Below this width (or when text-scaling would push either label
        // past it) two side-by-side buttons can't fit without clipping —
        // stack them instead, primary action on top per the recommended
        // mobile order.
        final textScale = MediaQuery.textScalerOf(context).scale(12);
        final narrow = constraints.maxWidth < 260 || textScale > 16;

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              approveButton,
              const SizedBox(height: 8),
              rejectButton,
            ],
          );
        }

        return Row(
          children: [
            rejectButton,
            const SizedBox(width: 8),
            Expanded(child: approveButton),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final name = (report.reporterName?.trim().isNotEmpty ?? false)
        ? report.reporterName!
        : 'A community member';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.textPrimary,
            child: Text(
              name.characters.isNotEmpty
                  ? name.characters.first.toUpperCase()
                  : '?',
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.background,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name · ${report.typeLabel}',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (report.timestamp != null)
                  Text(
                    _formatReportDateTime(report.timestamp),
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (report.comment != null &&
                    report.comment!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    report.comment!,
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
                if (report.newAddress != null &&
                    report.newAddress!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'New location: ${report.newAddress}',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
                if (_reportCaseId != null)
                  Text(
                    'Filed on merged duplicate report',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  ),
                if (report.isPendingMove && report.newLat != null && report.newLng != null) ...[
                  const SizedBox(height: 6),
                  _MoveCheckMap(current: widget.currentPin, reported: LatLng(report.newLat!, report.newLng!)),
                ],
                // Community Location Approval spec §9 — the case's own
                // address/lat/lng only ever change once Approve is tapped
                // here; this card never implies otherwise while pending.
                if (report.approvalStatus == 'pending') ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFF9C6B10,
                          ).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Moved? Verify before updating',
                          style: GoogleFonts.zain(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF9C6B10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _approvalActionButtons(),
                ] else if (report.approvalStatus == 'approved') ...[
                  const SizedBox(height: 4),
                  Text(
                    'Location change approved by ${report.approvedBy ?? '—'}${report.approvedAt != null ? ' on ${_formatReportDateTime(report.approvedAt)}' : ''}',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.greenrspwn,
                    ),
                  ),
                ] else if (report.approvalStatus == 'rejected') ...[
                  const SizedBox(height: 4),
                  Text(
                    'Location change rejected by ${report.rejectedBy ?? '—'}${report.rejectedAt != null ? ' on ${_formatReportDateTime(report.rejectedAt)}' : ''}',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (report.photoUrl != null && report.photoUrl!.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                report.photoUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 48,
                  height: 48,
                  color: AppColors.slaterspwn,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
