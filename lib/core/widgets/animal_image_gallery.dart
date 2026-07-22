import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Scrollable animal-image gallery — shared by the user animal detail page
/// (`animal_page.dart`) and the admin Animal Record detail page
/// (`animal_record_detail_page.dart`), replacing what used to be two
/// different single-image (or no-image) headers. Horizontal `PageView` +
/// a small "i / N" page indicator (hidden entirely for 0 or 1 image, per
/// spec — no unnecessary carousel chrome for a single photo). Tapping a
/// page opens it full-screen. 0 images falls back to the existing paw
/// placeholder; a failed network load falls back to the same placeholder
/// per-image, never one broken image taking down the whole gallery.
class AnimalImageGallery extends StatefulWidget {
  final List<String> photoUrls;
  final double height;
  final Color backgroundColor;
  /// Optional overlay widgets (back/share/favorite buttons) positioned on
  /// top of the gallery, exactly where a caller previously stacked them on
  /// a plain `Container` — kept as a slot so callers don't need to know
  /// this is a `PageView` underneath.
  final List<Widget> overlays;

  const AnimalImageGallery({
    super.key,
    required this.photoUrls,
    this.height = 260,
    this.backgroundColor = AppColors.tearspwn,
    this.overlays = const [],
  });

  @override
  State<AnimalImageGallery> createState() => _AnimalImageGalleryState();
}

class _AnimalImageGalleryState extends State<AnimalImageGallery> {
  final _pageController = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _openFullscreen(int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullscreenGallery(photoUrls: widget.photoUrls, initialIndex: initialIndex),
        fullscreenDialog: true,
      ),
    );
  }

  Widget _placeholder() => Container(
        color: widget.backgroundColor,
        child: const Center(child: Icon(Icons.pets, size: 80, color: AppColors.textSecondary)),
      );

  @override
  Widget build(BuildContext context) {
    final urls = widget.photoUrls;

    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        children: [
          if (urls.isEmpty)
            _placeholder()
          else
            PageView.builder(
              controller: _pageController,
              itemCount: urls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => _openFullscreen(i),
                child: Image.network(
                  urls[i],
                  width: double.infinity,
                  height: widget.height,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      color: widget.backgroundColor,
                      child: const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
                    );
                  },
                  errorBuilder: (_, __, ___) => _placeholder(),
                ),
              ),
            ),
          if (urls.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    '${_page + 1} / ${urls.length}',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ),
          ...widget.overlays,
        ],
      ),
    );
  }
}

class _FullscreenGallery extends StatefulWidget {
  final List<String> photoUrls;
  final int initialIndex;
  const _FullscreenGallery({required this.photoUrls, required this.initialIndex});

  @override
  State<_FullscreenGallery> createState() => _FullscreenGalleryState();
}

class _FullscreenGalleryState extends State<_FullscreenGallery> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.photoUrls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => InteractiveViewer(
                child: Center(
                  child: Image.network(
                    widget.photoUrls[i],
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 80, color: Colors.white54),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              left: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            if (widget.photoUrls.length > 1)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Text('${_page + 1} / ${widget.photoUrls.length}',
                      style: GoogleFonts.zain(fontSize: 13, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
