// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';

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

// Rescue Type options — each type carries its own inherent urgency level,
// so reporters are no longer asked to separately self-assess urgency.
const List<Map<String, String>> kRescueTypeOptions = [
  {
    'label': 'Pet Surrender',
    'description': 'Voluntary ownership surrender',
    'urgency': 'Low',
  },
  {
    'label': 'Lost Pet',
    'description': 'Owner reporting a missing pet for reunification',
    'urgency': 'Low',
  },
  {
    'label': 'Abandonment',
    'description': 'Animal left without care',
    'urgency': 'Medium',
  },
  {
    'label': 'Illness',
    'description':
    'Appears weak, vomiting, coughing, skin disease; suspected illness',
    'urgency': 'Critical',
  },
  {
    'label': 'Injury',
    'description': 'Visible wounds, fractures, bleeding',
    'urgency': 'Critical',
  },

  {
    'label': 'Aggressive Animal',
    'description': 'Displaying aggressive behavior and posing a safety concern',
    'urgency': 'Critical',
  },
];

// Looks up the inherent urgency level for a given rescue type label.
String? urgencyForRescueType(String? label) {
  if (label == null) return null;
  for (final option in kRescueTypeOptions) {
    if (option['label'] == label) return option['urgency'];
  }
  return null;
}

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
