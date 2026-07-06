import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../app_theme.dart';
import 'collar_tag_data_model.dart';
import 'collar_tag_form_screen.dart';

//  Pet Identification Card Screen

class CollarIdTagCardScreen extends StatefulWidget {
  final CollarTagData tagData;
  final bool isNewlyCreated;
  // True when opened by someone other than the tag's owner (e.g. a rescuer
  // who scanned the QR code). Hides the Edit action so only the owner can
  // change the pet's record.
  final bool readOnly;

  const CollarIdTagCardScreen({
    super.key,
    required this.tagData,
    this.isNewlyCreated = false,
    this.readOnly = false,
  });

  @override
  State<CollarIdTagCardScreen> createState() => _CollarIdTagCardScreenState();
}

class _CollarIdTagCardScreenState extends State<CollarIdTagCardScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _sharing = false;

  // Local, live copy of the tag. Starts as whatever was passed in, then
  // stays in sync with Firestore so that when an admin flips qrEnabled on
  // (see admin_qr_generator_screen.dart), the QR appears here automatically
  // without the owner needing to reopen the screen.
  late CollarTagData _tag;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _tagSub;

  @override
  void initState() {
    super.initState();
    _tag = widget.tagData;
    if (widget.isNewlyCreated) _saveFcmTokenToTag();
    _listenToTag();
  }

  @override
  void dispose() {
    _tagSub?.cancel();
    super.dispose();
  }

  void _listenToTag() {
    final tagId = widget.tagData.tagId;
    if (tagId == null) return;

    _tagSub = FirebaseFirestore.instance
        .collection('collarTags')
        .doc(tagId)
        .snapshots()
        .listen((doc) {
      if (!mounted || !doc.exists) return;
      setState(() => _tag = CollarTagData.fromFirestore(doc.data()!, doc.id));
    }, onError: (_) {
      // Keep showing the last known state — this is a nice-to-have live
      // update, not a hard requirement to view the card.
    });
  }

  Future<void> _saveFcmTokenToTag() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || widget.tagData.tagId == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection('collarTags')
          .doc(widget.tagData.tagId)
          .update({'ownerFcmToken': token, 'ownerId': uid});

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc('main')
          .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // QR code data — same scheme the admin QR generator uses, so the same
  // code works whether it's shown here or printed from the admin screen.
  String get _qrData => 'https://rspwn.app/tag/${_tag.tagId}';

  Future<Uint8List?> _captureCard() async {
    try {
      final boundary = _cardKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareCard() async {
    setState(() => _sharing = true);
    try {
      final bytes = await _captureCard();
      if (bytes == null) throw Exception('Could not capture the ID card.');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/collar_tag_${_tag.tagId}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Pet Collar ID Card — ${_tag.name}',
      );
    } catch (e) {
      _showSnack('Share failed: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // Build

  @override
  Widget build(BuildContext context) {
    final tag = _tag;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!widget.readOnly)
            TextButton(
              onPressed: () => _editTag(context),
              child: Text('Edit',
                  style: GoogleFonts.zain(
                      fontSize: 15, color: AppColors.textPrimary)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            Text(
              'Pet Identification\nCard',
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),


            RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    // Pet photo
                    _PetPhoto(
                      imageUrl: tag.petImageUrl,
                      imagePath: tag.petImagePath,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      tag.name.isNotEmpty ? tag.name : '—',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    _infoRow('Breed:', tag.breed),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    _infoRow('Color/Markings:', tag.colorMarkings),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    _infoRow('Birthday: ${tag.birthday}', 'Sex: ${tag.sex}',
                        isDouble: true),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    const SizedBox(height: 8),
                    _healthDots(tag),
                    const SizedBox(height: 16),

                    // QR code — hidden until an admin reviews the submission
                    // and enables it (see admin_qr_generator_screen.dart).
                    // Same visual slot either way so the card layout doesn't
                    // jump once it's approved.
                    if (tag.tagId != null) ...[
                      tag.qrEnabled
                          ? _qrReadyBlock()
                          : _qrPendingBlock(),
                      const SizedBox(height: 10),
                    ],

                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Owner Information',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              color: AppColors.textPrimary)),
                    ),

                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag.ownerName,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag.ownerMobile,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ),
                    const Divider(thickness: 0.5, color: AppColors.textPrimary),


                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Share the ID card (with its QR code) — only once the QR has
            // actually been enabled; sharing a card with a locked QR isn't
            // useful yet.
            if (tag.tagId != null)
              _ActionButton(
                icon: Icons.share_outlined,
                label: _sharing
                    ? 'Preparing…'
                    : (tag.qrEnabled
                    ? 'Share ID Card'
                    : 'Share (available once approved)'),
                loading: _sharing,
                onTap: (tag.qrEnabled && !_sharing) ? _shareCard : null,
              ),

            const SizedBox(height: 16),

            // Finish
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.popUntil(context, (r) => r.isFirst),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: Text('Finish',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // QR blocks

  Widget _qrReadyBlock() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: QrImageView(
            data: _qrData,
            version: QrVersions.auto,
            size: 160,
            backgroundColor: Colors.white,
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Colors.black,
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Scan to view full profile',
          style: GoogleFonts.zain(
              fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _qrPendingBlock() {
    return Container(
      width: 160,
      height: 160,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tearspwn.withOpacity(0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top_rounded,
              size: 32, color: AppColors.textPrimary.withOpacity(0.5)),
          const SizedBox(height: 8),
          Text(
            'QR code pending\nadmin approval',
            textAlign: TextAlign.center,
            style: GoogleFonts.zain(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  // Helpers

  Widget _infoRow(String left, String right, {bool isDouble = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(left,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
          Expanded(
            child: Text(right,
                textAlign: TextAlign.end,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _healthDots(CollarTagData tag) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dot(tag.isSpayedNeutered, 'Spayed'),
              _dot(tag.isVaccinated, 'Vaccinated'),
            ],
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dot(
                tag.allergies.isEmpty || tag.allergies.toLowerCase() == 'none',
                'No Allergies',
              ),
              _dot(
                tag.medicalCondition.isEmpty ||
                    tag.medicalCondition.toLowerCase() == 'none',
                'No Medical Condition',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dot(bool positive, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: positive ? AppColors.textPrimary : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );

  void _editTag(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CollarTagFormScreen(
          existingTag: widget.tagData,
        ),
      ),
    );
  }
}

// Pet Photo

class _PetPhoto extends StatelessWidget {
  final String? imageUrl;
  final String? imagePath;

  const _PetPhoto({this.imageUrl, this.imagePath});

  @override
  Widget build(BuildContext context) {
    Widget child;

    if (imagePath != null && File(imagePath!).existsSync()) {
      child = Image.file(File(imagePath!), fit: BoxFit.cover);
    } else if (imageUrl != null && imageUrl!.isNotEmpty) {
      child = Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
        const Icon(Icons.pets, size: 50, color: AppColors.textPrimary),
      );
    } else {
      child = const Icon(Icons.pets, size: 50, color: AppColors.textPrimary);
    }

    return Container(
      width: 180,
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: AppColors.tearspwn,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

// Action button
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
            color: onTap != null
                ? AppColors.textPrimary
                : AppColors.textPrimary.withOpacity(0.3),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textPrimary),
              )
            else
              Icon(icon,
                  size: 20,
                  color: onTap != null
                      ? AppColors.textPrimary
                      : AppColors.textPrimary.withOpacity(0.4)),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    color: onTap != null
                        ? AppColors.textPrimary
                        : AppColors.textPrimary.withOpacity(0.4))),
          ],
        ),
      ),
    );
  }
}