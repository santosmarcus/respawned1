/// A short description for each photo of an animal record, keyed by the
/// photo's download URL.
///
/// Stored on `animals/{id}` (and copied to `publicAnimals/{id}`) as
/// `photoCaptions: [{url, caption}, ...]`. Keyed by URL rather than by
/// position so a caption stays with its photo when photos are removed,
/// reordered, or appended by another writer (intake, returns).
library;

/// Reads `photoCaptions` from a record. Anything malformed is skipped;
/// blank captions are dropped.
Map<String, String> parsePhotoCaptions(Object? raw) {
  if (raw is! Iterable) return const {};
  final out = <String, String>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final url = item['url'];
    final caption = item['caption'];
    if (url is! String || url.isEmpty || caption is! String) continue;
    final trimmed = caption.trim();
    if (trimmed.isNotEmpty) out[url] = trimmed;
  }
  return out;
}

/// The stored form of [captions], for the photos in [photoUrls] only and in
/// their order, so a removed photo never leaves its caption behind.
List<Map<String, String>> photoCaptionsField(List<String> photoUrls, Map<String, String> captions) => [
      for (final url in photoUrls)
        if ((captions[url] ?? '').trim().isNotEmpty) {'url': url, 'caption': captions[url]!.trim()},
    ];

/// Longest caption allowed — Facebook photo captions and the web page both
/// show it under the photo, so it's meant to be a line or two.
const int kMaxPhotoCaptionLength = 300;
