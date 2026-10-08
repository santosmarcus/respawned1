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
