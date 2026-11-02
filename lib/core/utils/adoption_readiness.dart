/// Whether an animal is ready to be listed for adoption. Vaccination alone
/// isn't enough (organization interview): health and recovery, behavior and
/// temperament, vaccines, spay/neuter status and any continuing care all
/// count. Some items are read from the record; the rest need staff to
/// confirm them, because only people who know the animal can.
///
/// A blocked item stops the listing outright (e.g. still in an active
/// treatment episode); every other item needs its confirmation ticked.
enum ReadinessItem {
  health,
  behavior,
  vaccines,
  spayNeuter,
  continuingCare;

  String get title => switch (this) {
        ReadinessItem.health => 'Health and recovery',
        ReadinessItem.behavior => 'Behavior and temperament',
        ReadinessItem.vaccines => 'Vaccinations',
        ReadinessItem.spayNeuter => 'Spay / neuter',
        ReadinessItem.continuingCare => 'Continuing care',
      };
}

enum ReadinessState { ok, needsConfirmation, blocked }

class ReadinessCheck {
  final ReadinessItem item;
  final ReadinessState state;

  /// What the record shows, e.g. "2 vaccines on file, 1 overdue".
  final String finding;

  /// The statement staff tick to confirm; null when nothing to confirm.
  final String? confirmation;

  const ReadinessCheck(this.item, this.state, this.finding, [this.confirmation]);
}

class ReadinessInput {
  final bool inActiveTreatment;
  final List<String> temperament;
  final int vaccineCount;
  final int overdueVaccineCount;
  final bool spayedNeutered;
  final String? currentMedications;
  final String? chronicConditions;
  final List<String> specialNeeds;

  const ReadinessInput({
    required this.inActiveTreatment,
    this.temperament = const [],
    this.vaccineCount = 0,
    this.overdueVaccineCount = 0,
    this.spayedNeutered = false,
    this.currentMedications,
    this.chronicConditions,
    this.specialNeeds = const [],
  });
}

List<ReadinessCheck> assessAdoptionReadiness(ReadinessInput input) {
  String? text(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
  final meds = text(input.currentMedications);
  final conditions = text(input.chronicConditions);
  final care = [
    if (meds != null) 'medications: $meds',
    if (conditions != null) 'conditions: $conditions',
    if (input.specialNeeds.isNotEmpty) 'special needs: ${input.specialNeeds.join(', ')}',
  ];

  return [
    input.inActiveTreatment
        ? const ReadinessCheck(ReadinessItem.health, ReadinessState.blocked,
            'Still in an active treatment episode. Discharge it before listing.')
        : const ReadinessCheck(ReadinessItem.health, ReadinessState.needsConfirmation, 'Not in active treatment.',
            'Recovered and medically stable enough to go home'),
    ReadinessCheck(
      ReadinessItem.behavior,
      ReadinessState.needsConfirmation,
      input.temperament.isEmpty ? 'No temperament recorded.' : 'Recorded: ${input.temperament.join(', ')}.',
      'Behavior assessed; safe to place in a home',
    ),
    ReadinessCheck(
      ReadinessItem.vaccines,
      ReadinessState.needsConfirmation,
      input.vaccineCount == 0
          ? 'No vaccines on file.'
          : '${input.vaccineCount} vaccine record(s)'
              '${input.overdueVaccineCount > 0 ? ', ${input.overdueVaccineCount} overdue' : ', none overdue'}.',
      'Vaccination status reviewed and will be shared with adopters',
    ),
    input.spayedNeutered
        ? const ReadinessCheck(ReadinessItem.spayNeuter, ReadinessState.ok, 'Spayed/neutered.')
        : const ReadinessCheck(ReadinessItem.spayNeuter, ReadinessState.needsConfirmation, 'Not spayed/neutered yet.',
            'Spay/neuter is planned or arranged, and adopters will be told'),
    care.isEmpty
        ? const ReadinessCheck(ReadinessItem.continuingCare, ReadinessState.ok, 'No ongoing care recorded.')
        : ReadinessCheck(ReadinessItem.continuingCare, ReadinessState.needsConfirmation, 'Needs ${care.join('; ')}.',
            'Continuing care will be disclosed to adopters'),
  ];
}

/// True when nothing is blocked and every confirmation in [confirmed] is
/// ticked.
bool readinessSatisfied(List<ReadinessCheck> checks, Set<ReadinessItem> confirmed) =>
    checks.every((c) => switch (c.state) {
          ReadinessState.ok => true,
          ReadinessState.blocked => false,
          ReadinessState.needsConfirmation => confirmed.contains(c.item),
        });
