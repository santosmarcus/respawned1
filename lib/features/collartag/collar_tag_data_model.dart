import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CollarTagData {
  // Pet info
  String? petImagePath;     // local path (form preview only, never sent to Firestore)
  String? petImageUrl;      // Firebase Storage URL
  String name;
  String birthday;
  String sex;
  String breed;
  String colorMarkings;
  String briefDescription;

  // Health info
  bool isSpayedNeutered;
  bool isVaccinated;
  String? vaccinationImagePath;
  String? vaccinationImageUrl;
  String allergies;
  String medicalCondition;

  // Owner info
  String ownerName;
  String ownerMobile;
  String ownerEmail;
  String ownerFacebookLink;

  String status;
  String? activeRescueSessionId;

  /// The Lost & Found report (petAlerts/{id}) opened when the owner marked
  /// this pet lost, closed when it's found. Set by CollarTagLostFound only.
  String? linkedAlertId;

  double? lastSeenLat;
  double? lastSeenLng;
  String? lastSeenAddress;
  DateTime? lostAt;

  // Generated / system fields
  String? tagId;        // Firestore document ID
  String? qrCodeUrl;
  DateTime? createdAt;

  String? ownerId;
  bool qrEnabled;
  // Set by NfcService.writeTag only; never written by toFirestore(), so
  // saving a tag doesn't reset it.
  bool nfcWritten;
  DateTime? nfcWrittenAt;

  CollarTagData({
    this.petImagePath,
    this.petImageUrl,
    this.name = '',
    this.birthday = '',
    this.sex = '',
    this.breed = '',
    this.colorMarkings = '',
    this.briefDescription = '',
    this.isSpayedNeutered = false,
    this.isVaccinated = false,
    this.vaccinationImagePath,
    this.vaccinationImageUrl,
    this.allergies = '',
    this.medicalCondition = '',
    this.ownerName = '',
    this.ownerMobile = '',
    this.ownerEmail = '',
    this.ownerFacebookLink = '',
    this.status = 'active',
    this.activeRescueSessionId,
    this.linkedAlertId,
    this.lastSeenLat,
    this.lastSeenLng,
    this.lastSeenAddress,
    this.lostAt,
    this.tagId,
    this.qrCodeUrl,
    this.createdAt,
    this.ownerId,
    this.qrEnabled = false,
    this.nfcWritten = false,
    this.nfcWrittenAt,
  });

  // Firestore serialisation

  Map<String, dynamic> toFirestore() => {
    'petImageUrl': petImageUrl ?? '',
    'name': name,
    'birthday': birthday,
    'sex': sex,
    'breed': breed,
    'colorMarkings': colorMarkings,
    'briefDescription': briefDescription,
    'isSpayedNeutered': isSpayedNeutered,
    'isVaccinated': isVaccinated,
    'vaccinationImageUrl': vaccinationImageUrl ?? '',
    'allergies': allergies,
    'medicalCondition': medicalCondition,
    'ownerName': ownerName,
    'ownerMobile': ownerMobile,
    'ownerEmail': ownerEmail,
    'ownerFacebookLink': ownerFacebookLink,
    'qrCodeUrl': qrCodeUrl ?? '',
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
  };

  static DateTime? _parseCreatedAt(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  factory CollarTagData.fromFirestore(
      Map<String, dynamic> data,
      String id,
      ) =>
      CollarTagData(
        tagId: id,
        petImageUrl: data['petImageUrl'] as String?,
        name: data['name'] as String? ?? '',
        birthday: data['birthday'] as String? ?? '',
        sex: data['sex'] as String? ?? '',
        breed: data['breed'] as String? ?? '',
        colorMarkings: data['colorMarkings'] as String? ?? '',
        briefDescription: data['briefDescription'] as String? ?? '',
        isSpayedNeutered: data['isSpayedNeutered'] as bool? ?? false,
        isVaccinated: data['isVaccinated'] as bool? ?? false,
        vaccinationImageUrl: data['vaccinationImageUrl'] as String?,
        allergies: data['allergies'] as String? ?? '',
        medicalCondition: data['medicalCondition'] as String? ?? '',
        ownerName: data['ownerName'] as String? ?? '',
        ownerMobile: data['ownerMobile'] as String? ?? '',
        ownerEmail: data['ownerEmail'] as String? ?? '',
        ownerFacebookLink: data['ownerFacebookLink'] as String? ?? '',
        status: data['status'] as String? ?? 'active',
        activeRescueSessionId: data['activeRescueSessionId'] as String?,
        linkedAlertId: data['linkedAlertId'] as String?,
        lastSeenLat: (data['lastSeenLat'] as num?)?.toDouble(),
        lastSeenLng: (data['lastSeenLng'] as num?)?.toDouble(),
        lastSeenAddress: data['lastSeenAddress'] as String?,
        lostAt: _parseCreatedAt(data['lostAt']),
        qrCodeUrl: data['qrCodeUrl'] as String?,
        createdAt: _parseCreatedAt(data['createdAt']),
        ownerId: data['ownerId'] as String?,
        qrEnabled: data['qrEnabled'] as bool? ?? false,
        nfcWritten: data['nfcWritten'] as bool? ?? false,
        nfcWrittenAt: _parseCreatedAt(data['nfcWrittenAt']),
      );
}

/// Marking a collar-tagged pet lost or found, shared by the ID card, the
/// scan chat and an adoption's "Report Lost Pet".
///
/// Lost: the tag goes to status 'lost' with the last-seen pin, and a Lost &
/// Found report (petAlerts, type 'lost', collarTagId) is opened for it, so
/// the pet shows on the Explore map, nearby users are alerted and possible
/// matches are scored like any other lost report. Found: the tag goes back
/// to 'active', every open scan chat is closed and the linked report is
/// marked reunited (onPetAlertReunited in functions/pet_alerts.js does the
/// same in reverse when the report is closed from Lost & Found).
class CollarTagLostFound {
  CollarTagLostFound._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// "Dog - Aspin" (how the tag form saves it) -> ("Dog", "Aspin").
  static (String?, String) speciesAndBreed(String breed) {
    final parts = breed.split(' - ');
    if (parts.length == 2 && (parts[0] == 'Dog' || parts[0] == 'Cat')) {
      return (parts[0], parts[1].trim());
    }
    return (null, breed.trim());
  }

  static String _sexLabel(String sex) => switch (sex.trim().toUpperCase()) {
    'M' => 'Male',
    'F' => 'Female',
    _ => sex.trim(),
  };

  /// Writes [update] to the tag and its owner's users/{uid}/collarTags copy.
  static Future<void> _writeTag(
      String tagId, String? ownerId, Map<String, dynamic> update) async {
    await _db.collection('collarTags').doc(tagId).set(update, SetOptions(merge: true));
    if (ownerId != null && ownerId.isNotEmpty) {
      await _db
          .collection('users')
          .doc(ownerId)
          .collection('collarTags')
          .doc(tagId)
          .set(update, SetOptions(merge: true));
    }
  }

  /// Closes every scan chat still open on the tag (one per finder), plus a
  /// session from before chats were per finder ([legacySessionId]).
  static Future<void> resolveScanChats(String tagId, {String? legacySessionId}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final ids = <String>{?legacySessionId};
    if (uid != null) {
    try {
    final open = await _db
        .collection('rescueSessions')
        .where('tagId', isEqualTo: tagId)
        .where('ownerId', isEqualTo: uid)
        .get();
    for (final d in open.docs) {
    if (d.data()['status'] != 'resolved') ids.add(d.id);
    }
    } catch (_) {}
    }
    for (final id in ids) {
    try {
    await _db.collection('rescueSessions').doc(id).set(
    {'status': 'resolved', 'resolvedAt': FieldValue.serverTimestamp()},
    SetOptions(merge: true),
    );
    } catch (_) {
    // Best effort: a chat that can't be closed must not block the rest.
    }
    }
  }

  /// Marks the pet lost at [lat]/[lng] and opens (or moves) its Lost &
  /// Found report. Returns the report's id.
  static Future<String> markLost(
      CollarTagData tag, {
        required double lat,
        required double lng,
        required String address,
        String? species,
        Map<String, dynamic> extraTagFields = const {},
        Map<String, dynamic> extraAlertFields = const {},
      }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final tagId = tag.tagId!;
    final ownerId = tag.ownerId ?? uid;

    // Chats left over from an earlier lost cycle start fresh.
    await resolveScanChats(tagId, legacySessionId: tag.activeRescueSessionId);

    final (parsedSpecies, breed) = speciesAndBreed(tag.breed);
    final alertFields = <String, dynamic>{
      'petName': tag.name,
      'species': species ?? parsedSpecies,
      'breed': breed,
      'sex': _sexLabel(tag.sex),
      'colorMarkings': tag.colorMarkings,
      'photoUrls': [
        if (tag.petImageUrl?.isNotEmpty == true) tag.petImageUrl!,
      ],
      'contactNumber': tag.ownerMobile,
      'address': address,
      'lat': lat,
      'lng': lng,
      'lastSeenDate': Timestamp.now(),
      ...extraAlertFields,
    };

    // Reuse the report if one is still open (marked lost again before it
    // was found), otherwise open a new one.
    String? alertId;
    final existingId = tag.linkedAlertId;
    if (existingId != null && existingId.isNotEmpty) {
      final existing = await _db.collection('petAlerts').doc(existingId).get();
      if (existing.exists && (existing.data()?['status'] ?? 'open') == 'open') {
        await existing.reference.update(alertFields);
        alertId = existingId;
      }
    }
    if (alertId == null) {
      final ref = await _db.collection('petAlerts').add({
        'type': 'lost',
        'source': 'collar_tag',
        'collarTagId': tagId,
        'groupId': null,
        'reporterId': uid,
        'reporterName': tag.ownerName,
        ...alertFields,
        'status': 'open',
        'createdAt': Timestamp.now(),
        'serverCreatedAt': FieldValue.serverTimestamp(),
      });
      await ref.update({'groupId': ref.id});
      alertId = ref.id;
    }

    await _setTagLost(tagId, ownerId,
        alertId: alertId, lat: lat, lng: lng, address: address, extra: extraTagFields);
    return alertId;
  }

  /// The owner filed a lost report for this pet from the report form
  /// (petAlerts/[alertId], with collarTagId): marks the tag lost with the
  /// same pin and links the report, so anyone who scans the tag (in the app
  /// or on the web page) can message the owner, and finding the pet closes
  /// both.
  static Future<void> linkLostReport(
      CollarTagData tag, {
        required String alertId,
        required double lat,
        required double lng,
        required String address,
      }) async {
    final tagId = tag.tagId!;
    await resolveScanChats(tagId, legacySessionId: tag.activeRescueSessionId);
    await _setTagLost(tagId, tag.ownerId ?? FirebaseAuth.instance.currentUser!.uid,
        alertId: alertId, lat: lat, lng: lng, address: address);
  }

  static Future<void> _setTagLost(
      String tagId,
      String? ownerId, {
        required String alertId,
        required double lat,
        required double lng,
        required String address,
        Map<String, dynamic> extra = const {},
      }) {
    return _writeTag(tagId, ownerId, {
      'status': 'lost',
      'lastSeenLat': lat,
      'lastSeenLng': lng,
      'lastSeenAddress': address,
      'lostAt': FieldValue.serverTimestamp(),
      'linkedAlertId': alertId,
      'activeRescueSessionId': FieldValue.delete(),
      ...extra,
    });
  }

  /// Marks the pet found: the tag goes back to active, its scan chats close
  /// and its Lost & Found report is marked reunited (and archived for the
  /// owner, who is the one marking it).
  static Future<void> markFound(CollarTagData tag) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final tagId = tag.tagId!;

    await resolveScanChats(tagId, legacySessionId: tag.activeRescueSessionId);

    await _writeTag(tagId, tag.ownerId ?? uid, {
      'status': 'active',
      'lastSeenLat': FieldValue.delete(),
      'lastSeenLng': FieldValue.delete(),
      'lastSeenAddress': FieldValue.delete(),
      'lostAt': FieldValue.delete(),
      'activeRescueSessionId': FieldValue.delete(),
      'linkedAlertId': FieldValue.delete(),
    });

    final alertId = tag.linkedAlertId;
    if (alertId == null || alertId.isEmpty) return;
    try {
      final alert = await _db.collection('petAlerts').doc(alertId).get();
      final status = alert.data()?['status'] as String? ?? 'open';
      if (!alert.exists || status == 'reunited' || status == 'resolved') return;
      await alert.reference.update({
        'status': 'reunited',
        'reunitedAt': FieldValue.serverTimestamp(),
        'reunitedBy': uid,
        'reporterAcknowledgedReunion': true,
      });
    } catch (_) {
      // The tag is already back to active; the report can still be closed
      // from Lost & Found.
    }
  }
}
