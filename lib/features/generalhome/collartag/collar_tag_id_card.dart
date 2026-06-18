import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'collar_tag_intro.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app_theme.dart';

//  Pet Identification Card Screen
class CollarTagIdCard extends StatefulWidget {
  final CollarTagData tagData;
  final bool isNewlyCreated;

  const CollarTagIdCard({
    super.key,
    required this.tagData,
    this.isNewlyCreated = false,
  });

  @override
  State<CollarTagIdCard> createState() => _CollarTagIdCardState();
}

class _CollarTagIdCardState extends State<CollarTagIdCard> {
  bool _nfcAvailable = false;
  bool _writingNfc = false;
  final GlobalKey _cardKey = GlobalKey();

  // The URL embedded in the QR / written to NFC
  // Points to a public deep-link so it works offline (cached) and online
  String get _tagUrl =>
      'https://respawnd.app/tag/${widget.tagData.tagId}';

  @override
  void initState() {
    super.initState();
    _checkNfc();
    if (widget.isNewlyCreated) _saveFcmTokenToTag();
  }

  //  NFC availability

  Future<void> _checkNfc() async {
    try {
      final available = await NfcManager.instance.isAvailable();
      if (mounted) setState(() => _nfcAvailable = available);
    } catch (_) {}
  }

  //Save FCM token so we can push "your tag was scanned" notifications

  Future<void> _saveFcmTokenToTag() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || widget.tagData.tagId == null) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      // Store under the public tag doc so the scan Cloud Function can reach it
      await FirebaseFirestore.instance
          .collection('collarTags')
          .doc(widget.tagData.tagId)
          .update({'ownerFcmToken': token, 'ownerId': uid});

      // Also keep under user profile for refresh
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc('main')
          .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  // NFC write

  Future<void> _writeNfc() async {
    if (!_nfcAvailable) {
      _showSnack('NFC is not available on this device.');
      return;
    }

    setState(() => _writingNfc = true);
    _showSnack('Hold your phone near the NFC tag to write…');

    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            if (ndef == null || !ndef.isWritable) {
              _showSnack('Tag is not writable.');
              await NfcManager.instance.stopSession(errorMessage: 'Not writable');
              return;
            }

            final message = NdefMessage([
              NdefRecord.createUri(Uri.parse(_tagUrl)),
              NdefRecord.createText(widget.tagData.name),
            ]);

            await ndef.write(message);
            await NfcManager.instance.stopSession();
            _showSnack('NFC tag written successfully!');
          } catch (e) {
            await NfcManager.instance
                .stopSession(errorMessage: e.toString());
            _showSnack('NFC write failed: $e');
          } finally {
            if (mounted) setState(() => _writingNfc = false);
          }
        },
      );
    } catch (e) {
      _showSnack('NFC error: $e');
      setState(() => _writingNfc = false);
    }
  }

  //Share / export the card as an image
  Future<void> _shareCard() async {
    try {
      final boundary = _cardKey.currentContext!.findRenderObject()
      as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData =
      await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pet_id_card.png');
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await Share.shareXFiles([XFile(file.path)],
          text: 'My pet\'s digital ID – ${widget.tagData.name}');
    } catch (e) {
      _showSnack('Could not share card: $e');
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
    final tag = widget.tagData;

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
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 16),

            // Printable card
            RepaintBoundary(
              key: _cardKey,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
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
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    _infoRow('Breed:', tag.breed),
                    _infoRow('Color/Markings:', tag.colorMarkings),
                    _infoRow('Birthday: ${tag.birthday}', 'Sex: ${tag.sex}',
                        isDouble: true),
                    const SizedBox(height: 8),
                    _healthDots(tag),
                    const SizedBox(height: 10),
                    const Divider(thickness: 0.5),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Owner Information',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag.ownerName,
                        style: GoogleFonts.zain(
                            fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                    const Divider(thickness: 0.5),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tag.ownerMobile,
                        style: GoogleFonts.zain(
                            fontSize: 13, color: AppColors.textPrimary),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // QR code
                    QrImageView(
                      data: _tagUrl,
                      version: QrVersions.auto,
                      size: 120,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.textPrimary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Scan to view full profile',
                      style: GoogleFonts.zain(
                          fontSize: 10,
                          color: AppColors.textPrimary.withOpacity(0.6)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.share_outlined,
                    label: 'Share Card',
                    onTap: _shareCard,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.nfc,
                    label: _writingNfc ? 'Writing…' : 'Write NFC',
                    onTap: _nfcAvailable && !_writingNfc ? _writeNfc : null,
                    loading: _writingNfc,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

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
                        fontSize: 16,
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

  //Helpers

  Widget _infoRow(String left, String right, {bool isDouble = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(left,
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textPrimary)),
          ),
          Expanded(
            child: Text(right,
                textAlign: TextAlign.end,
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textPrimary)),
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
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: positive ? AppColors.textPrimary : Colors.grey.shade400,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              style: GoogleFonts.zain(
                  fontSize: 11, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );

  void _editTag(BuildContext context) {
    _showSnack('Edit flow: re-open the form pre-populated (coming soon).');
  }
}

//Pet Photo widget (network / local / placeholder)

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
      width: 110,
      height: 110,
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