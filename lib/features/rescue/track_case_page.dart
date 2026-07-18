import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/rescue/case_completed_page.dart';

// Same Google Geocoding key used elsewhere in the rescue flow (rescue_page.dart)
// for turning a lat/lng into a human-readable address.
const String _geocodingApiKey = 'AIzaSyChQ9xBxn59vAehhzsPuMgCqJoW_qbVOs0';


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

        // Navigate to completed page when case reaches any final state —
        // covers 'completed'/'closed' as well as variants like 'Rescue
        // Completed' or 'Rescue Ended' that other flows may write.
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
              // The map is always the top element on this page — it shows
              // the case's pickup pin plus, once a transporter has been
              // assigned/starts moving, the drop-off pin, live transporter
              // position, and the route traveled so far.
              SizedBox(
                height: 200,
                child: _TrackCaseMap(caseId: widget.caseId, data: data ?? {}),
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

// Transit progress map shown to everyone viewing this case — pickup marker,
// drop-off marker (once assigned), the transporter's live position, and the
// route actually traveled so far (built from the periodic location pings
// the transporter's app writes to cases/{caseId}/tracking). Before a
// transporter is assigned this just shows the reported pickup location.
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

        // Current transporter position: latest ping if we have one,
        // otherwise fall back to the last known lat/lng stored on the
        // case doc itself.
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

        // The traveled route: pickup, then every recorded ping in order.
        // If there's no ping history yet but we do have both endpoints,
        // fall back to a straight pickup→drop-off line so progress is
        // still visible from the very start.
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

// Tracking detail tab
class _TrackingTab extends StatelessWidget {
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
    final item = statusHistory[index];
    final isLast = index == statusHistory.length - 1;
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
            if (index < statusHistory.length - 1)
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            children: [
              if (statusHistory.isEmpty)
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
                for (int i = 0; i < statusHistory.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildTimelineItem(i),
                  ),

              const SizedBox(height: 12),
              _buildMediaSection(
                context,
                'Pickup Verification',
                List<String>.from(data['pickupVerificationUrls'] ?? []),
              ),
              const SizedBox(height: 12),
              _buildMediaSection(
                context,
                'Dropoff Verification',
                List<String>.from(data['dropoffVerificationUrls'] ?? []),
              ),
              const SizedBox(height: 16),

              // Community Reports — visible to the reporter (for
              // situational awareness) and to every other user (who can
              // submit sighting reports to help verify/update the case).
              _CommunityReportSection(caseId: caseId),
              const SizedBox(height: 8),
              const Divider(color: AppColors.slaterspwn),
            ],
          ),
        ),

        // Messages to the Organization — reporter-only private channel.
        if (isReporter) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Messages to the Organization',
                  style: GoogleFonts.zain(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ),

          // Message list
          SizedBox(
            height: 100,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('cases')
                  .doc(caseId)
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
                    controller: messageController,
                    focusNode: messageFocusNode,
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
                  onTap: onSend,
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

// Community Report — lets any viewer (reporter included) see a feed of
// sighting/status updates from the community, and lets them submit one of
// four quick report types to help verify the case is still accurate.
class _CommunityReportSection extends StatefulWidget {
  final String caseId;
  const _CommunityReportSection({required this.caseId});

  @override
  State<_CommunityReportSection> createState() =>
      _CommunityReportSectionState();
}

class _CommunityReportSectionState extends State<_CommunityReportSection> {
  bool _expanded = false;
  String? _selectedType;
  XFile? _pickedImage;
  bool _submitting = false;
  bool _detectingLocation = false;
  final _commentController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _commentController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _reportsRef =>
      FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('communityReports');

  String _typeLabel(String? t) => switch (t) {
    'still_here' => 'Animal still here',
    'moved' => 'Animal moved',
    'rescued' => 'Animal rescued',
    'no_animal' => 'No animal present',
    _ => 'Update',
  };

  String _typeIconAsset(String? t) => switch (t) {
    'still_here' => 'assets/icons/animalstillhere.png',
    'moved' => 'assets/icons/animalmoved.png',
    'rescued' => 'assets/icons/animalrescued.png',
    'no_animal' => 'assets/icons/noanimal.png',
    _ => 'assets/icons/info.png',
  };

  String _typeDescription(String? t) => switch (t) {
    'still_here' =>
    'Upload a recent photo to confirm the animal is still at the reported location.',
    'moved' =>
    'The animal is no longer at the original location. Upload a recent photo and share the new location so rescuers can keep monitoring safely.',
    'rescued' =>
    'This animal has already been rescued by a rescuer, bystander, or partner organization. Add a photo or other proof to help verify the report.',
    'no_animal' =>
    'No animal was found at the reported location. Add a recent photo of the area to confirm the report may no longer be accurate.',
    _ => '',
  };

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80);
    if (file != null && mounted) {
      setState(() => _pickedImage = file);
    }
  }

  // Auto-detects the reporter's current GPS location and reverse-geocodes
  // it into a readable address, so the "Location Found" field for a
  // moved-animal report is prefilled instead of requiring manual typing.
  // The field stays editable afterward in case it needs correcting.
  Future<void> _autoDetectLocation() async {
    if (_detectingLocation) return;
    setState(() {
      _detectingLocation = true;
      _locationController.text = 'Detecting your location…';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() => _locationController.clear());
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'Please enable location services to auto-detect.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationController.clear());
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => Geolocator.getLastKnownPosition().then(
              (p) =>
          p ??
              Position(
                latitude: 14.5416,
                longitude: 121.0644,
                timestamp: DateTime.now(),
                accuracy: 0,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0,
              ),
        ),
      );

      String resolvedAddress =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
              '?latlng=${pos.latitude},${pos.longitude}'
              '&key=$_geocodingApiKey',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        final data = jsonDecode(res.body);
        if (res.statusCode == 200 &&
            data['status'] == 'OK' &&
            (data['results'] as List).isNotEmpty) {
          resolvedAddress = data['results'][0]['formatted_address'];
        }
      } catch (_) {
        // Keep the coordinate fallback already assigned above.
      }

      if (mounted) setState(() => _locationController.text = resolvedAddress);
    } catch (e) {
      if (mounted) {
        setState(() => _locationController.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
              Text('Could not detect your location — please type it in.')),
        );
      }
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null || _submitting) return;
    if (_selectedType == 'moved' && _locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter the new location.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name =
      '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
          .trim();

      final reportRef = _reportsRef.doc();

      String? photoUrl;
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('cases/${widget.caseId}/communityReports/${reportRef.id}.jpg');
        await ref.putFile(
          File(_pickedImage!.path),
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await ref.getDownloadURL();
      }

      await reportRef.set({
        'reporterId': uid,
        'reporterName': name.isEmpty ? 'A community member' : name,
        'type': _selectedType,
        'comment': _commentController.text.trim(),
        'newAddress':
        _selectedType == 'moved' ? _locationController.text.trim() : null,
        'photoUrl': photoUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _selectedType = null;
          _pickedImage = null;
          _expanded = false;
        });
        _commentController.clear();
        _locationController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks! Your report has been submitted.'),
            backgroundColor: AppColors.greenrspwn,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit report: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _optionButton(String type, String iconAsset, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedType = type);
          if (type == 'moved') _autoDetectLocation();
        },
        child: Column(
          children: [
            Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.textPrimary,
                  shape: BoxShape.circle,
                ),
                child: Image.asset(
                  iconAsset,
                  width: 10,
                  height: 10,
                )
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 4),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Image.asset(
                  _typeIconAsset(_selectedType),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(_typeLabel(_selectedType),
                style: GoogleFonts.tiltWarp(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(
              _typeDescription(_selectedType),
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slaterspwn),
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.background,
                ),
                child: _pickedImage != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(_pickedImage!.path),
                      fit: BoxFit.cover),
                )
                    : const Icon(Icons.add_a_photo_outlined,
                    color: AppColors.textSecondary, size: 26),
              ),
            ),

            const SizedBox(height: 14),
            if (_selectedType == 'moved') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Location Found',
                          style: GoogleFonts.zain(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      const TextSpan(
                          text: ' *',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _locationController,
                enabled: !_detectingLocation,
                style: GoogleFonts.zain(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter the new location',
                  hintStyle: GoogleFonts.zain(
                      fontSize: 12, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search,
                      size: 18, color: AppColors.textSecondary),
                  suffixIcon: _detectingLocation
                      ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                      : IconButton(
                    icon: const Icon(Icons.my_location,
                        size: 18, color: AppColors.textSecondary),
                    tooltip: 'Use current location',
                    onPressed: _autoDetectLocation,
                  ),
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.slaterspwn),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Auto-detected from your current location — you can edit it if needed.',
                style: GoogleFonts.zain(
                    fontSize: 10.5, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _commentController,
              maxLines: 2,
              style: GoogleFonts.zain(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Comment',
                hintStyle: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textSecondary),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                ),
                child: _submitting
                    ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textPrimary),
                )
                    : Text('Report',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => setState(() => _selectedType = null),
            child: const Icon(Icons.close,
                size: 20, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final ts = r['timestamp'] as Timestamp?;
    final date = ts?.toDate();
    final newAddress = r['newAddress'] as String?;
    final comment = r['comment'] as String?;
    final photoUrl = r['photoUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.textPrimary,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Image.asset(
                _typeIconAsset(r['type'] as String?),
                fit: BoxFit.contain,
              ),
            ),
          ),

          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${r['reporterName'] ?? 'Someone'} · ${_typeLabel(r['type'] as String?)}',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    if (date != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_formatTime(date),
                              style: GoogleFonts.zain(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                          Text(_formatDate(date),
                              style: GoogleFonts.zain(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                  ],
                ),
                if (newAddress != null && newAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 20, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(newAddress,
                              style: GoogleFonts.zain(
                                  fontSize: 13, color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  ),
                if (comment != null && comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(comment,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          if (photoUrl != null && photoUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                photoUrl,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 36,
                  height: 36,
                  color: AppColors.slaterspwn,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Community Report',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary), textAlign: TextAlign.center,),
                ),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: Icon(
                    _expanded ? Icons.expand_less : Icons.add_circle_outline,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 10),
              if (_selectedType == null) ...[
                Text('What is happening?',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  'Help keep rescue reports accurate by sharing timely updates on the animal\'s location, condition, and safety.',
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _optionButton(
                      'still_here',
                      'assets/icons/animalstillhere.png',
                      'Animal still here',
                    ),

                    _optionButton(
                      'moved',
                      'assets/icons/animalmoved.png',
                      'Animal moved',
                    ),

                    _optionButton(
                      'rescued',
                      'assets/icons/animalrescued.png',
                      'Animal rescued',
                    ),

                    _optionButton(
                      'no_animal',
                      'assets/icons/noanimal.png',
                      'No Animal Present',
                    ),
                  ],
                ),
              ] else
                _buildForm(),
            ],
            const SizedBox(height: 12),
            const Divider(color: AppColors.slaterspwn),
            const SizedBox(height: 4),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _reportsRef
                  .orderBy('timestamp', descending: true)
                  .limit(20)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('No community reports yet.',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  );
                }
                return Column(
                  children:
                  docs.map((d) => _reportTile(d.data())).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}