/// Reads the EXACT nested structure adoption_process.dart already writes
/// (personal/household/petExperience/lifestyle/agreement) and turns it into
/// readable label/answer pairs, grouped the same way the user-side form
/// itself is grouped. Never invents a question that isn't actually in that
/// form; a question missing from an older application (fewer fields were
/// asked at submission time) renders as "Not provided" rather than being
/// silently dropped, so the section shape stays stable across old and new
/// applications.
class ResponseSection {
  final String title;
  final List<ResponseItem> items;
  const ResponseSection(this.title, this.items);
}

class ResponseItem {
  final String label;
  final String answer;
  const ResponseItem(this.label, this.answer);
}

const String kNotProvided = 'Not provided';

String _orNA(dynamic v) {
  if (v == null) return kNotProvided;
  final s = v.toString().trim();
  return s.isEmpty ? kNotProvided : s;
}

String _yesNo(bool? v) => v == null ? kNotProvided : (v ? 'Yes' : 'No');

List<ResponseSection> buildAdoptionResponseSections(Map<String, dynamic> data) {
  final household = (data['household'] as Map?) ?? const {};
  final petExperience = (data['petExperience'] as Map?) ?? const {};
  final currentPets = (petExperience['currentPets'] as Map?) ?? const {};
  final lifestyle = (data['lifestyle'] as Map?) ?? const {};
  final canAfford = (lifestyle['canAfford'] as Map?) ?? const {};
  final agreement = (data['agreement'] as Map?) ?? const {};

  final petCounts = <String>[
    if ((currentPets['dogs'] as num?)?.toInt() != null && (currentPets['dogs'] as num).toInt() > 0)
      'Dogs: ${currentPets['dogs']}',
    if ((currentPets['cats'] as num?)?.toInt() != null && (currentPets['cats'] as num).toInt() > 0)
      'Cats: ${currentPets['cats']}',
    if ((currentPets['birds'] as num?)?.toInt() != null && (currentPets['birds'] as num).toInt() > 0)
      'Birds: ${currentPets['birds']}',
    if ((currentPets['fish'] as num?)?.toInt() != null && (currentPets['fish'] as num).toInt() > 0)
      'Fish: ${currentPets['fish']}',
    if ((currentPets['reptiles'] as num?)?.toInt() != null && (currentPets['reptiles'] as num).toInt() > 0)
      'Reptiles: ${currentPets['reptiles']}',
    if ((currentPets['other'] as num?)?.toInt() != null && (currentPets['other'] as num).toInt() > 0)
      'Other (${_orNA(currentPets['otherType'])}): ${currentPets['other']}',
  ];

  final affordable = <String>[
    if (canAfford['food'] == true) 'Food',
    if (canAfford['vaccinations'] == true) 'Vaccinations',
    if (canAfford['vetVisits'] == true) 'Vet Visits',
    if (canAfford['emergencyMedicalCare'] == true) 'Emergency Medical Care',
    if (canAfford['grooming'] == true) 'Grooming',
    if (canAfford['careSupplies'] == true) 'Care Supplies',
  ];

  return [
    ResponseSection('Household & Living Information', [
      ResponseItem('Residence Type',
          household['residenceType'] == 'Other' ? _orNA(household['residenceOther']) : _orNA(household['residenceType'])),
      ResponseItem('Ownership Status', _orNA(household['ownershipStatus'])),
      ResponseItem('Number of Household Members', _orNA(household['householdMembers'])),
    ]),
    ResponseSection('Pet Experience', [
      ResponseItem('Owned pets before?', _yesNo(petExperience['hadPetsBefore'] as bool?)),
      ResponseItem('Current pets', petCounts.isEmpty ? 'None' : petCounts.join(', ')),
      ResponseItem('Are all current pets vaccinated?', _orNA(petExperience['currentPetsVaccinated'])),
      ResponseItem('Are all current pets spayed/neutered?', _orNA(petExperience['currentPetsSpayedNeutered'])),
    ]),
    ResponseSection('Lifestyle & Care', [
      ResponseItem('Hours animal will be left alone', _orNA(lifestyle['hoursAlone'])),
      ResponseItem('Primary Caregiver', _orNA(lifestyle['primaryCaregiver'])),
      ResponseItem('Where will pet stay?', _orNA(lifestyle['petStayLocation'])),
      ResponseItem('Can afford', affordable.isEmpty ? kNotProvided : affordable.join(', ')),
      ResponseItem('Monthly Pet Budget', _orNA(lifestyle['monthlyBudget'])),
    ]),
    ResponseSection('Adoption Intent', [
      ResponseItem('Why do you want to adopt?', _orNA(agreement['reason'])),
    ]),
    ResponseSection('Agreements', [
      ResponseItem('Will provide proper care', _yesNo(agreement['care'] as bool?)),
      ResponseItem('Will not abandon the animal', _yesNo(agreement['noAbandon'] as bool?)),
      ResponseItem('Agrees to post-adoption follow-ups', _yesNo(agreement['followUp'] as bool?)),
      ResponseItem('Information provided is accurate', _yesNo(agreement['infoAccurate'] as bool?)),
      ResponseItem('Understands approval is not guaranteed', _yesNo(agreement['approvalNotGuaranteed'] as bool?)),
    ]),
  ];
}
