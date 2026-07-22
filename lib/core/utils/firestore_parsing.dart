/// Centralized, backward-compatible Firestore field parsing — replaces
/// scattered unsafe `as String?`/`as bool?` casts across model classes.
/// Firestore's dynamic, schema-less nature means an older document can
/// legitimately store a field as a different type than the current writer
/// uses (e.g. an `age` field written as `int64` by a long-removed form,
/// while every current writer treats it as free text) — these helpers
/// coerce rather than throw, so one old document never crashes an entire
/// list read.
library;

/// Coerces any non-null value to its String form via `toString()` — never
/// throws on a mismatched type (an int, bool, etc. all convert cleanly).
String? parseOptionalString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// Same as [parseOptionalString], with a non-null fallback for callers that
/// already default to `''` on missing/legacy data.
String parseRequiredString(dynamic value, {String fallback = ''}) {
  return parseOptionalString(value) ?? fallback;
}

/// For genuinely numeric fields — accepts an int, any other num (coerced via
/// truncation, matching the existing `(value as num?)?.toInt()` pattern),
/// or a numeric string left over from an older schema.
int? parseOptionalInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double? parseOptionalDouble(dynamic value) {
  if (value == null) return null;
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

/// Accepts a bare bool, or a legacy string/num representation
/// ("true"/"false", "1"/"0", 1/0) — never throws, defaults to `false` for
/// anything unrecognized rather than guessing affirmative.
bool parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return fallback;
}

/// Accepts a real list (any element type, stringified), a single legacy
/// scalar string/value (wrapped as a one-item list), or anything else
/// (empty list) — never throws on a shape mismatch.
List<String> parseStringList(dynamic value) {
  if (value == null) return const [];
  if (value is Iterable) {
    return value.where((item) => item != null).map((item) => item.toString()).toList();
  }
  final asString = value.toString();
  return asString.isEmpty ? const [] : [asString];
}
