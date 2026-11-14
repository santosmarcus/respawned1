import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/repos/general_expense_repository.dart';
import 'package:respawnd1/core/services/expense_funding_service.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/donation/models.dart';

/// Add or edit a single expense record. Returns true if a write actually
/// happened (caller can rely on the live `expensesProvider` stream to
/// reflect it — this is just for e.g. showing a confirmation snackbar).
///
/// A rescue case's bill passes [caseId]. The organization's general running
/// costs pass [organizationId] instead and are saved to `orgExpenses`.
///
/// A funding line paid from a campaign can be linked to it (financial admins
/// only): saving records the same amount as spending on that campaign, so
/// donors see the bill their money paid; removing the line voids it again.
///
/// [animalOptions] — the case's animals, for the "Applies to" selector
/// (One animal / Multiple animals / Shared case expense); pass an empty or
/// single-entry list to skip it entirely for a single-animal case, where
/// every expense is implicitly case-wide. [initialAnimalIndexes] pre-selects
/// the currently-viewed animal when opened from a specific-animal context.
Future<bool> showAddEditExpenseSheet(
  BuildContext context, {
  String? caseId,
  String? organizationId,
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
      organizationId: organizationId,
      existing: existing,
      animalOptions: animalOptions,
      initialAnimalIndexes: initialAnimalIndexes,
    ),
  );
  return result ?? false;
}

class _AddEditExpenseSheetBody extends ConsumerStatefulWidget {
  final String? caseId;
  final String? organizationId;
  final Expense? existing;
  final List<CaseAnimalOption> animalOptions;
  final Set<int> initialAnimalIndexes;
  const _AddEditExpenseSheetBody({
    required this.caseId,
    this.organizationId,
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
  // Category starts unselected (null) for a new expense — rather than
  // silently defaulting to Other — so "must be selected" is a real,
  // checkable requirement instead of one that's trivially satisfied by a
  // default nobody chose.
  ExpenseCategory? _category;

  // Funding lines (source + amount). None = unfunded; lines covering less
  // than the amount leave the rest outstanding (e.g. treatment paid partly
  // from the organization budget before a fundraiser covers the rest).
  late final List<_FundingRow> _fundingRows = [
    for (final f in widget.existing?.fundings ?? const <ExpenseFunding>[])
      _FundingRow(
        f.source,
        TextEditingController(text: _plainAmount(f.amount)),
        campaignId: f.campaignId,
        campaignTitle: f.campaignTitle,
        allocationId: f.allocationId,
      ),
  ];

  static String _plainAmount(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
  late DateTime _incurredAt = widget.existing?.incurredAt ?? DateTime.now();
  late Set<int> _animalIndexes =
      (widget.existing?.animalIndexes?.toSet()) ?? widget.initialAnimalIndexes.toSet();

  // Receipt — uploaded immediately on pick (not deferred to Save) so
  // "replacing before saving" is just picking again, and so a failed
  // upload surfaces its own retry affordance right where it happened
  // rather than only at Save time.
  final _picker = ImagePicker();
  String? _receiptUrl; // existing (edit) or freshly-uploaded url
  bool _uploadingReceipt = false;
  String? _receiptError;
  // A legacy expense that already existed with no receipt — never forced
  // to retroactively add one, only labeled, per spec.
  bool get _isLegacyWithoutReceipt => _isEditing && (widget.existing!.receiptUrl == null || widget.existing!.receiptUrl!.isEmpty);

  // Field-level errors — shown directly under each field, not only as one
  // generic message. _errorMessage is reserved for the actual write
  // failing (network/Firestore error), which isn't a "which field" problem.
  String? _titleError;
  String? _categoryError;
  String? _amountError;
  String? _fundingError;
  String? _errorMessage;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;
  bool get _isGeneral => widget.caseId == null;

  /// Campaigns a line can be paid from: this organization's, with money
  /// available, and (for restricted funds) raised for this same case.
  List<DonationListing> _linkableCampaigns(List<DonationListing> all, String? orgId) => [
        for (final l in all)
          if (l.organizationId == orgId &&
              l.type == 'donation' &&
              !l.isDraft &&
              !l.isArchived &&
              l.availableBalance > 0 &&
              (!l.restricted || (l.linkedCaseId != null && l.linkedCaseId == widget.caseId)))
            l,
      ];

  @override
  void initState() {
    super.initState();
    _category = widget.existing?.category;
    _receiptUrl = widget.existing?.receiptUrl;
  }

  double? get _enteredAmount => double.tryParse(_amountController.text.trim());

  double get _fundedTotal =>
      _fundingRows.fold<double>(0, (sum, r) => sum + (double.tryParse(r.amount.text.trim()) ?? 0));

  /// New line pre-filled with whatever is still uncovered, so the common
  /// "one source pays it all" case is a single tap plus picking the source.
  void _addFundingRow() {
    final remaining = (_enteredAmount ?? 0) - _fundedTotal;
    setState(() {
      _fundingRows.add(_FundingRow(null, TextEditingController(text: remaining > 0 ? _plainAmount(remaining) : '')));
      _fundingError = null;
    });
  }

  void _removeFundingRow(int index) {
    setState(() {
      _fundingRows.removeAt(index).amount.dispose();
      _fundingError = null;
    });
  }

  /// Null when the lines are valid against [amount].
  String? _validateFundings(double? amount) {
    final seen = <String>{};
    for (final row in _fundingRows) {
      if (row.source == null) return 'Pick a source for every funding line.';
      if (!seen.add('${row.source!.name}/${row.campaignId ?? ''}')) {
        return 'Each source (or campaign) can only appear once.';
      }
      final value = double.tryParse(row.amount.text.trim());
      if (value == null || value <= 0) return 'Enter an amount greater than zero for every funding line.';
    }
    if (amount != null && _fundedTotal > amount + 0.005) {
      return 'Funding adds up to more than the expense amount.';
    }
    return null;
  }

  Future<void> _pickReceipt() async {
    final picked = await pickImageWithSource(context, _picker, imageQuality: 85);
    if (picked == null) return;
    setState(() {
      _uploadingReceipt = true;
      _receiptError = null;
    });
    try {
      final ext = picked.path.contains('.') ? picked.path.split('.').last : 'jpg';
      // Independent of the eventual expense doc id (none exists yet for a
      // new expense) — timestamp-keyed, same convention already used
      // elsewhere in this module for pre-doc-id uploads.
      final folder = _isGeneral
          ? 'organizations/${widget.organizationId}/expenseReceipts'
          : 'cases/${widget.caseId}/expenseReceipts';
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}.$ext';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _receiptUrl = url;
          _uploadingReceipt = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingReceipt = false;
          _receiptError = 'Could not upload receipt: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    for (final row in _fundingRows) {
      row.amount.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_uploadingReceipt) return;
    final title = _titleController.text.trim();
    final amount = double.tryParse(_amountController.text.trim());
    // A legacy expense (already existed with no receipt) is never forced
    // to retroactively add one just because it's being edited — every
    // other case (new expense, or an existing expense that already had a
    // receipt) requires one.
    final receiptRequired = !_isLegacyWithoutReceipt;

    // Every required field is checked at once (not short-circuited on the
    // first failure) so every problem is visible in one pass.
    setState(() {
      _titleError = title.isEmpty ? 'Title is required.' : null;
      _categoryError = _category == null ? 'Select a category.' : null;
      _amountError = (amount == null || amount <= 0) ? 'Enter an amount greater than zero.' : null;
      _fundingError = _validateFundings(amount);
      _receiptError = (receiptRequired && (_receiptUrl == null || _receiptUrl!.isEmpty))
          ? 'Attach a receipt before saving.'
          : null;
    });

    if (_titleError != null ||
        _categoryError != null ||
        _amountError != null ||
        _fundingError != null ||
        _receiptError != null) {
      return;
    }

    setState(() {
      _errorMessage = null;
      _saving = true;
    });

    final lines = [
      for (final row in _fundingRows)
        ExpenseFunding(
          source: row.source!,
          amount: double.parse(row.amount.text.trim()),
          campaignId: row.campaignId,
          campaignTitle: row.campaignTitle,
          allocationId: row.allocationId,
        ),
    ];
    final funding = ExpenseFundingService();
    List<ExpenseFunding> linked;
    try {
      // Spending is recorded on the campaigns first; if that fails nothing
      // is saved.
      linked = await funding.recordNewLinks(
        lines: lines,
        title: title,
        category: _category!,
        caseId: widget.caseId,
        receiptUrl: _receiptUrl,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Could not record the spending on the campaign: $e';
        });
      }
      return;
    }
    final newLinks = [
      for (var i = 0; i < linked.length; i++)
        if (linked[i].allocationId != null && lines[i].allocationId == null) linked[i],
    ];

    final expense = Expense(
      id: widget.existing?.id ?? '',
      caseId: widget.caseId ?? '',
      title: title,
      category: _category!,
      amount: amount!,
      fundings: linked,
      receiptUrl: _receiptUrl,
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      incurredAt: _incurredAt,
      createdBy: widget.existing?.createdBy ?? 'Admin Staff',
      animalIndexes: _animalIndexes.isEmpty ? null : _animalIndexes.toList(),
    );

    try {
      if (_isGeneral) {
        final repo = GeneralExpenseRepository();
        if (_isEditing) {
          await repo.update(organizationId: widget.organizationId!, expense: expense, before: widget.existing);
        } else {
          await repo.add(organizationId: widget.organizationId!, expense: expense);
        }
      } else {
        final repo = ref.read(rescueCaseRepositoryProvider);
        if (_isEditing) {
          await repo.updateExpense(caseId: widget.caseId!, expense: expense);
        } else {
          await repo.addExpense(caseId: widget.caseId!, expense: expense);
        }
      }
    } catch (e) {
      // Undo the spending just recorded for a bill that wasn't saved.
      try {
        await funding.voidRemovedLinks(before: newLinks, reason: 'Expense was not saved');
      } catch (_) {}
      if (mounted) {
        setState(() {
          _saving = false;
          _errorMessage = 'Could not save expense: $e';
        });
      }
      return;
    }
    // Lines taken off the expense give their money back to the campaign.
    String? warning;
    try {
      await funding.voidRemovedLinks(
        before: widget.existing?.fundings ?? const [],
        after: linked,
        reason: 'Removed from the expense',
      );
    } catch (e) {
      warning = 'Saved, but a removed campaign line could not be undone: $e';
    }
    if (!mounted) return;
    if (warning != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(warning), backgroundColor: AppColors.error));
    }
    Navigator.pop(context, true);
  }

  Widget _fundingRowEditor(int i, bool canFinance, List<DonationListing> campaigns) {
    final row = _fundingRows[i];
    final locked = row.allocationId != null;
    final linkable = row.source == FundingSource.fundraiser || row.source == FundingSource.donationFund;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: IgnorePointer(
                  ignoring: locked,
                  child: _EnumDropdown<FundingSource>(
                    value: row.source,
                    hint: 'Source',
                    items: FundingSource.fundable,
                    labelOf: (s) => s.label,
                    onChanged: (v) => setState(() {
                      row.source = v;
                      if (v != FundingSource.fundraiser && v != FundingSource.donationFund) {
                        row.campaignId = null;
                        row.campaignTitle = null;
                      }
                      _fundingError = null;
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: row.amount,
                  readOnly: locked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() => _fundingError = null),
                  decoration: const InputDecoration(
                    prefixText: '₱ ',
                    hintText: '0',
                    isDense: true,
                    contentPadding: EdgeInsets.only(bottom: 8),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
                  ),
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
              IconButton(
                tooltip: 'Remove funding line',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: AppColors.textSecondary),
                onPressed: () => _removeFundingRow(i),
              ),
            ],
          ),
          if (locked)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Paid from "${row.campaignTitle ?? 'campaign'}" and recorded on it. Remove the line to give the money back.',
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
              ),
            )
          else if (linkable && canFinance)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: DropdownButtonFormField<String?>(
                key: ValueKey('campaign-$i-${row.campaignId}'),
                initialValue: row.campaignId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Paid from campaign',
                  isDense: true,
                  contentPadding: EdgeInsets.only(bottom: 8),
                ),
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Not linked to a campaign')),
                  for (final l in campaigns)
                    DropdownMenuItem<String?>(
                      value: l.id,
                      child: Text('${l.title} · ${formatPeso(l.availableBalance)} available',
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (id) => setState(() {
                  row.campaignId = id;
                  row.campaignTitle = id == null ? null : campaigns.firstWhere((l) => l.id == id).title;
                  _fundingError = null;
                }),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final orgId = widget.organizationId ?? ref.watch(currentOrganizationIdProvider).asData?.value;
    final campaigns = canFinance
        ? _linkableCampaigns(ref.watch(adminCampaignsProvider).asData?.value ?? const [], orgId)
        : const <DonationListing>[];
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
            Text(
                _isGeneral
                    ? (_isEditing ? 'Edit General Expense' : 'Add General Expense')
                    : (_isEditing ? 'Edit Expense' : 'Add Expense'),
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 16),

            _Label('Title', required: true),
            _Input(
              controller: _titleController,
              hint: _isGeneral ? 'e.g. Electricity bill, October' : 'e.g. Anti-rabies vaccine',
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
              items: [
                ...(_isGeneral ? ExpenseCategory.forGeneral : ExpenseCategory.forCase),
                // A record saved before the lists split keeps its category.
                if (_category != null &&
                    !(_isGeneral ? ExpenseCategory.forGeneral : ExpenseCategory.forCase).contains(_category))
                  _category!,
              ],
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
              // Rebuilds the funding summary as the amount changes.
              onChanged: (_) => setState(() => _amountError = null),
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

            _Label('Funding'),
            Text(
              'Where the money came from. Leave empty if it isn\'t funded yet — '
              'anything not covered stays outstanding. Financial admins can link a Fundraiser or '
              'Donation Fund line to the campaign that paid it.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
            ),
            for (var i = 0; i < _fundingRows.length; i++) _fundingRowEditor(i, canFinance, campaigns),
            if (_fundingRows.length < 6)
              TextButton.icon(
                onPressed: _addFundingRow,
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.add, size: 16, color: AppColors.textPrimary),
                label: Text('Add funding source',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            Builder(builder: (context) {
              final amount = _enteredAmount;
              final funded = _fundedTotal;
              final text = amount == null || amount <= 0
                  ? (funded > 0 ? 'Funded ${formatPeso(funded)}' : 'Unfunded')
                  : 'Funded ${formatPeso(funded)} of ${formatPeso(amount)} · '
                      '${formatPeso((amount - funded).clamp(0, amount))} outstanding';
              return Text(text,
                  style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
            }),
            if (_fundingError != null) _FieldError(_fundingError!),
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
                    Text(formatDate(_incurredAt),
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textPrimary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            _Label('Receipt', required: !_isLegacyWithoutReceipt),
            if (_isLegacyWithoutReceipt)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('Legacy expense — no receipt on file. You may add one, but it is not required to save.',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
              ),
            GestureDetector(
              onTap: _uploadingReceipt ? null : _pickReceipt,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  border: Border.all(color: _receiptError != null ? AppColors.error : AppColors.slaterspwn),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _uploadingReceipt
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                      )
                    : (_receiptUrl != null && _receiptUrl!.isNotEmpty)
                        ? Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(_receiptUrl!,
                                    width: 48, height: 48, fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                        width: 48, height: 48, color: AppColors.tearspwn, child: const Icon(Icons.receipt_long_outlined))),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text('Receipt attached — tap to replace',
                                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
                              ),
                              const Icon(Icons.check_circle, color: AppColors.greenrspwn, size: 18),
                            ],
                          )
                        : Center(
                            child: Text('Attach receipt', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                          ),
              ),
            ),
            if (_receiptError != null) _FieldError(_receiptError!),
            const SizedBox(height: 14),

            _Label('Notes'),
            _Input(controller: _notesController, hint: 'Optional notes'),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Text(_errorMessage!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.error)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: AppButtons.primary,
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

class _FundingRow {
  FundingSource? source;
  final TextEditingController amount;
  String? campaignId;
  String? campaignTitle;

  /// Set once the amount is recorded on the campaign; the line is then
  /// fixed until it is removed.
  final String? allocationId;
  _FundingRow(this.source, this.amount, {this.campaignId, this.campaignTitle, this.allocationId});
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
            if (required) const Text(' *', style: TextStyle(color: AppColors.error, fontSize: 12)),
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
        child: Text(message, style: GoogleFonts.zain(fontSize: 11, color: AppColors.error)),
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
      key: ValueKey(value),
      initialValue: value,
      // Long labels ("Organization Budget") ellipsize instead of
      // overflowing the narrow funding-line column.
      isExpanded: true,
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
