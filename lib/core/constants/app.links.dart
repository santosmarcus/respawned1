class AppLinks {

  static const String _projectId = 'respawnd1-45021';
  static const String _hostingDomain = '$_projectId.web.app';

  static String tagUrl(String tagId) => 'https://$_hostingDomain/tag/$tagId';

  /// An animal's public web page (functions/public_animal_page.js): every
  /// public detail, and a button that opens the animal in the app.
  static String animalUrl(String animalId) => 'https://$_hostingDomain/animal/$animalId';

  /// The animal id in a link that opens the app on an animal: the web page
  /// (`https://host/animal/ID`), the app's own scheme
  /// (`respawnd://open/animal/ID`), or the route Flutter passes for either
  /// (`/animal/ID`, `/open/animal/ID`). Null for anything else.
  static String? animalIdFromLink(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    final segments = [if (uri.scheme == 'respawnd' && uri.host.isNotEmpty) uri.host, ...uri.pathSegments];
    final i = segments.indexOf('animal');
    if (i == -1 || i + 1 >= segments.length) return null;
    final id = segments[i + 1];
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id) ? id : null;
  }

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