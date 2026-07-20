import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Add or edit a single expense record. Returns true if a write actually
/// happened (caller can rely on the live `expensesProvider` stream to
/// reflect it — this is just for e.g. showing a confirmation snackbar).
Future<bool> showAddEditExpenseSheet(
  BuildContext context, {
  required String caseId,
  Expense? existing,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddEditExpenseSheetBody(caseId: caseId, existing: existing),
  );
  return result ?? false;
}

class _AddEditExpenseSheetBody extends ConsumerStatefulWidget {
  final String caseId;
  final Expense? existing;
  const _AddEditExpenseSheetBody({required this.caseId, this.existing});

  @override
  ConsumerState<_AddEditExpenseSheetBody> createState() => _AddEditExpenseSheetBodyState();
}

class _AddEditExpenseSheetBodyState extends ConsumerState<_AddEditExpenseSheetBody> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _amountController =
      TextEditingController(text: widget.existing != null ? widget.existing!.amount.toStringAsFixed(0) : '');
  late final _notesController = TextEditingController(text: widget.existing?.notes ?? '');
  late ExpenseCategory _category = widget.existing?.category ?? ExpenseCategory.other;
  late FundingSource _fundingSource = widget.existing?.fundingSource ?? FundingSource.unfunded;
  late DateTime _incurredAt = widget.existing?.incurredAt ?? DateTime.now();
  String? _errorMessage;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());

    if (title.isEmpty) {
      setState(() => _errorMessage = 'Please enter a title.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _errorMessage = 'Amount must be greater than zero.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _saving = true;
    });

    final expense = Expense(
      id: widget.existing?.id ?? '',
      caseId: widget.caseId,
      title: title,
      category: _category,
      amount: amount,
      fundingSource: _fundingSource,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      incurredAt: _incurredAt,
      createdBy: widget.existing?.createdBy ?? 'Admin Staff',
    );

    try {
      final repo = ref.read(rescueCaseRepositoryProvider);
      if (_isEditing) {
        await repo.updateExpense(caseId: widget.caseId, expense: expense);
      } else {
        await repo.addExpense(caseId: widget.caseId, expense: expense);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Could not save expense: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text(_isEditing ? 'Edit Expense' : 'Add Expense',
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            _Label('Title'),
            _Input(controller: _titleController, hint: 'e.g. Anti-rabies vaccine'),
            const SizedBox(height: 14),

            _Label('Category'),
            _EnumDropdown<ExpenseCategory>(
              value: _category,
              items: ExpenseCategory.values,
              labelOf: (c) => c.label,
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 14),

            _Label('Amount'),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '₱ ',
                hintText: '0',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                focusedBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),

            _Label('Funding Source'),
            _EnumDropdown<FundingSource>(
              value: _fundingSource,
              items: FundingSource.values,
              labelOf: (s) => s.label,
              onChanged: (v) => setState(() => _fundingSource = v!),
            ),
            const SizedBox(height: 14),

            _Label('Date Incurred'),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _incurredAt,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _incurredAt = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${_incurredAt.month}/${_incurredAt.day}/${_incurredAt.year}',
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            _Label('Receipt'),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.slaterspwn),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text('Attach receipt (optional)',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ),
            const SizedBox(height: 14),

            _Label('Notes'),
            _Input(controller: _notesController, hint: 'Optional notes'),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(_errorMessage!, style: GoogleFonts.zain(fontSize: 12, color: Colors.redAccent)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text(_isEditing ? 'Save Changes' : 'Add Expense',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text,
            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      );
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _Input({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
        isDense: true,
        contentPadding: const EdgeInsets.only(bottom: 8),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder:
            const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
      ),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
    );
  }
}

class _EnumDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  const _EnumDropdown({required this.value, required this.items, required this.labelOf, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.only(bottom: 8),
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
      ),
      items: items
          .map((item) => DropdownMenuItem(
              value: item,
              child: Text(labelOf(item), style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))))
          .toList(),
      onChanged: onChanged,
    );
  }
}
