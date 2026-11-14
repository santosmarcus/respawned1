import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/repos/general_expense_repository.dart';
import 'package:respawnd1/core/services/expense_funding_service.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/expenses/add_edit_expense_sheet.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';

final generalExpensesProvider = StreamProvider.autoDispose.family<List<Expense>, String>((ref, orgId) {
  return GeneralExpenseRepository().watch(orgId);
});

/// The organization's running costs that aren't a rescue case's bill:
/// utilities, rent, food and supplies, staff compensation. Financial admins
/// only. Each can be paid from a campaign, which records it on that
/// campaign's Fund Tracking.
class GeneralExpensesPage extends ConsumerStatefulWidget {
  const GeneralExpensesPage({super.key});

  @override
  ConsumerState<GeneralExpensesPage> createState() => _GeneralExpensesPageState();
}

class _GeneralExpensesPageState extends ConsumerState<GeneralExpensesPage> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(String orgId, Expense e) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Delete expense?',
      message: '"${e.title}" (${formatPeso(e.amount)}) will be removed. Any amount paid from a campaign goes back '
          'to that campaign\'s balance.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ExpenseFundingService().voidRemovedLinks(before: e.fundings, reason: 'Expense deleted');
      await GeneralExpenseRepository().delete(organizationId: orgId, expense: e);
      messenger.showSnackBar(appSnackBar('Expense deleted.', kind: AppMessageKind.success));
    } catch (err) {
      messenger.showSnackBar(appSnackBar('Could not delete the expense: $err', kind: AppMessageKind.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider);
    final orgId = ref.watch(currentOrganizationIdProvider).asData?.value;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AdminAppBar(title: 'General Expenses', showDrawerButton: false),
      floatingActionButton: (canFinance.asData?.value ?? false) && orgId != null
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              onPressed: () => showAddEditExpenseSheet(context, organizationId: orgId),
              icon: const Icon(Icons.add),
              label: Text('Add Expense', style: GoogleFonts.tiltWarp(fontSize: 14)),
            )
          : null,
      body: canFinance.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const AdminListMessage('Could not check your permissions.'),
        data: (allowed) {
          if (!allowed) {
            return const AdminListMessage('Only financial administrators can see general expenses.');
          }
          if (orgId == null) return const AdminListMessage('Link your account to an organization first.');
          final async = ref.watch(generalExpensesProvider(orgId));
          return Column(
            children: [
              AdminSearchBar(
                controller: _search,
                hintText: 'Search title, category or campaign…',
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
              Expanded(
                child: async.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => AdminListMessage('Could not load expenses.',
                      onRetry: () => ref.invalidate(generalExpensesProvider(orgId))),
                  data: (all) {
                    final list = [
                      for (final e in all)
                        if (_query.isEmpty ||
                            e.title.toLowerCase().contains(_query) ||
                            e.category.label.toLowerCase().contains(_query) ||
                            e.fundingLabel.toLowerCase().contains(_query))
                          e,
                    ];
                    if (all.isEmpty) {
                      return const AdminListMessage(
                          'No general expenses yet. Add utilities, rent, supplies or staff pay with Add Expense.');
                    }
                    if (list.isEmpty) return const AdminListMessage('No expenses match your search.');
                    final now = DateTime.now();
                    final thisMonth = all.where((e) =>
                        e.incurredAt != null && e.incurredAt!.year == now.year && e.incurredAt!.month == now.month);
                    final monthTotal = thisMonth.fold<double>(0, (s, e) => s + e.amount);
                    final outstanding = all.fold<double>(0, (s, e) => s + e.outstandingAmount);
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                      children: [
                        Row(
                          children: [
                            Expanded(child: _Figure('This month', formatPeso(monthTotal))),
                            const SizedBox(width: 10),
                            Expanded(child: _Figure('Not yet funded', formatPeso(outstanding))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        for (final e in list)
                          _ExpenseTile(
                            expense: e,
                            onEdit: () => showAddEditExpenseSheet(context, organizationId: orgId, existing: e),
                            onDelete: () => _delete(orgId, e),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Text(value, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, required this.onEdit, required this.onDelete});

  final Expense expense;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final e = expense;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.title, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text('${e.category.label} · ${formatDateOr(e.incurredAt, 'No date')}',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text(
                  e.isUnfunded
                      ? 'Unfunded'
                      : '${e.fundingLabel}${e.isPartlyFunded ? ' · ${formatPeso(e.outstandingAmount)} outstanding' : ''}',
                  style: GoogleFonts.zain(fontSize: 12, color: e.isFullyFunded ? AppColors.success : AppColors.textPrimary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatPeso(e.amount),
                  style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
