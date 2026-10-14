import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

/// A PayMongo payment method offered in the donation/sponsorship sheets.
class DonationPaymentMethod {
  final String label;

  final String type;

  const DonationPaymentMethod(this.label, this.type);
}

/// Add GrabPay ('grab_pay') / QR Ph ('qrph') here once they're enabled on
/// the PayMongo account
const List<DonationPaymentMethod> kDonationPaymentMethods = [
  DonationPaymentMethod('Credit Card', 'card'),
  DonationPaymentMethod('GCash', 'gcash'),
  DonationPaymentMethod('Maya', 'paymaya'),
];

/// Maps a UI label to its PayMongo type. Also accepts the old
/// "Credit Card (**** 1234)" labels from donation_cards.dart.
String? donationPaymentTypeForLabel(String label) {
  if (label.startsWith('Credit Card')) return 'card';
  for (final m in kDonationPaymentMethods) {
    if (m.label == label) return m.type;
  }
  return null;
}

class DonationCheckout {
  final String paymentId;
  final String status;
  final String? checkoutUrl;

  const DonationCheckout({required this.paymentId, required this.status, required this.checkoutUrl});

  bool get isOpen => status == 'pending' && checkoutUrl != null;
}

/// Thin client for the PayMongo Cloud Functions. Never talks to PayMongo
/// and never decides whether a payment succeeded
class DonationPaymentService {
  DonationPaymentService._();

  static FirebaseFunctions get _functions => FirebaseFunctions.instance;

  /// Random id in Firestore auto-id format. Nothing is written.
  static String newPaymentId() =>
      FirebaseFirestore.instance.collection('donationPayments').doc().id;

  static DocumentReference<Map<String, dynamic>> paymentDoc(String paymentId) =>
      FirebaseFirestore.instance.collection('donationPayments').doc(paymentId);

  static Future<DonationCheckout> createCheckout({
    required String paymentId,
    required String campaignId,
    required double amount,
    required String paymentMethod,
    required bool isAnonymous,
  }) async {
    final result = await _functions.httpsCallable('createDonationCheckout').call(<String, dynamic>{
      'paymentId': paymentId,
      'campaignId': campaignId,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'isAnonymous': isAnonymous,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return DonationCheckout(
      paymentId: data['paymentId'] as String,
      status: data['status'] as String,
      checkoutUrl: data['checkoutUrl'] as String?,
    );
  }

  static Future<String> syncStatus(String paymentId) async {
    final result = await _functions.httpsCallable('syncDonationPayment').call(<String, dynamic>{'paymentId': paymentId});
    return (result.data as Map)['status'] as String;
  }

  static Future<String> cancel(String paymentId) async {
    final result = await _functions.httpsCallable('cancelDonationCheckout').call(<String, dynamic>{'paymentId': paymentId});
    return (result.data as Map)['status'] as String;
  }

  /// Opens PayMongo's hosted checkout in the browser (https PayMongo URLs
  /// only). No canLaunchUrl(), so Android 11+ needs no <queries> entry.
  static Future<bool> openCheckoutPage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || !uri.host.endsWith('paymongo.com')) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  static String errorMessage(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'Please sign in again to donate.';
        case 'invalid-argument':
        case 'failed-precondition':
        case 'not-found':
        case 'aborted':
          return error.message ?? 'This payment could not be started.';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'The payment service is unavailable right now. Please try again.';
      }
    }
    return 'Something went wrong. Please try again.';
  }
}