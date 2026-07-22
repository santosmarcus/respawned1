/// Single source of truth for the animal-record characteristic groups —
/// shared by the create/edit form (`create_animal_record_page.dart`), the
/// admin profile tab (`animal_profile_tab.dart`), and the user-side adoption
/// filter sheet (`adoption_page.dart`). All three used to keep their own
/// private copies of these label lists, which had already drifted out of
/// sync (the user filter sheet offered labels — "Rescued From Street",
/// "Special Needs", "Protective" — the create form has no checkbox for).
/// `keyCharacteristics` is one flat array in Firestore (see
/// create_animal_record_page.dart's own comment on why); these three lists
/// are how every reader re-partitions it back into labeled groups.
library;

const List<String> kTemperamentValues = ['Friendly', 'Shy', 'Playful', 'Calm'];

const List<String> kCompatibilityValues = [
  'Good with children',
  'Good with other pets',
  'First-time owner friendly',
];

const List<String> kTrainingValues = [
  'Leash trained',
  'Crate trained',
  'Potty trained',
  'Knows commands',
];

/// The only rescue-background values the create form actually writes —
/// not the more granular "Rescued From Street"/"Rescued From Abuse"/etc.
/// wording other UI once assumed; those aren't separately stored anywhere.
const List<String> kRescueBackgroundValues = ['Rescued', 'Transferred', 'Surrendered'];
