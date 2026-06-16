// collar_tag_model.dart

class CollarTagData {
  // Pet info
  String? petImagePath;       // local path (for form preview)
  String? petImageUrl;        // Firebase Storage URL (after upload)
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

  // Generated
  String? tagId;              // Firestore document ID
  String? qrCodeUrl;          // URL embedded in QR (points to tag profile)
  DateTime? createdAt;

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
  });

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
    'createdAt': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
  };

  factory CollarTagData.fromFirestore(Map<String, dynamic> data, String id) =>
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
        createdAt: data['createdAt'] != null
            ? DateTime.tryParse(data['createdAt'] as String)
            : null,
      );
}