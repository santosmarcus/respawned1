import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_service.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

/// All donation records
class DonationRecordsPage extends ConsumerStatefulWidget {
  const DonationRecordsPage({super.key});

  @override
  ConsumerState<DonationRecordsPage> createState() => _DonationRecordsPageState();
}

class _DonationRecordsPageState extends ConsumerState<DonationRecordsPage> {
  String _query = '';
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final tabs = ['All', 'Monetary', 'Sponsorship', 'In-Kind', if (canFinance) 'Payments'];
    if (_tab >= tabs.length) _tab = 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const DonationAdminHeader(
            title: 'Donation Records',
            helpText: 'Every recorded donation. Monetary records are created only after PayMongo confirms the payment '
                'or a financial administrator records an offline payment. In-kind pledges stay "Pending" until you '
                'confirm the items were received.',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _SearchField(onChanged: (v) => setState(() => _query = v.trim().toLowerCase())),
          ),
          _Tabs(labels: tabs, selected: _tab, onSelect: (i) => setState(() => _tab = i)),
          Expanded(child: tabs[_tab] == 'Payments' ? const _PaymentAttemptsList() : _recordsList()),
        ],
      ),
    );
  }

  Widget _recordsList() {
    final async = ref.watch(allDonationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      error: (e, _) => Center(child: Text('Could not load donations: $e', style: GoogleFonts.zain(color: Colors.redAccent))),
      data: (all) {
        final items = all.where((d) {
          final matchesTab = switch (_tab) {
            1 => d.type == 'donation',
            2 => d.type == 'sponsorship',
            3 => d.type == 'inkind',
            _ => true,
          };
          if (!matchesTab) return false;
          if (_query.isEmpty) return true;
          return d.displayName.toLowerCase().contains(_query) ||
              d.campaignName.toLowerCase().contains(_query) ||
              d.itemDescription.toLowerCase().contains(_query) ||
              d.refNumber.toLowerCase().contains(_query);
        }).toList();
        if (items.isEmpty) {
          return Center(child: Text('No records found.', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [for (final d in items) DonationRecordCard(record: d)],
        );
      },
    );
  }
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: 'Search',
        hintStyle: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
        prefixIcon: const Icon(Icons.search, color: AppColors.textPrimary),
        filled: true,
        fillColor: const Color(0xFFFFF1C7),
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Tabs({required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              InkWell(
                onTap: () => onSelect(i),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                  margin: const EdgeInsets.only(right: 22),
                  decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: i == selected ? AppColors.textPrimary : Colors.transparent, width: 2)),
                  ),
                  child: Text(labels[i],
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          color: i == selected ? AppColors.textPrimary : AppColors.textSecondary,
                          fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Row in Recent Donations / record lists: name + date left, amount right
class DonationRecordCard extends StatelessWidget {
  final DonationHistoryRecord record;
  final DonationListing? campaign;
  const DonationRecordCard({super.key, required this.record, this.campaign});

  @override
  Widget build(BuildContext context) {
    final r = record;
    final dateText = r.date.isNotEmpty ? r.date : formatLongDate(r.when);
    String trailing;
    if (r.isInKind) {
      trailing = r.category.isNotEmpty ? r.category : 'In-kind';
    } else {
      trailing = formatPesoExact(r.amountValue);
    }
    return InkWell(
      onTap: () => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.background,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (_) => DonationRecordSheet(record: r, campaign: campaign),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            if (r.isInKind)
              const Padding(
                padding: EdgeInsets.only(right: 10),
                child: Icon(Icons.inventory_2_outlined, color: AppColors.textPrimary, size: 22),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(r.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                      if (r.isManual) ...[const SizedBox(width: 6), const _Badge('OFFLINE', AppColors.lavenderrspwn)],
                      if (r.type == 'sponsorship') ...[const SizedBox(width: 6), const _Badge('SPONSOR', AppColors.pinkrspwn)],
                      if (r.isInKind) ...[
                        const SizedBox(width: 6),
                        _Badge(
                          r.isCompletedInKind ? 'RECEIVED' : (r.status == 'cancelled' ? 'CANCELLED' : 'PENDING'),
                          r.isCompletedInKind ? AppColors.greenrspwn : AppColors.yellowrspwn,
                        ),
                      ],
                    ],
                  ),
                  Text(dateText, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(trailing,
                style: GoogleFonts.zain(fontSize: r.isInKind ? 13 : 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.25),
      border: Border.all(color: color, width: 0.6),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(text, style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
  );
}

/// Record details + in-kind actions (confirm received / cancel / follow up).
class DonationRecordSheet extends ConsumerStatefulWidget {
  final DonationHistoryRecord record;
  final DonationListing? campaign;
  const DonationRecordSheet({super.key, required this.record, this.campaign});

  @override
  ConsumerState<DonationRecordSheet> createState() => _DonationRecordSheetState();
}

class _DonationRecordSheetState extends ConsumerState<DonationRecordSheet> {
  bool _busy = false;
  final _qty = TextEditingController();
  final _notes = TextEditingController();
  int? _itemIndex;

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _run(String action) async {
    final r = widget.record;
    int? qty;
    if (action == 'received' && _qty.text.trim().isNotEmpty) {
      qty = int.tryParse(_qty.text.trim());
      if (qty == null || qty <= 0) {
        showAdminSnack(context, 'Quantity received must be a whole number.', error: true);
        return;
      }
    }
    if (action == 'cancel' &&
        !await confirmAction(context,
            title: 'Cancel pledge',
            message: 'Mark this in-kind pledge as cancelled? The record is kept for history.',
            confirmLabel: 'Cancel pledge',
            destructive: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await DonationAdminService.manageInKind(r.id, action, itemIndex: qty != null ? _itemIndex : null, quantityReceived: qty, notes: _notes.text.trim());
      if (!mounted) return;
      showAdminSnack(context, switch (action) {
        'received' => 'Marked as received.',
        'cancel' => 'Pledge cancelled.',
        _ => 'Follow-up sent to the donor.',
      });
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final campaign = widget.campaign ??
        (r.campaignId.isEmpty ? null : ref.watch(campaignProvider(r.campaignId)).asData?.value);
    final items = campaign?.inKindItems ?? const <InKindItem>[];

    Widget row(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(k, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary))),
          Expanded(child: Text(v, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary))),
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(r.isInKind ? 'In-Kind Donation' : (r.type == 'sponsorship' ? 'Sponsorship' : 'Donation'),
                  style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              row('Donor', r.displayName),
              row('Campaign', r.campaignName.isNotEmpty ? r.campaignName : (campaign?.title ?? (r.campaignId.isEmpty ? 'General' : r.campaignId))),
              row('Date', r.date.isNotEmpty ? r.date : formatLongDate(r.when)),
              if (!r.isInKind) row('Amount', formatPesoExact(r.amountValue)),
              if (!r.isInKind) row('Method', r.method.isEmpty ? '—' : r.method),
              row('Reference', r.refNumber.isEmpty ? '—' : r.refNumber),
              row('Verification', r.isManual ? 'Recorded offline by ${r.recordedByName ?? 'an administrator'}' : (r.isInKind ? 'Pledge' : 'PayMongo (verified by server)')),
              if (r.type == 'sponsorship') row('Sponsorship', '${r.sponsorshipStatus.isEmpty ? r.status : r.sponsorshipStatus} · next due ${formatLongDate(r.nextChargeDate)}'),
              if (r.isInKind) ...[
                row('Category', r.category),
                row('Items', r.clarification),
                row('Drop-off / pickup', r.address.isEmpty ? '—' : r.address),
                row('Status', r.isCompletedInKind ? 'Received${r.quantityReceived != null ? ' (${r.quantityReceived})' : ''}' : (r.status == 'cancelled' ? 'Cancelled' : 'Pending')),
              ],
              if (r.isPendingInKind) ...[
                const Divider(height: 28),
                const FieldLabel('Confirm receipt'),
                if (items.any((i) => i.quantityNeeded != null)) ...[
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: _itemIndex,
                    hint: Text('Item received (optional)', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
                    items: [
                      for (var i = 0; i < items.length; i++)
                        DropdownMenuItem(
                          value: i,
                          child: Text('${items[i].category}: ${items[i].description}',
                              overflow: TextOverflow.ellipsis, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _itemIndex = v),
                  ),
                ],
                SheetTextField(controller: _qty, hint: 'Quantity received', keyboardType: TextInputType.number),
                SheetTextField(controller: _notes, hint: 'Notes (optional)'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: YellowPillButton(label: 'Received', busy: _busy, onPressed: () => _run('received'))),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: _busy || r.userId == null ? null : () => _run('follow_up'),
                      child: Text('Send follow-up', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => _run('cancel'),
                      child: Text('Cancel pledge', style: GoogleFonts.zain(fontSize: 15, color: Colors.redAccent)),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentAttemptsList extends ConsumerWidget {
  const _PaymentAttemptsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(paymentAttemptsProvider).when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Payment attempts are not readable with the current Firestore rules ($e).',
              textAlign: TextAlign.center, style: GoogleFonts.zain(color: Colors.redAccent)),
        ),
      ),
      data: (items) => items.isEmpty
          ? Center(child: Text('No payment attempts yet.', style: GoogleFonts.zain(color: AppColors.textSecondary)))
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final p = items[i];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p.campaignName.isEmpty ? p.id : p.campaignName,
                style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            subtitle: Text('${p.methodLabel} · ${formatLongDate(p.createdAt)}${p.refNumber != null ? ' · ${p.refNumber}' : ''}',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPesoExact(p.amount),
                    style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(p.status.replaceAll('_', ' ').toUpperCase(),
                    style: GoogleFonts.zain(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: p.status == 'paid'
                            ? const Color(0xFF2E7D32)
                            : (p.status == 'needs_review' ? Colors.deepOrange : AppColors.textSecondary))),
              ],
            ),
          );
        },
      ),
    );
  }
}
