/// Donations & funds analytics (RESPAWND_ANALYTICS_PLAN D1–D8). Pure
/// functions over small row types the Analytics view builds from its
/// providers, tested in test/features/adminhome/finance_metrics_test.dart.
///
/// Received, cashed out, allocated and spent are four separate figures,
/// never derived from each other. A running bill is owed, not spent. In-kind
/// goods are counted in quantities and never added to money. Donors are
/// counted, never named.
library;

import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/metrics/metric_fraction.dart';

/// One donation as analytics needs it (no donor details).
class DonationRow {
  const DonationRow({
    required this.amount,
    required this.type,
    required this.status,
    required this.source,
    required this.method,
    required this.at,
    this.category = '',
    this.quantity,
  });

  final double amount;
  final String type; // donation | sponsorship | inkind
  final String status;
  final String source; // paymongo | manual
  final String method;
  final DateTime? at;
  final String category;
  final int? quantity;

  bool get isInKind => type == 'inkind';
}

const _notReceived = ['reversed', 'voided', 'void', 'cancelled', 'refunded', 'pending', 'failed', 'needs_review', 'creating', 'error'];

/// Money that actually came in (not in-kind, not pending, not reversed).
bool isMoneyReceived(DonationRow d) => !d.isInKind && !_notReceived.contains(d.status.toLowerCase());

/// In-kind goods marked received.
bool isInKindReceived(DonationRow d) =>
    d.isInKind && const ['complete', 'completed', 'received'].contains(d.status.toLowerCase());

// ─── D1 / D8: funds collected ──────────────────────────────────────────────

class FundsCollected {
  const FundsCollected({required this.total, required this.count, required this.byChannel, required this.automatic});
  final double total;
  final int count;

  /// e.g. "PayMongo · GCash", "Manual · Bank transfer": amount and count.
  final Map<String, ({double amount, int count})> byChannel;

  /// Recorded automatically through PayMongo, out of all received.
  final Fraction automatic;
}

String _channelOf(DonationRow d) {
  final method = d.method.trim();
  final where = d.source == 'manual' ? 'Logged by staff' : 'PayMongo';
  return method.isEmpty ? where : '$where · $method';
}

FundsCollected fundsCollectedIn(Period p, List<DonationRow> donations) {
  final money = donations.where((d) => isMoneyReceived(d) && p.has(d.at)).toList();
  final byChannel = <String, ({double amount, int count})>{};
  for (final d in money) {
    final k = _channelOf(d);
    final prev = byChannel[k];
    byChannel[k] = (amount: (prev?.amount ?? 0) + d.amount, count: (prev?.count ?? 0) + 1);
  }
  return FundsCollected(
    total: money.fold(0, (s, d) => s + d.amount),
    count: money.length,
    byChannel: byChannel,
    automatic: Fraction(money.where((d) => d.source != 'manual').length, money.length),
  );
}

// ─── D2: expenses ──────────────────────────────────────────────────────────

DateTime? expenseDateOf(Expense e) => e.incurredAt ?? e.createdAt;

class ExpenseSummary {
  const ExpenseSummary({required this.paid, required this.running, required this.byCategory});

  /// Paid expenses dated in the period: money spent.
  final double paid;

  /// Running bills dated in the period: owed, not spent yet.
  final double running;

  /// Paid and running per category label.
  final Map<String, ({double paid, double running})> byCategory;
}

ExpenseSummary expensesIn(Period p, List<Expense> expenses) {
  var paid = 0.0, running = 0.0;
  final byCategory = <String, ({double paid, double running})>{};
  for (final e in expenses.where((e) => p.has(expenseDateOf(e)))) {
    final prev = byCategory[e.category.label] ?? (paid: 0.0, running: 0.0);
    if (e.isRunningBill) {
      running += e.amount;
      byCategory[e.category.label] = (paid: prev.paid, running: prev.running + e.amount);
    } else {
      paid += e.amount;
      byCategory[e.category.label] = (paid: prev.paid + e.amount, running: prev.running);
    }
  }
  return ExpenseSummary(paid: paid, running: running, byCategory: byCategory);
}

// ─── D3: funds flow ────────────────────────────────────────────────────────

/// A dated amount (a cash-out, or an allocation to a fund).
typedef DatedAmount = ({double amount, DateTime? at});

class FundsFlow {
  const FundsFlow({required this.received, required this.cashedOut, required this.allocated, required this.spent});
  final double received;
  final double cashedOut;
  final double allocated;
  final double spent;
}

FundsFlow fundsFlowIn(
  Period p, {
  required List<DonationRow> donations,
  required List<DatedAmount> cashOuts,
  required List<DatedAmount> allocations,
  required List<Expense> expenses,
}) {
  double sum(List<DatedAmount> xs) => xs.where((x) => p.has(x.at)).fold(0, (s, x) => s + x.amount);
  return FundsFlow(
    received: fundsCollectedIn(p, donations).total,
    cashedOut: sum(cashOuts),
    allocated: sum(allocations),
    spent: expensesIn(p, expenses).paid,
  );
}

// ─── D4 / D5: in-kind ──────────────────────────────────────────────────────

/// In-kind donations received in the period, by category: how many
/// donations and the quantity received.
Map<String, ({int donations, int quantity})> inKindReceivedIn(Period p, List<DonationRow> donations) {
  final out = <String, ({int donations, int quantity})>{};
  for (final d in donations.where((d) => isInKindReceived(d) && p.has(d.at))) {
    final k = d.category.trim().isEmpty ? 'Other' : d.category.trim();
    final prev = out[k];
    out[k] = (donations: (prev?.donations ?? 0) + 1, quantity: (prev?.quantity ?? 0) + (d.quantity ?? 0));
  }
  return out;
}

/// In-kind stock items (`stock/inkind_<category>`, filled by
/// manageInKindDonation): quantity received and used in the period, from
/// `stockMovements`.
List<({String item, double received, double used})> inKindUsageIn(Period p, List<Map<String, dynamic>> movements) {
  final received = <String, double>{}, used = <String, double>{};
  for (final m in movements) {
    final id = m['itemId'] as String? ?? '';
    if (!id.startsWith('inkind_') || !p.has(dateOf(m['at']))) continue;
    final name = (m['itemName'] as String?)?.trim().isNotEmpty == true ? m['itemName'] as String : id.substring(7);
    final change = (m['change'] as num?)?.toDouble() ?? 0;
    switch (m['kind']) {
      case 'received':
        received[name] = (received[name] ?? 0) + change.abs();
      case 'used':
        used[name] = (used[name] ?? 0) + change.abs();
    }
  }
  final names = {...received.keys, ...used.keys}.toList()..sort();
  return [for (final n in names) (item: n, received: received[n] ?? 0, used: used[n] ?? 0)];
}

// ─── D6: campaigns ─────────────────────────────────────────────────────────

typedef CampaignRow = ({String title, double target, double collected, bool active, DateTime? createdAt});

/// Active campaigns with a goal, lowest share reached first.
List<CampaignRow> campaignsByProgress(List<CampaignRow> campaigns) {
  final list = campaigns.where((c) => c.active && c.target > 0).toList()
    ..sort((a, b) => (a.collected / a.target).compareTo(b.collected / b.target));
  return list;
}

// ─── D7: cost per animal ───────────────────────────────────────────────────

/// Recorded case spending per animal (paid and running), counting only
/// expenses tied to exactly one animal: one listed in `animalIndexes`, or
/// any expense on a single-animal case. Shared multi-animal expenses are
/// never split. Key: `caseId#index`.
Map<String, ({double paid, double running})> costPerAnimal(List<Expense> caseExpenses, Map<String, int> animalsPerCase) {
  final out = <String, ({double paid, double running})>{};
  for (final e in caseExpenses) {
    if (e.caseId.isEmpty) continue;
    int? index;
    if (e.animalIndexes != null && e.animalIndexes!.length == 1) {
      index = e.animalIndexes!.single;
    } else if (e.isSharedCaseExpense && (animalsPerCase[e.caseId] ?? 1) == 1) {
      index = 0;
    }
    if (index == null) continue;
    final key = '${e.caseId}#$index';
    final prev = out[key] ?? (paid: 0.0, running: 0.0);
    out[key] = e.isRunningBill
        ? (paid: prev.paid, running: prev.running + e.amount)
        : (paid: prev.paid + e.amount, running: prev.running);
  }
  return out;
}
