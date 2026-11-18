import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// Expenses waiting for a second financial admin's approval (Donation gap 6).
List<Expense> expensesAwaitingApproval(List<Expense> all) => all.where((e) => e.isAwaitingApproval).toList()
  ..sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));

/// Expenses whose receipt is past due (Donation gap 7), oldest due first.
List<Expense> expensesWithOverdueReceipts(List<Expense> all, int defaultDays, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return all.where((e) => e.isReceiptOverdue(t, defaultDays: defaultDays)).toList()
    ..sort((a, b) => (a.effectiveReceiptDueAt(defaultDays: defaultDays) ?? t)
        .compareTo(b.effectiveReceiptDueAt(defaultDays: defaultDays) ?? t));
}

/// Approves [e] as a financial admin who did not ask for the approval.
/// firestore.rules enforces the same: only the approval fields change, and
/// the approver is not the requester.
Future<void> approveExpense(Expense e, {String? organizationId}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) throw StateError('Sign in again.');
  if (e.approvalRequestedBy == user.uid) {
    throw StateError('Another financial admin has to approve an expense you asked approval for.');
  }
  final db = FirebaseFirestore.instance;
  final ref = e.caseId.isEmpty
      ? db.collection('orgExpenses').doc(e.id)
      : db.collection('cases').doc(e.caseId).collection('expenses').doc(e.id);
  await ref.update({
    'approvalStatus': 'approved',
    'approvedBy': user.uid,
    'approvedByName': user.displayName,
    'approvedAt': FieldValue.serverTimestamp(),
    'approvedAmount': e.amount,
  });
  await AuditLogRepository().log(
    category: AuditCategory.expenses,
    action: 'Expense approved',
    actorId: user.uid,
    actorEmail: user.email,
    actorName: user.displayName,
    organizationId: organizationId,
    targetType: e.caseId.isEmpty ? 'General expense' : 'Case expense',
    targetId: e.id,
    newValues: {'title': e.title, 'amount': e.amount, 'requestedBy': e.approvalRequestedByName},
  );
}

/// Approvals & receipts on its own screen (dashboard shortcut). The
/// Donations home shows the same content as its Approvals tab.
class ExpenseOversightPage extends StatelessWidget {
  const ExpenseOversightPage({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: AppColors.background,
        appBar: AdminAppBar(title: 'Approvals & Receipts', showDrawerButton: false),
        body: ExpenseOversightTab(),
      );
}

/// Expenses waiting for a second financial admin, and receipts past due.
class ExpenseOversightTab extends ConsumerWidget {
  const ExpenseOversightTab({super.key});

  Future<void> _approve(BuildContext context, WidgetRef ref, Expense e) async {
    final ok = await confirmAction(context,
        title: 'Approve expense',
        message: 'Approve "${e.title}" for ${formatPeso(e.amount)}? Funding lines can be added after this.',
        confirmLabel: 'Approve');
    if (!ok) return;
    try {
      final orgId = await ref.read(dashboardOrgIdProvider.future);
      await approveExpense(e, organizationId: orgId);
      if (context.mounted) showAdminSnack(context, 'Expense approved.');
    } catch (err) {
      if (context.mounted) {
        showAdminSnack(context, err is StateError ? err.message : 'Could not approve: $err', error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseExpenses = ref.watch(allCaseExpensesProvider);
    final general = ref.watch(myGeneralExpensesProvider);
    final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (caseExpenses.isLoading || general.isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));
    }
    final all = [...?caseExpenses.asData?.value, ...?general.asData?.value];
    final pending = expensesAwaitingApproval(all);
    final overdue = expensesWithOverdueReceipts(all, settings.effectiveReceiptDueDays);
    String where(Expense e) => e.caseId.isEmpty ? 'General expense' : 'Case ${e.caseId}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        DonationSectionHeader(
          'Awaiting approval (${pending.length})',
          help: settings.expenseApprovalThreshold == null
              ? 'No approval threshold is set. Set one under Shelter setup.'
              : 'Expenses above ${formatPeso(settings.expenseApprovalThreshold!)} need a second financial admin '
                  'before they are funded.',
        ),
        if (pending.isEmpty)
          const _Empty('Nothing waiting for approval.')
        else
          for (final e in pending)
            _ExpenseCard(
              title: e.title,
              subtitle: '${formatPeso(e.amount)} · ${where(e)}'
                  '${e.approvalRequestedByName == null ? '' : ' · asked by ${e.approvalRequestedByName}'}',
              trailing: e.approvalRequestedBy == uid
                  ? const DonationPill('Yours', AppColors.slaterspwn)
                  : !canFinance
                      ? null
                      : ElevatedButton(
                          style: AppButtons.primary.copyWith(
                            padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 18, vertical: 8)),
                          ),
                          onPressed: () => _approve(context, ref, e),
                          child: const Text('Approve'),
                        ),
            ),
        const SizedBox(height: 20),
        DonationSectionHeader(
          'Receipts overdue (${overdue.length})',
          help: 'Receipts are due ${settings.effectiveReceiptDueDays} days after an expense is recorded.',
        ),
        if (overdue.isEmpty)
          const _Empty('No overdue receipts.')
        else
          for (final e in overdue)
            _ExpenseCard(
              title: e.title,
              subtitle: '${formatPeso(e.amount)} · ${where(e)}',
              trailing: DonationPill(
                'Due ${formatDate(e.effectiveReceiptDueAt(defaultDays: settings.effectiveReceiptDueDays)!)}',
                AppColors.warning,
              ),
            ),
      ],
    );
  }
}

class _ExpenseCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _ExpenseCard({required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );
}
