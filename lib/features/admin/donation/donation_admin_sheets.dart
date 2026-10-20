import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_service.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

Future<void> showAdminSheet(BuildContext context, Widget sheet) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: AppColors.background,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
  builder: (_) => sheet,
);

Widget _sheetLabel(String text) => Padding(
  padding: const EdgeInsets.only(top: 14, bottom: 2),
  child: Text(text, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary)),
);

Widget _infoBox(String text, {Color color = AppColors.tearspwn}) => Container(
  margin: const EdgeInsets.only(top: 8),
  padding: const EdgeInsets.all(10),
  decoration: BoxDecoration(color: color.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(8)),
  child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
);

class AllocateFundsSheet extends StatefulWidget {
  final DonationListing campaign;
  const AllocateFundsSheet({super.key, required this.campaign});

  @override
  State<AllocateFundsSheet> createState() => _AllocateFundsSheetState();
}

class _AllocateFundsSheetState extends State<AllocateFundsSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _inKindText = TextEditingController();
  final _picker = ImagePicker();
  // One id per opened sheet: a retried "Done" can't record the expense twice.
  final String _requestId = DonationAdminService.newRequestId();
  String _category = 'Medicine and Treatment';
  bool _includeInKind = false;
  XFile? _receipt;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _inKindText.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parsePesoInput(_amount.text);
    if (_title.text.trim().isEmpty || amount == null) {
      showAdminSnack(context, 'Enter a title and a valid amount.', error: true);
      return;
    }
    if (amount > widget.campaign.availableBalance + 0.001) {
      showAdminSnack(context, 'Only ${formatPesoExact(widget.campaign.availableBalance)} is available.', error: true);
      return;
    }
    if (_includeInKind && _inKindText.text.trim().isEmpty) {
      showAdminSnack(context, 'Type the in-kind donations used, or untick the box.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final receiptUrl = _receipt == null ? null : await DonationAdminService.uploadImage(_receipt!, 'receipts');
      await DonationAdminService.recordAllocation(
        campaignId: widget.campaign.id,
        requestId: _requestId,
        label: _title.text.trim(),
        category: _category,
        amount: amount,
        receiptUrl: receiptUrl,
        inKindDescription: _includeInKind ? _inKindText.text.trim() : null,
      );
      if (!mounted) return;
      showAdminSnack(context, 'Allocation recorded.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSheetFrame(
      title: 'Allocate Funds',
      busy: _busy,
      onDone: _submit,
      children: [
        SheetTextField(controller: _title, hint: 'Enter Title'),
        InlineSelectRow(
          label: 'Select Category',
          value: _category,
          options: kAllocationCategories,
          onChanged: (v) => setState(() => _category = v),
        ),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text('Upload Receipt', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary))),
              ImagePickBox(
                file: _receipt,
                size: 92,
                onTap: () async {
                  final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
                  if (f != null) setState(() => _receipt = f);
                },
              ),
            ],
          ),
        ),
        SheetTextField(
          controller: _amount,
          hint: 'Amount',
          prefix: '₱ ',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Available: ${formatPesoExact(widget.campaign.availableBalance)}',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
        CheckRow(
          label: 'Include In-Kind Donations',
          value: _includeInKind,
          onChanged: (v) => setState(() => _includeInKind = v),
        ),
        if (_includeInKind) SheetTextField(controller: _inKindText, hint: 'Type accepted In-Kind Donations'),
      ],
    );
  }
}

// ─── Record offline donation ─────────────────────────────────────────────────

class OfflineDonationSheet extends StatefulWidget {
  final DonationListing campaign;
  const OfflineDonationSheet({super.key, required this.campaign});

  @override
  State<OfflineDonationSheet> createState() => _OfflineDonationSheetState();
}

class _OfflineDonationSheetState extends State<OfflineDonationSheet> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _donor = TextEditingController();
  final _notes = TextEditingController();
  final _picker = ImagePicker();
  String _method = 'bank_transfer';
  DateTime _receivedAt = DateTime.now();
  XFile? _receipt;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    _donor.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = parsePesoInput(_amount.text);
    if (amount == null || _reference.text.trim().isEmpty) {
      showAdminSnack(context, 'Enter a valid amount and the payment reference number.', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Record offline donation',
      message: 'Add ${formatPesoExact(amount)} (${kOfflineMethods[_method]}, ref ${_reference.text.trim()}) to '
          '"${widget.campaign.title}"? It will count toward the campaign total and be marked as recorded by you.',
      confirmLabel: 'Record',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final receiptUrl = _receipt == null ? null : await DonationAdminService.uploadImage(_receipt!, 'receipts');
      await DonationAdminService.recordOfflineDonation(
        campaignId: widget.campaign.id,
        amount: amount,
        method: _method,
        referenceNumber: _reference.text.trim(),
        receivedAt: _receivedAt,
        donorName: _donor.text.trim().isEmpty ? null : _donor.text.trim(),
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        receiptUrl: receiptUrl,
      );
      if (!mounted) return;
      showAdminSnack(context, 'Offline donation recorded.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSheetFrame(
      title: 'Offline Donation',
      busy: _busy,
      onDone: _submit,
      children: [
        _infoBox('For payments received outside the app (bank transfer, cash, check). '
            'Each reference number can be recorded only once per campaign.'),
        SheetTextField(controller: _amount, hint: 'Amount', prefix: '₱ ', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        InlineSelectRow(
          label: 'Received via',
          value: kOfflineMethods[_method],
          options: kOfflineMethods.values.toList(),
          onChanged: (label) => setState(() => _method = kOfflineMethods.entries.firstWhere((e) => e.value == label).key),
        ),
        SheetTextField(controller: _reference, hint: 'Reference / transaction number'),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: _receivedAt,
              firstDate: now.subtract(const Duration(days: 365)),
              lastDate: now,
            );
            if (d != null) setState(() => _receivedAt = DateTime(d.year, d.month, d.day, 12));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
            child: Row(
              children: [
                Expanded(child: Text('Date received', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary))),
                Text(formatLongDate(_receivedAt),
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
        SheetTextField(controller: _donor, hint: 'Donor name (blank = Anonymous)'),
        SheetTextField(controller: _notes, hint: 'Notes (optional)'),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              Expanded(child: Text('Proof of payment', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary))),
              ImagePickBox(
                file: _receipt,
                size: 80,
                onTap: () async {
                  final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600);
                  if (f != null) setState(() => _receipt = f);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Deadline decision: extend / relaunch / close / convert ─────────────────

class ResolveDeadlineSheet extends StatefulWidget {
  final DonationListing campaign;
  /// 'extend' (goal not met) or 'relaunch' (closed).
  final String mode;
  const ResolveDeadlineSheet({super.key, required this.campaign, this.mode = 'extend'});

  @override
  State<ResolveDeadlineSheet> createState() => _ResolveDeadlineSheetState();
}

class _ResolveDeadlineSheetState extends State<ResolveDeadlineSheet> {
  final _reason = TextEditingController();
  DateTime? _deadline;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(String decision) async {
    final c = widget.campaign;
    if ((decision == 'extend' || decision == 'relaunch') && _deadline == null) {
      showAdminSnack(context, 'Choose the new deadline.', error: true);
      return;
    }
    if (decision != 'close' && _reason.text.trim().isEmpty) {
      showAdminSnack(context, 'Give a reason — it is kept in the campaign history.', error: true);
      return;
    }
    final message = switch (decision) {
      'extend' || 'relaunch' =>
      'Reopen "${c.title}" until ${formatLongDate(_deadline)}? The ${formatPesoExact(c.collected)} already raised is kept.',
      'convert_to_general' =>
      'Turn "${c.title}" into an open-ended general fund? Donations so far stay with it; it will have no deadline.',
      _ => 'Close "${c.title}" without extending it? Donations and history are kept and stay visible.',
    };
    final ok = await confirmAction(context,
        title: 'Confirm', message: message, confirmLabel: 'Confirm', destructive: decision == 'close');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await DonationAdminService.resolveExpired(c.id, decision, newDeadline: _deadline, reason: _reason.text.trim());
      if (!mounted) return;
      showAdminSnack(context, 'Campaign updated.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.campaign;
    final relaunch = widget.mode == 'relaunch';
    return AdminSheetFrame(
      title: relaunch ? 'Relaunch Campaign' : 'Campaign Ended',
      busy: _busy,
      doneLabel: relaunch ? 'Relaunch' : 'Extend',
      onDone: () => _run(relaunch ? 'relaunch' : 'extend'),
      children: [
        if (!relaunch)
          _infoBox('"${c.title}" reached its deadline with ${formatPesoExact(c.collected)} of its '
              '${formatPesoExact(c.target)} goal. Is this campaign still needed? You can extend it with a new deadline.',
              color: AppColors.yellowrspwn),
        InkWell(
          onTap: () async {
            final now = DateTime.now();
            final d = await showDatePicker(
              context: context,
              initialDate: now.add(const Duration(days: 30)),
              firstDate: now.add(const Duration(days: 1)),
              lastDate: now.add(const Duration(days: 730)),
            );
            if (d != null) setState(() => _deadline = DateTime(d.year, d.month, d.day, 23, 59));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
            child: Row(
              children: [
                Expanded(child: Text('New deadline', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary))),
                Text(_deadline == null ? 'Select' : formatLongDate(_deadline),
                    style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_calendar_outlined, color: AppColors.textPrimary, size: 20),
              ],
            ),
          ),
        ),
        SheetTextField(controller: _reason, hint: 'Reason (kept in history)', maxLines: 2),
        if (!relaunch) ...[
          const SizedBox(height: 18),
          Text('Not extending?', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => _run('convert_to_general'),
                  child: Text('Convert to general fund',
                      textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                ),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _busy ? null : () => _run('close'),
                  child: Text('Keep closed', style: GoogleFonts.zain(fontSize: 15, color: Colors.redAccent)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Redirect eligible excess ────────────────────────────────────────────────

class ReallocateExcessSheet extends ConsumerStatefulWidget {
  final DonationListing source;
  const ReallocateExcessSheet({super.key, required this.source});

  @override
  ConsumerState<ReallocateExcessSheet> createState() => _ReallocateExcessSheetState();
}

class _ReallocateExcessSheetState extends ConsumerState<ReallocateExcessSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  final String _requestId = DonationAdminService.newRequestId();
  String? _destinationId;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  /// Same eligibility the backend enforces (reallocateExcess in campaigns.js).
  bool _eligible(DonationListing d) {
    final s = widget.source;
    return d.id != s.id &&
        d.type == 'donation' &&
        d.status == 'active' &&
        d.organizationId == s.organizationId &&
        d.purposeTags.any(s.purposeTags.contains);
  }

  Future<void> _submit(List<DonationListing> options) async {
    final s = widget.source;
    final amount = parsePesoInput(_amount.text);
    final dest = options.where((d) => d.id == _destinationId).firstOrNull;
    if (dest == null) {
      showAdminSnack(context, 'Choose a destination campaign.', error: true);
      return;
    }
    if (amount == null || amount > s.eligibleExcess + 0.001) {
      showAdminSnack(context, 'Enter an amount up to ${formatPesoExact(s.eligibleExcess)}.', error: true);
      return;
    }
    if (_reason.text.trim().isEmpty) {
      showAdminSnack(context, 'A reason is required for transparency.', error: true);
      return;
    }
    final ok = await confirmAction(
      context,
      title: 'Confirm reallocation',
      message: 'Move ${formatPesoExact(amount)} of excess funds from "${s.title}" to "${dest.title}"?\n\n'
          'This is an allocation of existing funds, not a new donation. It is recorded permanently and shown '
          'on both campaigns\' public pages. Original donor records stay with "${s.title}".',
      confirmLabel: 'Reallocate',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await DonationAdminService.reallocateExcess(
        sourceCampaignId: s.id,
        destinationCampaignId: dest.id,
        requestId: _requestId,
        amount: amount,
        reason: _reason.text.trim(),
      );
      if (!mounted) return;
      showAdminSnack(context, 'Excess funds reallocated.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final all = ref.watch(adminCampaignsProvider).asData?.value ?? const <DonationListing>[];
    final options = all.where(_eligible).toList();

    return AdminSheetFrame(
      title: 'Redirect Excess',
      busy: _busy,
      doneLabel: 'Next',
      onDone: () => _submit(options),
      children: [
        _infoBox('Raised ${formatPesoExact(s.collected)} of a ${formatPesoExact(s.target)} goal. '
            'Eligible excess: ${formatPesoExact(s.eligibleExcess)}'
            '${s.transferredOutAmount > 0 ? ' (after ${formatPesoExact(s.transferredOutAmount)} already moved)' : ''}. '
            'Amounts are gross; PayMongo fees are not deducted here.'),
        _sheetLabel('Destination (same organization, shares a tag: ${s.purposeTags.join(', ')})'),
        if (options.isEmpty)
          Text('No active campaign with a matching purpose. Create one first.',
              style: GoogleFonts.zain(fontSize: 15, color: Colors.redAccent))
        else
          DropdownButtonFormField<String>(
            initialValue: _destinationId,
            isExpanded: true,
            hint: Text('Select campaign', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary)),
            items: [
              for (final d in options)
                DropdownMenuItem(
                  value: d.id,
                  child: Text('${d.title} · ${d.purposeTags.join(', ')}',
                      overflow: TextOverflow.ellipsis, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                ),
            ],
            onChanged: (v) => setState(() => _destinationId = v),
          ),
        SheetTextField(controller: _amount, hint: 'Amount', prefix: '₱ ', keyboardType: const TextInputType.numberWithOptions(decimal: true)),
        SheetTextField(controller: _reason, hint: 'Reason for reallocation', maxLines: 3),
      ],
    );
  }
}

// ─── Progress update ────────────────────────────────────────────────────────

class PostUpdateSheet extends StatefulWidget {
  final DonationListing campaign;
  const PostUpdateSheet({super.key, required this.campaign});

  @override
  State<PostUpdateSheet> createState() => _PostUpdateSheetState();
}

class _PostUpdateSheetState extends State<PostUpdateSheet> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _type = 'General';
  bool _busy = false;
  static const _types = {'General': 'general', 'Medical': 'medical', 'Milestone': 'milestone'};

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      showAdminSnack(context, 'Enter a title for the update.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await DonationAdminService.postUpdate(widget.campaign.id,
          title: _title.text.trim(), body: _body.text.trim(), type: _types[_type]!);
      if (!mounted) return;
      showAdminSnack(context, 'Update posted.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminSheetFrame(
      title: 'Post Update',
      busy: _busy,
      onDone: _submit,
      children: [
        SheetTextField(controller: _title, hint: 'Enter Title'),
        InlineSelectRow(label: 'Type', value: _type, options: _types.keys.toList(), onChanged: (v) => setState(() => _type = v)),
        SheetTextField(controller: _body, hint: 'Details (optional)', maxLines: 4),
      ],
    );
  }
}
