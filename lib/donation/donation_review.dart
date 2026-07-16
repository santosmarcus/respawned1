import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../app_theme.dart';
import '../userauth/history_provider.dart';
import 'models.dart';
import 'donation_summary.dart';
import 'paymongo_service.dart';

final donationReviewProvider = ChangeNotifierProvider.autoDispose.family<DonationReviewNotifier, DonationReviewParams>((ref, params) {
  final payMongoService = PayMongoService(
    secretKey: 'pk_test_your_test_key_here', 
    isTestMode: true,
  );
  
  return DonationReviewNotifier(
    params: params,
    payMongoService: payMongoService,
  );
});

class DonationReviewNotifier extends ChangeNotifier {
  final DonationReviewParams params;
  final PayMongoService payMongoService;
  final double totalAmount;
  bool _isProcessing = false;
  String? _errorMessage;

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
  bool get isSponsorship => params.isSponsorship;

  Future<bool> processPayment() async {
    _isProcessing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await Future.delayed(const Duration(milliseconds: 600));

      bool success = false;
      
      if (payMongoService.isTestMode) {
        success = await payMongoService.simulateTransaction(
          amount: item.amount,
          method: donationMethod,
        );
      } else {
        switch (donationMethod.toLowerCase()) {
          case 'gcash':
          case 'paymaya':
          case 'maya':
            final intent = await payMongoService.createPaymentIntent(amount: item.amount);
            success = intent != null;
            break;
          default:
            await Future.delayed(const Duration(seconds: 1));
            success = true;
        }
      }

      if (!success) {
        _errorMessage = "Payment was declined or failed. Please try again.";
      }

      _isProcessing = false;
      notifyListeners();
      return success;
    } catch (e) {
      _errorMessage = "A secure connection error occurred: ${e.toString()}";
      _isProcessing = false;
      notifyListeners();
      return false;
    }
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
                  if (donation.pet != null) ...[
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
                                color: AppColors.tearspwn.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.pets, color: AppColors.textPrimary),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  donation.pet!.name,
                                  style: GoogleFonts.zain(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                ),
                                Text(
                                  donation.pet!.breed,
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
                        Text(
                          'Recurring charge every 30 days',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.greenrspwn, fontWeight: FontWeight.bold),
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
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: donation.isProcessing
                          ? null
                          : () async {
                              final notifier = ref.read(donationReviewProvider(params).notifier);
                              final success = await notifier.processPayment();
                              
                              if (success && context.mounted) {
                                final refNumber = 'REF-${DateTime.now().millisecondsSinceEpoch}';
                                final now = DateTime.now();
                                
                                // Record in history
                                final historyItem = HistoryItem(
                                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                                  type: donation.isSponsorship ? HistoryType.sponsorship : HistoryType.donation,
                                  organizer: donation.organizationName,
                                  dateTime: now,
                                  refNumber: refNumber,
                                  donationMethod: donation.donationMethod,
                                  amount: donation.item.amount,
                                  itemDescription: donation.item.description,
                                  nextChargeDate: donation.isSponsorship ? now.add(const Duration(days: 30)) : null,
                                  isCancelled: donation.isSponsorship ? false : null,
                                  pet: donation.pet,
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
                              } else if (!success && context.mounted) {
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
