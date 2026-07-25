import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';

/// Add or edit a single expense record. Returns true if a write actually
/// happened (caller can rely on the live `expensesProvider` stream to
/// reflect it — this is just for e.g. showing a confirmation snackbar).
///
/// [animalOptions] — the case's animals, for the "Applies to" selector
/// (One animal / Multiple animals / Shared case expense); pass an empty or
/// single-entry list to skip it entirely for a single-animal case, where
/// every expense is implicitly case-wide. [initialAnimalIndexes] pre-selects
/// the currently-viewed animal when opened from a specific-animal context.
Future<bool> showAddEditExpenseSheet(
  BuildContext context, {
  required String caseId,
  Expense? existing,
  List<CaseAnimalOption> animalOptions = const [],
  Set<int> initialAnimalIndexes = const {},
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AddEditExpenseSheetBody(
      caseId: caseId,
      existing: existing,
      animalOptions: animalOptions,
      initialAnimalIndexes: initialAnimalIndexes,
    ),
  );
  return result ?? false;
}

class _AddEditExpenseSheetBody extends ConsumerStatefulWidget {
  final String caseId;
  final Expense? existing;
  final List<CaseAnimalOption> animalOptions;
  final Set<int> initialAnimalIndexes;
  const _AddEditExpenseSheetBody({
    required this.caseId,
    this.existing,
    this.animalOptions = const [],
    this.initialAnimalIndexes = const {},
  });

  @override
  ConsumerState<_AddEditExpenseSheetBody> createState() => _AddEditExpenseSheetBodyState();
}

class _AddEditExpenseSheetBodyState extends ConsumerState<_AddEditExpenseSheetBody> {
  late final _titleController = TextEditingController(text: widget.existing?.title ?? '');
  late final _amountController =
      TextEditingController(text: widget.existing != null ? widget.existing!.amount.toStringAsFixed(0) : '');
  late final _notesController = TextEditingController(text: widget.existing?.notes ?? '');
  // Category/Funding Source start unselected (null) for a new expense —
  // rather than silently defaulting to Other/Unfunded — so "must be
  // selected" is a real, checkable requirement instead of one that's
  // trivially satisfied by a default nobody chose.
  ExpenseCategory? _category;
  FundingSource? _fundingSource;
  late DateTime _incurredAt = widget.existing?.incurredAt ?? DateTime.now();
  late Set<int> _animalIndexes =
      (widget.existing?.animalIndexes?.toSet()) ?? widget.initialAnimalIndexes.toSet();

  // Field-level errors — shown directly under each field, not only as one
  // generic message. _errorMessage is reserved for the actual write
  // failing (network/Firestore error), which isn't a "which field" problem.
  String? _titleError;
  String? _categoryError;
  String? _amountError;
  String? _fundingSourceError;
  String? _errorMessage;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _category = widget.existing?.category;
    _fundingSource = widget.existing?.fundingSource;
  }

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

    // Every required field is checked at once (not short-circuited on the
    // first failure) so every problem is visible in one pass.
    setState(() {
      _titleError = title.isEmpty ? 'Title is required.' : null;
      _categoryError = _category == null ? 'Select a category.' : null;
      _amountError = (amount == null || amount <= 0) ? 'Enter an amount greater than zero.' : null;
      _fundingSourceError = _fundingSource == null ? 'Select a funding source.' : null;
    });

    if (_titleError != null || _categoryError != null || _amountError != null || _fundingSourceError != null) {
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
      category: _category!,
      amount: amount!,
      fundingSource: _fundingSource!,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      incurredAt: _incurredAt,
      createdBy: widget.existing?.createdBy ?? 'Admin Staff',
      animalIndexes: _animalIndexes.isEmpty ? null : _animalIndexes.toList(),
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

            _Label('Title', required: true),
            _Input(
              controller: _titleController,
              hint: 'e.g. Anti-rabies vaccine',
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            if (_titleError != null) _FieldError(_titleError!),
            const SizedBox(height: 14),

            if (widget.animalOptions.length > 1) ...[
              _Label('Applies to'),
              CaseAnimalMultiSelectBar(
                options: widget.animalOptions,
                selected: _animalIndexes,
                onChanged: (next) => setState(() => _animalIndexes = next),
              ),
              const SizedBox(height: 14),
            ],

            _Label('Category', required: true),
            _EnumDropdown<ExpenseCategory>(
              value: _category,
              hint: 'Select',
              items: ExpenseCategory.values,
              labelOf: (c) => c.label,
              onChanged: (v) => setState(() {
                _category = v;
                _categoryError = null;
              }),
            ),
            if (_categoryError != null) _FieldError(_categoryError!),
            const SizedBox(height: 14),

            _Label('Amount', required: true),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) {
                if (_amountError != null) setState(() => _amountError = null);
              },
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
            if (_amountError != null) _FieldError(_amountError!),
            const SizedBox(height: 14),

            _Label('Funding Source', required: true),
            _EnumDropdown<FundingSource>(
              value: _fundingSource,
              hint: 'Select',
              items: FundingSource.values,
              labelOf: (s) => s.label,
              onChanged: (v) => setState(() {
                _fundingSource = v;
                _fundingSourceError = null;
              }),
            ),
            if (_fundingSourceError != null) _FieldError(_fundingSourceError!),
            const SizedBox(height: 14),

            _Label('Date', required: true),
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
  final bool required;
  const _Label(this.text, {this.required = false});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Text(text,
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            if (required) const Text(' *', style: TextStyle(color: Colors.red, fontSize: 12)),
          ],
        ),
      );
}

/// Shown directly under a field when it fails validation — field-level,
/// not just a single generic message at the bottom of the sheet.
class _FieldError extends StatelessWidget {
  final String message;
  const _FieldError(this.message);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(message, style: GoogleFonts.zain(fontSize: 11, color: Colors.redAccent)),
      );
}

class _Input extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  const _Input({required this.controller, required this.hint, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
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
  final T? value;
  final String hint;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T?> onChanged;
  const _EnumDropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      hint: Text(hint, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
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
