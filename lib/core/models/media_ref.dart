/// An uploaded photo or video attached to a record: its download URL and
/// whether it is a video.
class MediaRef {
  const MediaRef(this.url, {this.isVideo = false});

  final String url;
  final bool isVideo;

  /// Pairs a list of URLs with a list of types ('video' / 'image'); a
  /// missing type counts as a photo, which every older record is.
  static List<MediaRef> fromLists(List<String> urls, List<String> types) => [
        for (var i = 0; i < urls.length; i++)
          MediaRef(urls[i], isVideo: i < types.length && types[i] == 'video'),
      ];
}

/// `attachmentUrls` / `attachmentTypes` as stored on medical records.
Map<String, dynamic> attachmentFields(List<MediaRef> media) => media.isEmpty
    ? const {}
    : {
        'attachmentUrls': [for (final m in media) m.url],
        'attachmentTypes': [for (final m in media) m.isVideo ? 'video' : 'image'],
      };

List<MediaRef> attachmentsFrom(Map<String, dynamic> data) => MediaRef.fromLists(
      List<String>.from(data['attachmentUrls'] as List? ?? const []),
      List<String>.from(data['attachmentTypes'] as List? ?? const []),
    );
