import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/rescue/case_completed_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';


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

  @override
  void dispose() {
    _messageController.dispose();
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

        // Navigate to completed page when case is done
        if (status == 'completed') {
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
              // Map area placeholder
              data?['riderId'] != null
                  ? SizedBox(
                height: 200,
                child: _TrackCaseMap(caseId: widget.caseId),
              )
                  : Container(
                height: 200,
                color: AppColors.slaterspwn,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.map_outlined,
                          size: 40, color: AppColors.textSecondary),
                      const SizedBox(height: 8),
                      Text('Map will appear once a transporter is assigned.',
                          style: GoogleFonts.zain(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
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
                          onSend: () => _sendMessage(widget.caseId),
                          data: data ?? {},  // ADDED
                        )
                            : _CaseDetailTab(
                          caseId: widget.caseId,
                          data: data ?? {},
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

class _TrackCaseMap extends StatefulWidget {
  final String caseId;
  const _TrackCaseMap({required this.caseId});

  @override
  State<_TrackCaseMap> createState() => _TrackCaseMapState();
}

class _TrackCaseMapState extends State<_TrackCaseMap> {
  GoogleMapController? _controller;
  bool _centered = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('tracking')
          .orderBy('timestamp')
          .limitToLast(100)
          .snapshots(),
      builder: (context, snapshot) {
        final points = <LatLng>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final d = doc.data() as Map<String, dynamic>;
            final lat = d['lat'];
            final lng = d['lng'];
            if (lat is num && lng is num) {
              points.add(LatLng(lat.toDouble(), lng.toDouble()));
            }
          }
        }

        final center = points.isNotEmpty
            ? points.last
            : const LatLng(14.5995, 120.9842);

        if (_controller != null && points.isNotEmpty && !_centered) {
          _centered = true;
          _controller!.animateCamera(
              CameraUpdate.newLatLngZoom(points.last, 15));
        }

        return ClipRRect(
          borderRadius: BorderRadius.zero,
          child: GoogleMap(
            onMapCreated: (ctrl) => _controller = ctrl,
            initialCameraPosition: CameraPosition(target: center, zoom: 14),
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: points.isEmpty
                ? {}
                : {
              Marker(
                markerId: const MarkerId('rider_current'),
                position: points.last,
                infoWindow: const InfoWindow(title: 'Transporter'),
              ),
            },
            polylines: points.length < 2
                ? {}
                : {
              Polyline(
                polylineId: const PolylineId('route_trail'),
                points: points,
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

// Tracking detail tab
class _TrackingTab extends StatelessWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final Map<String, dynamic> data;

  const _TrackingTab({
    required this.statusHistory,
    required this.caseId,
    required this.messageController,
    required this.onSend,
    required this.data,
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
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: statusHistory.isEmpty
              ? Center(
            child: Text('No status updates yet.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary)),
          )
              : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: statusHistory.length,
            itemBuilder: (context, index) {
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
                            width: 2,
                            height: 40,
                            color: AppColors.textPrimary),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['status'] ?? '',
                              style: GoogleFonts.zain(
                                  fontSize: 13,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                          Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.end,
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
            },
          ),
        ),

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
        const SizedBox(height: 8),

        const Divider(),

        // Messages
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Messages',
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
    );
  }
}

// Case detail tab
class _CaseDetailTab extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _CaseDetailTab({required this.caseId, required this.data});

  @override
  State<_CaseDetailTab> createState() => _CaseDetailTabState();
}

class _CaseDetailTabState extends State<_CaseDetailTab> {
  bool _isSubmitting = false;

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

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Case media
          _buildMediaSection(
            context,
            'Report Photos',
            List<String>.from(data['photoUrls'] ?? []),
          ),
          const SizedBox(height: 16),
          _DetailRow('Reporter Name', data['reporterName']),
          _DetailRow('Reporter Mobile Number', data['reporterPhone']),
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

          // Adoption / foster availability banner — only shown while
          // nobody has claimed the animal yet.
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