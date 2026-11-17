import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/stock/stock_service.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// Donation gap 5: what the shelter has on hand. Received in-kind goods
/// arrive here automatically; staff record usage, purchases and low-stock
/// levels. A food item at or below its level makes the "Food & medicine"
/// readiness factor read Constrained.
class StockPage extends ConsumerWidget {
  const StockPage({super.key});

  static const categories = [
    'Food & Water',
    'Medicine & Treatment',
    'Supplies & Equipment',
    'Hygiene & Cleaning',
    'Transport Crates',
    'Others',
  ];

  static String fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  Future<String?> _orgId(WidgetRef ref) => ref.read(dashboardOrgIdProvider.future);

  void _snack(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _adjust(BuildContext context, WidgetRef ref, StockItem item, {required bool use}) async {
    final res = await showDialog<(double, String?)>(
      context: context,
      builder: (_) => _QuantityDialog(
        title: use ? 'Record usage · ${item.name}' : 'Add stock · ${item.name}',
        unit: item.unit,
        withNote: true,
      ),
    );
    if (res == null || !context.mounted) return;
    final orgId = await _orgId(ref);
    if (orgId == null) return;
    try {
      await StockService(orgId).adjust(item, use ? -res.$1 : res.$1, kind: use ? 'used' : 'purchased', note: res.$2);
    } catch (e) {
      if (context.mounted) _snack(context, e is StateError ? e.message : 'Could not save: $e', error: true);
    }
  }

  Future<void> _threshold(BuildContext context, WidgetRef ref, StockItem item) async {
    final res = await showDialog<(double, String?)>(
      context: context,
      builder: (_) => _QuantityDialog(title: 'Low-stock level · ${item.name}', unit: item.unit, allowZero: true),
    );
    if (res == null || !context.mounted) return;
    final orgId = await _orgId(ref);
    if (orgId == null) return;
    await StockService(orgId).setThreshold(item, res.$1 == 0 ? null : res.$1);
  }

  Future<void> _addItem(BuildContext context, WidgetRef ref) async {
    final res = await showDialog<_NewItem>(context: context, builder: (_) => const _NewItemDialog());
    if (res == null || !context.mounted) return;
    final orgId = await _orgId(ref);
    if (orgId == null) return;
    try {
      await StockService(orgId).addItem(
        name: res.name,
        category: res.category,
        unit: res.unit,
        quantity: res.quantity,
        lowStockThreshold: res.threshold,
      );
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not add: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(stockItemsProvider);
    final perDay = ref.watch(shelterSettingsProvider).asData?.value.foodPerDayKg;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Stock', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.background,
        onPressed: () => _addItem(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
        error: (e, _) => Center(child: Text('Could not load stock: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No stock yet. Received in-kind donations are added here automatically, or add an item yourself.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final foodKg = items.where((i) => i.isFood).fold<double>(0, (s, i) => s + (i.kilograms ?? 0));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              if (foodKg > 0 && perDay != null && perDay > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('${fmt(foodKg)} kg of food ≈ ${(foodKg / perDay).floor()} days at ${fmt(perDay)} kg a day',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                ),
              for (final i in items)
                Card(
                  color: AppColors.surface,
                  child: ListTile(
                    title: Text(i.name, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      '${i.category}${i.lowStockThreshold == null ? '' : ' · low at ${fmt(i.lowStockThreshold!)} ${i.unit}'}',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    leading: Icon(i.isLow ? Icons.warning_amber : Icons.inventory_2_outlined,
                        color: i.isLow ? AppColors.warning : AppColors.textPrimary),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${fmt(i.quantity)} ${i.unit}',
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                        PopupMenuButton<String>(
                          onSelected: (v) => switch (v) {
                            'use' => _adjust(context, ref, i, use: true),
                            'add' => _adjust(context, ref, i, use: false),
                            _ => _threshold(context, ref, i),
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'use', child: Text('Record usage')),
                            PopupMenuItem(value: 'add', child: Text('Add stock')),
                            PopupMenuItem(value: 'level', child: Text('Set low-stock level')),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuantityDialog extends StatefulWidget {
  final String title;
  final String unit;
  final bool withNote;
  final bool allowZero;
  const _QuantityDialog({required this.title, required this.unit, this.withNote = false, this.allowZero = false});

  @override
  State<_QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<_QuantityDialog> {
  final _qty = TextEditingController();
  final _note = TextEditingController();

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _value {
    final v = double.tryParse(_qty.text.trim());
    if (v == null || v < 0 || (!widget.allowZero && v == 0)) return null;
    return v;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(widget.title, style: GoogleFonts.tiltWarp(fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _qty,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(labelText: 'Quantity', suffixText: widget.unit),
            onChanged: (_) => setState(() {}),
          ),
          if (widget.withNote) TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          if (widget.allowZero)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Enter 0 to turn the low-stock alert off.', style: GoogleFonts.zain(fontSize: 12)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: AppButtons.primary,
          onPressed: _value == null
              ? null
              : () => Navigator.pop(context, (_value!, _note.text.trim().isEmpty ? null : _note.text.trim())),
          child: const Text('Save'),
        ),
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

class _NewItemDialog extends StatefulWidget {
  const _NewItemDialog();

  @override
  State<_NewItemDialog> createState() => _NewItemDialogState();
}

class _NewItemDialogState extends State<_NewItemDialog> {
  final _name = TextEditingController();
  final _unit = TextEditingController(text: 'kg');
  final _qty = TextEditingController(text: '0');
  final _threshold = TextEditingController();
  String _category = StockPage.categories.first;

  @override
  void dispose() {
    for (final c in [_name, _unit, _qty, _threshold]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ok = _name.text.trim().isNotEmpty && _unit.text.trim().isNotEmpty && double.tryParse(_qty.text.trim()) != null;
    return AlertDialog(
      backgroundColor: AppColors.background,
      title: Text('New stock item', style: GoogleFonts.tiltWarp(fontSize: 17)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name, e.g. Dry dog food'),
                onChanged: (_) => setState(() {})),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [for (final c in StockPage.categories) DropdownMenuItem(value: c, child: Text(c))],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            TextField(
                controller: _unit,
                decoration: const InputDecoration(labelText: 'Unit (kg, pcs, sacks...)'),
                onChanged: (_) => setState(() {})),
            TextField(
                controller: _qty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'On hand now'),
                onChanged: (_) => setState(() {})),
            TextField(
                controller: _threshold,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Alert when at or below (optional)')),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: AppButtons.primary,
          onPressed: !ok
              ? null
              : () => Navigator.pop(
            context,
            _NewItem(_name.text.trim(), _category, _unit.text.trim(), double.parse(_qty.text.trim()),
                double.tryParse(_threshold.text.trim())),
          ),
          child: const Text('Add'),
        ),
      ],
    );
  }
}
