import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

/// Thin client for the admin callables in functions/campaigns.js.
class DonationAdminService {
  DonationAdminService._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instance;

  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    final result = await _functions.httpsCallable(name).call<Object?>(data);
    final raw = result.data;
    return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  /// Id in Firestore auto-id format, reused on retry so the backend can
  /// de-duplicate allocations / transfers. Nothing is written.
  static String newRequestId() => FirebaseFirestore.instance.collection('fundTransfers').doc().id;

  /// Uploads a picked image
  static Future<String> uploadImage(XFile file, String folder) async {
    final ref = FirebaseStorage.instance.ref().child('$folder/${DateTime.now().millisecondsSinceEpoch}.jpg');
    await ref.putFile(File(file.path));
    return ref.getDownloadURL();
  }

  static Future<String> saveCampaign({
    String? campaignId,
    required Map<String, dynamic> data,
    bool publish = false,
  }) async {
    final res = await _call('saveCampaign', {
      'campaignId': ?campaignId,
      'data': data,
      'publish': publish,
    });
    return res['campaignId'] as String? ?? campaignId ?? '';
  }

  /// action: publish | deactivate | reactivate | close
  static Future<void> setStatus(String campaignId, String action, {String? reason}) =>
      _call('setCampaignStatus', {'campaignId': campaignId, 'action': action, 'reason': ?reason});

  /// decision: extend | relaunch | close | convert_to_general
  static Future<void> resolveExpired(String campaignId, String decision, {DateTime? newDeadline, String? reason}) =>
      _call('resolveExpiredCampaign', {
        'campaignId': campaignId,
        'decision': decision,
        if (newDeadline != null) 'newDeadlineMs': newDeadline.millisecondsSinceEpoch,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

  static Future<void> postUpdate(String campaignId, {required String title, String? body, String type = 'general'}) =>
      _call('postCampaignUpdate', {'campaignId': campaignId, 'title': title, 'body': body, 'type': type});

  static Future<void> recordOfflineDonation({
    required String campaignId,
    required double amount,
    required String method,
    required String referenceNumber,
    required DateTime receivedAt,
    String? donorName,
    String? notes,
    String? receiptUrl,
  }) =>
      _call('recordOfflineDonation', {
        'campaignId': campaignId,
        'amount': amount,
        'method': method,
        'referenceNumber': referenceNumber,
        'receivedAtMs': receivedAt.millisecondsSinceEpoch,
        'donorName': donorName,
        'notes': notes,
        'receiptUrl': receiptUrl,
      });

  static Future<void> recordAllocation({
    required String campaignId,
    required String requestId,
    required String label,
    required String category,
    required double amount,
    String? notes,
    String? receiptUrl,
    String? inKindDescription,
  }) =>
      _call('recordAllocation', {
        'campaignId': campaignId,
        'requestId': requestId,
        'label': label,
        'category': category,
        'amount': amount,
        'notes': notes,
        'receiptUrl': receiptUrl,
        'inKindDescription': inKindDescription,
      });

  static Future<void> reallocateExcess({
    required String sourceCampaignId,
    required String destinationCampaignId,
    required String requestId,
    required double amount,
    required String reason,
  }) =>
      _call('reallocateExcess', {
        'sourceCampaignId': sourceCampaignId,
        'destinationCampaignId': destinationCampaignId,
        'requestId': requestId,
        'amount': amount,
        'reason': reason,
      });

  /// action: received | cancel | follow_up
  static Future<void> manageInKind(String donationId, String action, {int? itemIndex, int? quantityReceived, String? notes}) =>
      _call('manageInKindDonation', {
        'donationId': donationId,
        'action': action,
        'itemIndex': ?itemIndex,
        'quantityReceived': ?quantityReceived,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      });

  static String errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'Please sign in again.';
        case 'permission-denied':
        case 'invalid-argument':
        case 'failed-precondition':
        case 'not-found':
        case 'already-exists':
          return error.message ?? 'This action could not be completed.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'The server is unavailable right now. Please try again.';
      }
    }
    if (error is FirebaseException) return error.message ?? 'Upload failed. Please try again.';
    return 'Something went wrong. Please try again.';
  }
}
