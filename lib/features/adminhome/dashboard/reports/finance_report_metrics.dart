/// Donation, expense, in-kind and sponsorship KPIs for Reports by area →
/// Donations. Pure functions over small row types the report builds from
/// recorded transactions, tested in
/// test/features/adminhome/reports/finance_report_metrics_test.dart.
///
/// Money received, spent and in-kind quantities are never added together.
/// Each donation document counts once (one per PayMongo payment or manual
/// entry); reversed, refunded, voided, pending and failed ones are not
/// money received. Expenses are the expense ledger (case and general
/// expenses); campaign allocations are only used for each fund's own
/// spent / available figures, so a bill paid from a fund isn't counted
/// twice.
library;

import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/reports/report_math.dart';

class DonationRow {
  const DonationRow({
    required this.amount,
    required this.type,
    required this.status,
    required this.method,
    required this.at,
    this.campaignId = '',
    this.campaignName = '',
    this.generalFund = false,
    this.category = '',
    this.quantity,
    this.reversedAt,
  });

  final double amount;
  final String type; // donation | sponsorship | inkind
  final String status;
  final String method;
  final DateTime? at;
  final String campaignId;
  final String campaignName;
  final bool generalFund;
  final String category;
  final int? quantity;
  final DateTime? reversedAt;

  bool get isInKind => type == 'inkind';
}

const _notReceived = ['reversed', 'refunded', 'voided', 'void', 'cancelled', 'pending', 'failed', 'needs_review', 'creating', 'error'];
const _reversal = ['reversed', 'refunded', 'voided', 'void'];

bool isMoneyReceived(DonationRow d) => !d.isInKind && !_notReceived.contains(d.status.toLowerCase());

class MoneyReceived {
  const MoneyReceived({
    required this.total,
    required this.count,
    required this.byChannel,
    required this.byFund,
    required this.sponsorship,
    required this.unallocated,
    required this.reversed,
    required this.reversedCount,
  });

  final double total;
  final int count;
  final Map<String, double> byChannel;

  /// By campaign or animal fund; the general fund is "Not assigned to a fund".
  final Map<String, double> byFund;

  /// Sponsorship contributions (part of [total]).
  final double sponsorship;

  /// Given to the general fund, not to a campaign or animal.
  final double unallocated;

  /// Reversed or refunded in the period (not part of [total]).
  final double reversed;
  final int reversedCount;
}

const kGeneralFundLabel = 'Not assigned to a fund';

MoneyReceived moneyReceivedIn(Period p, List<DonationRow> donations) {
  final money = donations.where((d) => isMoneyReceived(d) && p.has(d.at)).toList();
  final byChannel = <String, double>{}, byFund = <String, double>{};
  var sponsorship = 0.0, unallocated = 0.0;
  for (final d in money) {
    final channel = d.method.trim().isEmpty ? 'Not recorded' : d.method.trim();
    byChannel[channel] = (byChannel[channel] ?? 0) + d.amount;
    final general = d.generalFund || d.campaignId.isEmpty;
    final fund = general ? kGeneralFundLabel : (d.campaignName.trim().isEmpty ? 'Unnamed fund' : d.campaignName.trim());
    byFund[fund] = (byFund[fund] ?? 0) + d.amount;
    if (d.type == 'sponsorship') sponsorship += d.amount;
    if (general) unallocated += d.amount;
  }
  final reversals = donations.where((d) =>
      !d.isInKind && _reversal.contains(d.status.toLowerCase()) && p.has(d.reversedAt ?? d.at));
  return MoneyReceived(
    total: money.fold(0, (s, d) => s + d.amount),
    count: money.length,
    byChannel: byChannel,
    byFund: byFund,
    sponsorship: sponsorship,
    unallocated: unallocated,
    reversed: reversals.fold(0, (s, d) => s + d.amount),
    reversedCount: reversals.length,
  );
}

// ─── Expenses ──────────────────────────────────────────────────────────────

enum ExpenseGroup {
  veterinary('Veterinary and treatment'),
  rescue('Rescue and transport'),
  shelter('Shelter'),
  operational('Operational');

  const ExpenseGroup(this.label);
  final String label;
}

ExpenseGroup expenseGroupOf(ExpenseCategory c) => switch (c) {
      ExpenseCategory.consultation ||
      ExpenseCategory.medication ||
      ExpenseCategory.procedure ||
      ExpenseCategory.laboratory ||
      ExpenseCategory.vaccination ||
      ExpenseCategory.confinement =>
        ExpenseGroup.veterinary,
      ExpenseCategory.transport => ExpenseGroup.rescue,
      ExpenseCategory.foodAndSupplies || ExpenseCategory.rent || ExpenseCategory.utilities => ExpenseGroup.shelter,
      ExpenseCategory.staffCompensation || ExpenseCategory.administrative || ExpenseCategory.other => ExpenseGroup.operational,
    };

class ExpenseTotals {
  const ExpenseTotals({required this.total, required this.byGroup, required this.awaitingApproval});
  final double total;
  final Map<ExpenseGroup, double> byGroup;

  /// Part of [total] still waiting for a second admin's approval.
  final double awaitingApproval;
}

ExpenseTotals expensesIn(Period p, List<Expense> expenses) {
  final byGroup = {for (final g in ExpenseGroup.values) g: 0.0};
  var total = 0.0, pending = 0.0;
  for (final e in expenses) {
    if (!p.has(e.incurredAt ?? e.createdAt)) continue;
    total += e.amount;
    byGroup[expenseGroupOf(e.category)] = byGroup[expenseGroupOf(e.category)]! + e.amount;
    if (e.isAwaitingApproval) pending += e.amount;
  }
  return ExpenseTotals(total: total, byGroup: byGroup, awaitingApproval: pending);
}

// ─── Funds ─────────────────────────────────────────────────────────────────

/// A campaign or sponsorship fund as recorded now.
typedef FundRow = ({
  String title,
  String type,
  String? animalName,
  double target,
  double collected,
  double transferredIn,
  double transferredOut,
  double spent,
  double? monthlyAmount,
  bool fullyFunded,
  bool draft,
  bool goalMet,
});

double availableOf(FundRow f) => f.collected + f.transferredIn - f.transferredOut - f.spent;

class FundStats {
  const FundStats({required this.available, required this.utilization, required this.targetCompletion, required this.goalsReached});

  /// Money still available across all funds (raised, minus moved out and
  /// spent).
  final double available;

  /// Spent out of everything raised into the funds (all time, in pesos;
  /// shown as a percentage).
  final ({double spent, double raised}) utilization;

  /// Donation campaigns with a target: raised out of target (pesos).
  final ({double raised, double target}) targetCompletion;

  /// Donation campaigns that reached their target, out of those with one.
  final Ratio goalsReached;
}

FundStats fundStatsOf(List<FundRow> funds) {
  final live = funds.where((f) => !f.draft).toList();
  final raised = live.fold<double>(0, (s, f) => s + f.collected + f.transferredIn - f.transferredOut);
  final spent = live.fold<double>(0, (s, f) => s + f.spent);
  final targeted = live.where((f) => f.type == 'donation' && f.target > 0).toList();
  return FundStats(
    available: live.fold(0, (s, f) => s + availableOf(f)),
    utilization: (spent: spent, raised: raised),
    targetCompletion: (
      raised: targeted.fold(0, (s, f) => s + f.collected),
      target: targeted.fold(0, (s, f) => s + f.target),
    ),
    goalsReached: Ratio(targeted.where((f) => f.goalMet || f.collected >= f.target).length, targeted.length),
  );
}

// ─── Sponsorship ───────────────────────────────────────────────────────────

class SponsorshipStats {
  const SponsorshipStats({
    required this.animals,
    required this.fullyFunded,
    required this.underfunded,
    required this.noMonthlyAmount,
    required this.outstanding,
    required this.progress,
  });

  /// Sponsorship funds (one per animal) open now.
  final int animals;
  final int fullyFunded;
  final int underfunded;

  /// Funds without a monthly amount can't be called funded or not.
  final int noMonthlyAmount;

  /// Still needed for this month across the underfunded animals.
  final double outstanding;

  /// Per animal: available out of the monthly amount.
  final List<({String name, double available, double monthly})> progress;
}

SponsorshipStats sponsorshipStatsOf(List<FundRow> funds) {
  final open = funds.where((f) => f.type == 'sponsorship' && !f.draft).toList();
  var full = 0, under = 0, none = 0;
  var outstanding = 0.0;
  final progress = <({String name, double available, double monthly})>[];
  for (final f in open) {
    final monthly = f.monthlyAmount ?? 0;
    if (monthly <= 0) {
      none++;
      continue;
    }
    final available = availableOf(f);
    progress.add((name: (f.animalName ?? '').trim().isEmpty ? f.title : f.animalName!.trim(), available: available, monthly: monthly));
    if (f.fullyFunded) {
      full++;
    } else {
      under++;
      outstanding += (monthly - available).clamp(0, monthly);
    }
  }
  progress.sort((a, b) => (a.available / a.monthly).compareTo(b.available / b.monthly));
  return SponsorshipStats(
    animals: open.length,
    fullyFunded: full,
    underfunded: under,
    noMonthlyAmount: none,
    outstanding: outstanding,
    progress: progress,
  );
}

// ─── In-kind ───────────────────────────────────────────────────────────────

class InKindStats {
  const InKindStats({required this.receivedByCategory, required this.usedByItem, required this.onHandByCategory});

  /// In-kind donations marked received in the period: quantity per category.
  final Map<String, int> receivedByCategory;

  /// Stock used (consumed or given out) in the period, per item, with unit.
  final Map<String, ({double quantity, String unit})> usedByItem;

  /// What is in stock now, per category and unit.
  final Map<String, double> onHandByCategory;
}

InKindStats inKindStatsIn(
  Period p, {
  required List<DonationRow> donations,
  required List<Map<String, dynamic>> movements,
  required List<({String name, String category, String unit, double quantity})> stock,
}) {
  final received = <String, int>{};
  for (final d in donations) {
    if (!d.isInKind || !p.has(d.at) || !const ['complete', 'completed', 'received'].contains(d.status.toLowerCase())) continue;
    final k = d.category.trim().isEmpty ? 'Other' : d.category.trim();
    received[k] = (received[k] ?? 0) + (d.quantity ?? 0);
  }
  final units = {for (final s in stock) s.name: s.unit};
  final used = <String, ({double quantity, String unit})>{};
  for (final m in movements) {
    if (m['kind'] != 'used' || !p.has(dateOf(m['at']))) continue;
    final name = (m['itemName'] as String?)?.trim() ?? '';
    final key = name.isEmpty ? 'Unnamed item' : name;
    final change = ((m['change'] as num?)?.toDouble() ?? 0).abs();
    used[key] = (quantity: (used[key]?.quantity ?? 0) + change, unit: units[key] ?? '');
  }
  final onHand = <String, double>{};
  for (final s in stock) {
    final k = '${s.category.trim().isEmpty ? 'Other' : s.category.trim()} (${s.unit})';
    onHand[k] = (onHand[k] ?? 0) + s.quantity;
  }
  return InKindStats(receivedByCategory: received, usedByItem: used, onHandByCategory: onHand);
}
