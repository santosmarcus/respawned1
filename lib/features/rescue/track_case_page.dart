import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/rescue/case_completed_page.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/core/models/rescue/route_result.dart';
import 'package:respawnd1/features/rescue/widgets/community_report_section.dart';


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
  final _messageController = TextEditingController();
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
    final name =
    '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
        .trim();

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
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final status = data?['status'] ?? 'pending';
        final statusHistory = List<Map<String, dynamic>>.from(
            data?['statusHistory'] ?? []);
        final isReporter = FirebaseAuth.instance.currentUser?.uid != null &&
            FirebaseAuth.instance.currentUser?.uid == data?['reporterId'];


        final normalizedStatus = status.toString().toLowerCase();
        final isFinalStatus = normalizedStatus == 'closed' ||
            normalizedStatus.contains('completed') ||
            normalizedStatus.contains('ended');

        if (isReporter && isFinalStatus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CaseCompletedPage(
                  caseId: widget.caseId,
                  caseData: data!,
                ),
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
            title: Text('Track Case',
                style: Theme.of(context).textTheme.displaySmall),
            centerTitle: true,
          ),
          body: Column(
            children: [
              SizedBox(
                height: 232,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 200,
                      child: _TrackCaseMap(caseId: widget.caseId, data: data ?? {}),
                    ),
                    Positioned(
                      left: 24,
                      right: 24,
                      bottom: 0,
                      child: _EtaCard(caseId: widget.caseId, data: data ?? {}),
                    ),
                  ],
                ),
              ),

              // Bottom panel
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Tab switcher
                      Container(
                        margin:
                        const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          children: [
                            _TabButton(
                              label: 'Tracking Detail',
                              selected: _tabIndex == 0,
                              onTap: () =>
                                  setState(() => _tabIndex = 0),
                            ),
                            _TabButton(
                              label: 'Case Detail',
                              selected: _tabIndex == 1,
                              onTap: () =>
                                  setState(() => _tabIndex = 1),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Case ID
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '#${widget.caseId.substring(0, 7).toUpperCase()}',
                            style: GoogleFonts.tiltWarp(
                                fontSize: 18,
                                color: AppColors.textPrimary),
                          ),
                        ),
                      ),

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
                          data: data ?? {},  // ADDED
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
  const _TrackCaseMap({required this.caseId, required this.data});

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
    final riderLastKnown =
    _latLngFrom(widget.data, 'riderLastLat', 'riderLastLng');

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

        final center = riderPos ?? pickup ?? dropoff ?? const LatLng(14.5416, 121.0644);

        if (_controller != null && riderPos != null && !_centered) {
          _centered = true;
          _controller!.animateCamera(CameraUpdate.newLatLngZoom(riderPos, 15));
        }

        final markers = <Marker>{
          if (pickup != null)
            Marker(
              markerId: const MarkerId('pickup'),
              position: pickup,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueGreen),
              infoWindow: const InfoWindow(title: 'Pickup location'),
            ),
          if (dropoff != null)
            Marker(
              markerId: const MarkerId('dropoff'),
              position: dropoff,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed),
              infoWindow: const InfoWindow(title: 'Drop-off location'),
            ),
          if (riderPos != null)
            Marker(
              markerId: const MarkerId('rider_current'),
              position: riderPos,
              infoWindow: const InfoWindow(title: 'Transporter'),
            ),
        };

        final routePoints = <LatLng>[
          if (pickup != null) pickup,
          ...trail,
          if (trail.isEmpty && dropoff != null) dropoff,
        ];

        return ClipRRect(
          borderRadius: BorderRadius.zero,
          child: GoogleMap(
            onMapCreated: (ctrl) => _controller = ctrl,
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: markers,
            polylines: routePoints.length < 2
                ? {}
                : {
              Polyline(
                polylineId: const PolylineId('route_trail'),
                points: routePoints,
                color: AppColors.textPrimary,
                width: 4,
              ),
            },
          ),
        );
      },
    );
  }
}

class _EtaCard extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _EtaCard({required this.caseId, required this.data});

  @override
  State<_EtaCard> createState() => _EtaCardState();
}

class _EtaCardState extends State<_EtaCard> {
  final _directionsRepository = DirectionsRepository();

  LatLng? _latLngFrom(Map<String, dynamic> data, String latKey, String lngKey) {
    final lat = data[latKey];
    final lng = data[lngKey];
    if (lat is num && lng is num) return LatLng(lat.toDouble(), lng.toDouble());
    return null;
  }

  String _formatDuration(Duration d) {
    final totalMinutes = (d.inSeconds / 60).round();
    if (totalMinutes < 1) return '<1 min';
    if (totalMinutes < 60) return '$totalMinutes min';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  String _formatDistance(double km) =>
      km < 10 ? '${km.toStringAsFixed(1)}km' : '${km.round()}km';

  @override
  Widget build(BuildContext context) {
    final pickup = _latLngFrom(widget.data, 'lat', 'lng');
    final dropoff = _latLngFrom(widget.data, 'dropoffLat', 'dropoffLng');
    final riderLastKnown = _latLngFrom(widget.data, 'riderLastLat', 'riderLastLng');
    final destination = dropoff ?? pickup;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
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
          if (lat is num && lng is num) riderPos = LatLng(lat.toDouble(), lng.toDouble());
        }

        if (riderPos == null || destination == null) {
          return const SizedBox.shrink();
        }

        return FutureBuilder<RouteResult>(
          future: _directionsRepository.fetchRoute(origin: riderPos, destination: destination),
          builder: (context, routeSnapshot) {
            final route = routeSnapshot.data;
            if (route == null) return const SizedBox.shrink();

            final distanceLabel = _formatDistance(route.distanceKm);
            final headline = route.duration != null
                ? '${_formatDuration(route.duration!)}   $distanceLabel away'
                : '$distanceLabel away';

            return Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    headline,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.tiltWarp(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (route.duration != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Estimated time of arrival',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(
                        fontSize: 12,
                        color: AppColors.textSecondary,
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
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
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
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
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
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(
      BuildContext context, String title, List<String> urls) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: urls.isEmpty
                ? Text(
              'Not available yet.',
              style: GoogleFonts.zain(
                  fontSize: 12, color: AppColors.textSecondary),
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
                              value: progress.expectedTotalBytes !=
                                  null
                                  ? progress.cumulativeBytesLoaded /
                                  progress.expectedTotalBytes!
                                  : null,
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, _, __) => Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textSecondary),
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
  Widget _buildTimelineItem(int index) {
    final item = widget.statusHistory[index];
    final isLast = index == widget.statusHistory.length - 1;
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
              child: isLast
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (index < widget.statusHistory.length - 1)
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
                        fontSize: 13, color: AppColors.textPrimary),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(timeStr,
                        style: GoogleFonts.zain(
                            fontSize: 11, color: AppColors.textSecondary)),
                    Text(dateStr,
                        style: GoogleFonts.zain(
                            fontSize: 11, color: AppColors.textSecondary)),
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
            Text(title,
                style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
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
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      children: [
        _collapsibleHeader(
          title: 'Tracking Progress',
          expanded: _trackingExpanded,
          onToggle: () => setState(() => _trackingExpanded = !_trackingExpanded),
        ),
        const SizedBox(height: 8),

        if (_trackingExpanded) ...[
          if (widget.statusHistory.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 24),
              child: Center(
                child: Text('No status updates yet.',
                    style: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textSecondary)),
              ),
            )
          else
            for (int i = 0; i < widget.statusHistory.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildTimelineItem(i),
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
        CommunityReportSection(caseId: widget.caseId),
        const SizedBox(height: 8),
        const Divider(color: AppColors.slaterspwn),

        // Messages to the Organization — reporter-only private channel.
        if (widget.isReporter) ...[
          _collapsibleHeader(
            title: 'Messages to the Organization',
            expanded: _messagesExpanded,
            onToggle: () => setState(() => _messagesExpanded = !_messagesExpanded),
          ),

          if (_messagesExpanded) ...[
            // Message list
            SizedBox(
              height: 100,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('cases')
                    .doc(widget.caseId)
                    .collection('messages')
                    .orderBy('timestamp')
                    .snapshots(),
                builder: (context, snap) {
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return const SizedBox();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: snap.data!.docs.length,
                    itemBuilder: (context, i) {
                      final msg = snap.data!.docs[i].data()
                      as Map<String, dynamic>;
                      final ts = msg['timestamp'] as Timestamp?;
                      final timeStr = ts != null
                          ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
                          : '';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: AppColors.slaterspwn,
                              child: Text(
                                (msg['senderName'] ?? 'U')[0],
                                style: GoogleFonts.zain(
                                    fontSize: 12,
                                    color: AppColors.textPrimary),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(msg['senderName'] ?? '',
                                          style: GoogleFonts.zain(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary)),
                                      Text(timeStr,
                                          style: GoogleFonts.zain(
                                              fontSize: 10,
                                              color: AppColors.textSecondary)),
                                    ],
                                  ),
                                  Text(msg['text'] ?? '',
                                      style: GoogleFonts.zain(
                                          fontSize: 12,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // Message input
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.messageController,
                      focusNode: widget.messageFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        hintStyle: GoogleFonts.zain(
                            fontSize: 13, color: AppColors.textSecondary),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50),
                          borderSide:
                          const BorderSide(color: AppColors.slaterspwn),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(50),
                          borderSide: const BorderSide(
                              color: AppColors.textPrimary),
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
                      child: const Icon(Icons.send,
                          size: 18, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
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

  Map<String, dynamic> get data => widget.data;

  double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    double deg2rad(double deg) => deg * (math.pi / 180.0);
    final dLat = deg2rad(lat2 - lat1);
    final dLng = deg2rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(deg2rad(lat1)) *
            math.cos(deg2rad(lat2)) *
            math.pow(math.sin(dLng / 2), 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  Future<void> _showCallSheet(BuildContext context, String riderName) async {
    final riderId = data['assignedVolunteerId'] as String?;
    String? phone;
    if (riderId != null && riderId.isNotEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(riderId)
          .get();
      phone = userDoc.data()?['phone'] as String?;
    }

    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(riderName,
            style: GoogleFonts.tiltWarp(
                fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
          (phone == null || phone.isEmpty)
              ? 'No contact number on file for this transporter yet.'
              : phone,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          if (phone != null && phone.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: phone!));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Number copied.')),
                );
              },
              child: Text('Copy',
                  style: GoogleFonts.zain(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Close',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }


  Widget? _buildRiderInfoCard(BuildContext context) {
    if (!widget.isReporter) return null;
    final name = data['assignedVolunteerName'] as String?;
    if (name == null || name.trim().isEmpty) return null;

    final vehicle = (data['assignedVehicle'] ?? '').toString();
    final plate = (data['assignedPlate'] ?? '').toString();

    String? distanceLabel;
    final riderLat = data['riderLastLat'];
    final riderLng = data['riderLastLng'];
    final caseLat = data['lat'];
    final caseLng = data['lng'];
    if (riderLat is num &&
        riderLng is num &&
        caseLat is num &&
        caseLng is num) {
      final km = _distanceKm(riderLat.toDouble(), riderLng.toDouble(),
          caseLat.toDouble(), caseLng.toDouble());
      distanceLabel = '${km.toStringAsFixed(1)}km';
    }

    final vehicleLine =
    [plate, vehicle].where((s) => s.isNotEmpty).join('  ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.person,
                  color: AppColors.textSecondary, size: 28),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
                  if (distanceLabel != null)
                    Text(distanceLabel,
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  if (vehicleLine.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(vehicleLine,
                        style: GoogleFonts.zain(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.message_outlined,
                  color: AppColors.textPrimary),
              onPressed: widget.onMessageOrg,
            ),
            IconButton(
              icon: const Icon(Icons.call, color: AppColors.textPrimary),
              onPressed: () => _showCallSheet(context, name),
            ),
          ],
        ),
      ),
    );
  }

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
      final label = type == 'foster' ? 'foster' : 'adopt';

      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'willingAdopterId': uid,
        'willingAdopterName': name.isEmpty ? 'A general user' : name,
        'willingAdopterType': type,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status':
            '${name.isEmpty ? 'A general user' : name} expressed interest to $label.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(type == 'foster'
                ? 'Thanks! Your interest to foster has been noted.'
                : 'Thanks! Your interest to adopt has been noted.'),
            backgroundColor: AppColors.greenrspwn,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to register interest: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
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
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaSection(
      BuildContext context, String title, List<String> urls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.zain(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: urls.isEmpty
              ? Text(
            'Not available yet.',
            style: GoogleFonts.zain(
                fontSize: 13, color: AppColors.textSecondary),
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
                    errorBuilder: (context, _, __) => Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: AppColors.slaterspwn,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.broken_image_outlined,
                          color: AppColors.textSecondary),
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
    final photoUrls = List<String>.from(data['photoUrls'] ?? []);
    final riderCard = _buildRiderInfoCard(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (riderCard != null) riderCard,

          // Case media
          _buildMediaSection(
            context,
            'Report Photos',
            List<String>.from(data['photoUrls'] ?? []),
          ),
          const SizedBox(height: 16),
          _DetailRow('Reporter Name', data['reporterName']),
          _DetailRow('Address', data['address']),
          _DetailRow('Description', data['condition']),
          _DetailRow('Type of Animal', data['animalType']),
          _DetailRow('Containment', data['containmentStatus']),
          _DetailRow('Approachability', data['strayTemperament']),
          _DetailRow('Urgency', data['urgency']),
          _DetailRow('Coordination', data['coordinateWithShelter']),
          if (data['coordinateWithShelter'] == 'no') ...[
            _DetailRow('Witness Name', data['witnessName']),
            _DetailRow('Witness Mobile Number', data['witnessPhone']),
          ],
          _DetailRow('Interest to adopt', data['interestedToAdopt']),
          const SizedBox(height: 12),


          if (!_hasWillingAdopter) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'This rescue is available for adoption or temporary foster.',
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
                    onPressed:
                    _isSubmitting ? null : () => _registerInterest('adopt'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textPrimary),
                    )
                        : Text('Interest to Adopt',
                        style: GoogleFonts.zain(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                    _isSubmitting ? null : () => _registerInterest('foster'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textPrimary),
                    )
                        : Text('Interest to Foster',
                        style: GoogleFonts.zain(fontSize: 13)),
                  ),
                ),
              ],
            ),
          ] else
            _DetailRow(
              'Willing adopter/foster',
              '${data['willingAdopterName'] ?? '-'}'
                  '${data['willingAdopterType'] != null ? ' (${data['willingAdopterType']})' : ''}',
            ),

          const SizedBox(height: 24),
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

