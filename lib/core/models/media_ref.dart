/// An uploaded photo, video or PDF attached to a record: its download URL
/// and what kind of file it is.
class MediaRef {
  const MediaRef(this.url, {this.isVideo = false, this.isDocument = false});

  final String url;
  final bool isVideo;

  /// A PDF (prescription, lab result, vet note). Opened outside the app.
  final bool isDocument;

  /// The stored type string: 'video', 'document' or 'image'.
  String get type => isVideo ? 'video' : (isDocument ? 'document' : 'image');

  /// Pairs a list of URLs with a list of types ('video' / 'document' /
  /// 'image'); a missing type counts as a photo, which every older record is.
  static List<MediaRef> fromLists(List<String> urls, List<String> types) => [
        for (var i = 0; i < urls.length; i++)
          MediaRef(
            urls[i],
            isVideo: i < types.length && types[i] == 'video',
            isDocument: i < types.length && types[i] == 'document',
          ),
      ];
}

/// `attachmentUrls` / `attachmentTypes` as stored on medical records.
Map<String, dynamic> attachmentFields(List<MediaRef> media) => media.isEmpty
    ? const {}
    : {
        'attachmentUrls': [for (final m in media) m.url],
        'attachmentTypes': [for (final m in media) m.type],
      };

List<MediaRef> attachmentsFrom(Map<String, dynamic> data) => MediaRef.fromLists(
      List<String>.from(data['attachmentUrls'] as List? ?? const []),
      List<String>.from(data['attachmentTypes'] as List? ?? const []),
    );
