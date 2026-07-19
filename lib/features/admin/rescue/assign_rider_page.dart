import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

// ---- Demo transporters ---------------------------------------------------
// Two fixed, clearly-marked (isDemo: true) test transporters so the whole
// offer/accept/reject lifecycle can be exercised without a real
// pet-transporter account. Not read from Firestore `users` at all — their
// uids never collide with real accounts. Remove this block (and its uses
// below) once real transporter accounts are available for testing instead.
// TODO: internal identifiers here (riderId/riderName/etc., inherited from
// the repository's existing parameter names) are left as-is for now —
// only user-facing text says "Transporter". Migrate rider* -> transporter*
// internally in a later pass if/when it's worth the churn.
const _demoAcceptingRiderUid = 'demo-rider-a';
const _demoAcceptingRiderName = 'Demo Transporter A (Auto-Accept)';
const _demoAcceptingRiderVehicle = 'Yamaha NMAX';
const _demoAcceptingRiderPlate = 'DEMO-001';

const _demoRejectingRiderUid = 'demo-rider-b';
const _demoRejectingRiderName = 'Demo Transporter B (Auto-Reject)';
const _demoRejectingRiderVehicle = 'Honda Click';
const _demoRejectingRiderPlate = 'DEMO-002';
const _demoRejectionReason = 'Already handling another rescue and cannot accept this case';

/// Schedules the demo auto-accept/auto-reject response, detached from any
/// widget's lifecycle (fire-and-forget, plain `RescueCaseRepository`/
/// `FirebaseFirestore` calls, no `ref`/`context`). This is deliberate: if
/// the admin navigates away or backgrounds the app before the delay
/// elapses, the response must still land — a State-scoped Timer would be
/// cancelled by `dispose()` and silently never fire (see spec edge case
/// "demo timer completes while screen not visible"). Re-reads the
/// assignment doc fresh right before acting and no-ops if it's no longer
/// pending, so this can never double-resolve an already-answered offer.
void _scheduleDemoResponse({
  required String caseId,
  required String assignmentId,
  required String riderId,
}) {
  final delay = Duration(seconds: 3 + math.Random().nextInt(3)); // 3-5s
  Future.delayed(delay, () async {
    try {
      final freshDoc = await FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('transportAssignments')
          .doc(assignmentId)
          .get();
      if (!freshDoc.exists || freshDoc.data()?['status'] != 'pending') return;

      final repo = RescueCaseRepository();
      if (riderId == _demoAcceptingRiderUid) {
        await repo.acceptAssignment(
          caseId: caseId,
          assignmentId: assignmentId,
          riderId: riderId,
          riderName: _demoAcceptingRiderName,
          riderVehicle: _demoAcceptingRiderVehicle,
          riderPlate: _demoAcceptingRiderPlate,
        );
      } else if (riderId == _demoRejectingRiderUid) {
        await repo.rejectAssignment(
          caseId: caseId,
          assignmentId: assignmentId,
          reason: _demoRejectionReason,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('AssignRiderPage: demo response failed: $e');
    }
  });
}

enum _RiderAvailability { available, pending, busy }

class _RiderVm {
  final String uid;
  final String name;
  final String type;
  final LatLng position;
  final String vehicle;
  final String plate;
  final String? photoUrl;
  final bool isDemo;
  final _RiderAvailability availability;
  final double distanceKm;

  const _RiderVm({
    required this.uid,
    required this.name,
    required this.type,
    required this.position,
    required this.vehicle,
    required this.plate,
    required this.photoUrl,
    required this.isDemo,
    required this.availability,
    required this.distanceKm,
  });
}

class AssignRiderPage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const AssignRiderPage(
      {super.key, required this.caseId, required this.data});

  @override
  ConsumerState<AssignRiderPage> createState() => _AssignRiderPageState();
}

class _AssignRiderPageState extends ConsumerState<AssignRiderPage> {
  /// Transporter tapped/chosen but not yet written to Firestore —
  /// selection is purely local state until "Next" is confirmed.
  String? _selectedRiderUid;

  /// True only while the confirmed assignment is being saved, to guard
  /// against duplicate taps on "Next".
  bool _isAssigning = false;

  GoogleMapController? _mapController;
  bool _hasFitCamera = false;

  LatLng? _caseLocationFrom(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// A transporter's most-recent assignment being `rejected` is bucketed as
  /// Busy here too, not Available — a transporter who just declined an
  /// offer shouldn't loop straight back into the selectable pool. Only
  /// `completed`/`cancelled` (or no assignment at all) reads as Available.
  _RiderAvailability _availabilityFor(String uid, Map<String, TransportAssignmentStatus> activeByRider) {
    final status = activeByRider[uid];
    if (status == TransportAssignmentStatus.accepted || status == TransportAssignmentStatus.rejected) {
      return _RiderAvailability.busy;
    }
    if (status == TransportAssignmentStatus.pending) return _RiderAvailability.pending;
    return _RiderAvailability.available;
  }

  LatLng _positionFor(LatLng center, String uid) {
    final offset = deterministicDemoOffset(center.latitude, center.longitude, uid);
    return LatLng(offset.lat, offset.lng);
  }

  /// Order: demo transporters while Available, then real transporters
  /// grouped Available -> Pending -> Busy (a demo transporter that goes
  /// Pending/Busy — e.g. right after declining — joins those same groups
  /// instead of staying pinned to the top). Each group sorted by distance.
  /// Pending/busy transporters are never hidden.
  List<_RiderVm> _buildRiderVms(
    LatLng center,
    List<PetTransporter> transporters,
    Map<String, TransportAssignmentStatus> activeByRider,
  ) {
    double distanceFor(LatLng pos) =>
        haversineDistanceKm(center.latitude, center.longitude, pos.latitude, pos.longitude);

    _RiderVm demoRider({
      required String uid,
      required String name,
      required String vehicle,
      required String plate,
    }) {
      final pos = _positionFor(center, uid);
      return _RiderVm(
        uid: uid,
        name: name,
        type: 'Pet Transporter',
        position: pos,
        vehicle: vehicle,
        plate: plate,
        photoUrl: null,
        isDemo: true,
        availability: _availabilityFor(uid, activeByRider),
        distanceKm: distanceFor(pos),
      );
    }

    final demoA = demoRider(
      uid: _demoAcceptingRiderUid,
      name: _demoAcceptingRiderName,
      vehicle: _demoAcceptingRiderVehicle,
      plate: _demoAcceptingRiderPlate,
    );
    final demoB = demoRider(
      uid: _demoRejectingRiderUid,
      name: _demoRejectingRiderName,
      vehicle: _demoRejectingRiderVehicle,
      plate: _demoRejectingRiderPlate,
    );

    final realRiders = transporters.map((t) {
      final pos = _positionFor(center, t.uid);
      return _RiderVm(
        uid: t.uid,
        name: t.name,
        type: 'Pet Transporter',
        position: pos,
        vehicle: t.vehicleType ?? 'Not provided',
        plate: t.licensePlate ?? 'Not provided',
        photoUrl: t.photoUrl,
        isDemo: false,
        availability: _availabilityFor(t.uid, activeByRider),
        distanceKm: distanceFor(pos),
      );
    }).toList();

    int byDistance(_RiderVm a, _RiderVm b) => a.distanceKm.compareTo(b.distanceKm);

    // Demo transporters are only pinned above the real-available group
    // while they themselves are Available. The moment one goes Pending or
    // Busy (e.g. right after declining), it drops into the same
    // distance-sorted Pending/Busy bucket as everyone else instead of
    // staying artificially glued to the top — that's what actually moves
    // a just-declined transporter down and out of easy re-selection.
    final allRiders = [demoA, demoB, ...realRiders];

    final demoAvailable = [demoA, demoB]
        .where((r) => r.availability == _RiderAvailability.available)
        .toList()
      ..sort(byDistance);
    final available = realRiders.where((r) => r.availability == _RiderAvailability.available).toList()
      ..sort(byDistance);
    final pending = allRiders.where((r) => r.availability == _RiderAvailability.pending).toList()
      ..sort(byDistance);
    final busy = allRiders.where((r) => r.availability == _RiderAvailability.busy).toList()
      ..sort(byDistance);

    return [...demoAvailable, ...available, ...pending, ...busy];
  }

  void _selectRider(_RiderVm rider) {
    if (rider.availability != _RiderAvailability.available || _isAssigning) return;
    setState(() {
      // Tapping the already-selected transporter deselects it; tapping a
      // different available transporter replaces the selection — only one
      // at a time either way.
      _selectedRiderUid = _selectedRiderUid == rider.uid ? null : rider.uid;
    });
  }

  /// The live case document, not the possibly-stale snapshot passed in at
  /// construction time.
  Map<String, dynamic> _currentCaseData() =>
      ref.read(caseDetailProvider(widget.caseId)).asData?.value?.raw ?? widget.data;

  Future<void> _handleNext(List<_RiderVm> riders) async {
    final selectedUid = _selectedRiderUid;
    if (selectedUid == null || _isAssigning) return; // nothing selected / already saving

    // Re-verify availability at confirmation time — the transporter may
    // have become pending/busy on another case between selection and now.
    final rider = riders.where((r) => r.uid == selectedUid).cast<_RiderVm?>().firstWhere((r) => true, orElse: () => null);
    if (rider == null || rider.availability != _RiderAvailability.available) {
      setState(() => _selectedRiderUid = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This transporter is no longer available. Please select another.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() => _isAssigning = true);

    // A single modal instance carries the admin through
    // confirmation -> pending -> accepted/declined/error without ever
    // navigating away from this screen. See _TransporterAssignmentDialog.
    final outcome = await showDialog<_DialogOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _TransporterAssignmentDialog(caseId: widget.caseId, rider: rider),
    );

    if (!mounted) return;
    setState(() => _isAssigning = false);

    switch (outcome) {
      case _DialogOutcome.accepted:
        // Assignment is confirmed accepted (persisted, not just local
        // state) — Track Case now shows the live tracking map directly.
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => AdminTrackCasePage(caseId: widget.caseId, data: _currentCaseData())));
        break;
      case _DialogOutcome.declined:
        // Stay here; clear the selection so the admin can pick someone
        // else. The declined transporter itself will already show as Busy
        // and drop to the bottom of the list via the reactive rider stream
        // — no extra state to manage here.
        setState(() => _selectedRiderUid = null);
        break;
      case _DialogOutcome.cancelled:
      case null:
        // Cancelled, closed on error, or dismissed some other way — keep
        // the selection, stay on Assign Transporter, nothing was written.
        break;
    }
  }

  void _fitCameraOnce(LatLng? center, List<_RiderVm> riders) {
    if (_hasFitCamera || _mapController == null || center == null) return;
    _hasFitCamera = true;
    final points = [center, ...riders.map((r) => r.position)];
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      48,
    ));
  }

  Set<Marker> _buildMarkers(LatLng? center, List<_RiderVm> riders) {
    return {
      if (center != null)
        Marker(
          markerId: const MarkerId('rescue_case'),
          position: center,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Rescue Case'),
        ),
      for (final rider in riders)
        Marker(
          markerId: MarkerId(rider.uid),
          position: rider.position,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            rider.uid == _selectedRiderUid
                ? BitmapDescriptor.hueGreen
                : switch (rider.availability) {
                    _RiderAvailability.pending => BitmapDescriptor.hueOrange,
                    _RiderAvailability.busy => BitmapDescriptor.hueViolet,
                    _RiderAvailability.available => BitmapDescriptor.hueRed,
                  },
          ),
          infoWindow: InfoWindow(
            title: rider.name,
            snippet: '${rider.distanceKm.toStringAsFixed(1)} km',
          ),
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    // Watched (not just read) so the header/clinic info here stay live if
    // the case changes while this page is open, not just at the moment it
    // was opened.
    final liveCase = ref.watch(caseDetailProvider(widget.caseId)).asData?.value;
    final d = liveCase?.raw ?? widget.data;
    final urgency = d['urgency'] ?? '';

    final caseLocation = _caseLocationFrom(d);
    // Riders still need a center to be positioned around even when the
    // case itself has no saved coordinates yet.
    final riderCenter = caseLocation ?? const LatLng(14.5995, 120.9842); // Manila fallback

    final transporters = ref.watch(petTransportersProvider).asData?.value ?? const <PetTransporter>[];
    final activeByRider =
        ref.watch(activeAssignmentsByRiderProvider).asData?.value ?? const <String, TransportAssignmentStatus>{};

    final riders = _buildRiderVms(riderCenter, transporters, activeByRider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          // Normal page navigation only — always returns to Rescue
          // Details, regardless of selection.
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Assign Transporter',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Case header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['animalType'] ?? 'Animal',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 22, color: AppColors.textPrimary)),
                    Text(
                        'CASE ID: ${shortCaseId(widget.caseId)}',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: urgency == 'Critical'
                        ? Colors.red
                        : AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(urgency,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),
          ),

          // Real map: case marker + transporter markers (real-or-demo positions).
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: caseLocation == null
                    ? Container(
                        color: AppColors.slaterspwn,
                        child: Center(
                          child: Text('No coordinates saved for this case.',
                              style: GoogleFonts.zain(
                                  fontSize: 12, color: AppColors.textSecondary)),
                        ),
                      )
                    : GoogleMap(
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                        },
                        initialCameraPosition: CameraPosition(target: caseLocation, zoom: 13),
                        markers: _buildMarkers(caseLocation, riders),
                        onMapCreated: (ctrl) {
                          _mapController = ctrl;
                          _fitCameraOnce(caseLocation, riders);
                        },
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Transporters',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary)),
            ),
          ),

          const SizedBox(height: 8),

          // Transporter list — fixed order (see _buildRiderVms): demo
          // transporters pinned above the real-Available group only while
          // they're Available themselves, then real transporters grouped
          // available -> pending -> busy, each by distance. Pending/busy
          // transporters stay visible, just not selectable.
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: riders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final rider = riders[index];
                final isSelected = _selectedRiderUid == rider.uid;
                return _RiderCard(
                  rider: rider,
                  isSelected: isSelected,
                  onSelect: () => _selectRider(rider),
                );
              },
            ),
          ),

          // Fixed bottom action — always visible; "Next" is simply disabled
          // until an available transporter is selected. No Back button
          // here — the app-bar back arrow is the only way to leave this page.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(top: BorderSide(color: AppColors.slaterspwn)),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selectedRiderUid == null || _isAssigning) ? null : () => _handleNext(riders),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  disabledBackgroundColor: AppColors.slaterspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isAssigning
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Next',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 15,
                            color: _selectedRiderUid == null
                                ? AppColors.textSecondary
                                : AppColors.textPrimary)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  final _RiderVm rider;
  final bool isSelected;
  final VoidCallback onSelect;

  const _RiderCard({
    required this.rider,
    required this.isSelected,
    required this.onSelect,
  });

  (String, Color, Color) _statusChip() => switch (rider.availability) {
        _RiderAvailability.available => ('Available', AppColors.greenrspwn, AppColors.textPrimary),
        _RiderAvailability.pending => ('Pending', AppColors.yellowrspwn, AppColors.textPrimary),
        _RiderAvailability.busy => ('Busy', AppColors.slaterspwn, AppColors.textSecondary),
      };

  @override
  Widget build(BuildContext context) {
    final isAvailable = rider.availability == _RiderAvailability.available;
    final (statusLabel, statusColor, statusTextColor) = _statusChip();

    return GestureDetector(
      // Tapping anywhere on an available card selects it; pending/busy
      // cards aren't interactive at all (stay visible, just not selectable).
      onTap: isAvailable ? onSelect : null,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          // Selection is communicated ONLY through this border highlight —
          // never by changing the status chip (which always reflects true
          // Available/Pending/Busy state, selected or not).
          border: isSelected
              ? Border.all(color: AppColors.textPrimary, width: 2)
              : Border.all(color: Colors.transparent, width: 2),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Avatar(photoUrl: rider.photoUrl),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(rider.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.yellowrspwn,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(rider.type,
                            style: GoogleFonts.zain(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                      ),
                      if (rider.isDemo) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.5)),
                          ),
                          child: Text('DEMO',
                              style: GoogleFonts.zain(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textSecondary)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('${rider.distanceKm.toStringAsFixed(1)} km',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text('${rider.plate}  ${rider.vehicle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // Contact + one status chip — no "Selected" state here at all;
            // selection is shown only by the card border above.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.chat_outlined,
                            size: 20, color: AppColors.textPrimary),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {},
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        child: const Icon(Icons.phone_outlined,
                            size: 20, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel,
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: statusTextColor)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  const _Avatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          photoUrl!,
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.tearspwn,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.directions_car, color: AppColors.textSecondary),
      );
}

/// What the modal resolved to, once it closes — drives what
/// _AssignRiderPageState._handleNext does next (navigate to Track Case,
/// clear the selection, or just stay put).
enum _DialogOutcome { cancelled, accepted, declined }

enum _ModalPhase { confirmation, creating, pending, accepted, declined, error }

/// The single dialog instance that carries the admin from "Confirm
/// Transporter Assignment" through Pending and into Accepted/Declined/Error
/// — it is never closed and replaced with another page. Watches the
/// created assignment doc directly (a raw Firestore stream, not a
/// Riverpod provider) so it keeps reacting even though this widget's own
/// lifecycle is just "however long the dialog is open," and reflects
/// persisted Firestore state rather than any assumption about how the
/// demo timer resolves.
class _TransporterAssignmentDialog extends ConsumerStatefulWidget {
  final String caseId;
  final _RiderVm rider;
  const _TransporterAssignmentDialog({required this.caseId, required this.rider});

  @override
  ConsumerState<_TransporterAssignmentDialog> createState() => _TransporterAssignmentDialogState();
}

class _TransporterAssignmentDialogState extends ConsumerState<_TransporterAssignmentDialog> {
  _ModalPhase _phase = _ModalPhase.confirmation;
  String? _errorMessage;
  String? _rejectionReason;

  /// Guards "Confirm"/"Retry" against a second tap creating a second
  /// offer — cleared only when a create attempt actually fails, so Retry
  /// can try again.
  bool _hasCreatedOffer = false;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _assignmentSub;

  @override
  void dispose() {
    _assignmentSub?.cancel();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_hasCreatedOffer) return; // prevents a duplicate confirm action
    _hasCreatedOffer = true;
    setState(() {
      _phase = _ModalPhase.creating;
      _errorMessage = null;
    });

    try {
      final assignmentId = await ref.read(rescueCaseRepositoryProvider).createAssignmentOffer(
            caseId: widget.caseId,
            riderId: widget.rider.uid,
            riderName: widget.rider.name,
            riderType: widget.rider.type,
            isDemo: widget.rider.isDemo,
          );
      if (!mounted) return;

      if (widget.rider.isDemo) {
        _scheduleDemoResponse(caseId: widget.caseId, assignmentId: assignmentId, riderId: widget.rider.uid);
      }
      setState(() => _phase = _ModalPhase.pending);
      _listenForResponse(assignmentId);
    } catch (e) {
      _hasCreatedOffer = false; // let Retry actually attempt again
      if (mounted) {
        setState(() {
          _phase = _ModalPhase.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// Reacts to the persisted assignment doc rather than any local timer —
  /// this is what lets the demo auto-response (running completely detached
  /// from this dialog) still update the UI the moment it resolves, and
  /// what would just as correctly reflect a real transporter's own
  /// accept/reject action if one existed.
  void _listenForResponse(String assignmentId) {
    _assignmentSub?.cancel();
    _assignmentSub = FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('transportAssignments')
        .doc(assignmentId)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;
      final status = data['status'] as String?;

      if (status == 'accepted' && _phase != _ModalPhase.accepted) {
        setState(() => _phase = _ModalPhase.accepted);
        // Brief success state, then close and let the caller navigate to
        // Track Case — never navigates from inside the dialog itself.
        Future.delayed(const Duration(milliseconds: 900), () {
          if (mounted) Navigator.of(context).pop(_DialogOutcome.accepted);
        });
      } else if (status == 'rejected' && _phase != _ModalPhase.declined) {
        setState(() {
          _phase = _ModalPhase.declined;
          _rejectionReason = data['rejectionReason'] as String? ?? 'No reason given';
        });
      }
    });
  }

  String get _title => switch (_phase) {
        _ModalPhase.confirmation ||
        _ModalPhase.creating ||
        _ModalPhase.pending =>
          'Confirm Transporter Assignment',
        _ModalPhase.accepted => 'Assignment Accepted',
        _ModalPhase.declined => 'Assignment Declined',
        _ModalPhase.error => 'Assignment Failed',
      };

  Widget _content(BuildContext context) => switch (_phase) {
        _ModalPhase.confirmation => _confirmationContent(),
        _ModalPhase.creating => _loadingContent('Creating assignment…'),
        _ModalPhase.pending => _pendingContent(),
        _ModalPhase.accepted => _acceptedContent(),
        _ModalPhase.declined => _declinedContent(),
        _ModalPhase.error => _errorContent(),
      };

  Widget _confirmationContent() {
    // Live case data, not a stale snapshot — a clinic saved moments ago
    // should already show up here.
    final liveData = ref.watch(caseDetailProvider(widget.caseId)).asData?.value?.raw ?? const <String, dynamic>{};
    final clinicName = liveData['vetClinicName'] as String?;
    final clinicAddress = liveData['vetClinicAddress'] as String?;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoRow('Transporter', '${widget.rider.name} (${widget.rider.type})'),
        _infoRow('Distance', '${widget.rider.distanceKm.toStringAsFixed(1)} km'),
        _infoRow('Vehicle', '${widget.rider.plate}  ${widget.rider.vehicle}'),
        _infoRow(
          'Selected Clinic',
          (clinicName != null && clinicName.isNotEmpty)
              ? (clinicAddress != null && clinicAddress.isNotEmpty ? '$clinicName\n$clinicAddress' : clinicName)
              : 'No clinic selected',
        ),
      ],
    );
  }

  Widget _loadingContent(String message) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );

  Widget _pendingContent() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
              width: 36, height: 36, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.yellowrspwn)),
          const SizedBox(height: 16),
          Text(widget.rider.name,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(20)),
            child: Text('Pending',
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          ),
          const SizedBox(height: 16),
          Text('Waiting for the transporter to respond…',
              textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      );

  Widget _acceptedContent() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 40),
          const SizedBox(height: 12),
          Text('Transporter accepted the assignment.',
              textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ],
      );

  Widget _declinedContent() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.rider.name} declined the assignment.',
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          _infoRow('Reason', _rejectionReason ?? 'No reason given'),
        ],
      );

  Widget _errorContent() => Text(
        _errorMessage ?? 'Something went wrong while creating the assignment.',
        style: GoogleFonts.zain(fontSize: 13, color: Colors.redAccent),
      );

  Widget _infoRow(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: GoogleFonts.zain(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            Text(value, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      );

  List<Widget> _actions(BuildContext context) => switch (_phase) {
        _ModalPhase.confirmation => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_DialogOutcome.cancelled),
              child: Text('Cancel',
                  style: GoogleFonts.zain(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text('Confirm', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
            ),
          ],
        // No dismiss affordance while a write is in flight or the dialog
        // is about to auto-close on its own — this is what "disable
        // dismissal while the assignment write is being created" means in
        // practice, alongside barrierDismissible:false at the call site.
        _ModalPhase.creating || _ModalPhase.pending || _ModalPhase.accepted => const [],
        _ModalPhase.declined => [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(_DialogOutcome.declined),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text('Choose Another Transporter', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
            ),
          ],
        _ModalPhase.error => [
            TextButton(
              onPressed: () => Navigator.of(context).pop(_DialogOutcome.cancelled),
              child: Text('Close',
                  style: GoogleFonts.zain(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text('Retry', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
            ),
          ],
      };

  @override
  Widget build(BuildContext context) {
    // Blocks the system back gesture/button from dismissing the dialog
    // while a write is in flight or it's about to auto-close — mirrors
    // barrierDismissible:false's effect on barrier taps.
    final canPop = _phase == _ModalPhase.confirmation ||
        _phase == _ModalPhase.declined ||
        _phase == _ModalPhase.error;

    return PopScope(
      canPop: canPop,
      child: AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(_title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
        content: SizedBox(width: 320, child: _content(context)),
        actions: _actions(context),
      ),
    );
  }
}
