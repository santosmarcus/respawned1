/*import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';
import 'package:respawnd1/features/admin/collarTags/nfc_service.dart';
import 'package:respawnd1/app_theme.dart';

class AdminNfc extends StatefulWidget {
  const AdminNfc({super.key});

  @override
  State<AdminNfc> createState() => _AdminNfcState();
}

class _AdminNfcState extends State<AdminNfc> {
  final _nfcService = NfcService();

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

  @override
  void dispose() {
    _nfcService.stopSession();
    super.dispose();
  }

  Future<void> _checkNfc() async {
    final available = await _nfcService.isAvailable();
    if (mounted) setState(() => _nfcAvailable = available);
  }

  Future<void> _fetchTags() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('collarTags')
          .orderBy('createdAt', descending: true)
          .get();

      final tags = snap.docs
          .map((d) => CollarTagData.fromFirestore(d.data(), d.id))
          .toList();

      if (mounted) {
        setState(() {
          _tags = tags;
          _loadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTags = false);
      _showSnack('Failed to load tags: $e');
    }
  }

  Future<void> _startNfcWrite() async {
    if (_selected == null || !_nfcAvailable) return;

    setState(() {
      _status = _NfcStatus.scanning;
      _statusMessage = 'Hold the NFC chip near the back of your device…';
    });

    try {
      await _nfcService.writeTag(_selected!.tagId!);

      if (mounted) {
        setState(() {
          _status = _NfcStatus.success;
          _statusMessage = 'NFC chip written successfully!';
        });
      }

      await _fetchTags();
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _NfcStatus.error;
          _statusMessage = e.toString();
        });
      }
    }
  }

  Future<void> _cancelWrite() async {
    await _nfcService.stopSession();
    if (mounted) {
      setState(() {
        _status = _NfcStatus.idle;
        _statusMessage = '';
      });
    }
  }

  void _showSnack(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

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

            if (!_nfcAvailable)
              _Banner(
                color: Colors.red,
                icon: Icons.warning_amber_rounded,
                text: 'NFC is not available or enabled on this device.',
              ),

            _Banner(
              color: Colors.blue,
              icon: Icons.lock_outline,
              text: 'Only the pet\'s profile URL is written to the chip. '
                  'All pet information stays in Firestore and can be updated '
                  'any time without rewriting the tag.',
            ),

            const SizedBox(height: 4),

            Text('Select Pet Tag',
                style: GoogleFonts.tiltWarp(
                    fontSize: 13, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            if (_loadingTags)
              const Center(child: CircularProgressIndicator())
            else if (_tags.isEmpty)
              _EmptyState()
            else
              ..._tags.map((tag) => _TagTile(
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
              Text('What Gets Written to the Chip',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 13, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              _ChipPreviewCard(tagId: _selected!.tagId ?? ''),
              const SizedBox(height: 24),
            ],

            if (_status != _NfcStatus.idle) ...[
              _StatusBanner(status: _status, message: _statusMessage),
              const SizedBox(height: 16),
            ],

            if (_status == _NfcStatus.scanning)
              _FullWidthButton(
                label: 'Cancel',
                icon: Icons.close,
                onPressed: _cancelWrite,
                outlined: true,
              )
            else
              _FullWidthButton(
                label: _status == _NfcStatus.success
                    ? 'Write Again'
                    : 'Write to NFC Chip',
                icon: Icons.nfc,
                onPressed: (_selected == null || !_nfcAvailable)
                    ? null
                    : _startNfcWrite,
              ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}


class _Banner extends StatelessWidget {
  final MaterialColor color;
  final IconData icon;
  final String text;
  const _Banner(
      {required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.shade200),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color.shade400, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.zain(
                  fontSize: 13, color: color.shade800)),
        ),
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Text('No collar tags found.',
          style: GoogleFonts.zain(
              fontSize: 15, color: AppColors.textSecondary)),
    ),
  );
}

class _TagTile extends StatelessWidget {
  final CollarTagData tag;
  final bool selected;
  final VoidCallback onTap;
  const _TagTile(
      {required this.tag, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.yellowrspwn.withValues(alpha: 0.18)
              : AppColors.tearspwn.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.yellowrspwn
                : AppColors.slaterspwn,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // Pet thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _thumb(),
            ),
            const SizedBox(width: 12),

            // Pet info
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

            // "Written" badge — shown once the chip has been programmed
            if (tag.nfcWritten == true)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(
                    horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.greenrspwn.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.greenrspwn.withValues(alpha: 0.4)),
                ),
                child: Text('Written',
                    style: GoogleFonts.zain(
                        fontSize: 11, color: AppColors.greenrspwn)),
              ),

            if (selected)
              const Icon(Icons.check_circle,
                  color: AppColors.greenrspwn, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _thumb() {
    if (tag.petImageUrl != null && tag.petImageUrl!.isNotEmpty) {
      return Image.network(
        tag.petImageUrl!,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 52,
    height: 52,
    color: AppColors.tearspwn,
    child: const Icon(Icons.pets,
        size: 28, color: AppColors.textPrimary),
  );
}

class _ChipPreviewCard extends StatelessWidget {
  final String tagId;
  const _ChipPreviewCard({required this.tagId});

  @override
  Widget build(BuildContext context) {
    final url = 'https://respawnd.app/tag/$tagId';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.tearspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, size: 15),
              const SizedBox(width: 6),
              Text('1 URI record — nothing else',
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(url,
                style: GoogleFonts.zain(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 10),
          Text(
            'Pet details, owner contact, and medical records\n'
                'are loaded from Firestore when someone scans this chip.\n'
                'Update them any time — the chip never needs rewriting.',
            style: GoogleFonts.zain(
                fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

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
      _ => (
      Colors.grey.shade50,
      Colors.grey.shade200,
      Icons.info_outline,
      ),
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
            child: Text(message,
                style: GoogleFonts.zain(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _FullWidthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool outlined;
  const _FullWidthButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label,
              style: GoogleFonts.tiltWarp(
                  fontSize: 15, color: AppColors.textPrimary)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.textPrimary),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
        label: Text(label,
            style: GoogleFonts.tiltWarp(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.yellowrspwn,
          foregroundColor: AppColors.textPrimary,
          disabledBackgroundColor:
          AppColors.yellowrspwn.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          elevation: 0,
        ),
      ),
    );
  }
}

enum _NfcStatus { idle, scanning, success, error }*/