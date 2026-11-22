// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';

import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';

// Static option lists and lookups for the Report a Stray form.

const String kDogSpecies = 'Dog';
const String kCatSpecies = 'Cat';
const String kOthersBreedLabel = 'Others / Not sure';

const List<String> kDogBreeds = [
  kOthersBreedLabel,
  'Aspin (Mixed/Native)',
  'Beagle',
  'Chihuahua',
  'Corgi',
  'Dachshund',
  'French Bulldog',
  'German Shepherd',
  'Golden Retriever',
  'Japanese Spitz',
  'Labrador Retriever',
  'Pomeranian',
  'Poodle',
  'Shiba Inu',
  'Shih Tzu',
  'Siberian Husky',
  'Rottweiler',
];

const List<String> kCatBreeds = [
  kOthersBreedLabel,
  'American Shorthair',
  'Bengal',
  'British Shorthair',
  'Himalayan',
  'Maine Coon',
  'Persian',
  'Puspin (Mixed/Native)',
  'Ragdoll',
  'Scottish Fold',
  'Siamese',
];

List<String> breedOptionsFor(String? species) {
  if (species == kDogSpecies) return kDogBreeds;
  if (species == kCatSpecies) return kCatBreeds;
  return const [kOthersBreedLabel];
}

// Pet Surrender: reasons for surrendering.
const List<String> kSurrenderReasonOptions = [
  'Financial difficulties',
  'Moving/Relocation',
  'Housing restrictions',
  'Medical issues (owner)',
  'Medical issues (pet)',
  'Behavioral issues',
  'Compatibility with other pets',
  'Compatibility with children/family',
  'Lack of time',
  'Lifestyle changes',
  'Owner passed away',
  'Emergency circumstances',
  'Other (please specify)',
];

// Pet Surrender: where the pet was acquired.
const List<String> kAcquisitionSourceOptions = [
  'Breeder',
  'Stray',
  'Pet Store',
  'Rescue Org',
  'Friend/Family',
  'Born at home',
];

// Pet Surrender: vaccination status.
const List<String> kSurrenderVaccinationOptions = [
  'Fully vaccinated (up to date)',
  'Partially vaccinated',
  'Not vaccinated',
  'Unknown',
];

// Pet Surrender: spay / neuter status.
const List<String> kSurrenderSpayNeuterOptions = ['Yes', 'No', 'Unknown'];

// Pet Surrender: compatibility. Reuses the Animal Record's own
// kCompatibilityValues so intake can carry the answers straight into the
// record, plus one "not sure" choice for owners who have never tested it.
const String kSurrenderCompatibilityUnknown = 'Not sure / Not yet tested';
const List<String> kSurrenderCompatibilityOptions = [
  ...kCompatibilityValues,
  kSurrenderCompatibilityUnknown,
];

// Pet Surrender: how soon the pet needs to be rehomed.
const List<String> kSurrenderTimelineOptions = [
  'Urgent (within 48 hours)',
  'Within a week',
  'Within a month',
  'Flexible',
];

// Most vet records a reporter can attach to a surrender.
const int kMaxVetRecordPhotos = 3;

// Abandonment: follow-up questions shown only for that rescue type.
const String kAbandonmentType = 'Abandonment';

const List<String> kAbandonmentDurationOptions = [
  'Less than 24 hours',
  '1–3 days',
  'More than 3 days',
  'Not sure',
];

const String kAbandonmentLocationOther = 'Others (please specify)';

const List<String> kAbandonmentLocationOptions = [
  'Inside a locked house or property',
  'Tied or caged outside',
  'Dumped in a box or sack',
  'Roaming freely',
  kAbandonmentLocationOther,
];

const List<String> kAbandonmentFoodWaterOptions = ['Yes', 'No', 'Unknown'];

const List<String> kYesNoOptions = ['Yes', 'No'];

const List<String> kAbandonmentWitnessOptions = [
  'I saw it happen',
  'Neighbors told me',
  'I found the animal alone',
];

// Neglect or Abuse: follow-up questions shown only for that rescue type.
const String kNeglectAbuseType = 'Neglect or Abuse';

const String kNeglectObservedOther = 'Other';
const List<String> kNeglectObservedOptions = [
  'Physical harm (beating, kicking, burning)',
  'Starvation or no food and water',
  'Constantly chained or caged',
  'No shelter from sun or rain',
  'Too many animals (hoarding)',
  'Poisoning',
  'Slaughter or meat trade',
  kNeglectObservedOther,
];

const List<String> kNeglectFrequencyOptions = [
  'Once',
  'Several times',
  'Ongoing for weeks or longer',
];

const List<String> kYesNoNotSureOptions = ['Yes', 'No', 'Not sure'];

// Neglect or Abuse, per animal: visible signs of harm.
const String kNeglectSignsNone = 'No visible signs';
const List<String> kNeglectAnimalSignsOptions = [
  'Open wounds or injuries',
  'Severely thin (visible ribs or bones)',
  'Signs of dehydration',
  'Untreated skin disease or hair loss',
  'Embedded collar or chain wounds',
  'Overgrown nails or heavily matted coat',
  'Limping or unable to stand',
  'Fearful, cowering or withdrawn',
  kNeglectSignsNone,
];

// Neglect or Abuse, per animal: living-condition choices added to the
// Environment and Safety section.
const List<String> kNeglectEnvironmentOptions = [
  'Exposed to sun or rain',
  'Dirty, flooded or surrounded by waste',
  'Cramped cage or very short chain',
  'No food or water in sight',
  'Kept with sick or dead animals',
];

// Injury, per animal: visible signs common in injured dogs and cats.
const List<String> kInjurySignsOptions = [
  'Open wound or deep cut',
  'Active or heavy bleeding',
  'Bite wounds from a fight',
  'Wound with maggots',
  'Limping or not using a leg',
  'Suspected broken bone',
  'Swelling or lump',
  'Burns',
  'Eye injury',
  'Head or face injury',
  'Unable to stand or walk',
  'Trapped in a snare, wire or net',
  'Likely hit by a vehicle',
  kNeglectSignsNone,
];

// Illness, per animal: visible signs common in sick dogs and cats
// (e.g. parvovirus, distemper, mange, tick-borne disease).
const List<String> kIllnessSignsOptions = [
  'Vomiting',
  'Diarrhea (with or without blood)',
  'Coughing or sneezing',
  'Nasal or eye discharge',
  'Difficulty breathing',
  'Not eating, or weak and sleepy',
  'Seizures, twitching or tremors',
  'Skin disease or hair loss (mange)',
  'Heavy ticks or fleas',
  'Pale or yellow gums',
  'Swollen belly',
  'Excessive drooling',
  kNeglectSignsNone,
];

// Aggressive Animal, per animal: signs of aggression in dogs and cats,
// including fear and pain aggression and signs that can point to rabies.
const String kAggressiveAnimalType = 'Aggressive Animal';

const List<String> kAggressionSignsOptions = [
  'Growling, snarling or hissing',
  'Baring teeth',
  'Fur standing up on its back',
  'Stiff body or fixed stare',
  'Lunging or charging',
  'Snapping or biting at people',
  'Attacking other animals',
  'Chasing people or vehicles',
  'Guarding food, an area or its young',
  'Ears pinned back or tail tucked (fearful)',
  'Foaming or drooling at the mouth',
  'Disoriented, wandering or staggering',
  'Biting at objects or the air',
  'Appears injured or in pain',
  kNeglectSignsNone,
];

// Aggressive Animal, per animal: Environment and Safety choices about the
// risk the animal poses where it is.
const List<String> kAggressiveEnvironmentOptions = [
  'Near children or a school',
  'In a crowded public area',
  'Roaming near homes or a market',
  'Part of a pack of animals',
  'Tied up or confined',
  'Cornered in an enclosed space',
];

/// The per-animal "visible signs" choices for [rescueType], or null when
/// that type doesn't ask (only Injury, Illness, Neglect or Abuse and
/// Aggressive Animal do). These types also ask whether the animal needs
/// immediate medical attention and add their own choices to Environment
/// and Safety.
List<String>? visibleSignsOptionsFor(String? rescueType) =>
    switch (rescueType) {
      'Injury' => kInjurySignsOptions,
      'Illness' => kIllnessSignsOptions,
      kNeglectAbuseType => kNeglectAnimalSignsOptions,
      kAggressiveAnimalType => kAggressionSignsOptions,
      _ => null,
    };

/// Label for the per-animal "visible signs" question.
String visibleSignsLabelFor(String? rescueType) => switch (rescueType) {
  'Injury' => 'Visible signs of injury',
  'Illness' => 'Visible signs of illness',
  kAggressiveAnimalType => 'Visible signs of aggression',
  _ => 'Visible signs of harm',
};

/// Choices added to Environment and Safety for [rescueType].
List<String> environmentExtrasFor(String? rescueType) => switch (rescueType) {
  kAggressiveAnimalType => kAggressiveEnvironmentOptions,
  'Injury' || 'Illness' || kNeglectAbuseType => kNeglectEnvironmentOptions,
  _ => const [],
};

/// The per-animal medical-attention question for [rescueType].
String medicalQuestionFor(String? rescueType) => switch (rescueType) {
  kAggressiveAnimalType =>
  'Does the animal appear injured or sick and need immediate medical '
      'attention?',
  _ => 'Does the animal need immediate medical attention?',
};

// Rescue Type options. Urgency is no longer tied to the type: it is
// assessed from the reporter's answers for each animal
// (core/utils/urgency_assessment.dart). Pet Surrender and Lost Pet are
// community reports the organization does not facilitate
// (OrgInvolvement.notFacilitated), so they carry no urgency at all.
const List<Map<String, String>> kRescueTypeOptions = [
  {
    'label': kRescueTypePetSurrender,
    'description': 'Rehoming your own pet through Community Adoption. '
  },
  {
    'label': kRescueTypeLostPet,
    'description': 'Owner or finder of a missing pet. Shared with the community '
        'for matching.',
  },
  {
    'label': 'Abandonment',
    'description': 'Animal left without care',
  },
  {
    'label': 'Illness',
    'description':
    'Appears weak, vomiting, coughing, skin disease; suspected illness',
  },
  {
    'label': 'Injury',
    'description': 'Visible wounds, fractures, bleeding',
  },
  {
    'label': 'Neglect or Abuse',
    'description': 'Suspected animal cruelty, starvation, chaining, hoarding. '
        'Ask the organization for help, or report it yourself with our guide.',
  },
  {
    'label': 'Aggressive Animal',
    'description': 'Displaying aggressive behavior and posing a safety concern',
  },
];

// Small color cue per urgency level, reusing existing app palette.
Color urgencyColorFor(String? urgency) {
  switch (urgency) {
    case 'Critical':
      return AppColors.error;
    case 'Medium':
      return AppColors.yellowrspwn;
    case 'Low':
      return AppColors.greenrspwn;
    default:
      return AppColors.slaterspwn;
  }
}
