/// Shelter animal collar tags (QR and NFC): one code format, one payload,
/// one parser, shared by the Management tab (where tags are created), the
/// NFC writer and every scanner.
///
/// A tag code is registered in `animalTags/{code}` (AnimalRecordRepository)
/// with the animal it belongs to. The document id IS the code, so a code
/// can never belong to two animals, and firestore.rules never lets a
/// registration move to another animal.
///
/// QR codes and NFC chips both carry [animalTagPayload]: a QR scan and an
/// NFC read are resolved the same way ([animalTagFromScan]).
library;

import 'dart:math' as math;

/// Prefix of the payload printed on QR tags and written to NFC chips.
const String kAnimalTagPrefix = 'RESPAWND-ANIMAL:';

/// No look-alike characters (0/O, 1/I), so a code can be read aloud or
/// typed from a damaged tag.
const String kAnimalTagAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const int kAnimalTagLength = 8;

/// The two kinds of collar tag. Stored as their [name] ('qr' | 'nfc').
enum AnimalTagType {
  qr,
  nfc;

  String get label => switch (this) {
        AnimalTagType.qr => 'QR tag',
        AnimalTagType.nfc => 'NFC tag',
      };

  /// The animal field holding this type's current code.
  String get animalField => switch (this) {
        AnimalTagType.qr => 'qrTagId',
        AnimalTagType.nfc => 'nfcTagId',
      };

  static AnimalTagType? fromName(Object? v) => switch (v) {
        'qr' => AnimalTagType.qr,
        'nfc' => AnimalTagType.nfc,
        _ => null,
      };
}

/// A new random code. Random (secure) rather than derived from the animal
/// id, so it can't be guessed; uniqueness is guaranteed by registering it
/// in a transaction (AnimalRecordRepository.registerTag).
String newAnimalTagCode([math.Random? random]) {
  final rng = random ?? math.Random.secure();
  return List.generate(kAnimalTagLength, (_) => kAnimalTagAlphabet[rng.nextInt(kAnimalTagAlphabet.length)]).join();
}

/// Codes this app generates. Older codes ([animalTagFromScan]'s 6-16
/// characters) are still accepted when scanned.
bool isGeneratedAnimalTagCode(String code) =>
    RegExp('^[$kAnimalTagAlphabet]{$kAnimalTagLength}\$').hasMatch(code);

/// The machine-readable value on a QR tag or NFC chip. Never empty: an
/// empty or malformed code throws instead of producing a tag nobody can
/// scan.
String animalTagPayload(String code) {
  final c = code.trim().toUpperCase();
  if (animalTagFromScan('$kAnimalTagPrefix$c') == null) {
    throw ArgumentError.value(code, 'code', 'Not a valid animal tag code');
  }
  return '$kAnimalTagPrefix$c';
}

/// The tag code inside a scanned QR or NFC payload, or null if [raw] isn't
/// an animal tag.
String? animalTagFromScan(String raw) {
  final value = raw.trim();
  if (!value.toUpperCase().startsWith(kAnimalTagPrefix)) return null;
  final tag = value.substring(kAnimalTagPrefix.length).trim().toUpperCase();
  return RegExp(r'^[A-Z0-9]{6,16}$').hasMatch(tag) ? tag : null;
}
