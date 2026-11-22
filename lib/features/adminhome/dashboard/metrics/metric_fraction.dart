/// Shared pieces for the module analytics calculators
/// (rescue_metrics.dart, adoption_metrics.dart, finance_metrics.dart).
///
/// The rules every card follows (analytics_view.dart header): a rate is
/// always shown with its fraction, a group under [kMinGroupSize] shows the
/// fraction only, and "nothing recorded" is never shown as 0.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart' show kMinGroupSize;

/// "[part] of [whole]".
class Fraction {
  const Fraction(this.part, this.whole);
  final int part;
  final int whole;

  /// Null when there is nothing to divide by.
  double? get rate => whole == 0 ? null : part / whole;

  /// Too few for a rate to mean much: show the fraction only.
  bool get tooFew => whole < kMinGroupSize;

  String get text => '$part of $whole';

  /// "42%" (or null when there is no rate, or the group is too small).
  String? get percent => (rate == null || tooFew) ? null : '${(rate! * 100).round()}%';

  @override
  bool operator ==(Object other) => other is Fraction && other.part == part && other.whole == whole;

  @override
  int get hashCode => Object.hash(part, whole);

  @override
  String toString() => text;
}

/// A median and how many values it was measured on.
class MedianOf {
  const MedianOf(this.value, this.count);
  final double? value;
  final int count;
  bool get isEmpty => count == 0;
}

MedianOf medianOf(Iterable<num> values) {
  final list = values.toList()..sort();
  if (list.isEmpty) return const MedianOf(null, 0);
  final mid = list.length ~/ 2;
  final m = list.length.isOdd ? list[mid].toDouble() : (list[mid - 1] + list[mid]) / 2;
  return MedianOf(m, list.length);
}

/// A Firestore timestamp (or DateTime) as a DateTime, else null.
DateTime? dateOf(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

/// Earliest of [times], ignoring nulls.
DateTime? earliest(Iterable<DateTime?> times) {
  DateTime? best;
  for (final t in times) {
    if (t != null && (best == null || t.isBefore(best))) best = t;
  }
  return best;
}

/// How many animals a case (or one map in it) stands for: the entries in
/// `animals[]`, or one for an older single-animal case.
int animalCountOf(Map<String, dynamic> caseData) {
  final a = caseData['animals'];
  return a is List && a.isNotEmpty ? a.length : 1;
}

/// The case's animals as maps (the case itself for an older single-animal
/// case, so its per-animal fields are still read).
List<Map<String, dynamic>> animalsOf(Map<String, dynamic> caseData) {
  final a = caseData['animals'];
  if (a is List && a.isNotEmpty) {
    return [for (final x in a) if (x is Map) Map<String, dynamic>.from(x)];
  }
  return [caseData];
}
