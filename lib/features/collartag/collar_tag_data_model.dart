import 'package:cloud_firestore/cloud_firestore.dart';

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

  // Generated / system fields
  String? tagId;        // Firestore document ID
  String? qrCodeUrl;
  DateTime? createdAt;

  // Owning user's uid. Written by the collar tag form screen onto both the
  // `users/{uid}/collarTags/{tagId}` doc and its `collarTags/{tagId}` mirror,
  // so it is always present once a tag has been read back from Firestore.
  String? ownerId;

  // Gates QR visibility. A newly submitted tag defaults to false — the QR
  // code stays hidden from the owner until an Organization Administrator
  // reviews the submission and enables it from the admin QR screen.
  bool qrEnabled;

  // NFC support is disabled for now — only QR is used to access a collar
  // tag. Fields kept commented (not deleted) so NFC can be re-enabled later
  // without redesigning the model.
  // final bool? nfcWritten;
  // DateTime? nfcWrittenAt;

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
    this.tagId,
    this.qrCodeUrl,
    this.createdAt,
    this.ownerId,
    this.qrEnabled = false,
    // this.nfcWritten,
    // this.nfcWrittenAt,
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
    'qrCodeUrl': qrCodeUrl ?? '',
    'createdAt': createdAt != null
        ? Timestamp.fromDate(createdAt!)
        : FieldValue.serverTimestamp(),
    // Deliberately NOT included here: a fresh submit (or an owner edit via
    // CollarTagFormScreen) must never flip this back on by accident. Only
    // the admin enable/disable action (see admin_qr_generator_screen.dart)
    // writes 'qrEnabled' directly to Firestore.
    // NFC disabled for now.
    // 'nfcWritten': nfcWritten ?? false,
    // if (nfcWrittenAt != null)
    //   'nfcWrittenAt': Timestamp.fromDate(nfcWrittenAt!),
  };

  // Firestore deserialisation

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
        qrCodeUrl: data['qrCodeUrl'] as String?,
        // createdAt stored as Timestamp — convert to DateTime
        createdAt: data['createdAt'] != null
            ? (data['createdAt'] as Timestamp).toDate()
            : null,
        ownerId: data['ownerId'] as String?,
        qrEnabled: data['qrEnabled'] as bool? ?? false,
        // nfcWritten: data['nfcWritten'] as bool? ?? false,
        // nfcWrittenAt: data['nfcWrittenAt'] != null
        //     ? (data['nfcWrittenAt'] as Timestamp).toDate()
        //     : null,
      );
}