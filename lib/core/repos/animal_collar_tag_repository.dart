import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';

/// Collar ID tags for shelter animals: collarTags/animal-{animalId}, the
/// same document shape as a pet owner's tag, so the QR code, an NFC chip
/// written with the tag link, the in-app scanner and public/tag/index.html
/// all open the same collar tag view.
///
/// The app creates/refreshes the tag when a record is saved ([sync]);
/// functions/animal_collar_tags.js (syncAnimalCollarTag) keeps it in step
/// with every later change. Keep [fieldsFor] in sync with collarTagOf there.
class AnimalCollarTagRepository {
  AnimalCollarTagRepository({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  static String tagIdFor(String animalId) => 'animal-$animalId';

  static String _str(Object? v) => v is String ? v.trim() : (v == null ? '' : v.toString());

  static bool _isUrl(Object? v) => v is String && RegExp(r'^https?://').hasMatch(v);

  static String _firstPhoto(Map<String, dynamic> data) {
    for (final key in const ['photoUrls', 'images', 'imageUrls']) {
      final list = data[key];
      if (list is List) {
        final url = list.firstWhere(_isUrl, orElse: () => null);
        if (url != null) return url as String;
      }
    }
    for (final key in const ['photoUrl', 'imageUrl', 'profileImage']) {
      if (_isUrl(data[key])) return data[key] as String;
    }
    return '';
  }

  static String _join(Iterable<Object?> parts, String sep) =>
      parts.map(_str).where((p) => p.isNotEmpty).join(sep);

  /// The collar tag fields for an animal record and its organization.
  static Map<String, dynamic> fieldsFor(
    String animalId,
    Map<String, dynamic> data,
    Map<String, dynamic>? org,
  ) {
    final o = org ?? const <String, dynamic>{};
    final specialNeeds = data['specialNeedsTypes'] is List ? data['specialNeedsTypes'] as List : const [];
    final coat = _str(data['coatLength']);
    return {
      'animalId': animalId,
      'organizationId': _str(data['organizationId']),
      'source': 'animal_record',
      'petImageUrl': _firstPhoto(data),
      'name': _str(data['name']),
      // Shelter animals have an age, not a birthday; the views label it
      // "Age" when animalId is set.
      'birthday': _str(data['age']),
      'sex': _str(data['sex']),
      'breed': _str(data['breed']).isNotEmpty ? _str(data['breed']) : _str(data['species']),
      'colorMarkings': _join([data['species'], data['size'], coat.isNotEmpty ? '$coat coat' : ''], ' · '),
      'briefDescription': _str(data['description']),
      'isSpayedNeutered': data['spayedNeutered'] == true,
      'isVaccinated': data['vaccinated'] == true,
      'allergies': _str(data['allergies']),
      'medicalCondition': _join([data['chronicConditions'], ...specialNeeds], ', '),
      'ownerName': _str(o['name']),
      'ownerMobile': _str(o['contactNumber']).isNotEmpty ? _str(o['contactNumber']) : _str(o['phone']),
      'ownerEmail': _str(o['email']),
      'ownerFacebookLink': _str(o['facebookUrl']),
      // The registered codes (animalTags) its QR tag and NFC chip carry.
      'animalQrCode': _str(data['qrTagId']),
      'animalNfcCode': _str(data['nfcTagId']),
      'qrEnabled': true,
      'archived': data['archived'] == true || data['status'] == 'deceased',
    };
  }

  /// Creates or refreshes the animal's collar tag from its record and
  /// returns the tag id. Lost/found fields on the tag are kept.
  Future<String> sync(String animalId) async {
    final tagId = tagIdFor(animalId);
    final animal = await _db.collection('animals').doc(animalId).get();
    final data = animal.data();
    if (data == null) throw StateError('Animal record $animalId not found.');

    Map<String, dynamic>? org;
    final orgId = _str(data['organizationId']);
    if (orgId.isNotEmpty) {
      try {
        org = (await _db.collection('organizations').doc(orgId).get()).data();
      } on FirebaseException {
        org = null;
      }
    }

    final ref = _db.collection('collarTags').doc(tagId);
    final isNew = !(await ref.get()).exists;
    await ref.set({
      ...fieldsFor(animalId, data, org),
      if (isNew) 'status': 'active',
      if (isNew) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return tagId;
  }

  /// The animal's collar tag, live; null until it exists.
  Stream<CollarTagData?> watch(String animalId) {
    final tagId = tagIdFor(animalId);
    return _db.collection('collarTags').doc(tagId).snapshots().map(
          (d) => d.exists ? CollarTagData.fromFirestore(d.data()!, d.id) : null,
        );
  }
}
