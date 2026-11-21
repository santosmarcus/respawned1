// Pure decisions for cash-outs: money leaving the organization's PayMongo
// balance, bank account or cash box, and where it went. Used by
// functions/campaigns.js (recordCashOut, assignCashOut, settleCashOut),
// functions/paymongo.js (payout webhook) and the notifyCashOut trigger in
// functions/index.js. No Firebase here, so `node --test` checks them.
//
// A cash-out is stored at organizations/{orgId}/cashOuts/{id}. Until every
// peso is assigned to a fund (or marked as already recorded), the Donations
// screen asks the people who manage money where it went. Assigning creates
// ordinary spending records (campaigns/{id}/allocations, kind 'expense') on
// the chosen funds, so Fund Tracking, reports and analytics see it.
//
// Keep the option lists equal to lib/core/models/donation/cash_out.dart.

/// Where the money was taken out from.
const SOURCES = {
  paymongo: 'PayMongo payout',
  bank: 'Bank withdrawal',
  gcash: 'GCash / e-wallet',
  cash: 'Cash on hand',
  other: 'Other',
};

const STATUSES = ['needs_assignment', 'partly_assigned', 'assigned', 'already_recorded'];
const OPEN_STATUSES = ['needs_assignment', 'partly_assigned'];
/// One assignment can split the money across this many funds.
const MAX_LINES = 10;
const MAX_AMOUNT_CENTAVOS = 10000000 * 100;

const centavos = (pesos) => Math.round(Number(pesos) * 100);
const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : 0);

function formatPeso(c) {
  const p = c / 100;
  return `₱${p.toLocaleString('en-PH', {minimumFractionDigits: p % 1 ? 2 : 0, maximumFractionDigits: 2})}`;
}

/// Status for [assignedC] of [amountC] centavos assigned.
function statusFor(amountC, assignedC) {
  if (assignedC <= 0) return 'needs_assignment';
  return assignedC >= amountC ? 'assigned' : 'partly_assigned';
}

/// Remaining centavos of a stored cash-out.
function remainingOf(cashOut) {
  return Math.max(0, centavos(num(cashOut.amount)) - centavos(num(cashOut.assignedAmount)));
}

/// Checks the lines an admin sends: [{campaignId, category, label, amount}].
/// Returns {error} or {lines} with amounts in centavos.
function validateLines(raw, {categories, idPattern}) {
  if (!Array.isArray(raw) || raw.length === 0) return {error: 'Add at least one fund.'};
  if (raw.length > MAX_LINES) return {error: `Split into at most ${MAX_LINES} funds at a time.`};
  const lines = [];
  for (const [i, l] of raw.entries()) {
    const n = i + 1;
    if (!l || typeof l.campaignId !== 'string' || !idPattern.test(l.campaignId)) {
      return {error: `Choose a fund for line ${n}.`};
    }
    if (!categories.includes(l.category)) return {error: `Choose what line ${n} was for.`};
    const label = typeof l.label === 'string' ? l.label.trim() : '';
    if (!label) return {error: `Describe line ${n} (for example "Dog food for November").`};
    if (label.length > 120) return {error: `Line ${n}'s description is too long (max 120).`};
    const a = l.amount;
    if (typeof a !== 'number' || !Number.isFinite(a)) return {error: `Enter an amount for line ${n}.`};
    const c = centavos(a);
    if (Math.abs(c - a * 100) > 1e-6) return {error: `Line ${n}'s amount can have at most 2 decimals.`};
    if (c <= 0) return {error: `Line ${n}'s amount must be more than zero.`};
    lines.push({campaignId: l.campaignId, category: l.category, label, amountC: c});
  }
  return {lines};
}

/// Checks [lines] against the cash-out and the funds' balances.
///   cashOut: stored doc; funds: Map campaignId → {organizationId, availableC, title}
/// Returns {error} or {totalC, assignedAfterC, status}.
function planAssignment({cashOut, organizationId, lines, funds}) {
  if (!cashOut) return {error: 'This cash-out no longer exists.'};
  if (!OPEN_STATUSES.includes(cashOut.status)) return {error: 'This cash-out has already been sorted out.'};
  const remaining = remainingOf(cashOut);
  const totalC = lines.reduce((s, l) => s + l.amountC, 0);
  if (totalC > remaining) {
    return {error: `That's ${formatPeso(totalC)}, but only ${formatPeso(remaining)} is left to assign.`};
  }
  const perFund = new Map();
  for (const l of lines) perFund.set(l.campaignId, (perFund.get(l.campaignId) || 0) + l.amountC);
  for (const [id, need] of perFund) {
    const f = funds.get(id);
    if (!f) return {error: 'One of the chosen funds no longer exists.'};
    if (f.organizationId && f.organizationId !== organizationId) {
      return {error: 'One of the chosen funds belongs to another organization.'};
    }
    if (need > f.availableC) {
      return {error: `${f.title || 'A fund'} only has ${formatPeso(Math.max(0, f.availableC))} available.`};
    }
  }
  const assignedAfterC = centavos(num(cashOut.assignedAmount)) + totalC;
  return {totalC, assignedAfterC, status: statusFor(centavos(num(cashOut.amount)), assignedAfterC)};
}

/// A PayMongo payout from a webhook's `data` resource, read defensively:
/// field names follow PayMongo's other resources (amounts in centavos,
/// seconds since epoch). Returns null when it isn't a usable payout.
function payoutFromPaymongo(resource) {
  if (!resource || typeof resource.id !== 'string' || !/^[A-Za-z0-9_]{1,128}$/.test(resource.id)) return null;
  const a = resource.attributes || {};
  const pick = (...keys) => keys.map((k) => a[k]).find((v) => Number.isInteger(v) && v > 0);
  const amountC = pick('net_amount', 'amount');
  if (!amountC || amountC > MAX_AMOUNT_CENTAVOS) return null;
  const secs = [a.paid_at, a.updated_at, a.created_at].find((v) => Number.isInteger(v) && v > 0);
  const dest = a.destination || a.bank_account || a.bank || {};
  const bank = [dest.bank_name || dest.bank_code || dest.name, dest.account_number_last4 || dest.last4]
    .filter((v) => typeof v === 'string' && v).join(' ···');
  return {
    payoutId: resource.id,
    amountC,
    grossC: Number.isInteger(a.amount) ? a.amount : null,
    feeC: Number.isInteger(a.fee) ? a.fee : null,
    status: typeof a.status === 'string' ? a.status.slice(0, 40) : null,
    occurredAtMs: secs ? secs * 1000 : null,
    destination: bank ? bank.slice(0, 80) : null,
  };
}

function plural(n, one, many) {
  return `${n} ${n === 1 ? one : (many || `${one}s`)}`;
}

function linesSummary(lines) {
  const parts = lines.slice(0, 3).map((l) => `${formatPeso(centavos(num(l.amount)))} to ${l.campaignTitle || 'a fund'}`);
  if (lines.length > 3) parts.push(`and ${plural(lines.length - 3, 'more fund')}`);
  return parts.join(', ');
}

/// The notice for a cash-out change, or null. Who changed it is told by
/// the screen they used, so callers leave [actorUid] out of the audience.
///   type: cash_out_needs_assignment | cash_out_assigned
function noticeFor(before, after) {
  if (!after) return null;
  const amount = formatPeso(centavos(num(after.amount)));
  const source = SOURCES[after.source] || 'Money taken out';
  const by = after.recordedByName || 'Someone';
  if (!before) {
    if (OPEN_STATUSES.includes(after.status)) {
      const who = after.source === 'paymongo' ? `${amount} was paid out from PayMongo` : `${by} recorded ${amount} taken out (${source})`;
      const left = after.status === 'partly_assigned' ? ` ${formatPeso(remainingOf(after))} still has no fund.` : '';
      return {
        type: 'cash_out_needs_assignment',
        title: 'Where did this money go?',
        body: `${who}.${left} Tap to choose which fund it came from and what it was for.`,
        actorUid: after.source === 'paymongo' ? null : after.recordedBy || null,
      };
    }
    if (after.status === 'assigned') {
      return {
        type: 'cash_out_assigned',
        title: `${amount} taken out and assigned`,
        body: `${by} took out ${amount} (${source}): ${linesSummary(after.lines || [])}.`,
        actorUid: after.recordedBy || null,
      };
    }
    return null;
  }
  if (before.status === after.status && num(before.assignedAmount) === num(after.assignedAmount)) return null;
  const actorName = after.lastActionByName || 'Someone';
  if (after.status === 'already_recorded') {
    return {
      type: 'cash_out_assigned',
      title: `${amount} cash-out marked as already recorded`,
      body: `${actorName}: ${after.settleNote || 'the spending was already recorded.'}`,
      actorUid: after.lastActionBy || null,
    };
  }
  if (['assigned', 'partly_assigned'].includes(after.status)) {
    const added = (after.lines || []).slice((before.lines || []).length);
    const left = after.status === 'partly_assigned' ? ` ${formatPeso(remainingOf(after))} still needs a fund.` : '';
    return {
      type: after.status === 'assigned' ? 'cash_out_assigned' : 'cash_out_needs_assignment',
      title: after.status === 'assigned' ? `${amount} cash-out assigned` : 'Part of a cash-out was assigned',
      body: `${actorName} assigned ${linesSummary(added)}.${left}`,
      actorUid: after.lastActionBy || null,
    };
  }
  return null;
}

module.exports = {
  SOURCES,
  STATUSES,
  OPEN_STATUSES,
  MAX_LINES,
  formatPeso,
  statusFor,
  remainingOf,
  validateLines,
  planAssignment,
  payoutFromPaymongo,
  noticeFor,
};
