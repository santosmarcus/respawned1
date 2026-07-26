/// Per-animal health/condition assessment vocabulary — shared by the
/// Rescue Report form (rescue_page.dart) and Track Case (track_case_page.dart)
/// so a reporter fills these in per animal and later sees the exact same
/// values reflected back. Kept as plain string constants, matching how
/// rescue_risk.dart already stores urgency/bite-risk/escape-risk vocabulary,
/// rather than a new enum — so raw-map readers can keep working directly
/// off `animals[i]['bodyCondition']` etc. without a parsing layer.
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

/// Multi-select.
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
/// beyond this predefined list (see _EnvironmentSafetySection in
/// rescue_page.dart) — so any value outside this list found on a saved
/// case is a custom entry, not an error.
const List<String> kEnvironmentSafetyOptions = [
  'Safe location',
  'Around busy roads',
  'In dirty cages',
];