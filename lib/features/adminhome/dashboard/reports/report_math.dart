/// Shared helpers for the Reports by area calculators (rescue_report_metrics
/// .dart, adoption_report_metrics.dart, finance_report_metrics.dart,
/// operations_report_metrics.dart). Pure Dart, unit-tested.
///
/// Rules every figure follows: a rate is shown with its fraction and the
/// denominator it was measured on; nothing recorded is "—", never 0%;
/// pending or in-progress records are left out of a rate instead of being
/// counted as failures; animals are counted as animals (`animals[]`), not
/// as case documents.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/features/adminhome/dashboard/analytics_range.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart' show kMinGroupSize;

/// [part] out of [whole].
class Ratio {
  const Ratio(this.part, this.whole);
  final int part;
  final int whole;

  double? get rate => whole == 0 ? null : part / whole;

  /// "42%", or "—" when there is nothing to divide by.
  String get percent => rate == null ? '—' : '${(rate! * 100).round()}%';

  /// "12 of 40".
  String get fraction => '$part of $whole';

  /// Fewer than [kMinGroupSize]: an early sign, not a conclusion.
  bool get small => whole > 0 && whole < kMinGroupSize;

  @override
  bool operator ==(Object other) => other is Ratio && other.part == part && other.whole == whole;

  @override
  int get hashCode => Object.hash(part, whole);

  @override
  String toString() => fraction;
}

/// Average and median of some durations or amounts, and how many there were.
class Spread {
  const Spread(this.average, this.median, this.count);
  final double? average;
  final double? median;
  final int count;
  bool get isEmpty => count == 0;
}

Spread spreadOf(Iterable<num> values) {
  final list = values.map((v) => v.toDouble()).toList()..sort();
  if (list.isEmpty) return const Spread(null, null, 0);
  final mid = list.length ~/ 2;
  final median = list.length.isOdd ? list[mid] : (list[mid - 1] + list[mid]) / 2;
  return Spread(list.reduce((a, b) => a + b) / list.length, median, list.length);
}

/// A Firestore timestamp (or DateTime) as a DateTime, else null.
DateTime? dateOf(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

DateTime? earliestOf(Iterable<DateTime?> times) {
  DateTime? best;
  for (final t in times) {
    if (t != null && (best == null || t.isBefore(best))) best = t;
  }
  return best;
}

Map<String, dynamic>? mapOf(Object? v) => v is Map ? Map<String, dynamic>.from(v) : null;

/// The case's animals (the case itself for an older single-animal case).
List<Map<String, dynamic>> animalsOf(Map<String, dynamic> caseData) {
  final a = caseData['animals'];
  if (a is List && a.isNotEmpty) return [for (final x in a) if (x is Map) Map<String, dynamic>.from(x)];
  return [caseData];
}

int animalCountOf(Map<String, dynamic> caseData) => animalsOf(caseData).length;

/// One bar per day (≤ 14 days), per week (≤ 92 days) or per month, across
/// [p]: the buckets trend charts use, so they always follow the period.
List<({String label, DateTime from, DateTime to})> bucketsOf(Period p) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final days = p.to.difference(p.from).inHours / 24;
  final out = <({String label, DateTime from, DateTime to})>[];
  if (days <= 14) {
    var d = DateTime(p.from.year, p.from.month, p.from.day);
    while (d.isBefore(p.to)) {
      final next = DateTime(d.year, d.month, d.day + 1);
      out.add((label: '${months[d.month - 1]} ${d.day}', from: d, to: next));
      d = next;
    }
  } else if (days <= 92) {
    var d = DateTime(p.from.year, p.from.month, p.from.day - (p.from.weekday - 1));
    while (d.isBefore(p.to)) {
      final next = DateTime(d.year, d.month, d.day + 7);
      out.add((label: '${months[d.month - 1]} ${d.day}', from: d, to: next));
      d = next;
    }
  } else {
    var d = DateTime(p.from.year, p.from.month);
    while (d.isBefore(p.to)) {
      final next = DateTime(d.year, d.month + 1);
      out.add((label: d.month == 1 ? '${months[0]} ${d.year % 100}' : months[d.month - 1], from: d, to: next));
      d = next;
    }
  }
  return out;
}

/// Sums [valueOf] of [items] dated by [dateOf] into [bucketsOf] [p].
Map<String, num> bucketed<T>(Period p, Iterable<T> items, DateTime? Function(T) whenOf, num Function(T) valueOf) {
  final buckets = bucketsOf(p);
  final out = {for (final b in buckets) b.label: 0 as num};
  for (final item in items) {
    final t = whenOf(item);
    if (t == null || !p.has(t)) continue;
    for (final b in buckets) {
      if (!t.isBefore(b.from) && t.isBefore(b.to)) {
        out[b.label] = out[b.label]! + valueOf(item);
        break;
      }
    }
  }
  return out;
}
