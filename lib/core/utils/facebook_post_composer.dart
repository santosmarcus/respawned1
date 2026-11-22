import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';

/// A detail staff can choose to put in a shared post, per animal.
enum ShareField {
  status('Adoption status'),
  speciesBreed('Species & breed'),
  sex('Sex'),
  age('Age'),
  size('Size'),
  coat('Coat length'),
  health('Health (vaccinated, spayed…)'),
  personality('Personality'),
  background('Rescue background'),
  description('Description');

  const ShareField(this.label);
  final String label;

  /// Checked when the composer opens.
  static const Set<ShareField> defaults = {
    ShareField.status,
    ShareField.speciesBreed,
    ShareField.sex,
    ShareField.age,
    ShareField.health,
    ShareField.description,
  };
}

/// Whether an animal has a public profile, so its web link works: the
/// same test as functions/public_animals.js isPublic.
bool hasPublicProfile(AnimalRecord a) => !a.archived && !a.publicProfileHidden && !a.isDeceased;

/// Plain-words adoption status, matching the public web page.
String publicStatusText(AnimalRecord a) {
  if (a.isAdopted) return 'Adopted';
  if (a.isReserved) return 'Reserved';
  if (a.isAdoptable) return 'Available for adoption';
  return 'Not yet available for adoption';
}

String displayNameOf(AnimalRecord a) => a.name.trim().isNotEmpty ? a.name.trim() : a.species;

/// The block of text for one animal: its name and status, then the chosen
/// details, then the link to its full profile when [withLink].
String composeAnimalBlock(AnimalRecord a, Set<ShareField> fields, {required bool withLink}) {
  final lines = <String>[];
  final heading = StringBuffer('🐾 ${displayNameOf(a)}');
  if (fields.contains(ShareField.status)) heading.write(' — ${publicStatusText(a)}');
  lines.add(heading.toString());

  final basics = <String>[
    if (fields.contains(ShareField.speciesBreed)) ...[
      if (a.species.trim().isNotEmpty) a.species.trim(),
      if (a.breed.trim().isNotEmpty) a.breed.trim(),
    ],
    if (fields.contains(ShareField.sex) && a.sex.trim().isNotEmpty) a.sex.trim(),
    if (fields.contains(ShareField.age) && a.age.trim().isNotEmpty) a.age.trim(),
    if (fields.contains(ShareField.size) && a.size.trim().isNotEmpty) '${a.size.trim()} size',
    if (fields.contains(ShareField.coat) && a.coatLength.trim().isNotEmpty) '${a.coatLength.trim()} coat',
  ];
  if (basics.isNotEmpty) lines.add(basics.join(' · '));

  if (fields.contains(ShareField.health)) {
    final health = [
      if (a.vaccinated) 'Vaccinated',
      if (a.spayedNeutered) 'Spayed/Neutered',
      if (a.dewormed) 'Dewormed',
      if (a.hasSpecialNeeds)
        a.specialNeedsTypes.isEmpty ? 'Special needs' : 'Special needs: ${a.specialNeedsTypes.join(', ')}',
    ];
    if (health.isNotEmpty) lines.add('✅ ${health.join(', ')}');
  }
  if (fields.contains(ShareField.personality) && a.keyCharacteristics.isNotEmpty) {
    lines.add('💛 ${a.keyCharacteristics.join(', ')}');
  }
  if (fields.contains(ShareField.background) && a.rescueBackground.isNotEmpty) {
    lines.add('📖 ${a.rescueBackground.join(', ')}');
  }
  if (fields.contains(ShareField.description) && a.description.trim().isNotEmpty) {
    lines.add(a.description.trim());
  }
  if (withLink && hasPublicProfile(a)) {
    lines.add('🔗 Full profile: ${AppLinks.animalUrl(a.id)}');
  }
  return lines.join('\n');
}

/// The whole post: [intro], one block per animal, then [closing]. Records
/// without a public profile never get a link (it would show "not available").
String composeFacebookPost({
  required List<AnimalRecord> animals,
  required Set<ShareField> fields,
  required bool withLinks,
  String intro = '',
  String closing = '',
}) {
  final parts = <String>[
    if (intro.trim().isNotEmpty) intro.trim(),
    for (final a in animals) composeAnimalBlock(a, fields, withLink: withLinks),
    if (closing.trim().isNotEmpty) closing.trim(),
  ];
  return parts.join('\n\n');
}

/// A suggested opening line for the selected animals.
String defaultIntro(List<AnimalRecord> animals) {
  if (animals.length == 1) return 'Meet ${displayNameOf(animals.single)}! 🐶🐱';
  return 'Meet ${animals.length} of our rescues looking for their forever homes! 🐶🐱';
}

const String kDefaultClosing = 'Message us or open the full profile to apply, sponsor or ask questions. 💛';
