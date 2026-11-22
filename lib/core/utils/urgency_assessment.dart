/// Rule-based urgency assessment for a rescue report.
///
/// Replaces the urgency that used to come from the rescue type alone. The
/// level is worked out from the reporter's answers for each animal (the
/// Health & Behavior Assessment, the injury question, the risk fields and
/// the female-only questions), using fixed, explainable criteria:
///
/// * Each answer maps to an indicator tier: **red flag** (an immediate
///   threat to life), **severe**, **moderate** or **minor**. Some moderate
///   and severe indicators are *functional*: they describe how the animal
///   is coping (mobility, alertness, eating/drinking, distress).
/// * **Critical** needs evidence of an emergency: an uncontradicted red
///   flag, two severe indicators, or a severe indicator corroborated by a
///   functional sign from a different answer. One severe answer on its own
///   is never Critical, and a minor injury never is.
/// * **Medium**: any severe or moderate indicator, or not enough
///   information to rate the animal lower.
/// * **Low**: only minor indicators (or none), with a complete assessment.
/// * Contradictory answers (e.g. "unresponsive/collapsed" but "walks and
///   runs normally") are recorded, the indicator involved counts one tier
///   lower, and the report is flagged for staff verification. A
///   contradiction can lower a red flag to severe, never below Medium.
///
/// Answers about the same body system (for example the injury question and
/// a "suspected broken bone" visible sign, or Walking and "unable to stand")
/// share a dimension, and only the strongest one in a dimension counts, so
/// one injury reported twice is never counted as two severe signs. "Not
/// sure / Not assessed" counts as missing information.
///
/// A multi-animal report takes the highest level among its animals.
///
/// Photos are NOT analyzed by the app: the reporter says whether the injury
/// is visible in them, and the result says so ([UrgencyAssessment.photosAnalyzed]
/// is always false). This is triage support for staff, not a veterinary
/// assessment.
library;

import 'package:respawnd1/core/utils/animal_health_assessment.dart';

/// Stored with each report (`urgencyAssessment.method`) so a later change
/// of criteria can tell which rules rated an older report.
const String kUrgencyAssessmentMethod = 'rules-v1';

const String kUrgencyCritical = 'Critical';
const String kUrgencyMedium = 'Medium';
const String kUrgencyLow = 'Low';

int _rank(String? level) => switch (level) {
      kUrgencyCritical => 3,
      kUrgencyMedium => 2,
      kUrgencyLow => 1,
      _ => 0,
    };

enum IndicatorTier { redFlag, severe, moderate, minor }

IndicatorTier _lower(IndicatorTier t) => switch (t) {
      IndicatorTier.redFlag => IndicatorTier.severe,
      IndicatorTier.severe => IndicatorTier.moderate,
      IndicatorTier.moderate => IndicatorTier.minor,
      IndicatorTier.minor => IndicatorTier.minor,
    };

class _Indicator {
  _Indicator(this.dimension, this.tier, this.text, {this.functional = false});
  final String dimension;
  IndicatorTier tier;
  final String text;
  final bool functional;
  bool contradicted = false;
}

/// One animal's answers, read from the form or from a saved
/// `cases/{id}.animals[i]` map (see [AnimalUrgencyInput.fromMap]).
class AnimalUrgencyInput {
  const AnimalUrgencyInput({
    this.injury,
    this.injuryVisibleInPhotos,
    this.bodyCondition,
    this.mobility,
    this.alertness,
    this.eyesNoseMouth,
    this.skinAndCoat,
    this.appetiteHydration,
    this.behavior = const {},
    this.environmentSafety = const {},
    this.biteRisk,
    this.sex,
    this.hasLitter,
    this.suspectedPregnancy,
    this.visibleSigns = const {},
    this.needsMedical,
  });

  final String? injury;
  final String? injuryVisibleInPhotos;
  final String? bodyCondition;
  final String? mobility;
  final String? alertness;
  final String? eyesNoseMouth;
  final String? skinAndCoat;
  final String? appetiteHydration;
  final Set<String> behavior;
  final Set<String> environmentSafety;
  final String? biteRisk;
  final String? sex;
  final String? hasLitter;
  final String? suspectedPregnancy;

  /// Injury, Illness, Neglect or Abuse and Aggressive Animal: the per-type
  /// visible signs (rescue_form_options.dart) and the reporter's answer to
  /// "needs immediate medical attention?" ('Yes' | 'No' | 'Not sure').
  final Set<String> visibleSigns;
  final String? needsMedical;

  factory AnimalUrgencyInput.fromMap(Map<String, dynamic> m) {
    String? s(String k) {
      final v = m[k];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    Set<String> list(String k) => {
          for (final v in (m[k] as List? ?? const []))
            if (v is String) v,
        };
    return AnimalUrgencyInput(
      injury: s('injury'),
      injuryVisibleInPhotos: s('injuryVisibleInPhotos'),
      bodyCondition: s('bodyCondition'),
      mobility: s('mobility'),
      alertness: s('alertness'),
      eyesNoseMouth: s('eyesNoseMouth'),
      skinAndCoat: s('skinAndCoat'),
      appetiteHydration: s('appetiteHydration'),
      behavior: list('behavior'),
      environmentSafety: list('environmentSafety'),
      biteRisk: s('biteRisk'),
      sex: s('sex'),
      hasLitter: s('hasLitter'),
      suspectedPregnancy: s('suspectedPregnancy'),
      visibleSigns: list('visibleSigns'),
      needsMedical: s('needsMedical'),
    );
  }
}

/// The outcome for a whole report (or one animal).
class UrgencyAssessment {
  const UrgencyAssessment({
    required this.level,
    this.reasons = const [],
    this.conflicts = const [],
    this.notes = const [],
    this.insufficientInformation = false,
    this.needsStaffVerification = false,
  });

  /// 'Critical' | 'Medium' | 'Low' — the same strings `cases.urgency`
  /// has always held (UrgencyLevel.fromFirestoreValue).
  final String level;

  /// Why the level was reached, most serious first.
  final List<String> reasons;

  /// Answers that disagree with each other.
  final List<String> conflicts;

  /// Context for staff that does not change the level (litter, suspected
  /// pregnancy, environment, photo visibility).
  final List<String> notes;
  final bool insufficientInformation;
  final bool needsStaffVerification;

  /// The app never analyzes photos itself.
  bool get photosAnalyzed => false;

  Map<String, dynamic> toMap() => {
        'level': level,
        'method': kUrgencyAssessmentMethod,
        'reasons': reasons,
        'conflicts': conflicts,
        'notes': notes,
        'insufficientInformation': insufficientInformation,
        'needsStaffVerification': needsStaffVerification,
        'photosAnalyzed': false,
      };

  /// Reads a saved `urgencyAssessment` map; null for reports saved before
  /// the assessment existed (their `urgency` came from the rescue type).
  static UrgencyAssessment? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final level = raw['level'];
    if (level is! String || _rank(level) == 0) return null;
    List<String> strings(Object? v) => [for (final e in (v as List? ?? const [])) if (e is String) e];
    return UrgencyAssessment(
      level: level,
      reasons: strings(raw['reasons']),
      conflicts: strings(raw['conflicts']),
      notes: strings(raw['notes']),
      insufficientInformation: raw['insufficientInformation'] == true,
      needsStaffVerification: raw['needsStaffVerification'] == true,
    );
  }
}

/// How each per-type visible sign (rescue_form_options.dart) is weighed:
/// (dimension, tier, functional). Signs not listed (e.g. most aggression
/// body language) describe handling, not health, and don't change the level.
const Map<String, (String, IndicatorTier, bool)> kVisibleSignWeights = {
  // Injury
  'Active or heavy bleeding': ('injury', IndicatorTier.redFlag, false),
  'Suspected broken bone': ('injury', IndicatorTier.severe, false),
  'Wound with maggots': ('injury', IndicatorTier.severe, false),
  'Likely hit by a vehicle': ('injury', IndicatorTier.severe, false),
  'Trapped in a snare, wire or net': ('injury', IndicatorTier.severe, false),
  'Burns': ('injury', IndicatorTier.severe, false),
  'Head or face injury': ('injury', IndicatorTier.severe, false),
  'Embedded collar or chain wounds': ('injury', IndicatorTier.severe, false),
  'Open wound or deep cut': ('injury', IndicatorTier.moderate, false),
  'Open wounds or injuries': ('injury', IndicatorTier.moderate, false),
  'Bite wounds from a fight': ('injury', IndicatorTier.moderate, false),
  'Swelling or lump': ('injury', IndicatorTier.moderate, false),
  'Eye injury': ('injury', IndicatorTier.moderate, false),
  'Appears injured or in pain': ('injury', IndicatorTier.moderate, false),
  // Mobility
  'Unable to stand or walk': ('mobility', IndicatorTier.severe, true),
  'Limping or unable to stand': ('mobility', IndicatorTier.moderate, true),
  'Limping or not using a leg': ('mobility', IndicatorTier.moderate, true),
  // Breathing and nervous system
  'Difficulty breathing': ('breathing', IndicatorTier.redFlag, true),
  'Seizures, twitching or tremors': ('neuro', IndicatorTier.redFlag, true),
  'Disoriented, wandering or staggering': ('alertness', IndicatorTier.moderate, true),
  // Illness
  'Pale or yellow gums': ('gums', IndicatorTier.severe, false),
  'Diarrhea (with or without blood)': ('gut', IndicatorTier.moderate, false),
  'Vomiting': ('gut', IndicatorTier.moderate, false),
  'Swollen belly': ('gut', IndicatorTier.moderate, false),
  'Excessive drooling': ('gut', IndicatorTier.moderate, false),
  'Not eating, or weak and sleepy': ('appetite', IndicatorTier.moderate, true),
  'Signs of dehydration': ('appetite', IndicatorTier.moderate, true),
  'Coughing or sneezing': ('respiratory', IndicatorTier.minor, false),
  'Nasal or eye discharge': ('eyes', IndicatorTier.minor, false),
  'Skin disease or hair loss (mange)': ('skin', IndicatorTier.minor, false),
  'Untreated skin disease or hair loss': ('skin', IndicatorTier.minor, false),
  'Heavy ticks or fleas': ('skin', IndicatorTier.minor, false),
  'Overgrown nails or heavily matted coat': ('skin', IndicatorTier.minor, false),
  // Neglect
  'Severely thin (visible ribs or bones)': ('body', IndicatorTier.severe, false),
  // Possible rabies signs: a public-health concern for staff.
  'Foaming or drooling at the mouth': ('safety', IndicatorTier.moderate, false),
  'Biting at objects or the air': ('safety', IndicatorTier.moderate, false),
  'Snapping or biting at people': ('safety', IndicatorTier.moderate, false),
};

int _tierRank(IndicatorTier t) => switch (t) {
      IndicatorTier.redFlag => 3,
      IndicatorTier.severe => 2,
      IndicatorTier.moderate => 1,
      IndicatorTier.minor => 0,
    };

/// Assesses one animal.
UrgencyAssessment assessAnimalUrgency(AnimalUrgencyInput a) {
  final indicators = <_Indicator>[];
  final notes = <String>[];
  final conflicts = <String>[];

  // One indicator per dimension: the strongest wins, so the same problem
  // reported by two questions is not counted twice.
  void add(String dim, IndicatorTier tier, String text, {bool functional = false}) {
    final i = indicators.indexWhere((x) => x.dimension == dim);
    if (i == -1) {
      indicators.add(_Indicator(dim, tier, text, functional: functional));
    } else if (_tierRank(tier) > _tierRank(indicators[i].tier)) {
      indicators[i] = _Indicator(dim, tier, text, functional: functional || indicators[i].functional);
    }
  }

  // Injury (reporter's own description).
  switch (a.injury) {
    case kInjuryLifeThreatening:
      add('injury', IndicatorTier.redFlag, 'Heavy or uncontrolled bleeding reported');
    case kInjurySevere:
      add('injury', IndicatorTier.severe, 'Severe injury reported (deep wound, exposed bone or suspected fracture)');
    case kInjuryModerate:
      add('injury', IndicatorTier.moderate, 'Moderate injury reported (open wound, swelling or injured limb)');
    case kInjuryMinor:
      add('injury', IndicatorTier.minor, 'Minor injury reported (small cut, scratch or scab)');
  }

  // Alertness.
  if (a.alertness == kAlertnessOptions[2]) {
    add('alertness', IndicatorTier.redFlag, 'Unresponsive, collapsed or disoriented', functional: true);
  } else if (a.alertness == kAlertnessOptions[1]) {
    add('alertness', IndicatorTier.moderate, 'Lethargic or timid', functional: true);
  }

  // Mobility.
  if (a.mobility == kMobilityOptions[2]) {
    add('mobility', IndicatorTier.severe, 'Cannot walk / crawling only', functional: true);
  } else if (a.mobility == kMobilityOptions[1]) {
    add('mobility', IndicatorTier.moderate, 'Minor limp or stiffness', functional: true);
  }

  // Body condition.
  if (a.bodyCondition == kBodyConditionOptions[3]) {
    add('body', IndicatorTier.severe, 'Extremely underweight (prominent ribs)');
  } else if (a.bodyCondition == kBodyConditionOptions[2]) {
    add('body', IndicatorTier.moderate, 'Underweight');
  }

  // Skin and coat.
  if (a.skinAndCoat == kSkinAndCoatOptions[2]) {
    add('skin', IndicatorTier.severe, 'Large open wounds or severe skin disease');
  } else if (a.skinAndCoat == kSkinAndCoatOptions[1]) {
    add('skin', IndicatorTier.minor, 'Minor hair loss or skin irritation');
  }

  // Eyes, nose, mouth.
  if (a.eyesNoseMouth == kEyesNoseMouthOptions[2]) {
    add('eyes', IndicatorTier.moderate, 'Thick, excessive discharge from eyes, nose or mouth');
  } else if (a.eyesNoseMouth == kEyesNoseMouthOptions[1]) {
    add('eyes', IndicatorTier.minor, 'Small amount of discharge');
  }

  // Appetite and hydration.
  if (a.appetiteHydration == kAppetiteHydrationOptions[2]) {
    add('appetite', IndicatorTier.moderate, 'Refuses food or water / obvious hunger or dehydration', functional: true);
  }

  // Behavior: distress is a functional sign; the others describe handling.
  if (a.behavior.contains('Distress/Anxious')) {
    add('distress', IndicatorTier.moderate, 'Showing signs of distress', functional: true);
  }

  // Public safety.
  if (a.biteRisk == 'Has bitten someone') {
    add('safety', IndicatorTier.moderate, 'Has bitten someone (public safety)');
  }

  // Per-type visible signs.
  for (final sign in a.visibleSigns) {
    final w = kVisibleSignWeights[sign];
    if (w != null) add(w.$1, w.$2, 'Visible sign: $sign', functional: w.$3);
  }

  // The reporter's own judgment that the animal needs a vet now: never
  // Critical alone, but never Low either.
  if (a.needsMedical == 'Yes') {
    add('reporterJudgment', IndicatorTier.moderate, 'Reporter says it needs immediate medical attention');
  }

  // ---- Contradictions: the indicator involved counts one tier lower.
  _Indicator? find(String dim) {
    for (final i in indicators) {
      if (i.dimension == dim) return i;
    }
    return null;
  }

  void contradict(_Indicator? i, String message) {
    conflicts.add(message);
    if (i != null && !i.contradicted) {
      i.contradicted = true;
      i.tier = _lower(i.tier);
    }
  }

  final alert = find('alertness');
  if (alert != null && alert.text.startsWith('Unresponsive')) {
    if (a.mobility == kMobilityOptions[0]) {
      contradict(alert, 'Reported as unresponsive/collapsed, but also as walking and running normally');
    } else if (a.behavior.contains('Friendly/Approachable')) {
      contradict(alert, 'Reported as unresponsive/collapsed, but also as friendly/approachable');
    }
  }
  if (a.injury == kInjuryNone && a.skinAndCoat == kSkinAndCoatOptions[2]) {
    contradict(find('skin'), 'Injury answer says no visible injury, but Skin and Coat reports large open wounds');
  }
  final injurySign = find('injury');
  if (a.injury == kInjuryNone && injurySign != null && injurySign.text.startsWith('Visible sign')) {
    contradict(injurySign, 'Injury answer says no visible injury, but an injury sign was selected');
  }
  final mobilitySign = find('mobility');
  if (a.mobility == kMobilityOptions[0] && mobilitySign != null && mobilitySign.text.startsWith('Visible sign')) {
    contradict(mobilitySign, 'Walking answer says normal, but a mobility sign was selected');
  }
  if (a.needsMedical == 'No') {
    for (final i in indicators.where((i) => i.tier == IndicatorTier.redFlag).toList()) {
      contradict(i, 'Reporter says no immediate medical attention is needed, but also reports: ${i.text}');
    }
  }

  // ---- Context notes (never change the level).
  final injuryReported = a.injury != null && a.injury != kInjuryNone && a.injury != kNotAssessedOption;
  if (injuryReported && a.injuryVisibleInPhotos == kInjuryPhotoOptions[1]) {
    notes.add('Reporter says the injury is not visible in the photos — verify on site');
  } else if (injuryReported && a.injuryVisibleInPhotos == kInjuryPhotoOptions[0]) {
    notes.add('Reporter says the injury is visible in the photos (not checked automatically)');
  }
  if (sexAllowsPregnancyQuestions(a.sex)) {
    if (a.hasLitter == 'Yes') notes.add('Has a litter (reported)');
    if (a.suspectedPregnancy == kSuspectedPregnancyOptions[0]) {
      notes.add('Suspected pregnancy (reporter observation, not vet-confirmed)');
    }
  }
  if (a.behavior.contains('Protecting young')) notes.add('Protecting young');
  if (a.environmentSafety.contains('Around busy roads')) notes.add('Near busy roads');
  if (a.environmentSafety.contains('In dirty cages')) notes.add('Kept in dirty cages');

  // ---- Information check: the answers the rules depend on most.
  bool unknown(String? v) => v == null || v == kNotAssessedOption;
  final missing = <String>[
    if (unknown(a.injury)) 'injury',
    if (unknown(a.alertness)) 'alertness',
    if (unknown(a.mobility)) 'mobility',
    if (unknown(a.bodyCondition)) 'body condition',
  ];
  final insufficient = missing.isNotEmpty;

  // ---- Level.
  final redFlags = indicators.where((i) => i.tier == IndicatorTier.redFlag).toList();
  final severe = indicators.where((i) => i.tier == IndicatorTier.severe).toList();
  final moderate = indicators.where((i) => i.tier == IndicatorTier.moderate).toList();
  bool corroborated(_Indicator s) => indicators.any((o) =>
      o != s &&
      o.dimension != s.dimension &&
      o.functional &&
      (o.tier == IndicatorTier.moderate || o.tier == IndicatorTier.severe));

  String level;
  final reasons = <String>[];
  if (redFlags.isNotEmpty) {
    level = kUrgencyCritical;
    reasons.addAll(redFlags.map((i) => '${i.text} — immediate threat to life'));
  } else if (severe.length >= 2) {
    level = kUrgencyCritical;
    reasons.add('Several severe signs: ${severe.map((i) => i.text).join('; ')}');
  } else if (severe.isNotEmpty && corroborated(severe.first)) {
    level = kUrgencyCritical;
    final support = indicators.firstWhere((o) =>
        o != severe.first && o.dimension != severe.first.dimension && o.functional &&
        (o.tier == IndicatorTier.moderate || o.tier == IndicatorTier.severe));
    reasons.add('${severe.first.text}, together with: ${support.text}');
  } else if (severe.isNotEmpty) {
    level = kUrgencyMedium;
    reasons.add('${severe.first.text} — serious, but no other sign of an immediate emergency was reported');
  } else if (moderate.isNotEmpty) {
    level = kUrgencyMedium;
    reasons.add(moderate.map((i) => i.text).join('; '));
  } else if (insufficient) {
    level = kUrgencyMedium;
  } else {
    level = kUrgencyLow;
    final minor = indicators.where((i) => i.tier == IndicatorTier.minor).map((i) => i.text).toList();
    reasons.add(minor.isEmpty
        ? 'No injury or health concern reported, and normal behavior'
        : '${minor.join('; ')}, with otherwise normal condition and behavior');
  }
  // Remaining indicators not already named, for staff context.
  for (final i in [...severe, ...moderate]) {
    if (!reasons.any((r) => r.contains(i.text))) reasons.add(i.text);
  }
  if (insufficient) {
    reasons.add('Not enough information to rate lower (missing: ${missing.join(', ')})');
  }
  if (conflicts.isNotEmpty) {
    reasons.add('Contradictory answers were counted one level lower; staff should verify');
  }

  return UrgencyAssessment(
    level: level,
    reasons: reasons,
    conflicts: conflicts,
    notes: notes,
    insufficientInformation: insufficient,
    needsStaffVerification: conflicts.isNotEmpty || insufficient ||
        notes.any((n) => n.startsWith('Reporter says the injury is not visible')),
  );
}

/// Assesses a whole report: the highest animal level wins. Each animal's
/// reasons are prefixed with "Animal N" when there is more than one.
UrgencyAssessment assessCaseUrgency(List<AnimalUrgencyInput> animals) {
  if (animals.isEmpty) {
    return const UrgencyAssessment(
      level: kUrgencyMedium,
      reasons: ['No animal details provided — not enough information to rate lower'],
      insufficientInformation: true,
      needsStaffVerification: true,
    );
  }
  final results = [for (final a in animals) assessAnimalUrgency(a)];
  if (results.length == 1) return results.single;

  var top = results.first.level;
  for (final r in results) {
    if (_rank(r.level) > _rank(top)) top = r.level;
  }
  final reasons = <String>[];
  final conflicts = <String>[];
  final notes = <String>[];
  // Animals that set the level first, then the rest, each in report order.
  for (final level in const [kUrgencyCritical, kUrgencyMedium, kUrgencyLow]) {
    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      if (r.level != level) continue;
      reasons.addAll(r.reasons.map((x) => 'Animal ${i + 1} (${r.level}): $x'));
    }
  }
  for (var i = 0; i < results.length; i++) {
    conflicts.addAll(results[i].conflicts.map((x) => 'Animal ${i + 1}: $x'));
    notes.addAll(results[i].notes.map((x) => 'Animal ${i + 1}: $x'));
  }
  return UrgencyAssessment(
    level: top,
    reasons: reasons,
    conflicts: conflicts,
    notes: notes,
    insufficientInformation: results.any((r) => r.insufficientInformation),
    needsStaffVerification: results.any((r) => r.needsStaffVerification),
  );
}
