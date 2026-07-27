import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../app_theme.dart';
import '../../core/config/paymongo_config.dart';
import '../generalhome/history_provider.dart';
import 'models.dart';
import 'donation_summary.dart';
import 'paymongo_service.dart';

final donationReviewProvider = ChangeNotifierProvider.autoDispose.family<DonationReviewNotifier, DonationReviewParams>((ref, params) {
  final payMongoService = ref.watch(payMongoServiceProvider);
  final notifier = DonationReviewNotifier(
    params: params,
    payMongoService: payMongoService,
  );
  
  // Add observer to handle app resume for payment verification
  final observer = _PaymentLifecycleObserver(notifier);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
  
  return notifier;
});

class _PaymentLifecycleObserver extends WidgetsBindingObserver {
  final DonationReviewNotifier notifier;
  _PaymentLifecycleObserver(this.notifier);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      notifier.checkPendingPayment();
    }
  }
}

class DonationReviewNotifier extends ChangeNotifier {
  final DonationReviewParams params;
  final PayMongoService payMongoService;
  final double totalAmount;
  bool _isProcessing = false;
  String? _errorMessage;
  String? _pendingIntentId;
  Completer<Map<String, String>?>? _redirectCompleter;

  DonationReviewNotifier({
    required this.params,
    required this.payMongoService,
  }) : totalAmount = params.item.amount;

  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  String get fundraiserId => params.fundraiserId;
  String get organizationName => params.organizationName;
  String get donationMethod => params.donationMethod;
  DonationItem get item => params.item;
  bool get isAnonymous => params.isAnonymous;
  SponsorPet? get pet => params.pet;
  DonationListing? get sponsorship => params.sponsorship;
  bool get isSponsorship => params.isSponsorship;

  Future<void> checkPendingPayment() async {
    if (_pendingIntentId == null || _redirectCompleter == null) return;

    try {
      final status = await payMongoService.getPaymentStatus(_pendingIntentId!);
      if (status == 'succeeded') {
        final result = await _recordToFirebase(_pendingIntentId!);
        _redirectCompleter?.complete(result);
      } else if (status != 'awaiting_next_action') {
        _errorMessage = payMongoService.getFriendlyErrorMessage(status);
        _redirectCompleter?.complete(null);
      }
      // If still awaiting_next_action, they might have just come back to the app 
      // without finishing, so we don't complete yet.
    } catch (e) {
      _errorMessage = "Error verifying payment: $e";
      _redirectCompleter?.complete(null);
    } finally {
      _pendingIntentId = null;
      _redirectCompleter = null;
      _isProcessing = false;
      notifyListeners();
    }
  }

  Future<Map<String, String>?> processPayment() async {
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      String donorName = "Anonymous";
      if (!isAnonymous && uid != null) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        donorName = userDoc.data()?['name'] ?? "User";
      }

      if (payMongoService.isTestMode) {
        final success = await payMongoService.simulateTransaction(
          amount: item.amount,
          method: donationMethod,
        );
        if (success) {
          final res = await _recordToFirebase('sim_${DateTime.now().millisecondsSinceEpoch}');
          _isProcessing = false;
          notifyListeners();
          return res;
        } else {
          _errorMessage = "Simulation failed.";
          _isProcessing = false;
          notifyListeners();
          return null;
        }
      }

      // REAL PAYMONGO FLOW
      // 1. Create Payment Intent
      final intent = await payMongoService.createPaymentIntent(
        amount: item.amount,
        description: item.description,
        metadata: {
          'userId': uid ?? 'anonymous',
          'campaignId': fundraiserId,
          'isAnonymous': isAnonymous.toString(),
          'donorName': isAnonymous ? 'Anonymous' : donorName,
          'isSponsorship': isSponsorship.toString(),
          'isPublic': (!isAnonymous).toString(),
        },
      );
      if (intent == null) {
        _errorMessage = "Failed to initiate payment intent.";
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      final intentId = intent['id'];
      final clientKey = intent['attributes']['client_key'];

      // 2. Create Payment Method based on selection
      String pmType = 'card';
      if (donationMethod.toLowerCase().contains('gcash')) pmType = 'gcash';
      if (donationMethod.toLowerCase().contains('maya')) pmType = 'paymaya';

      final method = await payMongoService.createPaymentMethod(type: pmType);
      if (method == null) {
        _errorMessage = "Failed to create payment method.";
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      final methodId = method['id'];

      // 3. Attach Payment Method
      final attach = await payMongoService.attachPaymentMethod(
        intentId: intentId,
        methodId: methodId,
        clientKey: clientKey,
      );

      if (attach == null) {
        _errorMessage = "Failed to process payment attachment.";
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      final status = attach['attributes']['status'];

      if (status == 'awaiting_next_action') {
        final redirectUrl = attach['attributes']['next_action']['redirect']['url'];
        if (await canLaunchUrl(Uri.parse(redirectUrl))) {
          _pendingIntentId = intentId;
          _redirectCompleter = Completer<Map<String, String>?>();
          
          await launchUrl(Uri.parse(redirectUrl), mode: LaunchMode.externalApplication);
          
          // Wait for the lifecycle observer to complete the payment check
          return await _redirectCompleter!.future;
        } else {
          _errorMessage = "Could not launch payment authenticaton page.";
          _isProcessing = false;
          notifyListeners();
          return null;
        }
      } else if (status != 'succeeded') {
        _errorMessage = payMongoService.getFriendlyErrorMessage(status);
        _isProcessing = false;
        notifyListeners();
        return null;
      }

      // Success
      final result = await _recordToFirebase(intentId);
      _isProcessing = false;
      notifyListeners();
      return result;
    } catch (e) {
      _errorMessage = "A secure connection error occurred: ${e.toString()}";
      _isProcessing = false;
      notifyListeners();
      return null;
    }
  }

  Future<Map<String, String>?> _recordToFirebase(String intentId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    // Fetch user name for admin record
    String donorName = "Anonymous";
    if (!isAnonymous) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          final firstName = userData?['firstName'] ?? '';
          final lastName = userData?['lastName'] ?? '';
          final fullName = '$firstName $lastName'.trim();
          donorName = fullName.isNotEmpty ? fullName : (userData?['name'] ?? "User");
        }
      } catch (_) {
        donorName = "User";
      }
    }

    final refNumber = intentId;
    final now = DateTime.now();
    final formattedDate = DateFormat('MMMM d, yyyy').format(now);
    final formattedAmount = '₱${item.amount.toStringAsFixed(2)}';

    // 1. Global donation record
    final donationDocRef = FirebaseFirestore.instance.collection('donations').doc(intentId);
    final donationData = {
      'userId': uid,
      'donorName': isAnonymous ? 'Anonymous' : donorName,
      'campaignId': fundraiserId,
      'amount': item.amount,
      'amountString': formattedAmount,
      'method': donationMethod,
      'isAnonymous': isAnonymous,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'date': formattedDate,
      'refNumber': refNumber,
      'type': isSponsorship ? 'sponsorship' : 'donation',
      'isPublic': !isAnonymous,
      'organizer': organizationName,
      'itemDescription': item.description,
    };

    if (isSponsorship) {
      final now = DateTime.now();
      donationData['lastPaymentTime'] = Timestamp.fromDate(now);
      donationData['nextChargeDate'] = Timestamp.fromDate(now.add(const Duration(days: 30)));
      donationData['status'] = 'active';
    }

    bool goalReached = false;
    String campaignTitle = "this campaign";

    // 2. Transaction to update campaign count and record history
    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final currentDonationSnap = await transaction.get(donationDocRef);
      // If webhook already recorded it and verified it, we don't need to re-run the campaign logic
      if (currentDonationSnap.exists && currentDonationSnap.data()?['webhookVerified'] == true) {
        return;
      }

      final campaignRef = FirebaseFirestore.instance.collection('campaigns').doc(fundraiserId);
      final campaignSnap = await transaction.get(campaignRef);

      if (campaignSnap.exists) {
        final data = campaignSnap.data()!;
        final currentCollected = (data['collectedAmount'] ?? 0).toDouble();
        final targetAmount = (data['targetAmount'] ?? 0).toDouble();
        campaignTitle = data['title'] ?? campaignTitle;
        
        final newCollected = currentCollected + item.amount;
        
        transaction.update(campaignRef, {
          'collectedAmount': newCollected,
          'numdonors': FieldValue.increment(1),
        });

        if (currentCollected < targetAmount && newCollected >= targetAmount && targetAmount > 0) {
          goalReached = true;
        }
      }

      // Add to global donations
      transaction.set(donationDocRef, donationData, SetOptions(merge: true));

      // Add to user history
      final historyRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('history').doc(donationDocRef.id);
      transaction.set(historyRef, donationData);

      // Compatibility for legacy 'donated' check
      final donatedRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('donated').doc(fundraiserId);
      transaction.set(donatedRef, {
        'donationId': fundraiserId,
        'donatedAt': FieldValue.serverTimestamp(),
      });
    });

    if (goalReached) {
      _sendGoalReachedNotifications(fundraiserId, campaignTitle);
    }

    return {
      'docId': donationDocRef.id,
      'refNumber': refNumber,
    };
  }

  Future<void> _sendGoalReachedNotifications(String campaignId, String title) async {
    try {
      final donationsSnap = await FirebaseFirestore.instance
          .collection('donations')
          .where('campaignId', isEqualTo: campaignId)
          .get();

      final userIds = donationsSnap.docs
          .map((doc) => doc.data()['userId'] as String?)
          .where((uid) => uid != null)
          .cast<String>()
          .toSet();

      final batch = FirebaseFirestore.instance.batch();
      for (final uid in userIds) {
        final notifRef = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('notifications')
            .doc();
        batch.set(notifRef, {
          'title': 'Goal Reached',
          'message': 'A campaign you donated to, $title, has reached its goal. Thank you for your contribution!',
          'timestamp': FieldValue.serverTimestamp(),
          'isRead': false,
        });
      }
      await batch.commit();
    } catch (_) {}
  }
}

class DonationReviewSectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const DonationReviewSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: AppColors.textPrimary, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const Divider(height: 24, thickness: 0.5),
          ...children,
        ],
      ),
    );
  }
}

class DonationReviewScreen extends ConsumerWidget {
  const DonationReviewScreen({super.key, required this.params});

  final DonationReviewParams params;

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 28),
            const SizedBox(width: 10),
            Text(
              'Payment Failed',
              style: GoogleFonts.tiltWarp(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          message,
          style: GoogleFonts.zain(fontSize: 18, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Try Again', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final donation = ref.watch(donationReviewProvider(params));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () {
            if (!donation.isProcessing) {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          donation.isSponsorship ? 'Sponsorship Review' : 'Donation Review',
          style: GoogleFonts.tiltWarp(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (donation.pet != null || donation.sponsorship != null) ...[
                    DonationReviewSectionCard(
                      title: 'Sponsored Pet',
                      icon: Icons.pets_outlined,
                      children: <Widget>[
                        Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: donation.pet != null 
                                    ? AppColors.tearspwn.withValues(alpha: 0.3)
                                    : donation.sponsorship?.backgroundColor.withValues(alpha: 0.3) ?? AppColors.tearspwn.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                                image: donation.sponsorship?.imageUrl != null && donation.pet == null
                                    ? DecorationImage(
                                        image: NetworkImage(donation.sponsorship!.imageUrl!),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                              ),
                              child: donation.sponsorship?.imageUrl == null || donation.pet != null
                                  ? const Icon(Icons.pets, color: AppColors.textPrimary)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  donation.pet?.name ?? donation.sponsorship?.animalName ?? 'Rescue Pet',
                                  style: GoogleFonts.zain(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Text(
                                  donation.pet?.breed ?? 'Rescue Pet',
                                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  DonationReviewSectionCard(
                    title: 'Organization',
                    icon: Icons.volunteer_activism_outlined,
                    children: <Widget>[
                      Text(
                        donation.organizationName,
                        style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DonationReviewSectionCard(
                    title: donation.isSponsorship ? 'Sponsorship Details' : 'Donation Details',
                    icon: Icons.attach_money_outlined,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              donation.item.description,
                              style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₱${donation.item.amount.toStringAsFixed(2)}',
                                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                              ),
                              Text(
                                'Currency: PHP',
                                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'International donors: Your bank may apply conversion fees.',
                                style: GoogleFonts.zain(fontSize: 12, color: Colors.blue[800]),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (donation.isSponsorship) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Recurring charge every 30 days',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.greenrspwn, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Next payment date:',
                              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                            ),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(DateTime.now().add(const Duration(days: 30))),
                              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Anonymous Donation',
                            style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
                          ),
                          Text(
                            donation.isAnonymous ? 'Yes' : 'No',
                            style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      const Divider(height: 24, thickness: 0.5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            'Total Amount',
                            style: GoogleFonts.tiltWarp(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            '₱${donation.totalAmount.toStringAsFixed(2)}',
                            style: GoogleFonts.tiltWarp(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DonationReviewSectionCard(
                    title: 'Payment Info',
                    icon: Icons.payment_outlined,
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            donation.donationMethod,
                            style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                          Row(
                            children: [
                              Icon(
                                donation.payMongoService.isTestMode ? Icons.bug_report : Icons.security, 
                                size: 16, 
                                color: donation.payMongoService.isTestMode ? Colors.orange : Colors.green
                              ),
                              const SizedBox(width: 4),
                              Text(
                                donation.payMongoService.isTestMode ? 'Test Mode' : 'Encrypted',
                                style: GoogleFonts.zain(
                                  fontSize: 14, 
                                  color: donation.payMongoService.isTestMode ? Colors.orange : Colors.green, 
                                  fontWeight: FontWeight.bold
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Irreversibility Warning: Please review carefully. Refunds are subject to manual audit and organization approval.',
                            style: GoogleFonts.zain(fontSize: 14, color: Colors.orange[900], fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: donation.isProcessing
                          ? null
                          : () async {
                              final notifier = ref.read(donationReviewProvider(params).notifier);
                              final result = await notifier.processPayment();
                              
                              if (result != null && context.mounted) {
                                final docId = result['docId']!;
                                final refNumber = result['refNumber']!;
                                final now = DateTime.now();
                                
                                // HistoryItem for summary UI
                                final historyItem = HistoryItem(
                                  id: docId, 
                                  type: donation.isSponsorship ? HistoryType.sponsorship : HistoryType.donation,
                                  organizer: donation.organizationName,
                                  dateTime: now,
                                  refNumber: refNumber,
                                  donationMethod: donation.donationMethod,
                                  amount: donation.item.amount,
                                  itemDescription: donation.item.description,
                                  nextChargeDate: donation.isSponsorship ? now.add(const Duration(days: 30)) : null,
                                  sponsorshipStatus: donation.isSponsorship ? 'active' : null,
                                  pet: donation.pet ?? (donation.sponsorship != null ? SponsorPet(
                                    id: donation.sponsorship!.animalId ?? 'temp',
                                    name: donation.sponsorship!.animalName ?? 'Rescue Pet',
                                    breed: 'Rescue Pet',
                                    age: '',
                                    description: '',
                                    tags: [],
                                    photoUrls: donation.sponsorship!.imageUrl != null ? [donation.sponsorship!.imageUrl!] : [],
                                  ) : null),
                                  nextChargeAmount: donation.isSponsorship ? donation.item.amount : null,
                                );
                                
                                ref.read(historyProvider.notifier).addHistoryItem(historyItem);
                                
                                Navigator.pushReplacement(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => DonationSummaryScreen(
                                      params: DonationSummaryParams(
                                        charityName: donation.organizationName,
                                        donationMethod: donation.donationMethod,
                                        item: donation.item,
                                        referenceNumber: refNumber,
                                        timestamp: now,
                                        historyItem: historyItem,
                                      ),
                                    ),
                                  ),
                                );
                              } else if (result == null && context.mounted) {
                                _showErrorDialog(context, notifier.errorMessage ?? "An unknown error occurred.");
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                      ),
                      child: donation.isProcessing
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'Processing...',
                                  style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ],
                            )
                          : Text(
                              donation.isSponsorship ? 'Confirm Sponsorship' : 'Confirm & Pay',
                              style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            if (donation.isProcessing)
              Container(
                color: Colors.black.withValues(alpha: 0.1),
                child: const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.yellowrspwn,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
