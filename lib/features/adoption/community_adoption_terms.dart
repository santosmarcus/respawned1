/// Terms of the Community Adoption agreement, signed by both the reporter
/// who is rehoming the animal and the adopter.
///
/// The adopter's terms follow the shelter adoption terms
/// (adoption_terms_page.dart adoptionTermsFor) with the parts that only
/// apply to an organization adapted: there is no organization to return
/// the pet to or to sign on adoption day, so the adopter instead commits
/// to the in-app check-ins and to never abandoning the pet.
library;

List<String> communityAdopterTermsFor(String animalName) => [
  'I am over eighteen (18) years of age and can legally adopt.',
  '$animalName is being transferred to me with the understanding that I am '
      'taking possession of the animal to treat and be responsible for it '
      'as my own pet from the moment of handover.',
  'I will treat the pet as a family member with loving care and affection, '
      'and do my best to ensure its safety and well-being.',
  'I will feed the pet at least twice a day and provide fresh water at all '
      'times.',
  'I will not keep the pet chained or tied up, or leave it isolated '
      'outdoors. I will walk it on a leash whenever I take it out.',
  'I will not have the pet attack-trained, ears cropped or tail docked, '
      'and will never allow any physical, mental or emotional abuse of the '
      'pet.',
  'I will bring the pet to a licensed veterinarian for its vaccinations and '
      'for prompt treatment of any illness or injury, and, for a dog, have '
      'it vaccinated against rabies and registered as required by the '
      'Anti-Rabies Act of 2007 (Republic Act No. 9482).',
  'All members of my household have agreed to welcome the pet, and no one '
      'in the household is allergic to or objects to keeping it.',
  'I will take part in post-adoption check-ins through the app and send '
      'updates on the pet\'s well-being when asked.',
  'If I can no longer care for the pet, I will contact the person who '
      'rehomed it to me or a rescue organization, and will never abandon '
      'it. I understand that abandoning an animal is punishable under the '
      'Animal Welfare Act (Republic Act No. 8485, as amended by Republic Act '
      'No. 10631).',
];

List<String> communityListerTermsFor(String animalName) => [
  'The information I gave about $animalName — including its health, '
      'behavior, vaccination and history — is true and complete to the best '
      'of my knowledge.',
  'To my knowledge, no owner has claimed $animalName, or I am its owner and '
      'have the right to rehome it.',
  'I am rehoming $animalName to this adopter and am not selling it.',
  'I will hand over $animalName together with any vaccination or veterinary '
      'records I have, at a time and place agreed with the adopter.',
  'Once the adoption is complete, $animalName is no longer available to '
      'other interested adopters.',
];

/// Shown above the signature fields.
const String kCommunityAgreementNotice =
    'By typing your full name and tapping "Sign Agreement", you agree to '
    'the terms above. Your name and the time you sign are recorded as your '
    'electronic signature. The adoption is complete once both of you have '
    'signed.';
