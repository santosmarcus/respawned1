import 'package:flutter/foundation.dart';

class PayMongoService {
  final String secretKey;
  final bool isTestMode;

  PayMongoService({
    required this.secretKey,
    this.isTestMode = true,
  });

  /// Simulates a transaction for testing purposes
  Future<bool> simulateTransaction({
    required double amount,
    required String method,
  }) async {
    debugPrint("Simulating PayMongo transaction: ₱$amount via $method");
    await Future.delayed(const Duration(seconds: 2));
    return true; // Always succeed in simulation
  }

  /// Creates a Payment Intent (Real PayMongo API placeholder)
  Future<String?> createPaymentIntent({required double amount}) async {
    debugPrint("Creating PayMongo Payment Intent for ₱$amount");
    await Future.delayed(const Duration(seconds: 1));
    return "pi_mock_${DateTime.now().millisecondsSinceEpoch}";
  }
}
