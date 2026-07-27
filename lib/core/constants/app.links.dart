class AppLinks {

  static const String _projectId = 'respawnd1-45021';
  static const String _hostingDomain = '$_projectId.web.app';

  static String tagUrl(String tagId) => 'https://$_hostingDomain/tag/$tagId';

  static String? tagIdFromScan(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final segments = uri.pathSegments;
      final tagIndex = segments.indexOf('tag');
      if (tagIndex != -1 && tagIndex + 1 < segments.length) {
        final id = segments[tagIndex + 1];
        return id.isEmpty ? null : id;
      }
      if (uri.hasScheme) return null;
    }

    if (!trimmed.contains('/') && !trimmed.contains(' ')) {
      return trimmed;
    }
    return null;
  }
}