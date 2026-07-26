/// Per-animal health/condition assessment vocabulary — shared by the
/// Rescue Report form (rescue_page.dart) and every read-only viewer that
/// displays it back (admin Rescue Details, reporter Track Case) so a
/// reporter fills these in per animal and later sees the exact same values
/// reflected back. Kept as plain string constants, matching how
/// rescue_risk.dart already stores urgency/bite-risk/escape-risk
/// vocabulary, rather than a new enum — so raw-map readers can keep
/// working directly off `animals[i]['bodyCondition']` etc. without a
/// parsing layer.
library;

/// Single-select.
const List<String> kBodyConditionOptions = [
  'Overweight',
  'Normal',
  'Underweight',
  'Extremely Underweight (prominent rib bones)',
];

/// Single-select.
const List<String> kMobilityOptions = [
  'Walks and runs normally',
  'Minor limp/stiffness',
  'Cannot walk/crawling only',
];

/// Single-select.
const List<String> kAlertnessOptions = [
  'Alert/responsive',
  'Lethargic/timid',
  'Unresponsive/collapsed/disoriented',
];

/// Multi-select. Kept as two genuinely separate options — a prior revision
/// of this list had 'Distress/Anxious' and 'Aggressive' as adjacent string
/// literals with no comma between them, which Dart silently concatenates
/// into one malformed option ('Distress/AnxiousAggressive'). They must
/// remain distinct entries.
const List<String> kBehaviorOptions = [
  'Friendly/Approachable',
  'Calm',
  'Cautious',
  'Distress/Anxious',
  'Aggressive',
  'Fearful',
  'Protecting young',
  'Hard to approach',
];

/// Selecting a key in this map deselects any of its listed values (and vice
/// versa) — a behavior can't be both calm and aggressive at once, for
/// example. Applied by the multi-select chip UI, not enforced at the
/// storage layer (an old report saved before this existed may still have a
/// "conflicting" combination on file; that's read as-is, never silently
/// edited).
const Map<String, Set<String>> kBehaviorConflicts = {
  'Calm': {'Aggressive', 'Fearful', 'Hard to approach', 'Distress/Anxious'},
  'Friendly/Approachable': {'Aggressive', 'Fearful', 'Hard to approach'},
  'Aggressive': {'Calm', 'Friendly/Approachable'},
  'Fearful': {'Calm', 'Friendly/Approachable'},
  'Hard to approach': {'Calm', 'Friendly/Approachable'},
  'Distress/Anxious': {'Calm'},
};

/// Single-select.
const List<String> kEyesNoseMouthOptions = [
  'Clear and no discharge',
  'Small amount of discharge',
  'Thick and excessive discharge',
];

/// Single-select.
const List<String> kSkinAndCoatOptions = [
  'Clean; no visible skin disease (fleas/ticks, mange)',
  'Minor hairloss; presence of irritation/skin disease (fleas/ticks, mange)',
  'Large open wounds; severe skin disease (fleas/ticks, mange)',
];

/// Single-select.
const List<String> kAppetiteHydrationOptions = [
  'Uncertain',
  'Eating/drinking normally',
  'Refuses food/water; Obvious hunger/dehydration',
];

/// Multi-select, plus the reporter may add their own additional entries
/// beyond this predefined list — so any value outside this list found on a
/// saved case is a custom entry, not an error.
const List<String> kEnvironmentSafetyOptions = [
  'Safe Location',
  'Around busy roads',
  'In dirty cages',
];
