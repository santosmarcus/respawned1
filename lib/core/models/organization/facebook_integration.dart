import 'package:cloud_firestore/cloud_firestore.dart';

/// Safe (non-secret) Facebook Page connection metadata for one
/// organization — mirrors `organizations/{orgId}/integrations/facebook`.
/// The raw Page access token is never present here or anywhere in
/// Firestore; it lives only in Google Secret Manager, touched exclusively
/// by the backend Cloud Functions in functions/facebook.js.
class FacebookIntegration {
  final String pageId;
  final String pageName;
  final String? pageUsername;
  final String? pagePictureUrl;
  final String? pageUrl;
  final String connectionStatus; // connected | disconnected | error
  final String? connectedBy;
  final DateTime? connectedAt;
  final DateTime? lastValidatedAt;
  final List<String> permissionsGranted;
  final String? graphApiVersion;

  const FacebookIntegration({
    required this.pageId,
    required this.pageName,
    this.pageUsername,
    this.pagePictureUrl,
    this.pageUrl,
    required this.connectionStatus,
    this.connectedBy,
    this.connectedAt,
    this.lastValidatedAt,
    this.permissionsGranted = const [],
    this.graphApiVersion,
  });

  bool get isConnected => connectionStatus == 'connected';

  factory FacebookIntegration.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    DateTime? asDate(dynamic v) => v is Timestamp ? v.toDate() : null;
    return FacebookIntegration(
      pageId: data['pageId'] as String? ?? '',
      pageName: data['pageName'] as String? ?? '',
      pageUsername: data['pageUsername'] as String?,
      pagePictureUrl: data['pagePictureUrl'] as String?,
      pageUrl: data['pageUrl'] as String?,
      connectionStatus: data['connectionStatus'] as String? ?? 'disconnected',
      connectedBy: data['connectedBy'] as String?,
      connectedAt: asDate(data['connectedAt']),
      lastValidatedAt: asDate(data['lastValidatedAt']),
      permissionsGranted: (data['permissionsGranted'] as List?)?.whereType<String>().toList() ?? const [],
      graphApiVersion: data['graphApiVersion'] as String?,
    );
  }
}

/// A candidate Page offered during connect, when the Facebook account
/// manages more than one Page and the admin must choose.
class FacebookPageOption {
  final String pageId;
  final String pageName;
  final String? pageUsername;
  final String? pagePictureUrl;
  const FacebookPageOption({
    required this.pageId,
    required this.pageName,
    this.pageUsername,
    this.pagePictureUrl,
  });

  factory FacebookPageOption.fromMap(Map<String, dynamic> map) => FacebookPageOption(
        pageId: map['pageId'] as String? ?? '',
        pageName: map['pageName'] as String? ?? '',
        pageUsername: map['pageUsername'] as String?,
        pagePictureUrl: map['pagePictureUrl'] as String?,
      );
}

/// Result of [FacebookIntegrationRepository.connect] — either the
/// connection finished immediately (one Page) or the admin must pick one of
/// several.
class FacebookConnectResult {
  final bool selectionRequired;
  final String? requestId;
  final List<FacebookPageOption> pages;
  final FacebookIntegration? connected;

  const FacebookConnectResult.selectionRequired({required this.requestId, required this.pages})
      : selectionRequired = true,
        connected = null;

  const FacebookConnectResult.connected(this.connected)
      : selectionRequired = false,
        requestId = null,
        pages = const [];
}
