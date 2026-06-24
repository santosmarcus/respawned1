import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:respawnd1/app_theme.dart';

// Status
// accepted  - rider accepted, not yet started
// ongoing   - otw to pickup
// arrived   - arrived at pickup, verify
// treatment - picked up, otw to clinic
// dropoff   - arrived at clinic, verifying drop-off
// completed - rescue done
// ended     - aborted

class TransitProgressPage extends StatefulWidget {
  final String caseId;
  const TransitProgressPage({super.key, required this.caseId});

  @override
  State<TransitProgressPage> createState() => _TransitProgressPageState();
}

class _TransitProgressPageState extends State<TransitProgressPage> {
  final _messageController = TextEditingController();
  final _picker = ImagePicker();
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;

  bool _isActing = false;

  // Verification images
  final List<File?> _pickupImages = [null, null];
  final List<File?> _dropoffImages = [null, null];

  @override
  void dispose() {
    _messageController.dispose();
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // Location streaming
  void _beginLocationStreaming() {
    if (_positionSub != null) return;
    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen((pos) {
      FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('tracking')
          .add({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'timestamp': FieldValue.serverTimestamp(),
      });
      FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'riderLastLat': pos.latitude,
        'riderLastLng': pos.longitude,
      });
      _mapController
          ?.animateCamera(CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)));
    });
  }

  // Status transitions
  Future<void> _setStatus(String status, String statusLabel) async {
    setState(() => _isActing = true);
    try {
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': status,
        'statusHistory': FieldValue.arrayUnion([
          {'status': statusLabel, 'timestamp': Timestamp.now()}
        ]),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _startTrip() async {
    await _setStatus('ongoing', 'On the way to pick up location.');
    _beginLocationStreaming();
  }

  Future<void> _markArrived() async {
    await _setStatus('arrived', 'Arrived at pick up location.');
  }

  Future<void> _submitPickupVerification() async {
    if (_pickupImages.every((f) => f == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one verification image.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(
          _pickupImages, 'pickup');
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'treatment',
        'pickupVerificationUrls': urls,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Animal rescued. On the way to treatment.',
            'timestamp': Timestamp.now()
          }
        ]),
      });
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _submitDropoffVerification() async {
    if (_dropoffImages.every((f) => f == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one verification image.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() => _isActing = true);
    try {
      final urls = await _uploadVerificationImages(
          _dropoffImages, 'dropoff');
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'completed',
        'dropoffVerificationUrls': urls,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Animal delivered to clinic. Rescue completed.',
            'timestamp': Timestamp.now()
          }
        ]),
      });
      _positionSub?.cancel();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<List<String>> _uploadVerificationImages(
      List<File?> images, String type) async {
    final urls = <String>[];
    for (int i = 0; i < images.length; i++) {
      final f = images[i];
      if (f == null) continue;
      final ref = FirebaseStorage.instance
          .ref('cases/${widget.caseId}/${type}_verify_$i.jpg');
      await ref.putFile(f);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _pickImage(List<File?> slot, int index) async {
    final picked =
    await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => slot[index] = File(picked.path));
    }
  }

  Future<void> _showEndReasonDialog() async {
    final reasons = [
      'Animal/Reporter not Found',
      'Invalid / fake report',
      'Animal Deceased',
      'Other',
    ];
    final selected = <String>{};
    String? other;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => Dialog(
          backgroundColor: AppColors.background,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text('End Reason',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 18, color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 16),
                ...reasons.map((r) => CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(r),
                  activeColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  title: Text(r,
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary)),
                  onChanged: (v) => setDlg(() {
                    if (v == true) {
                      selected.add(r);
                    } else {
                      selected.remove(r);
                    }
                  }),
                )),
                if (selected.contains('Other')) ...[
                  const SizedBox(height: 8),
                  TextField(
                    onChanged: (v) => other = v,
                    style: GoogleFonts.zain(
                        fontSize: 14, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Describe reason…',
                      hintStyle: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: AppColors.slaterspwn),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                        const BorderSide(color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () async {
                      Navigator.pop(ctx);
                      final reasonStr = [
                        ...selected.where((r) => r != 'Other'),
                        if (selected.contains('Other') &&
                            other != null &&
                            other!.isNotEmpty)
                          other!,
                      ].join(', ');
                      await _setStatus(
                          'ended', 'Rescue ended: $reasonStr');
                      _positionSub?.cancel();
                      if (mounted) Navigator.pop(context);
                    },
                    child: Text('Confirm',
                        style: GoogleFonts.zain(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: selected.isEmpty
                                ? AppColors.textSecondary
                                : Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openMessageSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),

              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Messages',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: _MessagesList(
                  caseId: widget.caseId,
                ),
              ),

              SafeArea(
                child: _MessageInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendMessage() async {
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
        .doc(widget.caseId)
        .collection('messages')
        .add({
      'senderId': uid,
      'senderName': name.isEmpty ? 'Rider' : name,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _messageController.clear();
  }

  // Build
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
        if (data == null) {
          return const Scaffold(
              body: Center(child: Text('Case no longer exists.')));
        }

        final status = data['status'] ?? 'accepted';

        // Auto-start streaming if already ongoing
        if ((status == 'ongoing' ||
            status == 'arrived' ||
            status == 'treatment' ||
            status == 'dropoff') &&
            _positionSub == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => _beginLocationStreaming());
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          bottomNavigationBar: _buildBottomNav(),
          body: Column(
            children: [

              // Map
              Expanded(
                flex: 2,
                child: Stack(
                  children: [
                    _TrackingMap(
                      caseId: widget.caseId,
                      onMapCreated: (ctrl) => _mapController = ctrl,
                    ),

                    // Online badge
                    Positioned(
                      top: 48,
                      left: 16,
                      child: _OnlineBadge(),
                    ),
                    // Settings / filter icon top right
                    Positioned(
                      top: 48,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 4)
                          ],
                        ),
                        child: const Icon(Icons.tune,
                            size: 18, color: AppColors.textPrimary),
                      ),
                    ),

                    Positioned(
                      bottom: 20,
                      right: 16,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          FloatingActionButton(
                            heroTag: 'chat_btn',
                            backgroundColor: AppColors.yellowrspwn,
                            onPressed: _openMessageSheet,
                            child: const Icon(
                              Icons.chat_bubble,
                              color: AppColors.textPrimary,
                            ),
                          ),

                          Positioned(
                            right: -2,
                            top: -2,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Center(
                                child: Text(
                                  '2',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom panel
              Expanded(
                flex: 1,
                child: _buildBottomPanel(status, data),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    // Arrived at pickup — verification
    if (status == 'arrived') {
      return _buildVerificationPanel(
        title: 'Arrived at pick up location',
        address: data['address'] ?? '',
        images: _pickupImages,
        onImageTap: (i) => _pickImage(_pickupImages, i),
        onConfirm: _submitPickupVerification,
        onEnd: _showEndReasonDialog,
        confirmLabel: 'Animal Rescued',
        isActing: _isActing,
      );
    }

    // Arrived at clinic — dropoff verification
    if (status == 'dropoff') {
      return _buildVerificationPanel(
        title: 'Arrived at drop off location',
        address: data['dropoffAddress'] ?? data['address'] ?? '',
        images: _dropoffImages,
        onImageTap: (i) => _pickImage(_dropoffImages, i),
        onConfirm: _submitDropoffVerification,
        confirmLabel: 'Complete',
        isActing: _isActing,
      );
    }

    // Standard panel for other statuses
    return _buildStandardPanel(status, data);
  }

  Widget _buildStandardPanel(String status, Map<String, dynamic> data) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Ongoing Request',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 15, color: AppColors.textPrimary)),
            ),
          ),

          const SizedBox(height: 10),

          // Address card
          _AddressCard(
            pickup: data['address'] ?? '',
            dropoff: data['dropoffAddress'] ?? data['address'] ?? '',
          ),

          const SizedBox(height: 20),

          // Swipe button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _buildSwipeButton(status),
          ),
        ],
      ),
    );
  }

  Widget _buildSwipeButton(String status) {
    String label;
    VoidCallback? onSwipe;

    switch (status) {
      case 'accepted':
        label = 'On the way to pick up location';
        onSwipe = _startTrip;
        break;
      case 'ongoing':
        label = 'Arrived at pick up location';
        onSwipe = _markArrived;
        break;
      case 'treatment':
        label = 'On the way to Treatment';
        onSwipe = () => _setStatus('dropoff', 'Arrived at clinic for treatment.');
        break;
      default:
        label = 'Processing…';
        onSwipe = null;
    }

    return _SwipeButton(
      label: label,
      onSwiped: _isActing ? null : onSwipe,
    );
  }

  Widget _buildVerificationPanel({
    required String title,
    required String address,
    required List<File?> images,
    required Function(int) onImageTap,
    required VoidCallback onConfirm,
    required String confirmLabel,
    required bool isActing,
    VoidCallback? onEnd,
  }) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.textPrimary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Text('Provide images and video to verify',
                    style: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(width: 4),
                const Text('*',
                    style: TextStyle(color: Colors.red, fontSize: 13)),
              ],
            ),
            const SizedBox(height: 10),

            // image grid
            Row(
              children: List.generate(
                2,
                    (i) => Padding(
                  padding: EdgeInsets.only(right: i == 0 ? 12 : 0),
                  child: GestureDetector(
                    onTap: () => onImageTap(i),
                    child: Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: images[i] != null
                              ? AppColors.greenrspwn
                              : AppColors.slaterspwn,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        color: AppColors.tearspwn.withOpacity(0.15),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: images[i] != null
                          ? Image.file(images[i]!, fit: BoxFit.cover)
                          : const Center(
                          child: Icon(Icons.add,
                              size: 28, color: AppColors.textSecondary)),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Address below images
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Confirm button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isActing ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.background,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: isActing
                    ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.background),
                )
                    : Text(confirmLabel,
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14, color: AppColors.background)),
              ),
            ),

            // End button (only at pickup)
            if (onEnd != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: onEnd,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                  ),
                  child: Text('End',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 14, color: AppColors.textPrimary)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home'),
        BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications'),
        BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'My Profile'),
      ],
      onTap: (_) {},
    );
  }
}

// Swipe button
class _SwipeButton extends StatefulWidget {
  final String label;
  final VoidCallback? onSwiped;

  const _SwipeButton({required this.label, this.onSwiped});

  @override
  State<_SwipeButton> createState() => _SwipeButtonState();
}

class _SwipeButtonState extends State<_SwipeButton> {
  double _dragX = 0;
  static const double _thumbSize = 52;
  static const double _triggerFraction = 0.75;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final trackWidth = constraints.maxWidth;
      final maxDrag = trackWidth - _thumbSize - 8;
      final fraction = (_dragX / maxDrag).clamp(0.0, 1.0);
      final trackColor = Color.lerp(
        Colors.grey.shade400,
        AppColors.textPrimary,
        fraction,
      )!;

      return GestureDetector(
        onHorizontalDragUpdate: widget.onSwiped == null
            ? null
            : (d) => setState(
                () => _dragX = (_dragX + d.delta.dx).clamp(0, maxDrag)),
        onHorizontalDragEnd: widget.onSwiped == null
            ? null
            : (d) {
          if (fraction >= _triggerFraction) {
            widget.onSwiped!();
          }
          setState(() => _dragX = 0);
        },
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.slaterspwn,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track fill
              AnimatedContainer(
                duration: const Duration(milliseconds: 50),
                width: _thumbSize + _dragX + 4,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(30),
                ),
              ),

              // Label
              Center(
                child: Text(
                  widget.label,
                  style: GoogleFonts.tiltWarp(
                      fontSize: 13, color: AppColors.background),
                  textAlign: TextAlign.center,
                ),
              ),

              // Thumb
              Positioned(
                left: 4 + _dragX,
                child: Container(
                  width: _thumbSize,
                  height: _thumbSize,
                  decoration: const BoxDecoration(
                    color: AppColors.textPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.chevron_right,
                      color: AppColors.yellowrspwn, size: 25),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

// Online badge
class _OnlineBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 10, color: Colors.green),
          const SizedBox(width: 6),
          Text('Online',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// Address card
class _AddressCard extends StatelessWidget {
  final String pickup;
  final String dropoff;
  const _AddressCard({required this.pickup, required this.dropoff});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6)
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle_outlined,
                          size: 13, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(pickup,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: SizedBox(
                      height: 14,
                      child: VerticalDivider(
                          color: AppColors.slaterspwn, thickness: 1.5),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 13, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(dropoff,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

//Messages list
class _MessagesList extends StatelessWidget {
  final String caseId;
  const _MessagesList({required this.caseId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
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
        final docs = snap.data!.docs;
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final msg =
            docs[docs.length - 1 - i].data() as Map<String, dynamic>;
            final ts = msg['timestamp'] as Timestamp?;
            final timeStr = ts != null
                ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                : '';
            final senderName = (msg['senderName'] ?? 'U').toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: AppColors.slaterspwn,
                    child: Text(
                      senderName.isEmpty ? 'U' : senderName[0],
                      style: GoogleFonts.zain(
                          fontSize: 11, color: AppColors.textPrimary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(msg['senderName'] ?? '',
                                style: GoogleFonts.zain(
                                    fontSize: 11,
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
    );
  }
}

// Message input
class _MessageInput extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  const _MessageInput({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Type a message',
                hintStyle: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                  const BorderSide(color: AppColors.slaterspwn),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(50),
                  borderSide:
                  const BorderSide(color: AppColors.textPrimary),
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
    );
  }
}

//Tracking map
class _TrackingMap extends StatefulWidget {
  final String caseId;
  final void Function(GoogleMapController) onMapCreated;

  const _TrackingMap({
    required this.caseId,
    required this.onMapCreated,
  });

  @override
  State<_TrackingMap> createState() => _TrackingMapState();
}

class _TrackingMapState extends State<_TrackingMap> {
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

        final initialCenter = points.isNotEmpty
            ? points.last
            : const LatLng(14.5995, 120.9842);

        if (_controller != null && points.isNotEmpty && !_centered) {
          _centered = true;
          _controller!.animateCamera(
              CameraUpdate.newLatLngZoom(points.last, 15));
        }

        return GoogleMap(
          onMapCreated: (ctrl) {
            _controller = ctrl;
            widget.onMapCreated(ctrl);
          },
          initialCameraPosition:
          CameraPosition(target: initialCenter, zoom: 14),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          markers: points.isEmpty
              ? {}
              : {
            Marker(
              markerId: const MarkerId('rider_current'),
              position: points.last,
              infoWindow: const InfoWindow(title: 'You'),
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
        );
      },
    );
  }
}