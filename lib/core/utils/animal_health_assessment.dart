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

/// Added to every single-select health field, so a reporter who couldn't
/// get close enough can say so instead of guessing a "normal" answer.
const String kNotAssessedOption = 'Not sure / Not assessed';

/// Single-select.
const List<String> kBodyConditionOptions = [
  'Overweight',
  'Normal',
  'Underweight',
  'Extremely Underweight (prominent rib bones)',
  kNotAssessedOption,
];

/// Single-select.
const List<String> kMobilityOptions = [
  'Walks and runs normally',
  'Minor limp/stiffness',
  'Cannot walk/crawling only',
  kNotAssessedOption,
];

/// Single-select.
const List<String> kAlertnessOptions = [
  'Alert/responsive',
  'Lethargic/timid',
  'Unresponsive/collapsed/disoriented',
  kNotAssessedOption,
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

/// Behavior of an owned pet, as its owner knows it — asked on the lost-pet
/// owner form instead of [kBehaviorOptions] (which describes a stray as
/// seen on the street). Tells a finder how to approach and identify the pet.
const List<String> kOwnedPetBehaviorOptions = [
  'Friendly with strangers',
  'Shy or wary of strangers',
  'Comes when called',
  'Answers to its name',
  'May run if approached',
  'Scared of loud noises',
  'Comes for food or treats',
  'Good with other animals',
  'Not good with other animals',
  'Good with children',
  'May bite or scratch when scared',
];

/// Same idea as [kBehaviorConflicts], for [kOwnedPetBehaviorOptions].
const Map<String, Set<String>> kOwnedPetBehaviorConflicts = {
  'Friendly with strangers': {'Shy or wary of strangers'},
  'Shy or wary of strangers': {'Friendly with strangers'},
  'Comes when called': {'May run if approached'},
  'May run if approached': {'Comes when called'},
  'Good with other animals': {'Not good with other animals'},
  'Not good with other animals': {'Good with other animals'},
};

/// Single-select.
const List<String> kEyesNoseMouthOptions = [
  'Clear and no discharge',
  'Small amount of discharge',
  'Thick and excessive discharge',
  kNotAssessedOption,
];

/// Single-select.
const List<String> kSkinAndCoatOptions = [
  'Clean; no visible skin disease (fleas/ticks, mange)',
  'Minor hairloss; presence of irritation/skin disease (fleas/ticks, mange)',
  'Large open wounds; severe skin disease (fleas/ticks, mange)',
  kNotAssessedOption,
];

/// Everyday wording shown on the report form for the stored values above
/// (and the risk levels in rescue_risk.dart). The stored strings stay as
/// they are: saved reports, staff screens and risk checks compare them.
const Map<String, String> kPlainOptionLabels = {
  'Extremely Underweight (prominent rib bones)': 'Very thin (ribs clearly showing)',
  'Walks and runs normally': 'Walks and runs normally',
  'Minor limp/stiffness': 'Limping a little or stiff',
  'Cannot walk/crawling only': "Can't walk, only crawls",
  'Alert/responsive': 'Alert and reacts to you',
  'Lethargic/timid': 'Weak, sleepy or very quiet',
  'Unresponsive/collapsed/disoriented': 'Not responding, collapsed or confused',
  'Clear and no discharge': 'Clean, nothing coming out',
  'Small amount of discharge': 'A little discharge (wet or crusty)',
  'Thick and excessive discharge': 'A lot of thick discharge (pus or mucus)',
  'Clean; no visible skin disease (fleas/ticks, mange)': 'Clean skin and fur',
  'Minor hairloss; presence of irritation/skin disease (fleas/ticks, mange)':
      'Some bald spots, itching, fleas or ticks',
  'Large open wounds; severe skin disease (fleas/ticks, mange)': 'Big open wounds or very bad skin',
  'Eating/drinking normally': 'Eating and drinking normally',
  'Refuses food/water; Obvious hunger/dehydration': "Won't eat or drink, or looks starved or dried out",
  'Uncertain': 'Not sure',
  'Has attempted to bite': 'Has tried to bite',
  'Actively fleeing': 'Running away',
  'Unable to contain': "Can't be held or kept in one place",
};

/// The form's label for a stored option value.
String plainOptionLabel(String value) => kPlainOptionLabels[value] ?? value;

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
