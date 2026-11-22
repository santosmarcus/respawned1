/// The single adoption readiness checklist, used by the Adoptable toggle on
/// the animal record form and by the admin dashboard. Vaccination alone
/// isn't enough (organization interview): treatment, preventive care, a
/// vet checkup, temperament and a photo all count.
///
/// Every item is read from the animal record and its subcollections; none
/// is a tick box. An item is either met or unmet, with a short reason.
/// When some item is unmet, staff can still list the animal, but only by
/// overriding with a written reason (see adoption_readiness_dialog.dart).
library;

import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';

enum ReadinessItem {
  notInTreatment,
  vaccinated,
  dewormed,
  spayNeuter,
  vetCheckup,
  temperament,
  photo;

  String get title => switch (this) {
        ReadinessItem.notInTreatment => 'Not in treatment',
        ReadinessItem.vaccinated => 'Vaccinated',
        ReadinessItem.dewormed => 'Dewormed',
        ReadinessItem.spayNeuter => 'Spay/neuter',
        ReadinessItem.vetCheckup => 'Vet checkup',
        ReadinessItem.temperament => 'Temperament/behavior',
        ReadinessItem.photo => 'Photo',
      };
}

class ReadinessCheck {
  final ReadinessItem item;
  final bool met;

  /// False when the record has no value for this item at all, as opposed
  /// to a recorded "no". The dashboard shows those as "not recorded".
  final bool recorded;

  /// Short reason, e.g. "2 vaccine record(s), 1 overdue."
  final String reason;

  const ReadinessCheck(this.item, {required this.met, required this.reason, this.recorded = true});

  String get label => item.title;

  /// Tri-state for display: true met, false recorded but unmet, null not
  /// recorded.
  bool? get done => met ? true : (recorded ? false : null);

  Map<String, dynamic> toMap() => {'met': met, 'reason': reason};
}

/// What the checklist is evaluated from. Nullable values mean "not
/// recorded" (or, for [vaccineCount], "the vaccinations subcollection
/// wasn't loaded").
class ReadinessInput {
  final bool inActiveTreatment;

  /// Number of docs in `animals/{id}/vaccinations`; null when not loaded.
  final int? vaccineCount;
  final int overdueVaccineCount;

  /// Legacy `vaccinated` flag on the record; null when the key is absent.
  final bool? vaccinated;
  final bool? dewormed;
  final bool? spayedNeutered;
  final DateTime? lastVetCheckup;
  final List<String> temperament;
  final int photoCount;

  const ReadinessInput({
    required this.inActiveTreatment,
    this.vaccineCount,
    this.overdueVaccineCount = 0,
    this.vaccinated,
    this.dewormed,
    this.spayedNeutered,
    this.lastVetCheckup,
    this.temperament = const [],
    this.photoCount = 0,
  });
}

List<ReadinessCheck> assessAdoptionReadiness(ReadinessInput input) {
  ReadinessCheck flag(ReadinessItem item, bool? value, String yes, String no, String missing) => value == null
      ? ReadinessCheck(item, met: false, recorded: false, reason: missing)
      : ReadinessCheck(item, met: value, reason: value ? yes : no);

  final count = input.vaccineCount;
  final ReadinessCheck vaccines;
  if (count != null && count > 0) {
    final overdue = input.overdueVaccineCount;
    vaccines = ReadinessCheck(
      ReadinessItem.vaccinated,
      met: overdue == 0,
      reason: overdue == 0 ? '$count vaccine record(s), none overdue.' : '$count vaccine record(s), $overdue overdue.',
    );
  } else if (input.vaccinated == true) {
    vaccines = const ReadinessCheck(ReadinessItem.vaccinated, met: true, reason: 'Marked vaccinated on the record.');
  } else if (count == 0 || input.vaccinated == false) {
    vaccines = const ReadinessCheck(ReadinessItem.vaccinated, met: false, reason: 'No vaccines on file.');
  } else {
    vaccines =
        const ReadinessCheck(ReadinessItem.vaccinated, met: false, recorded: false, reason: 'Vaccination not recorded.');
  }

  final checkup = input.lastVetCheckup;
  return [
    input.inActiveTreatment
        ? const ReadinessCheck(ReadinessItem.notInTreatment,
            met: false, reason: 'Still in an active treatment episode.')
        : const ReadinessCheck(ReadinessItem.notInTreatment, met: true, reason: 'No open treatment episode.'),
    vaccines,
    flag(ReadinessItem.dewormed, input.dewormed, 'Dewormed.', 'Not dewormed yet.', 'Deworming not recorded.'),
    flag(ReadinessItem.spayNeuter, input.spayedNeutered, 'Spayed/neutered.', 'Not spayed/neutered yet.',
        'Spay/neuter not recorded.'),
    checkup != null
        ? ReadinessCheck(ReadinessItem.vetCheckup, met: true, reason: 'Last checkup ${_date(checkup)}.')
        : const ReadinessCheck(ReadinessItem.vetCheckup, met: false, reason: 'No vet checkup on file.'),
    input.temperament.isEmpty
        ? const ReadinessCheck(ReadinessItem.temperament,
            met: false, recorded: false, reason: 'No temperament recorded.')
        : ReadinessCheck(ReadinessItem.temperament, met: true, reason: 'Recorded: ${input.temperament.join(', ')}.'),
    input.photoCount > 0
        ? ReadinessCheck(ReadinessItem.photo, met: true, reason: '${input.photoCount} photo(s).')
        : const ReadinessCheck(ReadinessItem.photo, met: false, reason: 'No photo yet.'),
  ];
}

/// The checklist for a saved record, from the record alone. The
/// vaccinations subcollection isn't read here, so vaccines fall back to the
/// record's `vaccinated` flag (pass [vaccineCount]/[overdueVaccineCount]
/// when you have them). Treatment is read from `currentCaseId`.
List<ReadinessCheck> readinessForRecord(AnimalRecord a, {int? vaccineCount, int overdueVaccineCount = 0}) {
  final temperament = a.keyCharacteristics.where(kTemperamentValues.contains).toList();
  return assessAdoptionReadiness(ReadinessInput(
    inActiveTreatment: (a.currentCaseId ?? '').isNotEmpty,
    vaccineCount: vaccineCount,
    overdueVaccineCount: overdueVaccineCount,
    vaccinated: a.raw.containsKey('vaccinated') ? a.vaccinated : null,
    dewormed: a.health.dewormed,
    spayedNeutered: a.health.sterilized,
    lastVetCheckup: a.health.lastVetCheckup,
    // Older records may only have compatibility/training traits; those
    // still show someone assessed the animal's behavior.
    temperament: temperament.isNotEmpty ? temperament : a.keyCharacteristics,
    photoCount: a.photoUrls.length,
  ));
}

List<ReadinessCheck> unmetReadiness(List<ReadinessCheck> checks) => [for (final c in checks) if (!c.met) c];

bool readinessAllMet(List<ReadinessCheck> checks) => checks.every((c) => c.met);

/// The `adoptionReadiness` map stored on the animal when it's listed.
/// [confirmedAt] is normally `FieldValue.serverTimestamp()`.
Map<String, dynamic> adoptionReadinessRecord({
  required List<ReadinessCheck> checks,
  required String confirmedBy,
  required Object confirmedAt,
  String? overrideReason,
}) {
  final unmet = unmetReadiness(checks);
  final overridden = unmet.isNotEmpty;
  return {
    'checks': {for (final c in checks) c.item.name: c.toMap()},
    'unmet': [for (final c in unmet) c.item.name],
    'overridden': overridden,
    'overrideReason': overridden ? overrideReason : null,
    'confirmedBy': confirmedBy,
    'confirmedAt': confirmedAt,
  };
}

String _date(DateTime d) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}
