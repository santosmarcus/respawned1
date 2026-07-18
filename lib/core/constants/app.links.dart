
class AppLinks {
  // Must match `projectId` in firebase_options.dart.
  static const String _projectId = 'respawnd1-45021';
  static const String _hostingDomain = '$_projectId.web.app';

  static String tagUrl(String tagId) => 'https://$_hostingDomain/tag/$tagId';
}