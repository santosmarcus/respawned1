import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PayMongoService {
  final String publicKey;
  final bool isTestMode;

  PayMongoService({
    required this.publicKey,
    this.isTestMode = true,
  });

  String get _publicAuthHeader => 'Basic ${base64Encode(utf8.encode('$publicKey:'))}';

  /// Simulates a transaction for testing purposes
  Future<bool> simulateTransaction({
    required double amount,
    required String method,
  }) async {
    debugPrint("Simulating PayMongo transaction: ₱$amount via $method");
    await Future.delayed(const Duration(seconds: 2));
    return true; // Always succeed in simulation
  }

  /// SECURE: Creates a Payment Intent via Firebase Cloud Functions
  Future<Map<String, dynamic>?> createPaymentIntent({
    required double amount,
    Map<String, String>? metadata,
    String? description,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('createPaymentIntent')
          .call({
        'amount': (amount * 100).toInt(),
        if (metadata != null) 'metadata': metadata,
        if (description != null) 'description': description,
      });
      
      // result.data is a Map from the server
      return Map<String, dynamic>.from(result.data as Map);
    } catch (e) {
      debugPrint("PayMongo Cloud Function Error: $e");
      return null;
    }
  }

  /// Creates a Payment Method (Hits v1/payment_methods)
  Future<Map<String, dynamic>?> createPaymentMethod({
    required String type, // 'card', 'gcash', 'paymaya'
    Map<String, dynamic>? details,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.paymongo.com/v1/payment_methods'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _publicAuthHeader,
        },
        body: jsonEncode({
          'data': {
            'attributes': {
              'type': type,
              if (details != null) 'details': details,
            }
          }
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['data'];
      }
      debugPrint("PayMongo Create Method Error: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("PayMongo Exception: $e");
      return null;
    }
  }

  /// Attaches a Payment Method to a Payment Intent
  Future<Map<String, dynamic>?> attachPaymentMethod({
    required String intentId,
    required String methodId,
    required String clientKey,
    String returnUrl = 'https://respawnd1-45021.web.app/payment-callback',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.paymongo.com/v1/payment_intents/$intentId/attach'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': _publicAuthHeader,
        },
        body: jsonEncode({
          'data': {
            'attributes': {
              'payment_method': methodId,
              'client_key': clientKey,
              'return_url': returnUrl,
            }
          }
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body)['data'];
      }
      debugPrint("PayMongo Attach Error: ${response.body}");
      return null;
    } catch (e) {
      debugPrint("PayMongo Exception: $e");
      return null;
    }
  }

  /// SECURE: Retrieves a Payment Intent to check status via Cloud Functions
  Future<String?> getPaymentStatus(String intentId) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('retrievePaymentIntent')
          .call({
        'intentId': intentId,
      });

      final data = Map<String, dynamic>.from(result.data as Map);
      return data['attributes']['status'];
    } catch (e) {
      debugPrint("PayMongo Status Check Error: $e");
      return null;
    }
  }

  /// SECURE: Requests a refund via Cloud Functions (Admin Approval Workflow)
  Future<bool> requestRefund({
    required String donationId,
    required String reason,
  }) async {
    try {
      final result = await FirebaseFunctions.instance
          .httpsCallable('requestRefund')
          .call({
        'donationId': donationId,
        'reason': reason,
      });

      return (result.data as Map)['success'] ?? false;
    } catch (e) {
      debugPrint("PayMongo Refund Request Error: $e");
      return false;
    }
  }

  /// Helper to map PayMongo error codes to user-friendly messages
  String getFriendlyErrorMessage(String? errorCode) {
    switch (errorCode) {
      case 'insufficient_funds':
        return 'Insufficient funds. Please check your balance and try again.';
      case 'payment_intent_invalid_state':
        return 'Payment is already processing or has expired.';
      case 'processor_blocked':
        return 'Transaction blocked by the bank. Please use a different card.';
      case 'lost_card':
      case 'stolen_card':
        return 'This card is reported as lost or stolen.';
      case 'expired_card':
        return 'The card has expired. Please use a valid card.';
      case 'cvc_invalid':
        return 'Invalid CVC code. Please check your card details.';
      default:
        return 'An error occurred during payment. Please try again or contact support.';
    }
  }
}
