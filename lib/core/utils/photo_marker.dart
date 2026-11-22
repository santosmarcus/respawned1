import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

/// Round map pins showing a photo (the rescued animal on Track Case), with
/// a coloured ring. Built once per photo and ring colour, then cached.
class PhotoMarkers {
  PhotoMarkers._();

  static final Map<String, Future<BitmapDescriptor?>> _cache = {};

  /// The pin for [url], or null when the photo can't be loaded (callers
  /// keep their default pin).
  static Future<BitmapDescriptor?> forUrl(String url, {Color ring = Colors.white}) =>
      _cache.putIfAbsent('$url|${ring.toARGB32()}', () => _build(url, ring));

  static Future<BitmapDescriptor?> _build(String url, Color ring) async {
    try {
      final data = await NetworkAssetBundle(Uri.parse(url)).load(url);
      const size = 120.0;
      const ringWidth = 8.0;
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: size.toInt());
      final image = (await codec.getNextFrame()).image;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const center = Offset(size / 2, size / 2);
      canvas.drawCircle(center, size / 2, Paint()..color = ring);
      canvas.drawCircle(center, size / 2 - ringWidth + 2, Paint()..color = Colors.white);

      final inner = const Rect.fromLTWH(0, 0, size, size).deflate(ringWidth);
      canvas.save();
      canvas.clipPath(Path()..addOval(inner));
      final w = image.width.toDouble();
      final h = image.height.toDouble();
      final side = w < h ? w : h;
      final src = Rect.fromLTWH((w - side) / 2, (h - side) / 2, side, side);
      canvas.drawImageRect(image, src, inner, Paint()..filterQuality = FilterQuality.medium);
      canvas.restore();

      final out = await recorder.endRecording().toImage(size.toInt(), size.toInt());
      final bytes = await out.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return null;
      return BitmapDescriptor.bytes(bytes.buffer.asUint8List(), width: 44, height: 44);
    } catch (e) {
      debugPrint('PhotoMarkers: could not build a pin for $url: $e');
      _cache.removeWhere((key, _) => key.startsWith('$url|'));
      return null;
    }
  }
}
