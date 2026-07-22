import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/route_result.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/community_reports_section.dart';
import 'package:respawnd1/features/admin/rescue/widgets/transporter_details_card.dart';

// Raw case-doc status values written by the pet-transporter app's own
// transit flow (see transit_progress_page.dart) once it has physically
// reached the clinic — either waiting on the clinic's accept/reject
// decision ('dropoff'), or already past it ('in_transit_shelter'). Neither
// of these is the multi-day clinical-care phase this screen's "Proceed to
// Treatment" button starts — that's a separate, admin-triggered status
// (RescueStatus.treatment / 'in_treatment').
const _kArrivedAtClinicStatuses = {'dropoff', 'in_transit_shelter'};

// Same transporter-written status vocabulary, but the slice that means
// "animal already picked up, headed toward a clinic" — 'treatment' here is
// the transporter's own (confusingly-named) en-route-to-clinic status, not
// RescueStatus.treatment. Once in one of these, the tracking destination
// switches from the rescue case to the selected clinic.
const _kPostPickupStatuses = {'treatment', 'dropoff', 'searching_clinic', 'in_transit_shelter'};

/// Which leg of the case this screen is tracking. Added so the same
/// Track Case screen (map, route, transporter card, timeline) serves both
/// the original rescue pickup and the later clinic-to-shelter intake
/// transport, instead of building a second tracking page — only the
/// origin/destination resolution and which sections are visible change.
enum TrackingMode { rescuePickup, intakeTransfer }

class AdminTrackCasePage extends ConsumerStatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final TrackingMode mode;
  const AdminTrackCasePage({
    super.key,
    required this.caseId,
    required this.data,
    this.mode = TrackingMode.rescuePickup,
  });

  @override
  ConsumerState<AdminTrackCasePage> createState() => _AdminTrackCasePageState();
}

class _AdminTrackCasePageState extends ConsumerState<AdminTrackCasePage> {
  int _tabIndex = 0;
  final _messageController = TextEditingController();
  GoogleMapController? _mapController;
  bool _hasFitCamera = false;

  // Drives the collapsible transporter card (see _CollapsibleTransporterCard)
  // — a purely local/visual toggle, never tied to re-fetching the
  // assignment stream itself (that's still watched once, at the top of
  // build()). Auto-collapses once the admin scrolls the tracking-detail
  // content down past a small threshold, expands again near the top; a tap
  // on the card itself can also toggle it directly (see onToggle below).
  final ScrollController _scrollController = ScrollController();
  bool _transporterCollapsed = false;
  static const _collapseThreshold = 24.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    final offset = _scrollController.offset;
    if (offset > _collapseThreshold && !_transporterCollapsed) {
      setState(() => _transporterCollapsed = true);
    } else if (offset <= _collapseThreshold && _transporterCollapsed) {
      setState(() => _transporterCollapsed = false);
    }
  }

  void _toggleTransporterCard() => setState(() => _transporterCollapsed = !_transporterCollapsed);

  /// Guards against double-tapping "Proceed to Treatment" and drives the
  /// button's loading state while the write is in flight and being
  /// verified.
  bool _isProceedingToTreatment = false;

  // Route request dedup: only kick off a new Directions call when the
  // rider/case coordinates actually differ from the last request — the
  // StreamBuilder in build() re-runs on every case-doc change, which would
  // otherwise re-fetch the route on unrelated field updates too.
  LatLng? _routeOrigin;
  LatLng? _routeDestination;
  Future<RouteResult>? _routeFuture;

  Future<RouteResult> _routeFor(LatLng riderLocation, LatLng caseLocation) {
    if (_routeFuture != null && _routeOrigin == riderLocation && _routeDestination == caseLocation) {
      return _routeFuture!;
    }
    _routeOrigin = riderLocation;
    _routeDestination = caseLocation;
    _hasFitCamera = false; // a genuinely new route deserves a fresh camera fit
    _routeFuture = ref.read(directionsRepositoryProvider).fetchRoute(
          origin: riderLocation,
          destination: caseLocation,
        );
    return _routeFuture!;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('messages')
        .add({
      'senderId': 'admin',
      'senderName': 'Loved by the Gapz',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _messageController.clear();
  }

  Future<void> _proceedToTreatment(Map<String, dynamic> data) async {
    if (_isProceedingToTreatment) return; // guard against double-tap
    setState(() => _isProceedingToTreatment = true);

    final caseRef = FirebaseFirestore.instance.collection('cases').doc(widget.caseId);
    final expectedStatus = RescueStatus.treatment.firestoreValue; // 'in_treatment'

    try {
      await caseRef.update({
        'status': expectedStatus,
        'dateAdmitted': Timestamp.now(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status':
            'The animal has reached the clinic. Animal is now in treatment.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      // Don't navigate optimistically — re-read the doc and only proceed
      // once the write has actually landed with the expected status. A
      // stale local snapshot or a write that silently didn't apply would
      // otherwise still open Treatment Details on a case that Rescue
      // Reports/Rescue Details still see as 'ongoing'.
      final freshSnap = await caseRef.get();
      final freshStatus = freshSnap.data()?['status'] as String?;
      if (freshStatus != expectedStatus) {
        throw StateError('Case status did not update as expected (got "$freshStatus").');
      }

      // Frees the accepted transporter (demo or real) back to "Available"
      // — activeAssignmentsByRiderProvider derives each transporter's chip
      // from their single most-recent assignment, so marking this one
      // 'completed' is what clears their Busy state elsewhere. Only done
      // once the treatment transition itself is confirmed, never before.
      final assignment = ref.read(currentAssignmentProvider(widget.caseId)).asData?.value;
      if (assignment != null && assignment.status == TransportAssignmentStatus.accepted) {
        await ref.read(rescueCaseRepositoryProvider).completeAssignment(
              caseId: widget.caseId,
              assignmentId: assignment.id,
            );
      }

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(
            builder: (_) => TreatmentDetailPage(caseId: widget.caseId, data: {...data, 'status': expectedStatus})));
      }
    } catch (e) {
      // Stay on Track Case — never navigate on an unconfirmed/failed write.
      if (mounted) {
        setState(() => _isProceedingToTreatment = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not move this case to treatment: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  // TESTING ONLY — simulates the transporter reaching the clinic without
  // waiting for real GPS movement (mirrors the same pattern already used by
  // transit_progress_page.dart's own _testSkipToNextStep). Lets staff
  // exercise "Proceed to Treatment" without a live rider in transit.
  Future<void> _fastForwardToClinic() async {
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'dropoff',
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': '[TEST] Fast-forwarded — transporter marked as arrived at the clinic.',
          'timestamp': Timestamp.now(),
        }
      ]),
    });
  }

  LatLng? _caseLocationFrom(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// Priority: real tracking location -> saved rider location -> DLSU demo
  /// fallback. This schema currently only has one rider-position field
  /// (`riderLastLat`/`riderLastLng`, written by the transporter app's own
  /// transit flow — see transit_progress_page.dart's `_findAndRouteToNextClinic`),
  /// so "real" and "saved" collapse to the same check here; there's no
  /// second, distinctly-cached position to fall back to before the demo
  /// coordinates. Never overwrites that field — this only reads it.
  ({LatLng location, bool isDemo}) _riderLocationFrom(Map<String, dynamic> data) {
    final lat = (data['riderLastLat'] as num?)?.toDouble();
    final lng = (data['riderLastLng'] as num?)?.toDouble();
    if (lat != null && lng != null) {
      return (location: LatLng(lat, lng), isDemo: false);
    }
    // TODO: Replace DLSU demo coordinates with the rider's live tracking location.
    return (location: const LatLng(dlsuManilaLat, dlsuManilaLng), isDemo: true);
  }

  /// Where the rider is currently heading. Before pickup, that's the
  /// rescue case; after pickup, it's the selected clinic — and once we're
  /// past pickup, this deliberately never falls back to the rescue case
  /// location even if clinic coordinates are temporarily missing, since
  /// that would silently send the rider to a stop they already left.
  /// Priority after pickup: saved selected-clinic coordinates ->
  /// legacy transporter-side dropoff coordinates -> visible warning
  /// (location null, caller shows markers-only / no route).
  ///
  /// In [TrackingMode.intakeTransfer], this is unrelated to the legacy
  /// pickup/dropoff status vocabulary entirely — the destination is always
  /// the intake shelter location saved by RescueCaseRepository.confirmIntake.
  ({LatLng? location, String label}) _destinationFrom(Map<String, dynamic> data) {
    if (widget.mode == TrackingMode.intakeTransfer) {
      final lat = (data['intakeDestinationLat'] as num?)?.toDouble();
      final lng = (data['intakeDestinationLng'] as num?)?.toDouble();
      final name = data['intakeDestinationName'] as String?;
      if (lat == null || lng == null) {
        return (location: null, label: 'No shelter destination available yet');
      }
      return (location: LatLng(lat, lng), label: (name != null && name.isNotEmpty) ? name : 'Organization Shelter');
    }

    final rawStatus = data['status'] as String?;
    if (!_kPostPickupStatuses.contains(rawStatus)) {
      return (location: _caseLocationFrom(data), label: 'Rescue Case');
    }

    final vetLat = (data['vetClinicLat'] as num?)?.toDouble();
    final vetLng = (data['vetClinicLng'] as num?)?.toDouble();
    if (vetLat != null && vetLng != null) {
      return (location: LatLng(vetLat, vetLng), label: 'Selected Clinic');
    }

    // Legacy: the transporter app's own independent clinic-search
    // destination (see transit_progress_page.dart's
    // _findAndRouteToNextClinic) — used if a clinic was picked there
    // rather than through the admin's Select Clinic sheet.
    final dropoffLat = (data['dropoffLat'] as num?)?.toDouble();
    final dropoffLng = (data['dropoffLng'] as num?)?.toDouble();
    if (dropoffLat != null && dropoffLng != null) {
      return (location: LatLng(dropoffLat, dropoffLng), label: 'Clinic (legacy destination)');
    }

    return (location: null, label: 'No clinic destination available yet');
  }

  /// The secondary "where they started from" marker — the original rescue
  /// location pre-intake, or the pickup clinic during intake transport.
  LatLng? _originMarkerLocationFrom(Map<String, dynamic> data) {
    if (widget.mode == TrackingMode.intakeTransfer) {
      final lat = (data['vetClinicLat'] as num?)?.toDouble();
      final lng = (data['vetClinicLng'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    }
    return _caseLocationFrom(data);
  }

  String get _originMarkerLabel =>
      widget.mode == TrackingMode.intakeTransfer ? 'Clinic Pickup' : 'Original Rescue Location';

  Future<void> _confirmAnimalReceived(TransportAssignment? assignment) async {
    try {
      await ref.read(rescueCaseRepositoryProvider).confirmAnimalReceived(
            caseId: widget.caseId,
            currentAssignmentId: assignment?.id,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Animal received — transport complete.'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm arrival: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  /// Fits the camera around every point on the route polyline (not just the
  /// two endpoints) so a road route that bows away from a straight line is
  /// still fully visible. Only runs once per distinct route — `_routeFor`
  /// resets `_hasFitCamera` whenever the rider/case coordinates actually
  /// change, so this never fights the user's own map gestures on rebuilds.
  void _fitTrackingCameraToRoute(List<LatLng> points) {
    if (_hasFitCamera || _mapController == null || points.isEmpty) return;
    _hasFitCamera = true;
    final lats = points.map((p) => p.latitude);
    final lngs = points.map((p) => p.longitude);
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(lats.reduce((a, b) => a < b ? a : b), lngs.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(lats.reduce((a, b) => a > b ? a : b), lngs.reduce((a, b) => a > b ? a : b)),
      ),
      56,
    ));
  }

  Widget _buildTrackingMap(Map<String, dynamic> data, TransportAssignment? assignment) {
    // Shown in place of the map, on this same page, whenever the current
    // offer hasn't been accepted yet — no separate Pending/Rejected page
    // or route. In normal use the admin never actually sees this: the
    // Assign Transporter modal already carries them through pending and
    // straight to acceptance before Track Case is ever opened. This only
    // matters for the edge case of reopening the case (e.g. after an app
    // restart) while an offer is still outstanding.
    if (assignment != null && assignment.status == TransportAssignmentStatus.pending) {
      return _PendingAssignmentBanner(assignment: assignment, caseData: data);
    }
    if (assignment != null && assignment.status == TransportAssignmentStatus.rejected) {
      return _DeclinedAssignmentBanner(
        assignment: assignment,
        onChooseAnother: () => Navigator.pop(context),
      );
    }

    final caseLocation = _originMarkerLocationFrom(data);
    final destination = _destinationFrom(data);

    if (caseLocation == null && destination.location == null) {
      // "Markers only" / no-line tier: nothing to plot at all. The
      // transporter card (when accepted) now lives below, in the
      // scrollable body — see build()'s _CollapsibleTransporterCard.
      return Container(
        height: 180,
        color: AppColors.slaterspwn,
        child: Center(
          child: Text('No coordinates saved for this case.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
    }

    final rider = _riderLocationFrom(data);

    if (destination.location == null) {
      // Post-pickup with no clinic coordinates on file at all (neither the
      // admin's selected clinic nor the transporter's own legacy dropoff
      // fields) — show a visible warning instead of silently routing back
      // to the rescue case, which the rider has already left.
      return SizedBox(
            height: 180,
            child: Stack(
              children: [
                GoogleMap(
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                  },
                  initialCameraPosition: CameraPosition(target: rider.location, zoom: 13),
                  markers: {
                    if (caseLocation != null)
                      Marker(
                        markerId: const MarkerId('rescue_case'),
                        position: caseLocation,
                        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                        infoWindow: InfoWindow(title: _originMarkerLabel),
                      ),
                    Marker(
                      markerId: const MarkerId('rider'),
                      position: rider.location,
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
                      infoWindow: InfoWindow(title: rider.isDemo ? 'Transporter (demo location)' : 'Transporter'),
                    ),
                  },
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE05353),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(destination.label,
                              style: GoogleFonts.zain(
                                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
    }

    final destinationLocation = destination.location!;
    final isPostPickupDestination = destination.label != 'Rescue Case';
    // Only add a separate "original case" marker once the destination has
    // actually moved on to the clinic — pre-pickup, the case *is* the
    // destination, so a second marker at the same point would be redundant.
    final showSeparateCaseMarker = isPostPickupDestination &&
        caseLocation != null &&
        (caseLocation.latitude != destinationLocation.latitude ||
            caseLocation.longitude != destinationLocation.longitude);

    return FutureBuilder<RouteResult>(
      future: _routeFor(rider.location, destinationLocation),
      builder: (context, snapshot) {
          final route = snapshot.data;
          final markers = {
            Marker(
              markerId: const MarkerId('destination'),
              position: destinationLocation,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
              infoWindow: InfoWindow(title: destination.label),
            ),
            if (showSeparateCaseMarker)
              Marker(
                markerId: const MarkerId('rescue_case'),
                position: caseLocation,
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                infoWindow: InfoWindow(title: _originMarkerLabel),
              ),
            Marker(
              markerId: const MarkerId('rider'),
              position: rider.location,
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
              infoWindow: InfoWindow(title: rider.isDemo ? 'Transporter (demo location)' : 'Transporter'),
            ),
          };

          // Distance prefers the route's own (road) distance; only the
          // straight-line fallback falls back to haversine, and RouteResult
          // already encodes that — this is never recomputed here.
          final distanceKm = route?.distanceKm ??
              haversineDistanceKm(rider.location.latitude, rider.location.longitude,
                  destinationLocation.latitude, destinationLocation.longitude);
          final isRoadFollowing = route?.isRoadFollowing ?? false;

          // Covers the ordering where the route resolves *after* the map
          // controller already exists (onMapCreated already fired with
          // route == null at that time) — this call is idempotent (guarded
          // by _hasFitCamera/_mapController in _fitTrackingCameraToRoute),
          // so it's harmless to also attempt it here on every rebuild.
          if (route != null) _fitTrackingCameraToRoute(route.polylinePoints);

          return SizedBox(
                height: 180,
                child: Stack(
            children: [
              GoogleMap(
                gestureRecognizers: {
                  Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
                },
                initialCameraPosition: CameraPosition(target: destinationLocation, zoom: 13),
                onMapCreated: (ctrl) {
                  _mapController = ctrl;
                  if (route != null) _fitTrackingCameraToRoute(route.polylinePoints);
                },
                markers: markers,
                polylines: {
                  if (route != null)
                    Polyline(
                      polylineId: const PolylineId('rider_to_destination'),
                      points: route.polylinePoints,
                      color: isRoadFollowing ? AppColors.textPrimary : AppColors.textSecondary,
                      patterns: isRoadFollowing ? const [] : [PatternItem.dash(12), PatternItem.gap(8)],
                      width: 4,
                    ),
                },
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
              Positioned(
                left: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${distanceKm.toStringAsFixed(1)} km to ${destination.label}'
                    '${!isRoadFollowing ? ' (straight-line estimate)' : ''}'
                    '${rider.isDemo ? ' · demo transporter location' : ''}',
                    style: GoogleFonts.zain(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                  ),
                ),
              ),
              // Explicit, visible fallback notice — never silently swap a
              // road route for a straight line. route == null only while
              // the FutureBuilder is still resolving (DirectionsRepository
              // never itself returns null), so this only shows once we
              // actually know the road API didn't come through.
              if (route != null && !isRoadFollowing)
                Positioned(
                  left: 10,
                  right: 10,
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0A353),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.white),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text('Road route unavailable. Showing approximate path.',
                              style: GoogleFonts.zain(
                                  fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
                ),
              );
        },
      );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData
            ? (snapshot.data!.data() as Map<String, dynamic>? ?? widget.data)
            : widget.data;
        final statusHistory = List<Map<String, dynamic>>.from(
            data['statusHistory'] ?? []);

        // Gate on the current transporter offer's persisted status — never
        // on local widget state — so reopening this page (e.g. after an
        // app restart while an offer is still pending) always shows the
        // right thing. This is a single page throughout: the pending/
        // declined states below only swap what's shown where the tracking
        // map normally goes (see _buildTrackingMap), never a separate
        // page/route. A missing assignment doc (legacy cases assigned
        // before this feature existed) falls through to the tracking map,
        // matching the old always-tracking behavior.
        final assignment = ref.watch(currentAssignmentProvider(widget.caseId)).asData?.value;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.background),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(widget.mode == TrackingMode.intakeTransfer ? 'Intake Transport' : 'Track Case',
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
          // One coherent scrollable layout below the map — see
          // _CollapsibleTransporterCard / _handleScroll for how the
          // transporter card collapses as this scrolls, and
          // _AdminTrackingTab for the collapsible Messages section further
          // down. No nested independently-scrolling regions: the old
          // per-tab ListView/SingleChildScrollView wrappers are gone, this
          // single controller drives everything except the map itself.
          body: Column(
            children: [
              _buildTrackingMap(data, assignment),
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Column(
                      children: [
                        const SizedBox(height: 12),

                        if (assignment != null && assignment.status == TransportAssignmentStatus.accepted)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _CollapsibleTransporterCard(
                              assignment: assignment,
                              collapsed: _transporterCollapsed,
                              onToggle: _toggleTransporterCard,
                              onMessage: () => setState(() => _tabIndex = 0),
                            ),
                          ),

                        // Tab switcher — intake transport is a restricted
                        // view with only one tab (Case Detail carries
                        // reporter-facing content that doesn't belong here;
                        // see the class-level restriction note).
                        if (widget.mode != TrackingMode.intakeTransfer)
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: AppColors.slaterspwn,
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: Row(
                              children: [
                                _AdminTabButton(
                                  label: 'Tracking Detail',
                                  selected: _tabIndex == 0,
                                  onTap: () => setState(() => _tabIndex = 0),
                                ),
                                _AdminTabButton(
                                  label: 'Case Detail',
                                  selected: _tabIndex == 1,
                                  onTap: () => setState(() => _tabIndex = 1),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 12),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '#${shortCaseId(widget.caseId)}',
                              style: GoogleFonts.tiltWarp(
                                  fontSize: 18, color: AppColors.textPrimary),
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        (widget.mode == TrackingMode.intakeTransfer || _tabIndex == 0)
                            ? _AdminTrackingTab(
                          statusHistory: statusHistory,
                          caseId: widget.caseId,
                          messageController: _messageController,
                          onSend: _sendMessage,
                          isIntakeMode: widget.mode == TrackingMode.intakeTransfer,
                          transporterHasReachedClinic:
                              _kArrivedAtClinicStatuses.contains(data['status']),
                          isProceedingToTreatment: _isProceedingToTreatment,
                          onProceedToTreatment: () => _proceedToTreatment(data),
                          onFastForward: _fastForwardToClinic,
                          hasReceivedIntake: data['intakeReceivedAt'] != null,
                          onConfirmAnimalReceived: () => _confirmAnimalReceived(assignment),
                          hideCommunityContent: data['sourceType'] == 'animalRecordAdmission',
                        )
                            : _AdminCaseDetailTab(data: data),
                      ],
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

class _AdminTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AdminTabButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(label,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.background
                        : AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

/// Now a plain (non-independently-scrolling) column of content — this is
/// rendered inside AdminTrackCasePage's own single SingleChildScrollView
/// (see build()'s doc comment), not in its own ListView/Expanded, so the
/// status timeline, community reports, and Messages all share one scroll
/// gesture with the transporter card and map above them instead of
/// competing nested scroll regions.
class _AdminTrackingTab extends StatefulWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final bool transporterHasReachedClinic;
  final bool isProceedingToTreatment;
  final VoidCallback onProceedToTreatment;
  final VoidCallback onFastForward;
  final bool isIntakeMode;
  final bool hasReceivedIntake;
  final VoidCallback onConfirmAnimalReceived;
  /// True for an animal-record medical admission (see
  /// RescueCaseRepository.createAdmissionCase / data['sourceType']) —
  /// suppresses CommunityReportsSection, which only makes sense for a
  /// community-submitted rescue report. Reporter-facing messaging already
  /// doesn't render anywhere on this admin screen regardless, so nothing
  /// else needs hiding here.
  final bool hideCommunityContent;

  const _AdminTrackingTab({
    required this.statusHistory,
    required this.caseId,
    required this.messageController,
    required this.onSend,
    required this.transporterHasReachedClinic,
    required this.isProceedingToTreatment,
    required this.onProceedToTreatment,
    this.hideCommunityContent = false,
    required this.onFastForward,
    required this.isIntakeMode,
    required this.hasReceivedIntake,
    required this.onConfirmAnimalReceived,
  });

  @override
  State<_AdminTrackingTab> createState() => _AdminTrackingTabState();
}

class _AdminTrackingTabState extends State<_AdminTrackingTab> {
  // Collapsed by default so the status timeline above is readable without
  // the message composer taking most of the screen — independent of the
  // transporter card's own collapse state, no scroll-position involved
  // here, just a direct tap toggle.
  bool _messagesExpanded = false;

  Widget _buildTimelineItem(int index) {
    final statusHistory = widget.statusHistory;
    final item = statusHistory[index];
    final isLast = index == statusHistory.length - 1;
    final ts = item['timestamp'] as Timestamp?;
    final timeStr = ts != null
        ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
        : '';
    final dateStr = ts != null
        ? 'February ${ts.toDate().day}, ${ts.toDate().year}'
        : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20, height: 20,
              decoration: BoxDecoration(
                color: isLast
                    ? AppColors.textPrimary
                    : AppColors.slaterspwn,
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.textPrimary, width: 2),
              ),
              child: isLast
                  ? const Icon(Icons.check,
                  size: 12, color: Colors.white)
                  : null,
            ),
            if (index < statusHistory.length - 1)
              Container(
                  width: 2, height: 40,
                  color: AppColors.textPrimary),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(item['status'] ?? '',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          color: AppColors.textPrimary)),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(timeStr,
                        style: GoogleFonts.zain(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                    Text(dateStr,
                        style: GoogleFonts.zain(
                            fontSize: 11,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusHistory = widget.statusHistory;
    return Column(
      children: [
        // Status timeline + community reports — same subcollection/section
        // widget the Rescue Details page uses, reused here rather than a
        // second implementation. Community reports (and, further down,
        // original case media/reporter content) are reporter-facing and
        // stay out of intake transport, which is restricted to the
        // organization + assigned transporter. No longer its own ListView —
        // this is now part of the page's single outer scroll (see the
        // class doc comment).
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              for (var i = 0; i < statusHistory.length; i++) _buildTimelineItem(i),
              const SizedBox(height: 8),
              if (!widget.isIntakeMode && !widget.hideCommunityContent) CommunityReportsSection(caseId: widget.caseId),
              const SizedBox(height: 8),
            ],
          ),
        ),

        /* todo for manual testing
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demo Controls',
                  style: GoogleFonts.zain(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _DemoButton(
                    label: 'Transporter Accepted',
                    caseId: caseId,
                    status: 'Pet Transporter has been assigned, in transit to pick up location.',
                  ),
                  _DemoButton(
                    label: 'Reached Animal',
                    caseId: caseId,
                    status: 'Pet Transporter has reached the animal.',
                  ),
                ],
              ),
            ],
          ),
        ),
        */

        const Divider(),

        // Collapsible Messages — collapsed by default so the status
        // timeline above is readable without the composer taking most of
        // the screen. A single StreamBuilder always stays mounted here
        // (never conditionally created/destroyed by the collapse toggle),
        // so expanding/collapsing never disposes or duplicates the
        // messages listener — see the class doc comment.
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('cases')
              .doc(widget.caseId)
              .collection('messages')
              .orderBy('timestamp')
              .snapshots(),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final count = docs.length;
            final summary = count == 0 ? 'No messages yet' : '$count message${count == 1 ? '' : 's'}';

            return Column(
              children: [
                InkWell(
                  onTap: () => setState(() => _messagesExpanded = !_messagesExpanded),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Messages',
                            style: GoogleFonts.zain(
                                fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        Row(
                          children: [
                            Text(summary,
                                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                            const SizedBox(width: 4),
                            Icon(
                              _messagesExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (_messagesExpanded) ...[
                  SizedBox(
                    height: 200,
                    child: docs.isEmpty
                        ? Center(
                            child: Text('No messages yet.',
                                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: docs.length,
                            itemBuilder: (context, i) {
                              final msg = docs[i].data() as Map<String, dynamic>;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 12,
                                      backgroundColor: AppColors.slaterspwn,
                                      child: Text((msg['senderName'] ?? 'U')[0],
                                          style: GoogleFonts.zain(fontSize: 10)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${msg['senderName']}: ${msg['text']}',
                                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: widget.messageController,
                            decoration: InputDecoration(
                              hintText: 'Type a message',
                              hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: const BorderSide(color: AppColors.slaterspwn),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(50),
                                borderSide: const BorderSide(color: AppColors.textPrimary),
                              ),
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: widget.onSend,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: AppColors.yellowrspwn,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.send, size: 18, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),

        // Intake transport's own confirmation action, replacing the
        // rescue-pickup "Proceed to Treatment"/fast-forward controls
        // entirely — arriving at the shelter doesn't move the case past
        // Intake, it just unlocks quarantine/animal-record steps back on
        // Intake Details (see RescueCaseRepository.confirmAnimalReceived).
        if (widget.isIntakeMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: widget.hasReceivedIntake
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.greenrspwn.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Center(
                      child: Text('Animal received at the shelter.',
                          style: GoogleFonts.zain(
                              fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ),
                  )
                : ElevatedButton(
                    onPressed: widget.onConfirmAnimalReceived,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      minimumSize: const Size(double.infinity, 48),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: Text('Confirm Animal Received',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
          )
        // Proceed to Treatment — only enabled once the transporter has
        // actually reached the clinic (status 'dropoff'/'in_transit_shelter').
        // Before that, show a fast-forward control for testing without GPS.
        else if (widget.transporterHasReachedClinic)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: ElevatedButton(
              onPressed: widget.isProceedingToTreatment ? null : widget.onProceedToTreatment,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                disabledBackgroundColor: AppColors.slaterspwn,
                minimumSize: const Size(double.infinity, 48),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: widget.isProceedingToTreatment
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                  : Text('Proceed to Treatment',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              children: [
                Text(
                  'Waiting for the transporter to reach the clinic…',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: widget.onFastForward,
                  icon: const Icon(Icons.fast_forward, size: 18),
                  label: Text('Fast-forward to Clinic (Test)',
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    side: const BorderSide(color: AppColors.slaterspwn),
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AdminCaseDetailTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AdminCaseDetailTab({required this.data});

  @override
  Widget build(BuildContext context) {
    // No longer its own SingleChildScrollView — this is now part of
    // AdminTrackCasePage's single outer scroll (see _AdminTrackingTab's
    // class doc comment for why nested independent scroll regions were
    // removed).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('Reporter Name', data['reporterName']),
          _Row('Reporter Mobile Number', data['reporterPhone']),
          _Row('Pet Transporter Name', data['assignedVolunteerName']),
          _Row('Pet Transporter Mobile Number', '-'),
          _Row('Address', data['address']),
          _Row('Description', data['condition']),
          _Row('Type of Animal', data['animalType']),
          _Row('Urgency', data['urgency']),
          _Row('Coordination', data['coordinateWithShelter']),
          if (data['coordinateWithShelter'] == 'no') ...[
            _Row('Witness Name', data['witnessName']),
            _Row('Witness Mobile Number', data['witnessPhone']),
          ],
          _Row('Interest to adopt', data['interestedToAdopt']),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          Text(value ?? '-',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Inline replacement for what used to be a separate "Pending Transporter
/// Response" page — same Track Case page/route, just swapped in where the
/// map normally renders. In the normal flow this is never actually seen
/// (the Assign Transporter modal already carries the admin through
/// Pending before Track Case opens); it only surfaces if the case is
/// reopened while an offer is still outstanding.
/// Wraps the existing TransporterDetailsCard (expanded state, unchanged
/// look) with a compact collapsed row for when the admin has scrolled the
/// tracking content down — see AdminTrackCasePage._handleScroll for what
/// drives [collapsed]. Both states watch the same
/// transporterProfileProvider family key (uid/name/type/isDemo), so
/// toggling between them never causes a second fetch — Riverpod keeps that
/// provider's cached value alive as long as either widget is watching it,
/// and one of them always is. [assignment] itself is passed down unchanged
/// from the single currentAssignmentProvider watch at the top of
/// AdminTrackCasePage.build() — collapsing/expanding is pure local visual
/// state, never a new stream subscription.
class _CollapsibleTransporterCard extends StatelessWidget {
  final TransportAssignment assignment;
  final bool collapsed;
  final VoidCallback onToggle;
  final VoidCallback? onMessage;

  const _CollapsibleTransporterCard({
    required this.assignment,
    required this.collapsed,
    required this.onToggle,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: collapsed
          ? _CompactTransporterRow(assignment: assignment, onTap: onToggle)
          : Column(
              children: [
                TransporterDetailsCard(assignment: assignment, onMessage: onMessage),
                GestureDetector(
                  onTap: onToggle,
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Icon(Icons.keyboard_arrow_up, size: 18, color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Collapsed-state row: `[avatar] Name · Vehicle    Status ▼`. Tapping
/// anywhere expands the card again (see _CollapsibleTransporterCard).
class _CompactTransporterRow extends ConsumerWidget {
  final TransportAssignment assignment;
  final VoidCallback onTap;
  const _CompactTransporterRow({required this.assignment, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(transporterProfileProvider((
      uid: assignment.riderId,
      fallbackName: assignment.riderName,
      type: assignment.riderType,
      isDemo: assignment.isDemo,
    )));
    final profile = profileAsync.asData?.value ??
        TransporterProfile(
          uid: assignment.riderId,
          name: assignment.riderName,
          type: assignment.riderType,
          vehicle: 'Not provided',
          plate: 'Not provided',
          isDemo: assignment.isDemo,
        );

    final isCompleted = assignment.status == TransportAssignmentStatus.completed;
    final chipLabel = isCompleted ? 'Completed' : 'Busy';
    final chipColor = isCompleted ? AppColors.slaterspwn : AppColors.yellowrspwn;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (profile.photoUrl != null && profile.photoUrl!.isNotEmpty)
                  ? Image.network(profile.photoUrl!,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          width: 32, height: 32, color: AppColors.tearspwn,
                          child: const Icon(Icons.directions_car, size: 16, color: AppColors.textSecondary)))
                  : Container(
                      width: 32,
                      height: 32,
                      color: AppColors.tearspwn,
                      child: const Icon(Icons.directions_car, size: 16, color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${profile.name} · ${profile.vehicle}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(20)),
              child: Text(chipLabel,
                  style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _PendingAssignmentBanner extends StatelessWidget {
  final TransportAssignment assignment;
  final Map<String, dynamic> caseData;
  const _PendingAssignmentBanner({required this.assignment, required this.caseData});

  @override
  Widget build(BuildContext context) {
    final clinicName = caseData['vetClinicName'] as String?;
    return Container(
      height: 180,
      color: AppColors.slaterspwn,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
                width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(height: 10),
            Text(assignment.riderName,
                style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(
              clinicName != null && clinicName.isNotEmpty
                  ? 'Waiting for the transporter to respond… · $clinicName'
                  : 'Waiting for the transporter to respond…',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline replacement for what used to be a separate "Rider Rejected"
/// page — same Track Case page/route, swapped in where the map normally
/// renders. The rescue case itself was never marked rejected, only this
/// transporter's offer was, so the case is already assignable again;
/// "Choose Another Transporter" just returns to Rescue Details, where
/// "Assign Transporter" is available once more.
class _DeclinedAssignmentBanner extends StatelessWidget {
  final TransportAssignment assignment;
  final VoidCallback onChooseAnother;
  const _DeclinedAssignmentBanner({required this.assignment, required this.onChooseAnother});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: AppColors.slaterspwn,
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cancel_outlined, size: 28, color: Color(0xFFE05353)),
            const SizedBox(height: 8),
            Text('${assignment.riderName} declined the assignment.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(assignment.rejectionReason ?? 'No reason given',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onChooseAnother,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary),
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: Text('Choose Another Transporter',
                  style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

/* TODO: demo button
class _DemoButton extends StatelessWidget {
  final String label;
  final String caseId;
  final String status;
  const _DemoButton({required this.label, required this.caseId, required this.status});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        await FirebaseFirestore.instance
            .collection('cases')
            .doc(caseId)
            .update({
          'statusHistory': FieldValue.arrayUnion([
            {'status': status, 'timestamp': Timestamp.now()}
          ]),
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.slaterspwn),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
    );
  }
}
*/
