import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/rescue/expenses/add_edit_expense_sheet.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

/// Every expense entry for one case — editing or deleting here always
/// updates the calculated Total/Funded/Outstanding totals automatically,
/// since those are computed live from this same `expensesProvider` stream,
/// never stored as an editable number.
///
/// [animalOptions] drives an optional animal filter bar (hidden entirely
/// for a single-animal case). When a specific animal is selected, the list
/// shows that animal's own expenses plus every shared case expense —
/// clearly labeled which is which — never a per-animal split of the
/// shared ones (spec §1: no automatic division of shared costs).
class ExpenseListPage extends ConsumerStatefulWidget {
  final String caseId;
  final List<CaseAnimalOption> animalOptions;
  final int? initialAnimalIndex;
  const ExpenseListPage({
    super.key,
    required this.caseId,
    this.animalOptions = const [],
    this.initialAnimalIndex,
  });

  @override
  ConsumerState<ExpenseListPage> createState() => _ExpenseListPageState();
}

class _ExpenseListPageState extends ConsumerState<ExpenseListPage> {
  late int? _selectedAnimalIndex = widget.initialAnimalIndex;

  Future<void> _delete(BuildContext context, WidgetRef ref, Expense expense) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Delete Expense?',
      message: '"${expense.title}" (${formatPeso(expense.amount)}) will be removed and the totals will update.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    try {
      await ref.read(rescueCaseRepositoryProvider).deleteExpense(caseId: widget.caseId, expenseId: expense.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete expense: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _labelForIndex(int i) {
    for (final o in widget.animalOptions) {
      if (o.index == i) return o.label;
    }
    return 'Animal ${i + 1}';
  }

  String? _animalLabelFor(Expense e) {
    if (e.isSharedCaseExpense) return widget.animalOptions.length > 1 ? 'Shared case expense' : null;
    return e.animalIndexes!.map(_labelForIndex).join(' and ');
  }

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(expensesProvider(widget.caseId));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Expenses', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.yellowrspwn,
        onPressed: () => showAddEditExpenseSheet(
          context,
          caseId: widget.caseId,
          animalOptions: widget.animalOptions,
          initialAnimalIndexes: _selectedAnimalIndex != null ? {_selectedAnimalIndex!} : const {},
        ),
        child: const Icon(Icons.add, color: AppColors.textPrimary),
      ),
      body: Column(
        children: [
          if (widget.animalOptions.length > 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: CaseAnimalSelectorBar(
                options: widget.animalOptions,
                selected: _selectedAnimalIndex,
                onChanged: (v) => setState(() => _selectedAnimalIndex = v),
              ),
            ),
          Expanded(
            child: expensesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Could not load expenses: $e',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
        data: (allExpenses) {
          final expenses = _selectedAnimalIndex == null
              ? allExpenses
              : allExpenses.where((e) => e.appliesToAnimal(_selectedAnimalIndex!)).toList();
          if (expenses.isEmpty) {
            return Center(
              child: Text('No expenses recorded yet.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: expenses.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final e = expenses[i];
              final dateStr = e.incurredAt != null
                  ? '${e.incurredAt!.month}/${e.incurredAt!.day}/${e.incurredAt!.year}'
                  : '-';
              final animalLabel = _animalLabelFor(e);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(e.title,
                                    style: GoogleFonts.zain(
                                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              ),
                              if (e.receiptUrl != null && e.receiptUrl!.isNotEmpty)
                                const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.textSecondary),
                            ],
                          ),
                          Text(e.category.label,
                              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                          if (animalLabel != null)
                            Text(animalLabel,
                                style: GoogleFonts.zain(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: e.isFunded ? AppColors.greenrspwn : AppColors.slaterspwn,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(e.fundingSource.label,
                                style: GoogleFonts.zain(
                                    fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                          ),
                          const SizedBox(height: 4),
                          Text(dateStr, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatPeso(e.amount),
                            style: GoogleFonts.zain(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => showAddEditExpenseSheet(
                                context,
                                caseId: widget.caseId,
                                existing: e,
                                animalOptions: widget.animalOptions,
                              ),
                              child: const Icon(Icons.edit_outlined, size: 18, color: AppColors.textPrimary),
                            ),
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () => _delete(context, ref, e),
                              child: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFE05353)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}
