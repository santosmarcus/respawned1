/// Formats a peso amount with thousands separators, e.g. 4000 -> "₱4,000".
/// No `intl` dependency — this project doesn't declare that package, so a
/// small manual formatter avoids adding another undeclared-dependency
/// warning alongside the ones that already exist elsewhere in the codebase.
String formatPeso(num amount) {
  final wholePesos = amount.round();
  final digits = wholePesos.abs().toString();
  final withCommas = digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return '${wholePesos < 0 ? '-' : ''}₱$withCommas';
}

/// Tolerantly parses a reward/monetary amount that may have been stored as a
/// `num`, a plain numeric string ("5000"), a pre-formatted string
/// ("₱10,000" or "10,000.50"), or `null`/blank. Returns `null` when nothing
/// usable is present so callers never render a bogus "₱0".
num? parseLooseAmount(dynamic raw) {
  if (raw == null) return null;
  if (raw is num) return raw;
  if (raw is String) {
    final cleaned = raw.replaceAll(RegExp(r'[₱,\s]'), '').trim();
    if (cleaned.isEmpty) return null;
    return num.tryParse(cleaned);
  }
  return null;
}

/// Builds the "Lost Pet reward" display string shared by every page that
/// shows it, from the raw `offerReward`/`rewardAmount` Firestore values.
/// Never renders "Yes (₱0)" or a malformed raw value — falls back to a bare
/// "Yes" when no positive amount was recorded, and never implies ResPAWnd
/// holds or guarantees the reward.
String formatRewardDisplay({required dynamic offerReward, dynamic rewardAmount}) {
  if (offerReward != true) return 'No reward offered';
  final amount = parseLooseAmount(rewardAmount);
  if (amount != null && amount > 0) return 'Yes (${formatPeso(amount)})';
  return 'Yes';
}
