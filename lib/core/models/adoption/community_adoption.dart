import 'package:cloud_firestore/cloud_firestore.dart';

/// Typed view over a `communityAdoptions/{id}` document.
///
/// A Community Adoption is deliberately lighter-weight than the org-run
/// shelter pipeline (create_animal_record_page.dart -> adoption_page.dart /
/// adoption_application.dart): it is created directly from a rescue report
/// that was rejected for being healthy/low-urgency (see
/// community_adoption_eligibility.dart), the animal never enters the
/// Animal Records module, and there is no vet intake, application review,
/// or reservation flow attached to it.
///
/// Unlike an org-run adoption listing, submitting this doc IS the adoption
/// — see community_adoption_listing_page.dart's doc comment. There's no
/// separate "active listing awaiting an adopter" state: the only person
/// who can ever create one is the specific community member who's
/// physically at the animal's last known location (gated in
/// community_adoption_track_page.dart before this screen is even
/// reachable), and doing so immediately finalizes them as the adopter.
class CommunityAdoption {
  final String id;
  final String? sourceCaseId; // the rescue `cases/{id}` this came from
  // Which entry in the source case's `animals[]` array this adoption
  // claims (0 for a legacy single-animal case, or the first/only animal
  // in a case with no `animals` array at all). Lets a multi-animal case
  // be adopted out one animal at a time, by different people, without two
  // adopters ever both claiming the same one — see
  // CommunityAdoptionRepository.claimedAnimalIndexes.
  final int animalIndex;
  final List<String> photoUrls; // carried over from the source case
  final String name;
  final String species; // 'Dog' | 'Cat'
  final String? breed;
  final String? size; // 'Small' | 'Medium' | 'Large'
  final String? sex; // 'Male' | 'Female' | 'Unknown'
  final String? description;
  final String rescuedBy; // original reporter's name, autofilled — not an org
  final String? address;
  final double? lat;
  final double? lng;

  // The adopter — the person submitting this doc, always themselves.
  final String? adopterId;
  final String? adopterName;
  final String? adopterContact;
  // True once they've checked the post-adoption participation agreement —
  // required before submission is allowed (see
  // community_adoption_listing_page.dart's validation).
  final bool agreementAccepted;

  final DateTime? createdAt;
  final DateTime? adoptedAt;
  final String status; // 'adopted' — reserved for future states (e.g. a
  // later "returned" flow) without needing a schema change now.

  const CommunityAdoption({
    required this.id,
    this.sourceCaseId,
    this.animalIndex = 0,
    this.photoUrls = const [],
    required this.name,
    required this.species,
    this.breed,
    this.size,
    this.sex,
    this.description,
    required this.rescuedBy,
    this.address,
    this.lat,
    this.lng,
    this.adopterId,
    this.adopterName,
    this.adopterContact,
    this.agreementAccepted = false,
    this.createdAt,
    this.adoptedAt,
    this.status = 'adopted',
  });

  factory CommunityAdoption.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final createdTs = data['createdAt'];
    final adoptedTs = data['adoptedAt'];
    return CommunityAdoption(
      id: doc.id,
      sourceCaseId: data['sourceCaseId'] as String?,
      animalIndex: (data['animalIndex'] as num?)?.toInt() ?? 0,
      photoUrls: List<String>.from(data['photoUrls'] ?? const []),
      name: data['name'] as String? ?? 'Unnamed',
      species: data['species'] as String? ?? '',
      breed: data['breed'] as String?,
      size: data['size'] as String?,
      sex: data['sex'] as String?,
      description: data['description'] as String?,
      rescuedBy: data['rescuedBy'] as String? ?? '-',
      address: data['address'] as String?,
      lat: (data['lat'] as num?)?.toDouble(),
      lng: (data['lng'] as num?)?.toDouble(),
      adopterId: data['adopterId'] as String?,
      adopterName: data['adopterName'] as String?,
      adopterContact: data['adopterContact'] as String?,
      agreementAccepted: data['agreementAccepted'] as bool? ?? false,
      createdAt: createdTs is Timestamp ? createdTs.toDate() : null,
      adoptedAt: adoptedTs is Timestamp ? adoptedTs.toDate() : null,
      status: data['status'] as String? ?? 'adopted',
    );
  }

  Map<String, dynamic> toCreateMap() => {
    if (sourceCaseId != null) 'sourceCaseId': sourceCaseId,
    'animalIndex': animalIndex,
    'photoUrls': photoUrls,
    'name': name,
    'species': species,
    'breed': breed,
    'size': size,
    'sex': sex,
    'description': description,
    'rescuedBy': rescuedBy,
    'address': address,
    'lat': lat,
    'lng': lng,
    'adopterId': adopterId,
    'adopterName': adopterName,
    'adopterContact': adopterContact,
    'agreementAccepted': agreementAccepted,
    'status': status,
    'createdAt': FieldValue.serverTimestamp(),
    'adoptedAt': FieldValue.serverTimestamp(),
  };
}