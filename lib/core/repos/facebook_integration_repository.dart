import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'package:respawnd1/core/models/organization/facebook_integration.dart';

/// A Facebook error the backend already classified (see
/// functions/facebook.js's classifyGraphError) into a stable code the UI
/// can switch on, instead of ever showing a raw Graph API/Firebase
/// exception. [message] is already a user-friendly sentence from the
/// backend; [code] lets the UI additionally tailor an action (e.g. only
/// "Reconnect" for token-expired).
class FacebookOperationException implements Exception {
  final String code;
  final String message;
  const FacebookOperationException({required this.code, required this.message});

  factory FacebookOperationException.fromFunctionsException(FirebaseFunctionsException e) {
    final details = e.details;
    final code = (details is Map && details['facebookErrorCode'] is String)
        ? details['facebookErrorCode'] as String
        : _codeFromFunctionsErrorCode(e.code);
    return FacebookOperationException(
      code: code,
      message: e.message?.isNotEmpty == true ? e.message! : 'Facebook rejected this request.',
    );
  }

  static String _codeFromFunctionsErrorCode(String code) => switch (code) {
        'permission-denied' => 'not-permitted',
        'deadline-exceeded' => 'expired-request',
        'not-found' => 'not-found',
        _ => 'facebook-error',
      };
}

Map<String, dynamic> _asStringKeyedMap(Object? raw) {
  if (raw is Map) return raw.map((k, v) => MapEntry(k.toString(), v));
  return const {};
}

/// Client-side wrapper over the Facebook Page Sharing callable functions
/// (functions/facebook.js). Never receives, stores, or displays a Page
/// access token — every method here only ever sees safe metadata or a
/// backend-classified error.
class FacebookIntegrationRepository {
  FacebookIntegrationRepository({FirebaseFirestore? firestore, FirebaseFunctions? functions})
      : _db = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  DocumentReference<Map<String, dynamic>> _integrationDoc(String organizationId) => _db
      .collection('organizations')
      .doc(organizationId)
      .collection('integrations')
      .doc('facebook');

  /// Null when never connected (doc doesn't exist yet) — distinct from a
  /// failed read, which surfaces as a stream error for the caller's
  /// StreamProvider to turn into an error-with-Retry state, never a false
  /// "not connected".
  Stream<FacebookIntegration?> streamIntegration(String organizationId) {
    return _integrationDoc(organizationId)
        .snapshots()
        .map((doc) => doc.exists ? FacebookIntegration.fromFirestore(doc) : null);
  }

  Future<T> _call<T>(String name, Map<String, dynamic> data, T Function(Map<String, dynamic>) parse) async {
    try {
      final result = await _functions.httpsCallable(name).call<Object?>(data);
      return parse(_asStringKeyedMap(result.data));
    } on FirebaseFunctionsException catch (e) {
      throw FacebookOperationException.fromFunctionsException(e);
    }
  }

  Future<FacebookConnectResult> connect({
    required String organizationId,
    required String userAccessToken,
  }) {
    return _call('facebookConnectPage', {
      'organizationId': organizationId,
      'userAccessToken': userAccessToken,
    }, (data) {
      if (data['status'] == 'selection_required') {
        final pages = (data['pages'] as List? ?? const [])
            .map((p) => FacebookPageOption.fromMap(_asStringKeyedMap(p)))
            .toList();
        return FacebookConnectResult.selectionRequired(requestId: data['requestId'] as String?, pages: pages);
      }
      return FacebookConnectResult.connected(_integrationFromCallableMap(_asStringKeyedMap(data['page'])));
    });
  }

  Future<FacebookConnectResult> confirmPageSelection({
    required String organizationId,
    required String requestId,
    required String pageId,
  }) {
    return _call('facebookConfirmPageSelection', {
      'organizationId': organizationId,
      'requestId': requestId,
      'pageId': pageId,
    }, (data) => FacebookConnectResult.connected(_integrationFromCallableMap(_asStringKeyedMap(data['page']))));
  }

  Future<void> testConnection(String organizationId) {
    return _call('facebookTestConnection', {'organizationId': organizationId}, (_) {});
  }

  Future<void> disconnect(String organizationId) {
    return _call('facebookDisconnectPage', {'organizationId': organizationId}, (_) {});
  }

  /// Posts to the organization's connected Page: [items] are the records with
  /// the photos to attach (each with its own description), [message] the
  /// post text, [link] the profile link for a post with no photos.
  Future<({String postId, String postUrl})> publishAnimalRecords({
    required String organizationId,
    required List<FacebookShareItem> items,
    String? message,
    String? link,
  }) {
    return _call('facebookPublishAnimalRecords', {
      'organizationId': organizationId,
      'items': [for (final i in items) i.toMap()],
      if (message != null && message.isNotEmpty) 'message': message,
      'link': ?link,
    }, (data) => (postId: data['postId'] as String? ?? '', postUrl: data['postUrl'] as String? ?? ''));
  }

  /// Posts one campaign or volunteer event to the organization's connected
  /// Page: [message] as the post text, with the record's own cover photo
  /// when [includePhoto] (the backend reads the photo from the record).
  Future<({String postId, String postUrl})> publishRecordPost({
    required String organizationId,
    required FacebookRecordKind kind,
    required String recordId,
    required String message,
    required bool includePhoto,
  }) {
    return _call('facebookPublishRecordPost', {
      'organizationId': organizationId,
      'kind': kind.name,
      'recordId': recordId,
      'message': message,
      'includePhoto': includePhoto,
    }, (data) => (postId: data['postId'] as String? ?? '', postUrl: data['postUrl'] as String? ?? ''));
  }

  /// Owner/Admin only (enforced by the callable). Lets a Member publish to
  /// the Page without changing their app role.
  Future<void> setPublisher({
    required String organizationId,
    required String memberUid,
    required bool enabled,
  }) {
    return _call('facebookSetPublisher', {
      'organizationId': organizationId,
      'memberUid': memberUid,
      'enabled': enabled,
    }, (_) {});
  }

  FacebookIntegration _integrationFromCallableMap(Map<String, dynamic> page) {
    return FacebookIntegration(
      pageId: page['pageId'] as String? ?? '',
      pageName: page['pageName'] as String? ?? '',
      pageUsername: page['pageUsername'] as String?,
      pagePictureUrl: page['pagePictureUrl'] as String?,
      connectionStatus: 'connected',
    );
  }
}

/// Records facebookPublishRecordPost can share (functions/facebook_share_rules.js
/// RECORD_KINDS); the name is sent as-is.
/// `referral`: a case referred by shared link (functions/facebook_share_rules.js RECORD_KINDS).
enum FacebookRecordKind { campaign, event, referral }

/// One record in a Facebook post and the photos to attach for it, in order.
class FacebookShareItem {
  const FacebookShareItem({required this.animalId, required this.photos});

  final String animalId;
  final List<({String url, String caption})> photos;

  Map<String, dynamic> toMap() => {
        'animalId': animalId,
        'photos': [
          for (final p in photos) {'url': p.url, if (p.caption.trim().isNotEmpty) 'caption': p.caption.trim()},
        ],
      };
}
