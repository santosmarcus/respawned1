import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';

class AdminNfc extends StatefulWidget {
  const AdminNfc({super.key});

  @override
  State<AdminNfc> createState() => _AdminNfcState();
}

class _AdminNfcState extends State<AdminNfc> {
  List<CollarTagData> _tags = [];
  CollarTagData? _selected;
  bool _loadingTags = true;
  bool _nfcAvailable = false;

  _NfcStatus _status = _NfcStatus.idle;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _checkNfc();
    _fetchTags();
  }

  // NFC availability
  Future<void> _checkNfc() async {
    try {
      final availability = await NfcManager.instance.checkAvailability();
      if (mounted) {
        setState(() => _nfcAvailable = availability == NfcAvailability.enabled);
      }
    } catch (_) {
      if (mounted) setState(() => _nfcAvailable = false);
    }
  }

  // Firestore
  Future<void> _fetchTags() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('collarTags')
          .orderBy('createdAt', descending: true)
          .get();

      final tags = snap.docs
          .map((d) => CollarTagData.fromFirestore(d.data(), d.id))
          .toList();

      if (mounted) setState(() { _tags = tags; _loadingTags = false; });
    } catch (e) {
      if (mounted) setState(() { _loadingTags = false; });
      _showSnack('Failed to load tags: $e');
    }
  }

  // NFC write
  Future<void> _startNfcWrite() async {
    if (_selected == null || !_nfcAvailable) return;

    setState(() {
      _status = _NfcStatus.scanning;
      _statusMessage = 'Hold the NFC chip near the back of your device…';
    });

    try {
      await NfcManager.instance.startSession(
        // pollingOptions is required in the latest nfc_manager
        pollingOptions: {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso15693,
        },
        onDiscovered: (NfcTag tag) async {
          try {
            // Ndef comes from nfc_manager_ndef package
            final ndef = Ndef.from(tag);

            if (ndef == null) {
              setState(() {
                _status = _NfcStatus.error;
                _statusMessage = 'Tag does not support NDEF.';
              });
              await NfcManager.instance.stopSession();
              return;
            }

            if (!ndef.isWritable) {
              setState(() {
                _status = _NfcStatus.error;
                _statusMessage = 'This NFC tag is not writable.';
              });
              await NfcManager.instance.stopSession();
              return;
            }

            // URI record — deep-link to pet profile
            final uri = 'https://rspwn.app/tag/${_selected!.tagId}';
            final uriRecord = NdefRecord.createUri(Uri.parse(uri));

            // Text record — minimal JSON payload as fallback
            final payload = jsonEncode({
              'tagId': _selected!.tagId,
              'name': _selected!.name,
              'ownerMobile': _selected!.ownerMobile,
            });
            final textRecord = NdefRecord.createText(payload);

            // write() takes a named 'message' parameter in latest nfc_manager_ndef
            await ndef.write(
              message: NdefMessage(records: [uriRecord, textRecord]),
            );

            // Mark written in Firestore
            if (_selected!.tagId != null) {
              await FirebaseFirestore.instance
                  .collection('collarTags')
                  .doc(_selected!.tagId)
                  .update({
                'nfcWritten': true,
                'nfcWrittenAt': FieldValue.serverTimestamp(),
              });
            }

            setState(() {
              _status = _NfcStatus.success;
              _statusMessage = 'NFC tag written successfully!';
            });
            await NfcManager.instance.stopSession();
          } catch (e) {
            setState(() {
              _status = _NfcStatus.error;
              _statusMessage = 'Write failed: $e';
            });
            await NfcManager.instance.stopSession();
          }
        },
      );
    } catch (e) {
      setState(() {
        _status = _NfcStatus.error;
        _statusMessage = 'Could not start NFC session: $e';
      });
    }
  }

  Future<void> _cancelNfc() async {
    await NfcManager.instance.stopSession();
    setState(() {
      _status = _NfcStatus.idle;
      _statusMessage = '';
    });
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // build
  @override
  Widget build(BuildContext context) {
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
        centerTitle: true,
        title: Text(
          'Write NFC Tag',
          style: GoogleFonts.tiltWarp(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // NFC unavailable banner
            if (!_nfcAvailable)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.red.shade400, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'NFC is not available or enabled on this device.',
                        style: GoogleFonts.zain(
                            fontSize: 13, color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),

            Text('Select Pet Tag',
                style: GoogleFonts.tiltWarp(
                    fontSize: 13, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            if (_loadingTags)
              const Center(child: CircularProgressIndicator())
            else if (_tags.isEmpty)
              _emptyState()
            else
              ..._tags.map((tag) => _TagListTile(
                tag: tag,
                selected: _selected?.tagId == tag.tagId,
                onTap: () => setState(() {
                  _selected = tag;
                  _status = _NfcStatus.idle;
                  _statusMessage = '';
                }),
              )),

            const SizedBox(height: 24),

            if (_selected != null) ...[
              Text('Tag Payload Preview',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              _PayloadPreviewCard(tag: _selected!),
              const SizedBox(height: 24),
            ],

            if (_status != _NfcStatus.idle) ...[
              _StatusBanner(status: _status, message: _statusMessage),
              const SizedBox(height: 16),
            ],

            if (_status == _NfcStatus.scanning)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _cancelNfc,
                  icon: const Icon(Icons.close),
                  label: Text('Cancel',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.textPrimary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_selected == null || !_nfcAvailable)
                      ? null
                      : _startNfcWrite,
                  icon: const Icon(Icons.nfc, size: 20),
                  label: Text(
                    _status == _NfcStatus.success
                        ? 'Write Again'
                        : 'Write to NFC Chip',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    disabledBackgroundColor:
                    AppColors.yellowrspwn.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                  ),
                ),
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text(
        'No collar tags found.',
        style: GoogleFonts.zain(
            fontSize: 15, color: AppColors.textSecondary),
      ),
    ),
  );
}

// Tag list tile
class _TagListTile extends StatelessWidget {
  final CollarTagData tag;
  final bool selected;
  final VoidCallback onTap;

  const _TagListTile({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.yellowrspwn.withOpacity(0.18)
              : AppColors.tearspwn.withOpacity(0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.yellowrspwn : AppColors.slaterspwn,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _thumb(tag),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tag.name,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(tag.breed,
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary)),
                  Text('Owner: ${tag.ownerName}',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.greenrspwn, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _thumb(CollarTagData tag) {
    if (tag.petImageUrl != null && tag.petImageUrl!.isNotEmpty) {
      return Image.network(tag.petImageUrl!,
          width: 52, height: 52, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholderThumb());
    }
    return _placeholderThumb();
  }

  Widget _placeholderThumb() => Container(
    width: 52,
    height: 52,
    color: AppColors.tearspwn,
    child: const Icon(Icons.pets, size: 28, color: AppColors.textPrimary),
  );
}

//Payload preview card
class _PayloadPreviewCard extends StatelessWidget {
  final CollarTagData tag;
  const _PayloadPreviewCard({required this.tag});

  @override
  Widget build(BuildContext context) {
    final uri = 'https://rspwn.app/tag/${tag.tagId}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tearspwn.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _row('Tag ID', tag.tagId ?? '—'),
          const SizedBox(height: 6),
          _row('Pet Name', tag.name),
          const SizedBox(height: 6),
          _row('Owner Mobile', tag.ownerMobile),
          const SizedBox(height: 6),
          _row('URI Record', uri),
        ],
      ),
    );
  }

  Widget _row(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 110,
        child: Text(label,
            style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
      ),
      Expanded(
        child: Text(value,
            style: GoogleFonts.zain(
                fontSize: 13, color: AppColors.textPrimary)),
      ),
    ],
  );
}

// Status banner
class _StatusBanner extends StatelessWidget {
  final _NfcStatus status;
  final String message;
  const _StatusBanner({required this.status, required this.message});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color border, IconData icon) = switch (status) {
      _NfcStatus.scanning => (
      Colors.blue.shade50,
      Colors.blue.shade200,
      Icons.nfc,
      ),
      _NfcStatus.success => (
      Colors.green.shade50,
      Colors.green.shade200,
      Icons.check_circle_outline,
      ),
      _NfcStatus.error => (
      Colors.red.shade50,
      Colors.red.shade200,
      Icons.error_outline,
      ),
      _ => (Colors.grey.shade50, Colors.grey.shade200, Icons.info_outline),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          if (status == _NfcStatus.scanning)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: GoogleFonts.zain(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

enum _NfcStatus { idle, scanning, success, error }