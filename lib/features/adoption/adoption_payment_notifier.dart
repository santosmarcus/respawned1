import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/paymongo_config.dart';
import '../donation/paymongo_service.dart';

final adoptionPaymentProvider = ChangeNotifierProvider.autoDispose.family<AdoptionPaymentNotifier, String>((ref, adoptionId) {
  final payMongoService = ref.watch(payMongoServiceProvider);
  final notifier = AdoptionPaymentNotifier(
    adoptionId: adoptionId,
    payMongoService: payMongoService,
  );

  final observer = _PaymentLifecycleObserver(notifier);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));

  return notifier;
});

class _PaymentLifecycleObserver extends WidgetsBindingObserver {
  final AdoptionPaymentNotifier notifier;
  _PaymentLifecycleObserver(this.notifier);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      notifier.checkPendingPayment();
    }
  }
}

class AdoptionPaymentNotifier extends ChangeNotifier {
  final String adoptionId;
  final PayMongoService payMongoService;
  
  bool _isProcessing = false;
  String? _errorMessage;
  String? _pendingIntentId;
  Completer<bool>? _redirectCompleter;

  AdoptionPaymentNotifier({
    required this.adoptionId,
    required this.payMongoService,
  });

  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  Future<void> checkPendingPayment() async {
    if (_pendingIntentId == null || _redirectCompleter == null) return;

    try {
      final status = await payMongoService.getPaymentStatus(_pendingIntentId!);
      if (status == 'succeeded') {
        await _recordToFirebase(_pendingIntentId!);
        _redirectCompleter?.complete(true);
      } else if (status != 'awaiting_next_action') {
        _errorMessage = payMongoService.getFriendlyErrorMessage(status);
        _redirectCompleter?.complete(false);
      }
    } catch (e) {
      _errorMessage = "Error verifying payment: $e";
      _redirectCompleter?.complete(false);
    } finally {
      _pendingIntentId = null;
      _redirectCompleter = null;
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<bool> processPayment({
    required double amount,
    required String methodLabel,
    required String animalName,
    String? cardToken,
  }) async {
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("User not authenticated");

      if (payMongoService.isTestMode && !methodLabel.toLowerCase().contains('credit card')) {
        final success = await payMongoService.simulateTransaction(
          amount: amount,
          method: methodLabel,
        );
        if (success) {
          await _recordToFirebase('sim_${DateTime.now().millisecondsSinceEpoch}');
          _isProcessing = false;
          notifyListeners();
          return true;
        } else {
          _errorMessage = "Simulation failed.";
          _isProcessing = false;
          notifyListeners();
          return false;
        }
      }

      // 1. Create Payment Intent
      final intent = await payMongoService.createPaymentIntent(
        amount: amount,
        description: "Adoption Fee for $animalName",
        metadata: {
          'userId': uid,
          'adoptionId': adoptionId,
          'type': 'adoption_fee',
          'animalName': animalName,
        },
      );

      if (intent == null) throw Exception("Failed to initiate payment intent.");

      final intentId = intent['id'];
      final clientKey = intent['attributes']['client_key'];

      // 2. Resolve Payment Method
      String methodId;
      if (cardToken != null) {
        methodId = cardToken;
      } else {
        String pmType = 'card';
        if (methodLabel.toLowerCase().contains('gcash')) pmType = 'gcash';
        if (methodLabel.toLowerCase().contains('maya')) pmType = 'paymaya';

        final method = await payMongoService.createPaymentMethod(type: pmType);
        if (method == null) throw Exception("Failed to create payment method.");
        methodId = method['id'];
      }

      // 3. Attach Payment Method
      final attach = await payMongoService.attachPaymentMethod(
        intentId: intentId,
        methodId: methodId,
        clientKey: clientKey,
      );

      if (attach == null) throw Exception("Failed to process payment attachment.");

      final status = attach['attributes']['status'];

      if (status == 'awaiting_next_action') {
        final redirectUrl = attach['attributes']['next_action']['redirect']['url'];
        if (await canLaunchUrl(Uri.parse(redirectUrl))) {
          _pendingIntentId = intentId;
          _redirectCompleter = Completer<bool>();
          await launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.externalApplication);
          return await _redirectCompleter!.future;
        } else {
          throw Exception("Could not launch payment authentication page.");
        }
      } else if (status == 'succeeded') {
        await _recordToFirebase(intentId);
        _isProcessing = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = payMongoService.getFriendlyErrorMessage(status);
        _isProcessing = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = e.toString();
      _isProcessing = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> _recordToFirebase(String intentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    
    await FirebaseFirestore.instance
        .collection('adoptions')
        .doc(adoptionId)
        .set({
      'payment': {
        'status': 'paid',
        'paidAt': Timestamp.now(),
        'paidBy': uid,
        'referenceNumber': intentId,
      },
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Adoption fee payment confirmed.',
          'timestamp': Timestamp.now(),
        }
      ]),
    }, SetOptions(merge: true));
  }
}
