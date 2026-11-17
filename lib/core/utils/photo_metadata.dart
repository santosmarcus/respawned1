import 'package:exif/exif.dart';
import 'package:image_picker/image_picker.dart';

/// Rescue gap 7: the capture time and place a camera stores inside a photo
/// file (EXIF). Read from gallery photos when a report is filed, so staff
/// can see whether a gallery photo was taken recently and near the pin.
class PhotoMetadata {
  final DateTime? takenAt;
  final double? lat;
  final double? lng;
  const PhotoMetadata({this.takenAt, this.lat, this.lng});

  bool get isEmpty => takenAt == null && lat == null;

  Map<String, dynamic> toMap() => {
  if (takenAt != null) 'takenAtMs': takenAt!.millisecondsSinceEpoch,
  'lat': ?lat,
  'lng': ?lng,
};

static PhotoMetadata? fromMap(Object? raw) {
if (raw is! Map) return null;
final ms = raw['takenAtMs'];
return PhotoMetadata(
takenAt: ms is num ? DateTime.fromMillisecondsSinceEpoch(ms.toInt()) : null,
lat: (raw['lat'] as num?)?.toDouble(),
lng: (raw['lng'] as num?)?.toDouble(),
);
}

/// Never throws: a file without EXIF (screenshots, edited or messaged
/// photos) simply has none.
static Future<PhotoMetadata> read(XFile file) async {
try {
final tags = await readExifFromBytes(await file.readAsBytes());
return PhotoMetadata(
takenAt: _date(tags['EXIF DateTimeOriginal']?.printable ?? tags['Image DateTime']?.printable),
lat: _coord(tags['GPS GPSLatitude'], tags['GPS GPSLatitudeRef']?.printable, 'S'),
lng: _coord(tags['GPS GPSLongitude'], tags['GPS GPSLongitudeRef']?.printable, 'W'),
);
} catch (_) {
return const PhotoMetadata();
}
}

// "2026:11:16 14:03:22" (local camera time).
static DateTime? _date(String? s) {
if (s == null) return null;
final m = RegExp(r'^(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})').firstMatch(s.trim());
if (m == null) return null;
final p = [for (var i = 1; i <= 6; i++) int.parse(m.group(i)!)];
return DateTime(p[0], p[1], p[2], p[3], p[4], p[5]);
}

static double? _coord(IfdTag? tag, String? ref, String negative) {
final values = tag?.values.toList();
if (values == null || values.length < 3) return null;
double part(Object? v) => v is Ratio ? v.toDouble() : (v is num ? v.toDouble() : 0);
final deg = part(values[0]) + part(values[1]) / 60 + part(values[2]) / 3600;
return (ref?.trim().toUpperCase() == negative) ? -deg : deg;
}
}
