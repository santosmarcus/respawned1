import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';
import '../generalhome/history_provider.dart';
import 'models.dart';
import 'donation_summary.dart';
import 'donation_payment_service.dart';

final donationReviewProvider = ChangeNotifierProvider.autoDispose.family<DonationReviewNotifier, DonationReviewParams>((ref, params) {
  final notifier = DonationReviewNotifier(params: params);

  // Back from the PayMongo page / e-wallet app: ask the backend to check with
  // PayMongo in case the webhook hasn't arrived yet. Never trusted on its own —
  // the backend still verifies with PayMongo.
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
      notifier.checkPaymentStatus(automatic: true);
    }
  }
}

enum DonationPaymentPhase { idle, starting, awaitingPayment }

/// Starts a PayMongo Hosted Checkout and waits for the backend's verdict.
///
/// Never records a donation itself: Cloud Functions write donations/,
/// users/{uid}/history, users/{uid}/donated and campaign totals only after
/// verifying the payment with PayMongo. Returning to the app is not proof
/// of payment.
class DonationReviewNotifier extends ChangeNotifier {
  final DonationReviewParams params;
  final double totalAmount;

  DonationReviewNotifier({required this.params}) : totalAmount = params.item.amount;

  DonationPaymentPhase _phase = DonationPaymentPhase.idle;
  String? _errorMessage;
  String? _notice;
  bool _lastAttemptFailed = false;
  bool _cancelling = false;
  bool _checking = false;
  bool _disposed = false;
  DateTime? _lastAutoCheck;

  // One id per attempt: a retry after a timeout reuses it so the backend
  // returns the same checkout instead of creating a second one.
  String? _paymentId;
  String? _checkoutUrl;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _paymentSub;
  Completer<Map<String, String>?>? _completer;

  bool get isProcessing => _phase != DonationPaymentPhase.idle;
  bool get isStarting => _phase == DonationPaymentPhase.starting;
  bool get isAwaitingPayment => _phase == DonationPaymentPhase.awaitingPayment;
  bool get isCancelling => _cancelling;
  bool get isChecking => _checking;
  bool get lastAttemptFailed => _lastAttemptFailed;
  bool get canReopenCheckout => _checkoutUrl != null;
  String? get errorMessage => _errorMessage;
  String? get notice => _notice;

  String get fundraiserId => params.fundraiserId;
  String get organizationName => params.organizationName;
  String get donationMethod => params.donationMethod;
  DonationItem get item => params.item;
  bool get isAnonymous => params.isAnonymous;
  SponsorPet? get pet => params.pet;
  DonationListing? get sponsorship => params.sponsorship;
  bool get isSponsorship => params.isSponsorship;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Completes with {'docId', 'refNumber'} once the backend confirms the
  /// payment, or null if it fails / is cancelled / expires.
  Future<Map<String, String>?> processPayment() async {
    if (_phase != DonationPaymentPhase.idle) return null;

    final methodType = donationPaymentTypeForLabel(donationMethod);
    if (methodType == null) {
      _errorMessage = 'Choose a supported payment method.';
      _notify();
      return null;
    }

    _phase = DonationPaymentPhase.starting;
    _errorMessage = null;
    _notice = null;
    _notify();

    _paymentId ??= DonationPaymentService.newPaymentId();
    try {
      final checkout = await DonationPaymentService.createCheckout(
        paymentId: _paymentId!,
        campaignId: fundraiserId,
        amount: item.amount,
        paymentMethod: methodType,
        isAnonymous: isAnonymous,
      );
      if (!checkout.isOpen && checkout.status != 'paid') {
        // That attempt already ended (error/cancelled/expired) — start fresh next time.
        _paymentId = null;
        _fail('We couldn\'t start the payment. You were not charged — please try again.');
        return null;
      }
      _checkoutUrl = checkout.checkoutUrl;
    } on FirebaseFunctionsException catch (e) {
      // A timeout or "still preparing" may have a checkout behind it: keep the
      // id so a retry resumes it. Anything else ends this attempt.
      if (e.code != 'deadline-exceeded' && e.code != 'aborted') _paymentId = null;
      _fail(DonationPaymentService.errorMessage(e));
      return null;
    } catch (e) {
      _fail(DonationPaymentService.errorMessage(e));
      return null;
    }

    _phase = DonationPaymentPhase.awaitingPayment;
    _lastAttemptFailed = false;
    _completer = Completer<Map<String, String>?>();
    _listenToPayment(_paymentId!);
    _notify();
    await openCheckoutPage();
    return _completer!.future;
  }

  void _listenToPayment(String paymentId) {
    _paymentSub?.cancel();
    _paymentSub = DonationPaymentService.paymentDoc(paymentId).snapshots().listen((snap) {
      final data = snap.data();
      if (data == null) return;

      final failed = data['lastPaymentError'] is Map;
      if (failed != _lastAttemptFailed) {
        _lastAttemptFailed = failed;
        _notify();
      }

      switch (data['status'] as String?) {
        case 'paid':
          _finish({'docId': paymentId, 'refNumber': (data['refNumber'] as String?) ?? ''});
        case 'cancelled':
          _paymentId = null;
          _finish(null); // user cancelled — no error dialog
        case 'expired':
          _paymentId = null;
          _finish(null, message: 'This payment session expired. You were not charged.');
        case 'needs_review':
          _finish(null, message: 'We received a payment that needs to be reviewed by our team. Please don\'t pay again for this donation.');
        case 'error':
          _paymentId = null;
          _finish(null, message: 'We couldn\'t start the payment. You were not charged — please try again.');
      }
    }, onError: (_) {
      _notice = 'Lost connection while waiting for confirmation. Tap "Check payment status".';
      _notify();
    });
  }

  void _finish(Map<String, String>? result, {String? message}) {
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;
    _paymentSub?.cancel();
    _paymentSub = null;
    _phase = DonationPaymentPhase.idle;
    _errorMessage = message;
    _notice = null;
    if (result == null) _checkoutUrl = null;
    _notify();
    completer.complete(result);
  }

  void _fail(String message) {
    _phase = DonationPaymentPhase.idle;
    _errorMessage = message;
    _notify();
  }

  Future<void> openCheckoutPage() async {
    final url = _checkoutUrl;
    if (url == null) return;
    final opened = await DonationPaymentService.openCheckoutPage(url);
    if (!opened) {
      _notice = 'Could not open the payment page. Tap "Open payment page" to try again.';
      _notify();
    }
  }

  /// Asks the backend to verify with PayMongo. Results arrive through the
  /// Firestore listener, never from this call's return value.
  Future<void> checkPaymentStatus({bool automatic = false}) async {
    final id = _paymentId;
    if (id == null || !isAwaitingPayment || _checking) return;
    if (automatic) {
      final now = DateTime.now();
      if (_lastAutoCheck != null && now.difference(_lastAutoCheck!) < const Duration(seconds: 5)) return;
      _lastAutoCheck = now;
    }
    _checking = true;
    if (!automatic) _notice = null;
    _notify();
    try {
      await DonationPaymentService.syncStatus(id);
    } catch (e) {
      if (!automatic) _notice = DonationPaymentService.errorMessage(e);
    } finally {
      _checking = false;
      _notify();
    }
  }

  Future<void> cancelPayment() async {
    final id = _paymentId;
    if (id == null || !isAwaitingPayment || _cancelling) return;
    _cancelling = true;
    _notice = null;
    _notify();
    try {
      final status = await DonationPaymentService.cancel(id);
      if (status == 'pending') _notice = 'This payment could not be cancelled yet. Please try again.';
    } catch (e) {
      _notice = DonationPaymentService.errorMessage(e);
    } finally {
      _cancelling = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _paymentSub?.cancel();
    final completer = _completer;
    if (completer != null && !completer.isCompleted) completer.complete(null);
    super.dispose();
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

  Widget _awaitingPaymentCard(DonationReviewNotifier donation) {
    return DonationReviewSectionCard(
      title: 'Waiting for PayMongo',
      icon: Icons.hourglass_top,
      children: <Widget>[
        Text(
          'Complete your payment on the PayMongo page. This screen continues automatically once PayMongo confirms it — returning to the app alone doesn\'t confirm a payment.',
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
        ),
        if (donation.lastAttemptFailed) ...[
          const SizedBox(height: 8),
          Text(
            'Your last payment attempt didn\'t go through. You can try again on the payment page.',
            style: GoogleFonts.zain(fontSize: 14, color: Colors.redAccent),
          ),
        ],
        if (donation.notice != null) ...[
          const SizedBox(height: 8),
          Text(donation.notice!, style: GoogleFonts.zain(fontSize: 14, color: Colors.redAccent)),
        ],
        const SizedBox(height: 12),
        if (donation.canReopenCheckout)
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: donation.openCheckoutPage,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.yellowrspwn, width: 2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Open payment page', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: donation.isChecking ? null : () => donation.checkPaymentStatus(),
                child: Text(donation.isChecking ? 'Checking…' : 'Check payment status',
                    style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: donation.isCancelling ? null : donation.cancelPayment,
                child: Text(donation.isCancelling ? 'Cancelling…' : 'Cancel payment',
                    style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.redAccent)),
              ),
            ),
          ],
        ),
      ],
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
            // Leaving while waiting is fine: if the payment completes, the
            // backend still records it and it appears in History.
            if (!donation.isStarting) {
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
                          Text(
                            '₱${donation.item.amount.toStringAsFixed(2)}',
                            style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                      if (donation.isSponsorship) ...[
                        const SizedBox(height: 8),
                        // One-time payment covering 30 days — there is no automatic
                        // recurring charge (see the guide's sponsorship note).
                        Text(
                          'Covers the next 30 days of sponsorship',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.greenrspwn, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Renew by:',
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
                              const Icon(Icons.lock_outline, size: 16, color: Colors.green),
                              const SizedBox(width: 4),
                              Text(
                                'Secured by PayMongo',
                                style: GoogleFonts.zain(fontSize: 14, color: Colors.green, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (donation.isAwaitingPayment) ...[
                    const SizedBox(height: 16),
                    _awaitingPaymentCard(donation),
                  ],
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

                          // HistoryItem for summary UI (same id as the
                          // backend's history doc, so they merge).
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
                        } else if (result == null && context.mounted && notifier.errorMessage != null) {
                          _showErrorDialog(context, notifier.errorMessage!);
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
                            donation.isAwaitingPayment ? 'Waiting for payment…' : 'Processing...',
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
            // Only while the checkout is being created — the waiting card's
            // buttons must stay tappable afterwards.
            if (donation.isStarting)
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