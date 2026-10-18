// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';

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
    'label': 'Neglect or Abuse',
    'description': 'Suspected animal cruelty, starvation, chaining, hoarding',
    'urgency': 'Critical',
  },

  {
    'label': 'Trapped/Disaster',
    'description':
        'Affected by natural disasters / Stuck in debris, infrastructure',
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
      return Colors.redAccent;
    case 'Medium':
      return AppColors.yellowrspwn;
    case 'Low':
      return AppColors.greenrspwn;
    default:
      return AppColors.slaterspwn;
  }
}
