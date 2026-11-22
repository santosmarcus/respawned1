import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:respawnd1/features/rescue/widgets/surrender_withdrawal_section.dart';
import 'package:respawnd1/features/rescue/widgets/litter_report_link.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:respawnd1/core/utils/rescue_progress.dart';
import 'package:respawnd1/core/widgets/progress_timeline.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:respawnd1/features/rescue/widgets/case_report_details.dart';
import 'package:respawnd1/core/models/rescue/rescue_adoption.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/rescue/rescue_adoption_form_page.dart';
import 'package:respawnd1/core/utils/case_access.dart';
import 'package:respawnd1/core/utils/public_case_status.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/case_completed_page.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/core/models/rescue/route_result.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/features/rescue/widgets/community_report_section.dart';
import 'package:respawnd1/features/rescue/widgets/live_proof_request_card.dart';
import 'package:respawnd1/features/rescue/widgets/independent_report_section.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/features/rescue/widgets/case_chat.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';

// Case statuses written once the pet transporter has verified pickup and
// has the animal (see transit_rules.dart for what each one means).
// Community reports are closed from here on.
const _kPickedUpStatuses = {
  'treatment',
  'dropoff',
  'searching_clinic',
  'in_transit_shelter',
  'awaiting_adopter_pickup',
  'in_treatment',
  'intake',
  'completed',
  'closed',
  'adopted',
};

bool _isAnimalPickedUp(Map<String, dynamic> data) {
  final status = (data['status'] as String?) ?? '';
  final pickupPhotos = data['pickupVerificationUrls'];
  return _kPickedUpStatuses.contains(status) ||
      (pickupPhotos is List && pickupPhotos.isNotEmpty);
}

/// The leg the transporter is currently driving, or null when they're not
/// moving (waiting, arrived, at the clinic, done, ...). Used by both the
/// map route and the status bar so they always agree.
class _TransitLeg {
  final LatLng destination;
  final String subtitle;
  const _TransitLeg(this.destination, this.subtitle);
}

LatLng? _latLngOf(Map<String, dynamic> data, String latKey, String lngKey) {
  final lat = data[latKey];
  final lng = data[lngKey];
  if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
  return null;
}

String? _firstText(Map<String, dynamic> data, List<String> keys) {
  for (final k in keys) {
    final v = (data[k] as String?)?.trim();
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

_TransitLeg? _currentTransitLeg(Map<String, dynamic> data) {
  final status = (data['status'] as String?) ?? '';
  LatLng? dest;
  String label;
  String? place;
  switch (status) {
    case 'ongoing': // on the way to the pick up location
      dest = _latLngOf(data, 'lat', 'lng');
      label = 'To the pick up location';
      place = _firstText(data, ['address']);
    case 'treatment': // animal picked up, on the way to the clinic
      dest =
          _latLngOf(data, 'dropoffLat', 'dropoffLng') ??
              _latLngOf(data, 'vetClinicLat', 'vetClinicLng');
      label = 'To the clinic';
      place = _firstText(data, [
        'dropoffName',
        'vetClinicName',
        'dropoffAddress',
        'vetClinicAddress',
      ]);
    case 'in_transit_shelter': // on the way to the shelter
      dest = _latLngOf(data, 'shelterLat', 'shelterLng');
      label = 'To the shelter';
      place = _firstText(data, ['shelterName', 'shelterAddress']);
    default:
      return null;
  }
  if (dest == null) return null;
  return _TransitLeg(dest, place == null ? label : '$label · $place');
}

/// One road route request shared by the map and the status bar, so both
/// show the same Directions API route and it's only fetched once per
/// rider position.
class _SharedRouteLoader {
  final _repo = DirectionsRepository();
  Future<RouteResult>? _future;
  LatLng? _origin;
  LatLng? _destination;

  Future<RouteResult> load(LatLng origin, LatLng destination) {
    if (_future != null && _origin == origin && _destination == destination) {
      return _future!;
    }
    _origin = origin;
    _destination = destination;
    return _future = _repo.fetchRoute(origin: origin, destination: destination);
  }
}

class TrackCasePage extends StatefulWidget {
  final String caseId;
  final int initialTabIndex;
  const TrackCasePage({
    super.key,
    required this.caseId,
    this.initialTabIndex = 0,
  });

  @override
  State<TrackCasePage> createState() => _TrackCasePageState();
}

class _TrackCasePageState extends State<TrackCasePage> {
  late int _tabIndex = widget.initialTabIndex;
  bool _mapExpanded = false;
  final _messageController = TextEditingController();
  final _routeLoader = _SharedRouteLoader();
  final _messageFocusNode = FocusNode();

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String caseId) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final fullName =
    '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
        .trim();
    // Accounts without first/last name (e.g. Google sign-in) fall back to
    // their account name so the organization sees who wrote.
    final authName = FirebaseAuth.instance.currentUser?.displayName?.trim() ?? '';
    final name = fullName.isNotEmpty
        ? fullName
        : (authName.isNotEmpty ? authName : 'Reporter');

    await FirebaseFirestore.instance
        .collection('cases')
        .doc(caseId)
        .collection('messages')
        .add({
      'senderId': uid,
      'senderName': name,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
  }

  void _focusOrgMessages() {
    setState(() => _tabIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _messageFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    // People not working the case (e.g. opened from Nearby Reports) see
    // the public copy.
    return StreamBuilder<DocumentSnapshot>(
      stream: watchCaseOrPublic(widget.caseId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final status = data?['status'] ?? 'pending';
        // True when the viewer can read the full case (reporter, willing
        // adopter, staff, the transporter). Everyone else only gets the
        // public copy: no status history, transporter or live location.
        final hasFullAccess = snapshot.data!.reference.parent.id == 'cases';
        final statusHistory = List<Map<String, dynamic>>.from(
          data?['statusHistory'] ?? [],
        );
        // The public copy has no history; show the current status instead
        // of "No status updates yet."
        if (statusHistory.isEmpty && !hasFullAccess && data != null) {
          statusHistory.add({
            'status': publicCaseStatusLabel(data['status'] as String?),
          });
        }
        final isReporter =
            FirebaseAuth.instance.currentUser?.uid != null &&
                FirebaseAuth.instance.currentUser?.uid == data?['reporterId'];

        final normalizedStatus = status.toString().toLowerCase();
        // 'transit_ended' (and legacy 'ended') is not final: the
        // transporter stopped, and staff still decide the next step.
        final isFinalStatus =
            normalizedStatus == 'closed' ||
                normalizedStatus.contains('completed');

        // A rejected report gets the same one-time success/acknowledgment
        // screen as a closed/completed case — but only until the reporter
        // has actually acknowledged it (tapped Close there, which sets
        // hiddenFromExplore, same flag CaseSummaryPage._close already
        // uses). After that, re-opening it from History goes straight to
        // the normal read-only Track Case view below instead of looping
        // back to this screen every time.
        final isUnacknowledgedRejection =
            normalizedStatus == 'rejected' &&
                data?['hiddenFromExplore'] != true;

        if (isReporter && (isFinalStatus || isUnacknowledgedRejection)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    CaseCompletedPage(caseId: widget.caseId, caseData: data!),
              ),
            );
          });
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Track Case',
              style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary),
            ),
            centerTitle: true,
          ),
          body: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                height: _mapExpanded ? 412 : 232,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: 32,
                      child: _TrackCaseMap(
                        caseId: widget.caseId,
                        data: data ?? {},
                        routeLoader: _routeLoader,
                      ),
                    ),
                    // Expand the map for a closer look; collapse to get the
                    // case details back on screen.
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        elevation: 2,
                        child: IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: _mapExpanded ? 'Collapse map' : 'Expand map',
                          icon: Icon(
                            _mapExpanded ? Icons.fullscreen_exit : Icons.fullscreen,
                            color: AppColors.textPrimary,
                          ),
                          onPressed: () => setState(() => _mapExpanded = !_mapExpanded),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 0,
                      child: hasFullAccess
                          ? _TransitStatusBar(
                        caseId: widget.caseId,
                        data: data ?? {},
                        routeLoader: _routeLoader,
                      )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              // Bottom panel
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Tab switcher
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          children: [
                            _TabButton(
                              label: 'Tracking Detail',
                              selected: _tabIndex == 0,
                              onTap: () => setState(() => _tabIndex = 0),
                            ),
                            _TabButton(
                              label: 'Case Detail',
                              selected: _tabIndex == 1,
                              onTap: () => setState(() => _tabIndex = 1),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Case ID
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '#${widget.caseId.substring(0, 7).toUpperCase()}',
                            style: GoogleFonts.tiltWarp(
                              fontSize: 18,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),

                      // Pet transporter details (name, plate, vehicle),
                      // right under the tracking number. Shown to everyone
                      // who can read the full case; the public copy has no
                      // transporter details.
                      if (hasFullAccess)
                        _TransporterHeaderCard(caseId: widget.caseId),

                      const SizedBox(height: 12),

                      // Tab content
                      Expanded(
                        child: _tabIndex == 0
                            ? _TrackingTab(
                          statusHistory: statusHistory,
                          caseId: widget.caseId,
                          messageController: _messageController,
                          messageFocusNode: _messageFocusNode,
                          onSend: () => _sendMessage(widget.caseId),
                          data: data ?? {}, // ADDED
                          isReporter: isReporter,
                        )
                            : _CaseDetailTab(
                          caseId: widget.caseId,
                          data: data ?? {},
                          isReporter: isReporter,
                          onMessageOrg: _focusOrgMessages,
                        ),
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
}

// Tab button widget
class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TrackCaseMap extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final _SharedRouteLoader routeLoader;
  const _TrackCaseMap({
    required this.caseId,
    required this.data,
    required this.routeLoader,
  });

  @override
  State<_TrackCaseMap> createState() => _TrackCaseMapState();
}

class _TrackCaseMapState extends State<_TrackCaseMap> {
  GoogleMapController? _controller;
  bool _centered = false;

  LatLng? _latLngFrom(Map<String, dynamic> data, String latKey, String lngKey) {
    final lat = data[latKey];
    final lng = data[lngKey];
    if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pickup = _latLngFrom(widget.data, 'lat', 'lng');
    final dropoff = _latLngFrom(widget.data, 'dropoffLat', 'dropoffLng');
    final riderLastKnown = _latLngFrom(
      widget.data,
      'riderLastLat',
      'riderLastLng',
    );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('communityReports')
          .where('approvalStatus', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, reportsSnapshot) {
        final proposedLocations =
            reportsSnapshot.data?.docs.where((doc) {
              final data = doc.data();
              return data['type'] == 'moved' &&
                  data['newLat'] is num &&
                  data['newLng'] is num;
            }).toList() ??
                <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('cases')
              .doc(widget.caseId)
              .collection('tracking')
              .orderBy('timestamp')
              .limitToLast(200)
              .snapshots(),
          builder: (context, snapshot) {
            final trail = <LatLng>[];
            if (snapshot.hasData) {
              for (final doc in snapshot.data!.docs) {
                final d = doc.data() as Map<String, dynamic>;
                final lat = d['lat'];
                final lng = d['lng'];
                if (lat is num && lng is num) {
                  trail.add(LatLng(lat.toDouble(), lng.toDouble()));
                }
              }
            }

            final riderPos = trail.isNotEmpty ? trail.last : riderLastKnown;

            final center =
                riderPos ??
                    pickup ??
                    dropoff ??
                    const LatLng(14.5416, 121.0644);

            if (_controller != null && riderPos != null && !_centered) {
              _centered = true;
              _controller!.animateCamera(
                CameraUpdate.newLatLngZoom(riderPos, 15),
              );
            }

            final markers = <Marker>{
              if (pickup != null)
                Marker(
                  markerId: const MarkerId('pickup'),
                  position: pickup,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen,
                  ),
                  infoWindow: const InfoWindow(title: 'Pickup location'),
                ),
              if (dropoff != null)
                Marker(
                  markerId: const MarkerId('dropoff'),
                  position: dropoff,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed,
                  ),
                  infoWindow: const InfoWindow(title: 'Drop-off location'),
                ),
              if (riderPos != null)
                Marker(
                  markerId: const MarkerId('rider_current'),
                  position: riderPos,
                  infoWindow: const InfoWindow(title: 'Transporter'),
                ),
              for (final report in proposedLocations)
                Marker(
                  markerId: MarkerId('proposed_location_${report.id}'),
                  position: LatLng(
                    (report.data()['newLat'] as num).toDouble(),
                    (report.data()['newLng'] as num).toDouble(),
                  ),
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueOrange,
                  ),
                  infoWindow: InfoWindow(
                    title: 'Proposed location — awaiting approval',
                    snippet: report.data()['newAddress'] as String?,
                  ),
                ),
            };

            // Road route from the Google Directions API, from the
            // transporter's live position to where they're heading now.
            // Only drawn while they're actually travelling.
            final leg = _currentTransitLeg(widget.data);
            if (leg != null) {
              markers.add(
                Marker(
                  markerId: const MarkerId('current_destination'),
                  position: leg.destination,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure,
                  ),
                  infoWindow: InfoWindow(title: leg.subtitle),
                ),
              );
            }
            final routeFuture = (leg != null && riderPos != null)
                ? widget.routeLoader.load(riderPos, leg.destination)
                : null;

            return FutureBuilder<RouteResult>(
              future: routeFuture,
              builder: (context, routeSnapshot) {
                final route = routeFuture == null ? null : routeSnapshot.data;
                final routePoints = route?.polylinePoints ?? const <LatLng>[];
                return ClipRRect(
                  borderRadius: BorderRadius.zero,
                  child: GoogleMap(
                    onMapCreated: (ctrl) => _controller = ctrl,
                    initialCameraPosition: CameraPosition(
                      target: center,
                      zoom: 14,
                    ),
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    markers: markers,
                    polylines: routePoints.length < 2
                        ? {}
                        : {
                      Polyline(
                        polylineId: const PolylineId('route'),
                        points: routePoints,
                        color: AppColors.success,
                        width: 5,
                      ),
                    },
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

/// "Transporter is on the way · 6 min" bar over the bottom of the map
/// (replaces the old "# km away" card). Only shown while the transporter is
/// travelling to the pick up location, the clinic, or the shelter.
class _TransitStatusBar extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final _SharedRouteLoader routeLoader;
  const _TransitStatusBar({
    required this.caseId,
    required this.data,
    required this.routeLoader,
  });

  String _formatDuration(Duration d) {
    final totalMinutes = (d.inSeconds / 60).round();
    if (totalMinutes < 1) return '<1 min';
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  String _formatDistance(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
  }

  @override
  Widget build(BuildContext context) {
    final leg = _currentTransitLeg(data);
    if (leg == null) return const SizedBox.shrink();
    final riderLastKnown = _latLngOf(data, 'riderLastLat', 'riderLastLng');

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('tracking')
          .orderBy('timestamp')
          .limitToLast(1)
          .snapshots(),
      builder: (context, snapshot) {
        LatLng? riderPos = riderLastKnown;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final d = snapshot.data!.docs.last.data() as Map<String, dynamic>;
          final lat = d['lat'];
          final lng = d['lng'];
          if (lat is num && lng is num) {
            riderPos = LatLng(lat.toDouble(), lng.toDouble());
          }
        }
        final routeFuture = riderPos == null
            ? null
            : routeLoader.load(riderPos, leg.destination);

        return FutureBuilder<RouteResult>(
          future: routeFuture,
          builder: (context, routeSnapshot) {
            final route = routeSnapshot.data;
            final eta = route?.duration;
            final km = route?.distanceKm;
            final etaText = [
              if (eta != null) _formatDuration(eta),
              if (km != null) _formatDistance(km),
            ].join(' · ');
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Transporter is on the way',
                          style: GoogleFonts.tiltWarp(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          leg.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (etaText.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      etaText,
                      style: GoogleFonts.tiltWarp(
                        fontSize: 16,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Pet transporter details under the tracking number: avatar, name and
/// type on the left, plate number and vehicle on the right, plus a call
/// button. Only shown once a transporter has accepted the assignment.
class _TransporterHeaderCard extends ConsumerWidget {
  final String caseId;
  const _TransporterHeaderCard({required this.caseId});

  Future<void> _call(BuildContext context, String phone) async {
    final launched = await launchUrl(
      Uri(scheme: 'tel', path: phone),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(appSnackBar('Could not start the call.'));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignment = ref
        .watch(currentAssignmentProvider(caseId))
        .asData
        ?.value;
    final show =
        assignment != null &&
            (assignment.status == TransportAssignmentStatus.accepted ||
                assignment.status == TransportAssignmentStatus.completed);
    if (!show) return const SizedBox.shrink();

    final profile = ref
        .watch(
      transporterProfileProvider((
      uid: assignment.riderId,
      fallbackName: assignment.riderName,
      type: assignment.riderType,
      isDemo: assignment.isDemo,
      )),
    )
        .asData
        ?.value;

    final name = profile?.name ?? assignment.riderName;
    final type = profile?.type ?? assignment.riderType;
    final plate = profile?.plate ?? assignment.plate ?? 'No plate';
    final vehicle =
        profile?.vehicle ?? assignment.vehicle ?? 'Vehicle not provided';
    final photoUrl = profile?.photoUrl;
    final phone = profile?.phone?.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.slaterspwn,
            backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                ? NetworkImage(photoUrl)
                : null,
            child: (photoUrl == null || photoUrl.isEmpty)
                ? const Icon(Icons.person, color: AppColors.textSecondary)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  plate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.tiltWarp(
                    fontSize: 17,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  vehicle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: (phone == null || phone.isEmpty)
                ? 'No phone number on file'
                : 'Call $name',
            onPressed: (phone == null || phone.isEmpty)
                ? null
                : () => _call(context, phone),
            icon: const Icon(Icons.phone_outlined),
            color: AppColors.textPrimary,
            style: IconButton.styleFrom(
              side: const BorderSide(color: AppColors.slaterspwn),
            ),
          ),
        ],
      ),
    );
  }
}

// Tracking detail tab
class _TrackingTab extends StatefulWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final FocusNode? messageFocusNode;
  final VoidCallback onSend;
  final Map<String, dynamic> data;
  final bool isReporter;

  const _TrackingTab({
    required this.statusHistory,
    required this.caseId,
    required this.messageController,
    this.messageFocusNode,
    required this.onSend,
    required this.data,
    required this.isReporter,
  });

  @override
  State<_TrackingTab> createState() => _TrackingTabState();
}

class _TrackingTabState extends State<_TrackingTab> {
  bool _trackingExpanded = true;
  bool _messagesExpanded = true;

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _formatDate(DateTime d) {
    const months = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(
      BuildContext context,
      String title,
      List<String> urls,
      ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: urls.isEmpty
                ? Text(
              'Not available yet.',
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            )
                : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: urls.map((url) {
                return GestureDetector(
                  onTap: () => _showFullImage(context, url),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppColors.slaterspwn,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: CircularProgressIndicator(
                              value: progress.expectedTotalBytes != null
                                  ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                                  : null,
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, _, _) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // Displayed newest-first (see build() below) — [displayIndex] indexes
  // into that reversed list, so index 0 is always the most recent update
  // and gets the checkmark, matching "latest update at the top" spec.
  Widget _buildTimelineItem(
      List<Map<String, dynamic>> displayList,
      int displayIndex,
      ) {
    final item = displayList[displayIndex];
    final isNewest = displayIndex == 0;
    final ts = item['timestamp'];
    final date = ts is Timestamp ? ts.toDate() : null;
    final timeStr = date != null ? _formatTime(date) : '';
    final dateStr = date != null ? _formatDate(date) : '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.textPrimary, width: 2),
              ),
              child: isNewest
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (displayIndex < displayList.length - 1)
              Container(width: 2, height: 40, color: AppColors.textPrimary),
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
                  child: Text(
                    item['status'] ?? '',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      timeStr,
                      style: GoogleFonts.zain(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: GoogleFonts.zain(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _collapsibleHeader({
    required String title,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: onToggle,
        behavior: HitTestBehavior.opaque,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }

  // Everything (tracking timeline, community reports, org messages, and
  // the message input) lives in ONE ListView instead of the previous
  // Column([Expanded(ListView), fixed-height messages block]) — that split
  // meant the messages header/list/input had a non-shrinkable minimum
  // height that didn't fit once the keyboard ate most of the remaining
  // space below the fixed 232px map, producing "BOTTOM OVERFLOWED BY 146
  // PIXELS". A single scrollable never overflows regardless of available
  // height, and a focused TextField inside it is auto-scrolled above the
  // keyboard by Flutter's own EditableText behavior — so the input stays
  // reachable without resizing the map or nesting a second unbounded
  // scroll view.
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      children: [
        // The rescue team is waiting on a fresh photo from the reporter.
        if (widget.isReporter) LiveProofRequestCard(caseId: widget.caseId, data: widget.data),
        // Rescue progress: where the case is on its normal path, so the
        // current stage is clear without reading the whole history.
        if (rescueProgressFinished(widget.data['status'] as String?) case final finished?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: ProgressTimeline(
              title: 'Rescue progress',
              statusLabel: finished >= kRescueProgressSteps.length ? 'Completed' : 'In progress',
              steps: [
                for (final (i, step) in ProgressTimeline.sequence(kRescueProgressSteps, finished).indexed)
                  i == finished && rescueProgressDetail(widget.data['status'] as String?) != null
                      ? TimelineStep(step.title,
                          subtitle: rescueProgressDetail(widget.data['status'] as String?), state: step.state)
                      : step,
              ],
            ),
          ),
        _collapsibleHeader(
          title: 'Tracking Progress',
          expanded: _trackingExpanded,
          onToggle: () =>
              setState(() => _trackingExpanded = !_trackingExpanded),
        ),
        const SizedBox(height: 8),

        if (_trackingExpanded) ...[
          if (widget.statusHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
              child: Center(
                child: Text(
                  'No status updates yet.',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            )
          else
            for (int i = 0; i < widget.statusHistory.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTimelineItem(
                  widget.statusHistory.reversed.toList(),
                  i,
                ),
              ),

          const SizedBox(height: 12),
          _buildMediaSection(
            context,
            'Pickup Verification',
            List<String>.from(widget.data['pickupVerificationUrls'] ?? []),
          ),
          const SizedBox(height: 12),
          _buildMediaSection(
            context,
            'Dropoff Verification',
            List<String>.from(widget.data['dropoffVerificationUrls'] ?? []),
          ),
        ],
        const SizedBox(height: 16),

        // Community Reports — visible to the reporter (for
        // situational awareness) and to every other user (who can
        // submit sighting reports to help verify/update the case).
        CommunityReportSection(
          caseId: widget.caseId,
          canSubmit: !_isAnimalPickedUp(widget.data),
        ),
        const SizedBox(height: 8),
        const Divider(color: AppColors.slaterspwn),

        // Messages to the Organization — reporter-only private channel.
        if (widget.isReporter) ...[
          _collapsibleHeader(
            title: 'Messages to the Organization',
            expanded: _messagesExpanded,
            onToggle: () =>
                setState(() => _messagesExpanded = !_messagesExpanded),
          ),

          if (_messagesExpanded) ...[
            // The same chat as the organization's (CaseChat): suggested
            // replies, sharing the animal's location, and confirming what
            // other community members reported.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: CaseChat(caseId: widget.caseId, staff: false, maxListHeight: 360),
            ),
          ] else
            const SizedBox(height: 12),
        ],
      ],
    );
  }
}

// Case detail tab
class _CaseDetailTab extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final bool isReporter;
  final VoidCallback? onMessageOrg;
  const _CaseDetailTab({
    required this.caseId,
    required this.data,
    required this.isReporter,
    this.onMessageOrg,
  });

  @override
  State<_CaseDetailTab> createState() => _CaseDetailTabState();
}

class _CaseDetailTabState extends State<_CaseDetailTab> {
  bool _isSubmitting = false;
  bool _isMarkingArrival = false;

  Map<String, dynamic> get data => widget.data;

  bool get _hasWillingAdopter {
    final reporterWantsToAdopt = data['interestedToAdopt'] == 'yes';
    final willingAdopterId = data['willingAdopterId'] as String?;
    return reporterWantsToAdopt ||
        (willingAdopterId != null && willingAdopterId.isNotEmpty);
  }

  Future<void> _registerInterest(String type) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() => _isSubmitting = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data();
      final name =
      '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
          .trim();


      await RescueCaseStore(FirebaseFirestore.instance).recordAction(
        caseId: widget.caseId,
        action: 'adoption_interest_registered',
        statusLine: '${name.isEmpty ? 'A general user' : name} expressed interest to adopt the animal you reported.',
        details: {'type': type},
        fields: {
          'willingAdopterId': uid,
          'willingAdopterName': name.isEmpty ? 'A general user' : name,
          'willingAdopterType': type,
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Failed to register interest: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _markArrivedAtTreatment() async {
    setState(() => _isMarkingArrival = true);
    try {
      await RescueCaseStore(FirebaseFirestore.instance).recordAction(
        caseId: widget.caseId,
        action: 'adopter_arrived_at_treatment',
        statusLine: 'Interested adopter reported arrival at the treatment location.',
        fields: {'adopterArrivedAtTreatment': true},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Thanks! Let the transporter know you\'re there in person.', kind: AppMessageKind.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Failed to update: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isMarkingArrival = false);
    }
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(
      BuildContext context,
      String title,
      List<String> urls,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.zain(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: urls.isEmpty
              ? Text(
            'Not available yet.',
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          )
              : Wrap(
            spacing: 12,
            runSpacing: 12,
            children: urls.map((url) {
              return GestureDetector(
                onTap: () => _showFullImage(context, url),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    url,
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                                : null,
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, _, _) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.slaterspwn,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Full rejection detail (reason, rejected date, reviewer) lives
          // here rather than on the compact Home Activity card — see
          // activity_card.dart's rejected-chip comment.
          if ((data['status'] as String?) == 'rejected')
            _RejectionDetailsSection(caseId: widget.caseId, data: data),

          // At a glance: photo, case number, urgency, animal, when and by
          // whom it was reported.
          _CaseSummaryCard(caseId: widget.caseId, data: data),
          const SizedBox(height: 12),

          // Case media
          _buildMediaSection(
            context,
            'Report Photos',
            List<String>.from(data['photoUrls'] ?? []),
          ),
          const SizedBox(height: 16),
          // Every field from the rescue form, grouped into cards: rescue
          // details, condition, animals, location, coordination (see
          // CaseReportDetails). The address is in its Location card.
          CaseReportDetails(caseId: widget.caseId, data: data),
          const SizedBox(height: 12),

          // Reporter-led Neglect or Abuse: what was filed with the
          // authorities, the guide, and asking the organization for help.
          // Pet Surrender: withdraw (older reports still waiting in review)
          // or, once withdrawn, the reason and date.
          // Litter: linked puppy / mother reports, and "report these puppies".
          LitterReportsSection(caseId: widget.caseId, data: data),
          if (isSurrenderRescueType(data['rescueType'] as String?))
            SurrenderWithdrawalSection(caseId: widget.caseId, data: data),
          if (OrgInvolvement.fromFirestoreValue(data['orgInvolvement']) == OrgInvolvement.independentReport)
            IndependentReportSection(caseId: widget.caseId, data: data, isReporter: widget.isReporter),

          // Rescue gaps 6/10: the interested adopter sends an adoption
          // request (with the vet-fee, obligations and pickup agreements)
          // and follows it here.
          _RescueAdoptionSection(caseId: widget.caseId, data: data),

          if (widget.isReporter &&
              data['interestedToAdopt'] == 'yes' &&
              (data['status'] as String?) == 'awaiting_adopter_pickup') ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.lavenderrspwn.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['adopterArrivedAtTreatment'] == true
                        ? 'You\'ve let the transporter know you\'re there.'
                        : 'The animal is at the treatment location, ready for pickup.',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    data['adopterArrivedAtTreatment'] == true
                        ? 'The transporter will confirm once they see you in person.'
                        : 'Once you\'ve arrived in person, let the transporter know.',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed:
                      (data['adopterArrivedAtTreatment'] == true ||
                          _isMarkingArrival)
                          ? null
                          : _markArrivedAtTreatment,
                      style: AppButtons.primary,
                      child: _isMarkingArrival
                          ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                          : Text(
                        data['adopterArrivedAtTreatment'] == true
                            ? 'Arrived ✓'
                            : 'Arrived at Treatment',
                        style: GoogleFonts.zain(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Never offered to the reporter: they answered the adoption
          // question on the report form ("yes" already makes them the
          // willing adopter), and a Pet Surrender's reporter is the owner
          // giving the animal up — that form doesn't ask, so the answer
          // is blank and must not reopen the offer. Everyone else still
          // sees it.
          if (!_hasWillingAdopter && !widget.isReporter) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'This rescue is available for adoption.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _registerInterest('adopt'),
                    style: AppButtons.outline,
                    child: _isSubmitting
                        ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textPrimary,
                      ),
                    )
                        : Text(
                      'Interest to Adopt',
                      style: GoogleFonts.zain(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_hasWillingAdopter)
            _DetailRow(
              'Willing adopter',
              '${data['willingAdopterName'] ?? 'Not provided'}'
                  '${data['willingAdopterType'] != null ? ' (${data['willingAdopterType']})' : ''}',
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Full rejection detail — reason, rejected date, and reviewer — moved
/// here from the compact Home Activity chip (spec: "Show the complete
/// reason, rejected date, and reviewer details on the report details page
/// rather than expanding the Activity card"). Reason/date are read
/// straight off the case doc already in scope; reviewer name requires one
/// extra read of the case's own `activityLogs` subcollection, since
/// `rejectedBy`/`rejectedAt` aren't top-level case fields (only the
/// `rejected` activity-log entry records who acted).
class _RejectionDetailsSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _RejectionDetailsSection({required this.caseId, required this.data});

  DateTime? get _rejectedAt {
    final history = List<Map<String, dynamic>>.from(
      data['statusHistory'] ?? [],
    );
    for (final h in history) {
      final s = h['status'] as String? ?? '';
      final ts = h['timestamp'];
      if (s.startsWith('Case rejected') && ts is Timestamp) return ts.toDate();
    }
    return null;
  }

  String get _reasonLabel {
    final reason = RejectionReason.fromName(data['rejectionReason'] as String?);
    if (reason == RejectionReason.other) {
      final other = (data['rejectionReasonOther'] as String?)?.trim();
      return (other?.isNotEmpty ?? false) ? other! : 'Other';
    }
    return reason.label;
  }

  @override
  Widget build(BuildContext context) {
    final rejectedAt = _rejectedAt;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.block, size: 16, color: AppColors.error),
              const SizedBox(width: 6),
              Text(
                'Report Rejected',
                style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DetailRow('Reason', _reasonLabel),
          if (rejectedAt != null)
            _DetailRow(
              'Rejected On',
              '${rejectedAt.month}/${rejectedAt.day}/${rejectedAt.year}',
            ),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('cases')
                .doc(caseId)
                .collection('activityLogs')
                .where('action', isEqualTo: 'rejected')
                .limit(1)
                .snapshots(),
            builder: (context, snapshot) {
              final docs = snapshot.data?.docs;
              if (docs == null || docs.isEmpty) return const SizedBox.shrink();
              final reviewer = docs.first.data()['actorName'] as String?;
              if (reviewer == null || reviewer.isEmpty) {
                return const SizedBox.shrink();
              }
              return _DetailRow('Reviewed By', reviewer);
            },
          ),
        ],
      ),
    );
  }
}

/// Track Case's top card on the Case Detail tab.
class _CaseSummaryCard extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _CaseSummaryCard({required this.caseId, required this.data});

  @override
  Widget build(BuildContext context) {
    final photos = List<String>.from(data['photoUrls'] ?? const []);
    final animals = data['animals'] as List?;
    final first = animals != null && animals.isNotEmpty && animals.first is Map
        ? Map<String, dynamic>.from(animals.first as Map)
        : <String, dynamic>{'species': data['animalType'], 'breed': data['breed'], 'size': data['size']};
    final animalLine = [first['species'], first['breed'], first['size']]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    final count = animals?.length ?? 1;
    final created = data['createdAt'];
    final reportedAt = created is Timestamp ? created.toDate() : null;
    final urgency = (data['urgency'] as String?)?.trim() ?? '';
    final reporter = (data['reporterName'] as String?)?.trim() ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDAD7CC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: photos.isEmpty
                ? Container(
                    width: 72,
                    height: 72,
                    color: AppColors.tearspwn,
                    child: const Icon(Icons.pets, color: AppColors.textSecondary),
                  )
                : Image.network(
                    photos.first,
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 72,
                      height: 72,
                      color: AppColors.tearspwn,
                      child: const Icon(Icons.pets, color: AppColors.textSecondary),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Case #${caseId.length >= 7 ? caseId.substring(0, 7).toUpperCase() : caseId}',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
                      ),
                    ),
                    if (urgency.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: urgency == 'Critical'
                              ? AppColors.error
                              : urgency == 'Medium'
                                  ? AppColors.yellowrspwn
                                  : AppColors.greenrspwn,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(urgency,
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: urgency == 'Critical' ? Colors.white : AppColors.textPrimary)),
                      ),
                  ],
                ),
                if (animalLine.isNotEmpty)
                  Text(
                    count > 1 ? '$animalLine  +${count - 1} more' : animalLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                if (reportedAt != null)
                  Text(formatDateTime(reportedAt),
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                if (reporter.isNotEmpty)
                  Text('Reported by $reporter',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                // An independent rescuer took the case (never their address).
                if (data['ownerKind'] == 'independent')
                  Text('Handled by a rescue volunteer',
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            (value == null || value!.trim().isEmpty) ? 'Not provided' : value!,
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}


/// Rescue gaps 6/10 on Track Case, for the interested adopter: send the
/// adoption request, then see whether it is confirmed and when and where to
/// collect the animal.
class _RescueAdoptionSection extends StatelessWidget {
  const _RescueAdoptionSection({required this.caseId, required this.data});
  final String caseId;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final request = CaseAdoptionRequest.fromCase(data);
    final mine = request != null && request.adopterId == uid;
    final canApply = canRequestRescueAdoption(data, uid) && (request == null || (mine && !request.isOpen));
    if (!mine && !canApply) return const SizedBox.shrink();
    final pickup = AdopterPickup.fromCase(data);

    final lines = <String>[
      if (mine) 'Your adoption request: ${request.status.label}.',
      if (mine && request.closedReason != null) request.closedReason!,
      if (mine && request.isConfirmed && (pickup == null || !pickup.isWaiting) && pickup?.collectedAt == null)
        'You will be told when the animal is ready for pickup.',
      if (mine && pickup != null && pickup.isWaiting && pickup.deadline != null)
        'Ready for pickup at ${pickup.place}. Collect it by ${formatDateTime(pickup.deadline!)}, or it goes to the '
            'shelter or another organization.',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.lavenderrspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(l, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ),
          if (canApply) ...[
            Text(
              'To adopt this animal, send an adoption request. You agree to pay its vet fees, take care of it as its '
                  'adopter, and collect it within ${kAdopterPickupWindow.inHours} hours once it is ready.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primary,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => RescueAdoptionFormPage(caseId: caseId, caseData: data)),
                ),
                child: Text('Send Adoption Request', style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
