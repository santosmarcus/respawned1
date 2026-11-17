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
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
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

class ExpenseOversightPage extends ConsumerWidget {
  const ExpenseOversightPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caseExpenses = ref.watch(allCaseExpensesProvider);
    final general = ref.watch(myGeneralExpensesProvider);
    final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final loading = caseExpenses.isLoading || general.isLoading;
    final all = [...?caseExpenses.asData?.value, ...?general.asData?.value];
    final pending = expensesAwaitingApproval(all);
    final overdue = expensesWithOverdueReceipts(all, settings.effectiveReceiptDueDays);

    Widget header(String text, String help) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          Text(help, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Approvals & receipts', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.textPrimary))
          : ListView(
        children: [
          header(
            'Awaiting approval (${pending.length})',
            settings.expenseApprovalThreshold == null
                ? 'No approval threshold is set. Set one under Shelter setup.'
                : 'Expenses above ${formatPeso(settings.expenseApprovalThreshold!)} need a second financial admin before they are funded.',
          ),
          if (pending.isEmpty)
            const _Empty('Nothing waiting for approval.')
          else
            for (final e in pending)
              ListTile(
                title: Text(e.title, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${formatPeso(e.amount)} · ${e.caseId.isEmpty ? 'General expense' : 'Case ${e.caseId}'}'
                      '${e.approvalRequestedByName == null ? '' : ' · asked by ${e.approvalRequestedByName}'}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                ),
                trailing: !canFinance || e.approvalRequestedBy == uid
                    ? Text(e.approvalRequestedBy == uid ? 'Yours' : '',
                    style: GoogleFonts.zain(color: AppColors.textSecondary))
                    : FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary),
                  onPressed: () async {
                    final ok = await showConfirmActionDialog(context,
                        title: 'Approve expense',
                        message: 'Approve "${e.title}" for ${formatPeso(e.amount)}? '
                            'Funding lines can be added after this.',
                        confirmLabel: 'Approve');
                    if (!ok) return;
                    try {
                      final orgId = await ref.read(dashboardOrgIdProvider.future);
                      await approveExpense(e, organizationId: orgId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                            .showSnackBar(const SnackBar(content: Text('Expense approved.')));
                      }
                    } catch (err) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(err is StateError ? err.message : 'Could not approve: $err'),
                            backgroundColor: AppColors.error));
                      }
                    }
                  },
                  child: const Text('Approve'),
                ),
              ),
          header(
            'Receipts overdue (${overdue.length})',
            'Receipts are due ${settings.effectiveReceiptDueDays} days after an expense is recorded.',
          ),
          if (overdue.isEmpty)
            const _Empty('No overdue receipts.')
          else
            for (final e in overdue)
              ListTile(
                leading: const Icon(Icons.receipt_long, color: AppColors.warning),
                title: Text(e.title, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
                subtitle: Text(
                  '${formatPeso(e.amount)} · ${e.caseId.isEmpty ? 'General expense' : 'Case ${e.caseId}'} · '
                      'due ${formatDate(e.effectiveReceiptDueAt(defaultDays: settings.effectiveReceiptDueDays)!)}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
          const SizedBox(height: 24),
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
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
  );
}
