import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_info.dart';
import 'package:respawnd1/features/admin/rescue/expenses/expense_list_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';

/// The newest fundraiser made for a case (Create Fundraiser stamps
/// `linkedCaseId`), or null when there is none yet.
final caseFundraiserIdProvider = StreamProvider.autoDispose.family<String?, String>((ref, caseId) {
  return FirebaseFirestore.instance
      .collection('campaigns')
      .where('linkedCaseId', isEqualTo: caseId)
      .snapshots()
      .map((snap) {
    if (snap.docs.isEmpty) return null;
    DateTime created(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final t = d.data()['createdAt'];
      return t is Timestamp ? t.toDate() : DateTime(0);
    }

    final docs = [...snap.docs]..sort((a, b) => created(b).compareTo(created(a)));
    return docs.first.id;
  });
});

/// A case's treatment costs after it has left the Treatment page (Intake
/// Details, and Rescue Details once the case is closed): totals, the
/// expense list and the case's fundraiser. Hidden when the case has no
/// expenses, or when the account may not read them (expenses need the
/// rescue permission or View donations & funds).
class CaseCostsCard extends ConsumerWidget {
  const CaseCostsCard({super.key, required this.rescueCase, this.topGap = kCaseGap});

  final RescueCase rescueCase;

  /// Space above the card, only when it shows.
  final double topGap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(expensesProvider(rescueCase.id)).asData?.value;
    if (expenses == null || expenses.isEmpty) return const SizedBox.shrink();
    final total = expenses.fold<double>(0, (t, e) => t + e.amount);
    final funded = expenses.fold<double>(0, (t, e) => t + e.fundedAmount);
    final fundraiserId = ref.watch(caseFundraiserIdProvider(rescueCase.id)).asData?.value;

    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: CaseCard(
        title: 'Case costs',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CostRow('Total case cost', total),
            CostRow('Funded', funded),
            CostRow('Outstanding', total - funded, strong: true),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpenseListPage(
                        caseId: rescueCase.id,
                        animalOptions: buildCaseAnimalOptions(rescueCase),
                      ),
                    ),
                  ),
                  style: AppButtons.outline,
                  child: Text('View Expenses', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                if (fundraiserId != null)
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: fundraiserId)),
                    ),
                    style: AppButtons.outline,
                    child: Text('View Fundraiser', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One label and peso amount line of a cost summary (Case costs card,
/// Donations > Case costs).
class CostRow extends StatelessWidget {
  const CostRow(this.label, this.amount, {super.key, this.strong = false});

  final String label;
  final double amount;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          Text(formatPeso(amount),
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: strong ? AppColors.textPrimary : AppColors.textSecondary)),
        ],
      ),
    );
  }
}
