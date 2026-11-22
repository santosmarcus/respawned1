import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_create.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_info.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/expenses/case_costs_card.dart';
import 'package:respawnd1/features/admin/rescue/expenses/expense_list_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_animal_selector.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/view_only.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/donation/models.dart';

/// One case's treatment costs: its expenses, the totals and the fundraiser
/// made for it (Create Fundraiser stamps `linkedCaseId`), if any.
class CaseCosts {
  const CaseCosts({required this.caseId, required this.expenses, this.fundraiser});

  final String caseId;

  /// Newest first.
  final List<Expense> expenses;
  final DonationListing? fundraiser;

  double get total => expenses.fold(0, (t, e) => t + e.amount);
  double get funded => expenses.fold(0, (t, e) => t + e.fundedAmount);
  double get outstanding => total - funded;

  /// When money was last spent on the case (for ordering).
  DateTime get lastSpentAt =>
      expenses.map((e) => e.incurredAt ?? e.createdAt ?? DateTime(0)).fold(DateTime(0), (a, b) => b.isAfter(a) ? b : a);
}

/// Groups [expenses] by case, newest spending first, and attaches each
/// case's newest linked fundraiser from [listings].
List<CaseCosts> groupCaseCosts(List<Expense> expenses, List<DonationListing> listings) {
  final byCase = <String, List<Expense>>{};
  for (final e in expenses) {
    (byCase[e.caseId] ??= []).add(e);
  }
  DateTime when(Expense e) => e.incurredAt ?? e.createdAt ?? DateTime(0);
  DateTime created(DonationListing l) => l.createdAt ?? DateTime(0);
  final fundraisers = <String, DonationListing>{};
  for (final l in listings) {
    final id = l.linkedCaseId;
    if (id == null || id.isEmpty) continue;
    final current = fundraisers[id];
    if (current == null || created(l).isAfter(created(current))) fundraisers[id] = l;
  }
  final out = [
    for (final entry in byCase.entries)
      CaseCosts(
        caseId: entry.key,
        expenses: [...entry.value]..sort((a, b) => when(b).compareTo(when(a))),
        fundraiser: fundraisers[entry.key],
      ),
  ]..sort((a, b) => b.lastSpentAt.compareTo(a.lastSpentAt));
  return out;
}

/// Donations › Case costs: every case's treatment expenses in one list,
/// with the details and its fundraiser, so costs stay findable after a
/// case leaves the Treatment page and whether or not anyone made a
/// fundraiser for it.
class CaseCostsTab extends ConsumerStatefulWidget {
  const CaseCostsTab({super.key});

  @override
  ConsumerState<CaseCostsTab> createState() => _CaseCostsTabState();
}

class _CaseCostsTabState extends ConsumerState<CaseCostsTab> {
  bool _onlyInTreatment = true;

  @override
  Widget build(BuildContext context) {
    final expensesAsync = ref.watch(allCaseExpensesProvider);
    final listings = ref.watch(adminCampaignsProvider).asData?.value ?? const <DonationListing>[];
    final inTreatment = ref.watch(casesForTabProvider(RescuePipelineTab.treatment));

    if (expensesAsync.hasError && !expensesAsync.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topCenter,
          child: RestrictedNotice(
            'Case expenses are visible to people with Rescue cases or View donations & funds access.',
          ),
        ),
      );
    }
    final expenses = expensesAsync.asData?.value;
    if (expenses == null) return const Center(child: CircularProgressIndicator(color: AppColors.textPrimary));

    final treatmentIds = {for (final c in inTreatment.asData?.value ?? const <RescueCase>[]) c.id};
    final all = groupCaseCosts(expenses, listings);
    final shown = _onlyInTreatment ? all.where((c) => treatmentIds.contains(c.caseId)).toList() : all;

    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(label),
            selected: on,
            showCheckmark: false,
            onSelected: (_) => onTap(),
            selectedColor: AppColors.textPrimary,
            labelStyle: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: on ? AppColors.background : AppColors.textPrimary,
            ),
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              chip('In treatment', _onlyInTreatment, () => setState(() => _onlyInTreatment = true)),
              chip('All cases', !_onlyInTreatment, () => setState(() => _onlyInTreatment = false)),
            ],
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? AdminListMessage(all.isEmpty
                  ? 'No case expenses yet. They are added from a case\'s Treatment page (Cost Tracking).'
                  : 'No case in treatment has expenses. See All cases for earlier ones.')
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 32),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _CaseCostsCard(costs: shown[i]),
                ),
        ),
      ],
    );
  }
}

class _CaseCostsCard extends ConsumerStatefulWidget {
  const _CaseCostsCard({required this.costs});
  final CaseCosts costs;

  @override
  ConsumerState<_CaseCostsCard> createState() => _CaseCostsCardState();
}

class _CaseCostsCardState extends ConsumerState<_CaseCostsCard> {
  bool _expanded = false;

  (String, ChipTone) _status(RescueCase c) => switch (c.status) {
        RescueStatus.treatment => ('In treatment', ChipTone.amber),
        RescueStatus.intake => ('Intake', ChipTone.info),
        _ when c.status.isTerminal || c.status == RescueStatus.referred => ('Closed', ChipTone.notRecorded),
        _ => ('Open', ChipTone.info),
      };

  @override
  Widget build(BuildContext context) {
    final costs = widget.costs;
    final c = ref.watch(caseDetailProvider(costs.caseId)).asData?.value;
    final options = c == null ? const <CaseAnimalOption>[] : buildCaseAnimalOptions(c);
    final photo = c != null && c.photoUrls.isNotEmpty ? c.photoUrls.first : null;
    final fundraiser = costs.fundraiser;
    final canCampaign = ref.watch(canEditProvider(OrgPermission.campaigns));

    String? animalLabel(Expense e) {
      if (options.length < 2) return null;
      if (e.isSharedCaseExpense) return 'Shared';
      return e.animalIndexes!
          .map((i) => options.where((o) => o.index == i).map((o) => o.label).firstOrNull ?? 'Animal ${i + 1}')
          .join(', ');
    }

    final status = c == null ? null : _status(c);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: photo == null
                      ? Container(color: AppColors.tearspwn, child: const Icon(Icons.pets, color: AppColors.textPrimary))
                      : Image.network(photo,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(color: AppColors.tearspwn, child: const Icon(Icons.pets))),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c?.speciesSummary ?? 'Case',
                        style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                    Text(
                      '#${c?.shortCaseId ?? costs.caseId.substring(0, costs.caseId.length.clamp(0, 7)).toUpperCase()}'
                      '${(c?.vetClinicName ?? '').isNotEmpty ? ' · ${c!.vetClinicName}' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (status != null) StatusChip(status.$1, tone: status.$2),
            ],
          ),
          const SizedBox(height: 10),
          CostRow('Total case cost', costs.total),
          CostRow('Funded', costs.funded),
          CostRow('Outstanding', costs.outstanding, strong: true),

          // Expense lines.
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    '${costs.expenses.length} expense${costs.expenses.length == 1 ? '' : 's'}',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final e in costs.expenses)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.title,
                              style: GoogleFonts.zain(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          Text(
                            [
                              e.category.label,
                              ?animalLabel(e),
                              if ((e.incurredAt ?? e.createdAt) != null) formatDate((e.incurredAt ?? e.createdAt)!),
                              if (e.isAwaitingApproval) 'Awaiting approval',
                            ].join(' · '),
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(formatPeso(e.amount),
                            style: GoogleFonts.zain(
                                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text('Funded ${formatPeso(e.fundedAmount)}',
                            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),

          // Fundraiser.
          const Divider(height: 14),
          Row(
            children: [
              const Icon(Icons.campaign_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: fundraiser == null
                    ? Text('No fundraiser', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(fundraiser.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.zain(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          Text('${formatPeso(fundraiser.collected)} raised of ${formatPeso(fundraiser.target)}',
                              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
              ),
              if (fundraiser != null)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: fundraiser.id)),
                  ),
                  child: Text('View', style: GoogleFonts.zain(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                )
              else if (canCampaign && c != null && costs.outstanding > 0)
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DonationAdminCreatePage(
                        prefill: CampaignPrefill.forCaseTreatment(c, costs.outstanding),
                      ),
                    ),
                  ),
                  child: Text('Create Fundraiser',
                      style: GoogleFonts.zain(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ExpenseListPage(caseId: costs.caseId, animalOptions: options),
                    ),
                  ),
                  style: AppButtons.outline,
                  child: Text('View Expenses', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: c == null ? null : () => openRescueCase(context, c),
                  style: AppButtons.outline,
                  child: Text('Open Case', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
