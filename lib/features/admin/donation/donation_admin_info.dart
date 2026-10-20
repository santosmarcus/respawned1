import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_create.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'donation_admin_providers.dart';
import 'donation_admin_records.dart';
import 'donation_admin_service.dart';
import 'donation_admin_sheets.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';

class DonationAdminInfoPage extends ConsumerWidget {
  final String campaignId;
  const DonationAdminInfoPage({super.key, required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(campaignProvider(campaignId));
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const DonationAdminHeader(
            title: 'Donation/Sponsorship',
            helpText: 'Total Received counts only verified money: PayMongo payments confirmed by the server and offline '
                'payments recorded by a financial administrator. Available Balance = received + transfers in − '
                'allocations − transfers out.',
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
              error: (e, _) => Center(child: Text('Could not load listing: $e', style: GoogleFonts.zain(color: Colors.redAccent))),
              data: (c) => c == null
                  ? Center(child: Text('This listing no longer exists.', style: GoogleFonts.zain(color: AppColors.textSecondary)))
                  : _InfoBody(campaign: c),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBody extends ConsumerStatefulWidget {
  final DonationListing campaign;
  const _InfoBody({required this.campaign});

  @override
  ConsumerState<_InfoBody> createState() => _InfoBodyState();
}

class _InfoBodyState extends ConsumerState<_InfoBody> {
  bool _busy = false;
  bool _showHistory = false;
  int _donationFilter = 0; // 0 all, 1 monetary, 2 in-kind

  DonationListing get c => widget.campaign;

  Future<void> _status(String action, {required String title, required String message, bool destructive = false}) async {
    final ok = await confirmAction(context, title: title, message: message, confirmLabel: title, destructive: destructive);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await DonationAdminService.setStatus(c.id, action);
      if (mounted) showAdminSnack(context, 'Listing updated.');
    } catch (e) {
      if (mounted) showAdminSnack(context, DonationAdminService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canFinance = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final allocations = ref.watch(campaignAllocationsProvider(c.id));
    final donations = ref.watch(campaignDonationsProvider(c.id));
    final isSponsorship = c.type == 'sponsorship';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(c.title, style: GoogleFonts.tiltWarp(fontSize: 19, color: AppColors.textPrimary))),
            const SizedBox(width: 8),
            StatusChip(c.status),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          [
            if (c.animalName != null && c.animalName!.isNotEmpty) c.animalName!,
            kFundKinds[c.fundKind] ?? c.fundKind,
            if (c.endDate != null) 'Ends ${formatLongDate(c.endDate)}' else if (!isSponsorship) 'No deadline',
            if (c.extensionCount > 0) 'Extended ${c.extensionCount}×',
          ].join(' · '),
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        if (c.purposeTags.isNotEmpty || c.restricted)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final t in c.purposeTags) _tag(t, AppColors.tearspwn),
                if (c.restricted) _tag('Restricted funds', AppColors.pinkrspwn),
              ],
            ),
          ),
        const SizedBox(height: 16),

        // Figma stat row.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat('Total Received', formatPesoExact(c.collected)),
            if (isSponsorship)
              _Stat('Monthly Amount', c.monthlyAmount != null ? formatPesoExact(c.monthlyAmount!) : '—')
            else
              _Stat('Target Funds', formatPesoExact(c.target)),
            _Stat('Available Balance', formatPesoExact(c.availableBalance)),
          ],
        ),
        if (!isSponsorship && c.target > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (c.collected / c.target).clamp(0, 1).toDouble(),
              minHeight: 8,
              backgroundColor: AppColors.tearspwn.withValues(alpha: 0.4),
              valueColor: const AlwaysStoppedAnimation(AppColors.textPrimary),
            ),
          ),
          const SizedBox(height: 4),
          Text('${c.percentage}% of goal${c.transferredInAmount > 0 ? ' · +${formatPesoExact(c.transferredInAmount)} transferred in (not donations)' : ''}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        ],

        ..._lifecycleSection(canFinance),

        const Divider(height: 36),
        Row(
          children: [
            Expanded(child: Text('Fund Tracking', style: GoogleFonts.zain(fontSize: 17, color: AppColors.textPrimary))),
            if (canFinance && !c.isDraft && !c.isArchived)
              IconButton(
                tooltip: 'Allocate funds',
                icon: const Icon(Icons.add_circle_outline, color: AppColors.textPrimary),
                onPressed: () => showAdminSheet(context, AllocateFundsSheet(campaign: c)),
              ),
          ],
        ),
        allocations.when(
          loading: () => const LinearProgressIndicator(color: AppColors.textPrimary),
          error: (e, _) => Text('Could not load allocations: $e', style: GoogleFonts.zain(color: Colors.redAccent)),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No fund allocations yet.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                ),
              for (final a in list) _AllocationRow(a),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: Text('Total Allocated', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary))),
                  Text(formatPesoExact(c.allocatedAmount + c.transferredOutAmount),
                      style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
                ],
              ),
              if (c.transferredOutAmount > 0)
                Text('Includes ${formatPesoExact(c.transferredOutAmount)} of excess moved to other campaigns.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),

        if (c.inKindItems.isNotEmpty) ...[
          const Divider(height: 36),
          Text('In-Kind Items', style: GoogleFonts.zain(fontSize: 17, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          ..._inKindItems(donations.asData?.value ?? const []),
        ],

        const Divider(height: 36),
        Row(
          children: [
            Expanded(
              child: Text(isSponsorship ? 'Sponsors' : 'Recent Donations',
                  style: GoogleFonts.zain(fontSize: 17, color: AppColors.textPrimary)),
            ),
            if (canFinance && !isSponsorship && !c.isDraft && !c.isArchived)
              TextButton.icon(
                onPressed: () => showAdminSheet(context, OfflineDonationSheet(campaign: c)),
                icon: const Icon(Icons.add, size: 18, color: AppColors.textPrimary),
                label: Text('Offline', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
              ),
          ],
        ),
        if (c.acceptInKind)
          Row(
            children: [
              for (final (i, label) in const ['All', 'Monetary', 'In-Kind'].indexed)
                Padding(
                  padding: const EdgeInsets.only(right: 18),
                  child: InkWell(
                    onTap: () => setState(() => _donationFilter = i),
                    child: Text(label,
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: i == _donationFilter ? FontWeight.w800 : FontWeight.w500,
                            color: i == _donationFilter ? AppColors.textPrimary : AppColors.textSecondary)),
                  ),
                ),
            ],
          ),
        donations.when(
          loading: () => const LinearProgressIndicator(color: AppColors.textPrimary),
          error: (e, _) => Text('Could not load donations: $e', style: GoogleFonts.zain(color: Colors.redAccent)),
          data: (list) {
            final filtered = list.where((d) {
              if (_donationFilter == 1) return !d.isInKind;
              if (_donationFilter == 2) return d.isInKind;
              return true;
            }).toList();
            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No activity yet.', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              );
            }
            final uniqueDonors = list.where((d) => !d.isInKind || d.isCompletedInKind).map((d) => d.userId ?? d.id).toSet().length;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$uniqueDonors ${isSponsorship ? 'sponsors' : 'donors'} · ${list.where((d) => !d.isInKind).length} payments',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                for (final d in filtered.take(15)) DonationRecordCard(record: d, campaign: c),
                if (filtered.length > 15)
                  TextButton(
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DonationRecordsPage())),
                    child: Text('Search all donations', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                  ),
              ],
            );
          },
        ),

        const Divider(height: 36),
        InkWell(
          onTap: () => setState(() => _showHistory = !_showHistory),
          child: Row(
            children: [
              Expanded(child: Text('Campaign History', style: GoogleFonts.zain(fontSize: 17, color: AppColors.textPrimary))),
              Icon(_showHistory ? Icons.expand_less : Icons.expand_more, color: AppColors.textPrimary),
            ],
          ),
        ),
        if (_showHistory) _HistoryList(campaignId: c.id),
      ],
    );
  }

  Widget _tag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
  );

  /// Status actions, the deadline decision prompt and the excess card.
  List<Widget> _lifecycleSection(bool canFinance) {
    final isDonation = c.type == 'donation';
    final widgets = <Widget>[];

    // Shown once per expiry: the backend clears needsExtensionDecision on any decision.
    if (c.needsExtensionDecision && c.status == 'goal_not_met') {
      widgets.add(_banner(
        color: AppColors.yellowrspwn,
        icon: Icons.hourglass_bottom,
        text: 'This campaign ended below its goal. Is it still needed?',
        action: 'Decide',
        onTap: () => showAdminSheet(context, ResolveDeadlineSheet(campaign: c)),
      ));
    }
    // Finished listings stay in the admin and general views until every peso
    // is allocated (or transferred); only then can they be archived.
    if (c.isArchived) {
      widgets.add(_banner(
        color: AppColors.slaterspwn,
        icon: Icons.inventory_2_outlined,
        text: 'Archived — every peso was allocated. Hidden from the admin home and from users.',
      ));
    } else if (c.status == 'goal_met' || c.status == 'closed') {
      final left = c.availableBalance;
      final done = left < 0.005;
      final lead = c.status == 'goal_met' ? 'Goal reached!' : 'Closed.';
      widgets.add(_banner(
        color: done ? AppColors.greenrspwn : AppColors.yellowrspwn,
        icon: done ? Icons.task_alt : Icons.account_balance_wallet_outlined,
        text: done
            ? '$lead All funds are allocated, so it can now be archived.'
            : '$lead ${formatPesoExact(left)} still to allocate. It stays visible to admins and users until every peso is allocated.',
        action: done ? 'Archive' : (canFinance ? 'Allocate' : null),
        onTap: done
            ? () => _status('archive',
            title: 'Archive',
            message: 'Archive "${c.title}"? It will be removed from the admin home and from the general view. '
                'Its records and history are kept and remain searchable by admins.')
            : (canFinance ? () => showAdminSheet(context, AllocateFundsSheet(campaign: c)) : null),
      ));
    }
    if (canFinance && isDonation && c.eligibleExcess > 0 && !c.restricted) {
      widgets.add(_banner(
        color: AppColors.lavenderrspwn,
        icon: Icons.call_split,
        text: '${formatPesoExact(c.eligibleExcess)} raised above the goal can be redirected to a campaign with the same purpose.',
        action: 'Redirect',
        onTap: () => showAdminSheet(context, ReallocateExcessSheet(source: c)),
      ));
    }

    final buttons = <Widget>[
      if (c.status != 'closed' && !c.isArchived)
        _ActionChip('Edit', Icons.edit_outlined, _busy
            ? null
            : () => Navigator.push(context, MaterialPageRoute(builder: (_) => DonationAdminCreatePage(existing: c)))),
      if (c.status == 'draft')
        _ActionChip('Publish', Icons.publish_outlined, _busy
            ? null
            : () => _status('publish', title: 'Publish', message: 'Publish "${c.title}"? Users will be able to see and donate to it.')),
      if (c.status == 'active')
        _ActionChip('Deactivate', Icons.pause_circle_outline, _busy
            ? null
            : () => _status('deactivate',
            title: 'Deactivate', message: 'Stop accepting donations for "${c.title}" for now? You can reactivate it later.')),
      if (c.status == 'paused')
        _ActionChip('Reactivate', Icons.play_circle_outline, _busy
            ? null
            : () => _status('reactivate', title: 'Reactivate', message: 'Accept donations for "${c.title}" again?')),
      if (const ['active', 'paused'].contains(c.status))
        _ActionChip('Close', Icons.lock_outline, _busy
            ? null
            : () => _status('close',
            title: 'Close',
            destructive: true,
            message: c.type == 'sponsorship'
                ? 'Close "${c.title}"? Active sponsorships end now; their records are kept.'
                : 'Close "${c.title}" now? Donations and history are kept and stay visible.')),
      if (isDonation && c.status == 'closed')
        _ActionChip('Relaunch', Icons.restart_alt, _busy
            ? null
            : () => showAdminSheet(context, ResolveDeadlineSheet(campaign: c, mode: 'relaunch'))),
      if (!c.isDraft && !c.isArchived)
        _ActionChip('Post update', Icons.campaign_outlined, _busy ? null : () => showAdminSheet(context, PostUpdateSheet(campaign: c))),
    ];

    return [
      if (widgets.isNotEmpty) const SizedBox(height: 14),
      ...widgets,
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: buttons),
      if (c.type == 'sponsorship' && (c.intendedUse ?? '').isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Intended use: ${c.intendedUse}', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
        ),
    ];
  }

  Widget _banner({required Color color, required IconData icon, required String text, String? action, VoidCallback? onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textPrimary, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary))),
          if (action != null && onTap != null)
            TextButton(
              onPressed: _busy ? null : onTap,
              child: Text(action, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            )
          else
            const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// Needed / pledged (pending) / received per item. Pledges are counted from
  /// pending in-kind records in the same category — the donor form has no
  /// quantity field, so pledged is a count of pledges, not of units.
  List<Widget> _inKindItems(List<DonationHistoryRecord> donations) {
    return [
      for (final it in c.inKindItems)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${it.category}: ${it.description}',
                  style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(
                [
                  if (it.quantityNeeded != null) 'Needed ${it.quantityNeeded} ${it.unit ?? ''}'.trim(),
                  'Received ${it.quantityReceived}${it.quantityNeeded != null ? ' · Remaining ${it.quantityRemaining}' : ''}',
                  '${donations.where((d) => d.isPendingInKind && d.category == it.category).length} pending pledge(s)',
                ].join(' · '),
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
              ),
              if ((it.instructions ?? '').isNotEmpty)
                Text('Drop-off: ${it.instructions}', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      Text('Tap a pending in-kind donation below to confirm receipt.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
    ];
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) => Flexible(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _ActionChip(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onTap,
    icon: Icon(icon, size: 18, color: AppColors.textPrimary),
    label: Text(label, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: AppColors.textPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    ),
  );
}

/// Figma Fund Tracking row: title + category left, amount + date right.
class _AllocationRow extends StatelessWidget {
  final AllocationEntry a;
  const _AllocationRow(this.a);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.background,
          title: Text(a.label, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${a.category} · ${formatPesoExact(a.amount)} · ${a.date}', style: GoogleFonts.zain(fontSize: 15)),
              if (a.recordedByName != null) Text('Recorded by ${a.recordedByName}', style: GoogleFonts.zain(fontSize: 14)),
              if ((a.notes ?? '').isNotEmpty) Text(a.notes!, style: GoogleFonts.zain(fontSize: 14)),
              if ((a.inKindDescription ?? '').isNotEmpty) Text('In-kind used: ${a.inKindDescription}', style: GoogleFonts.zain(fontSize: 14)),
              if ((a.receiptUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(a.receiptUrl!, height: 180, fit: BoxFit.cover)),
              ],
            ],
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (a.isTransfer)
              const Padding(
                padding: EdgeInsets.only(right: 6, top: 2),
                child: Icon(Icons.call_split, size: 16, color: AppColors.textPrimary),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                  Text(a.category, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatPesoExact(a.amount), style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                Text(a.date, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends ConsumerWidget {
  final String campaignId;
  const _HistoryList({required this.campaignId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(campaignHistoryProvider(campaignId)).when(
      loading: () => const LinearProgressIndicator(color: AppColors.textPrimary),
      error: (e, _) => Text('History is not readable with the current Firestore rules ($e).',
          style: GoogleFonts.zain(color: Colors.redAccent)),
      data: (list) => list.isEmpty
          ? Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No history recorded yet (listings created before this module have none).',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      )
          : Column(
        children: [
          for (final h in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 6, right: 10),
                    child: Icon(Icons.circle, size: 7, color: AppColors.textPrimary),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          h.label +
                              (h.amount != null ? ' · ${formatPesoExact(h.amount!)}' : '') +
                              (h.newDeadline != null
                                  ? ' · ${formatLongDate(h.previousDeadline)} → ${formatLongDate(h.newDeadline)}'
                                  : ''),
                          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        ),
                        Text('${h.byName.isEmpty ? 'Unknown' : h.byName} · ${formatLongDate(h.at)}',
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                        if ((h.reason ?? '').isNotEmpty)
                          Text('“${h.reason}”', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
