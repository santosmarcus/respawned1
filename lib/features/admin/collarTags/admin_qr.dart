import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import '../../../app_theme.dart';
import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';

class AdminQrGeneratorScreen extends StatefulWidget {
  const AdminQrGeneratorScreen({super.key});

  @override
  State<AdminQrGeneratorScreen> createState() => _AdminQrGeneratorScreenState();
}

class _AdminQrGeneratorScreenState extends State<AdminQrGeneratorScreen> {
  List<CollarTagData> _allTags = [];
  List<CollarTagData> _filtered = [];
  CollarTagData? _selected;
  bool _loadingTags = true;
  bool _sharing = false;

  final _searchCtrl = TextEditingController();
  final _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchTags();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  //Firestore
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
          _allTags = tags;
          _filtered = tags;
          _loadingTags = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTags = false);
      _showSnack('Failed to load tags: $e');
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _allTags
          : _allTags.where((t) {
        return t.name.toLowerCase().contains(q) ||
            t.ownerName.toLowerCase().contains(q) ||
            (t.tagId?.toLowerCase().contains(q) ?? false);
      }).toList();
    });
  }

  // QR helpers
  String _qrData(CollarTagData tag) =>
      'https://rspwn.app/tag/${tag.tagId}';


  Future<Uint8List?> _captureQr() async {
    try {
      final boundary = _qrKey.currentContext?.findRenderObject()
      as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _shareQr() async {
    if (_selected == null) return;
    setState(() => _sharing = true);

    try {
      final bytes = await _captureQr();
      if (bytes == null) throw Exception('Could not capture QR image.');

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/qr_${_selected!.tagId}.png');
      await file.writeAsBytes(bytes);

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Pet Collar Tag QR — ${_selected!.name}',
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
          'Generate QR Code',
          style: GoogleFonts.tiltWarp(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: TextField(
              controller: _searchCtrl,
              style: GoogleFonts.zain(
                  fontSize: 15, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search by pet name or owner…',
                hintStyle: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textSecondary),
                prefixIcon: const Icon(Icons.search,
                    color: AppColors.textSecondary, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear,
                      size: 18, color: AppColors.textSecondary),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged();
                  },
                )
                    : null,
                filled: true,
                fillColor: AppColors.tearspwn.withOpacity(0.2),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppColors.slaterspwn, width: 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: AppColors.greenrspwn, width: 1.5),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Tag list + QR panel
          Expanded(
            child: _loadingTags
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                ? Center(
              child: Text('No tags found.',
                  style: GoogleFonts.zain(
                      fontSize: 15,
                      color: AppColors.textSecondary)),
            )
                : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: scrollable tag list (40% width)
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.42,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 6, 16),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) =>
                    const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final tag = _filtered[i];
                      return _TagTile(
                        tag: tag,
                        selected:
                        _selected?.tagId == tag.tagId,
                        onTap: () => setState(
                                () => _selected = tag),
                      );
                    },
                  ),
                ),

                // Right: QR preview panel (60% width)
                Expanded(
                  child: _selected == null
                      ? _selectHint()
                      : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                        6, 0, 16, 16),
                    child: Column(
                      children: [
                        _QrPreviewCard(
                          tag: _selected!,
                          qrData: _qrData(_selected!),
                          cardKey: _qrKey,
                        ),
                        const SizedBox(height: 16),

                        // Share button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _sharing
                                ? null
                                : _shareQr,
                            icon: _sharing
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                              CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors
                                      .textPrimary),
                            )
                                : const Icon(
                                Icons.share_outlined,
                                size: 18),
                            label: Text(
                              _sharing
                                  ? 'Preparing…'
                                  : 'Share QR',
                              style: GoogleFonts.tiltWarp(
                                  fontSize: 14,
                                  fontWeight:
                                  FontWeight.bold,
                                  color: AppColors
                                      .textPrimary),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              AppColors.yellowrspwn,
                              foregroundColor:
                              AppColors.textPrimary,
                              shape:
                              RoundedRectangleBorder(
                                borderRadius:
                                BorderRadius.circular(
                                    30),
                              ),
                              padding:
                              const EdgeInsets.symmetric(
                                  vertical: 12),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectHint() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.qr_code_2,
            size: 56, color: AppColors.textPrimary.withOpacity(0.25)),
        const SizedBox(height: 12),
        Text(
          'Select a tag\nto generate its QR',
          textAlign: TextAlign.center,
          style: GoogleFonts.zain(
              fontSize: 14, color: AppColors.textSecondary),
        ),
      ],
    ),
  );
}

// Tag tile
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
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.yellowrspwn.withOpacity(0.18)
              : AppColors.tearspwn.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.yellowrspwn : AppColors.slaterspwn,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tag.name,
                style: GoogleFonts.tiltWarp(
                    fontSize: 13, color: AppColors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(tag.ownerName,
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// QR preview card
class _QrPreviewCard extends StatelessWidget {
  final CollarTagData tag;
  final String qrData;
  final GlobalKey cardKey;
  const _QrPreviewCard(
      {required this.tag, required this.qrData, required this.cardKey});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: cardKey,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Pet photo
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _petPhoto(),
            ),
            const SizedBox(height: 10),
            Text(
              tag.name,
              style: GoogleFonts.tiltWarp(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
            _row('Breed:', tag.breed),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
            _row('Color:', tag.colorMarkings),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
            _row('Birthday:', tag.birthday),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
            _row('Sex:', tag.sex),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
            const SizedBox(height: 8),

            // QR code
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: QrImageView(
                data: qrData,
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
            const SizedBox(height: 10),

            // Owner info
            Align(
              alignment: Alignment.centerLeft,
              child: Text('Owner Information',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tag.ownerName,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(tag.ownerMobile,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            const Divider(thickness: 0.5, color: AppColors.textPrimary),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Text(label,
            style: GoogleFonts.zain(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.end,
              style: GoogleFonts.zain(
                  fontSize: 12, color: AppColors.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );

  Widget _petPhoto() {
    if (tag.petImageUrl != null && tag.petImageUrl!.isNotEmpty) {
      return Image.network(tag.petImageUrl!,
          width: 120, height: 120, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder());
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
    width: 120,
    height: 120,
    color: AppColors.tearspwn,
    child: const Icon(Icons.pets, size: 40, color: AppColors.textPrimary),
  );
}