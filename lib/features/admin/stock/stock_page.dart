import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/stock/stock_service.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

const stockCategories = [
  'Food & Water',
  'Medicine & Treatment',
  'Supplies & Equipment',
  'Hygiene & Cleaning',
  'Transport Crates',
  'Others',
];

String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Opens the "New stock item" sheet and saves what the admin enters. Used by
/// the In Kind tab's FAB on the Donations home and by [StockPage].
Future<void> addStockItem(BuildContext context, WidgetRef ref) async {
  final res = await showAdminFormSheet<_NewItem>(context, const _NewItemSheet());
  if (res == null || !context.mounted) return;
  final orgId = await ref.read(dashboardOrgIdProvider.future);
  if (orgId == null) return;
  try {
    await StockService(orgId).addItem(
      name: res.name,
      category: res.category,
      unit: res.unit,
      quantity: res.quantity,
      lowStockThreshold: res.threshold,
    );
    if (context.mounted) showAdminSnack(context, '${res.name} added.');
  } catch (e) {
    if (context.mounted) showAdminSnack(context, 'Could not add: $e', error: true);
  }
}

/// Stock on its own screen (dashboard shortcut). The Donations home shows
/// the same list as its In Kind tab.
class StockPage extends ConsumerWidget {
  const StockPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const AdminAppBar(title: 'In Kind Stock', showDrawerButton: false),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.yellowrspwn,
        foregroundColor: AppColors.textPrimary,
        onPressed: () => addStockItem(context, ref),
        icon: const Icon(Icons.add),
        label: Text('Add item', style: GoogleFonts.tiltWarp(fontSize: 14)),
      ),
      body: const StockTab(),
    );
  }
}

/// Donation gap 5: what the shelter has on hand. Received in-kind goods
/// arrive here automatically; staff record usage, purchases and low-stock
/// levels. A food item at or below its level makes the "Food & medicine"
/// readiness factor read Constrained. No app bar or FAB of its own: the
/// host screen adds "Add item" (see [addStockItem]).
class StockTab extends ConsumerWidget {
  const StockTab({super.key});

  Future<void> _adjust(BuildContext context, WidgetRef ref, StockItem item, {required bool use}) async {
    final res = await showAdminFormSheet<(double, String?)>(
      context,
      _QuantitySheet(
        title: use ? 'Record usage' : 'Add stock',
        itemName: item.name,
        unit: item.unit,
        withNote: true,
      ),
    );
    if (res == null || !context.mounted) return;
    final orgId = await ref.read(dashboardOrgIdProvider.future);
    if (orgId == null) return;
    try {
      await StockService(orgId).adjust(item, use ? -res.$1 : res.$1, kind: use ? 'used' : 'purchased', note: res.$2);
      if (context.mounted) showAdminSnack(context, use ? 'Usage recorded.' : 'Stock added.');
    } catch (e) {
      if (context.mounted) showAdminSnack(context, e is StateError ? e.message : 'Could not save: $e', error: true);
    }
  }

  Future<void> _threshold(BuildContext context, WidgetRef ref, StockItem item) async {
    final res = await showAdminFormSheet<(double, String?)>(
      context,
      _QuantitySheet(title: 'Low-stock level', itemName: item.name, unit: item.unit, allowZero: true),
    );
    if (res == null || !context.mounted) return;
    final orgId = await ref.read(dashboardOrgIdProvider.future);
    if (orgId == null) return;
    try {
      await StockService(orgId).setThreshold(item, res.$1 == 0 ? null : res.$1);
      if (context.mounted) showAdminSnack(context, res.$1 == 0 ? 'Low-stock alert turned off.' : 'Low-stock level saved.');
    } catch (e) {
      if (context.mounted) showAdminSnack(context, 'Could not save: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockItemsProvider);
    final perDay = ref.watch(shelterSettingsProvider).asData?.value.foodPerDayKg;
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      error: (e, _) => AdminListMessage('Could not load stock: $e'),
      data: (items) {
        if (items.isEmpty) {
          return const AdminListMessage(
              'No stock yet. Received in-kind donations are added here automatically, or tap Add item.');
        }
        final foodKg = items.where((i) => i.isFood).fold<double>(0, (s, i) => s + (i.kilograms ?? 0));
        final low = items.where((i) => i.isLow).length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            DonationSectionHeader(
              'On hand (${items.length})',
              help: [
                if (low > 0) '$low running low',
                if (foodKg > 0 && perDay != null && perDay > 0)
                  '${_fmt(foodKg)} kg of food ≈ ${(foodKg / perDay).floor()} days at ${_fmt(perDay)} kg a day',
              ].join(' · ').ifEmpty('Received in-kind donations are added automatically.'),
            ),
            for (final i in items)
              _StockCard(
                item: i,
                onUse: () => _adjust(context, ref, i, use: true),
                onAdd: () => _adjust(context, ref, i, use: false),
                onLevel: () => _threshold(context, ref, i),
              ),
          ],
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _StockCard extends StatelessWidget {
  final StockItem item;
  final VoidCallback onUse;
  final VoidCallback onAdd;
  final VoidCallback onLevel;
  const _StockCard({required this.item, required this.onUse, required this.onAdd, required this.onLevel});

  @override
  Widget build(BuildContext context) {
    final i = item;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
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
                Row(
                  children: [
                    Flexible(
                      child: Text(i.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                    ),
                    if (i.isLow) ...[const SizedBox(width: 6), const DonationPill('Low', AppColors.warning)],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${i.category}${i.lowStockThreshold == null ? '' : ' · low at ${_fmt(i.lowStockThreshold!)} ${i.unit}'}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('${_fmt(i.quantity)} ${i.unit}', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          PopupMenuButton<String>(
            tooltip: 'Stock actions',
            color: AppColors.background,
            icon: const Icon(Icons.more_vert, color: AppColors.textPrimary),
            onSelected: (v) => switch (v) {
              'use' => onUse(),
              'add' => onAdd(),
              _ => onLevel(),
            },
            itemBuilder: (_) => [
              for (final (value, label) in const [
                ('use', 'Record usage'),
                ('add', 'Add stock'),
                ('level', 'Set low-stock level'),
              ])
                PopupMenuItem(
                  value: value,
                  child: Text(label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Parses a non-negative decimal quantity ("12", "2.5").
double? _parseQty(String raw) {
  final v = double.tryParse(raw.replaceAll(',', '').trim());
  return (v == null || v < 0) ? null : v;
}

class _QuantitySheet extends StatefulWidget {
  final String title;
  final String itemName;
  final String unit;
  final bool withNote;
  final bool allowZero;
  const _QuantitySheet({
    required this.title,
    required this.itemName,
    required this.unit,
    this.withNote = false,
    this.allowZero = false,
  });

  @override
  State<_QuantitySheet> createState() => _QuantitySheetState();
}

class _QuantitySheetState extends State<_QuantitySheet> {
  final _qty = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value {
    final v = _parseQty(_qty.text);
    if (v == null || (!widget.allowZero && v == 0)) return null;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return AdminSheetFrame(
      title: widget.title,
      doneLabel: 'Save',
      onDone: value == null
          ? null
          : () => Navigator.pop(context, (value, _note.text.trim().isEmpty ? null : _note.text.trim())),
      children: [
        Text(widget.itemName, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
        const SizedBox(height: 12),
        const FieldLabel('Quantity', required: true),
        SheetTextField(
          controller: _qty,
          hint: widget.allowZero ? '0 turns the alert off' : 'Enter',
          suffix: widget.unit,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        if (widget.withNote) ...[
          const SizedBox(height: 16),
          const FieldLabel('Note'),
          SheetTextField(controller: _note, hint: 'Optional'),
        ],
      ],
    );
  }
}

class _NewItem {
  final String name;
  final String category;
  final String unit;
  final double quantity;
  final double? threshold;
  const _NewItem(this.name, this.category, this.unit, this.quantity, this.threshold);
}

class _NewItemSheet extends StatefulWidget {
  const _NewItemSheet();

  @override
  State<_NewItemSheet> createState() => _NewItemSheetState();
}

class _NewItemSheetState extends State<_NewItemSheet> {
  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'kg');
  final _qty = TextEditingController(text: '0');
  final _threshold = TextEditingController();
  String _category = stockCategories.first;

  @override
  void dispose() {
    for (final c in [_name, _unit, _qty, _threshold]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final qty = _parseQty(_qty.text);
    final ok = _name.text.trim().isNotEmpty && _unit.text.trim().isNotEmpty && qty != null;
    void changed(String _) => setState(() {});
    return AdminSheetFrame(
      title: 'New stock item',
      doneLabel: 'Add',
      onDone: !ok
          ? null
          : () => Navigator.pop(
                context,
                _NewItem(_name.text.trim(), _category, _unit.text.trim(), qty, _parseQty(_threshold.text)),
              ),
      children: [
        const FieldLabel('Name', required: true),
        SheetTextField(controller: _name, hint: 'e.g. Dry dog food', autofocus: true, onChanged: changed),
        const SizedBox(height: 16),
        InlineSelectRow(
          label: 'Category',
          value: _category,
          options: stockCategories,
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: 16),
        const FieldLabel('Unit', required: true),
        SheetTextField(controller: _unit, hint: 'kg, pcs, sacks…', onChanged: changed),
        const SizedBox(height: 16),
        const FieldLabel('On hand now', required: true),
        SheetTextField(
          controller: _qty,
          hint: '0',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: changed,
        ),
        const SizedBox(height: 16),
        const FieldLabel('Alert when at or below'),
        SheetTextField(
          controller: _threshold,
          hint: 'Optional',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
      ],
    );
  }
}
