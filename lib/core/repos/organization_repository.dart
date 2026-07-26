import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';

/// Where an organization currently is in the manual verification pipeline.
/// Mirrors the shape of `users/{uid}.transporterVerificationStatus`
/// (pet-transporter signup) but lives on the `organizations/{orgId}` doc
/// instead, since an organization — unlike a transporter — is a shared
/// entity multiple staff accounts can belong to.
enum OrgVerificationStatus {
  draft,
  pending,
  approved,
  rejected,
  requiresChanges;

  static OrgVerificationStatus fromName(String? value) =>
      OrgVerificationStatus.values.firstWhere((v) => v.name == value, orElse: () => OrgVerificationStatus.draft);
}

/// Lowercases, trims, and collapses whitespace/punctuation differences so
/// "PAWS Manila", "paws manila", and "PAWS  Manila" normalize identically —
/// used for both the duplicate-registration check and service-area/species
/// value storage. Deliberately not a full fuzzy-match (typos can still slip
/// through) — see [OrganizationRepository.findPossibleDuplicates]'s own doc
/// comment on why that's flagged as a known, reported limitation rather than
/// solved here.
String normalizeForMatch(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(RegExp(r'\s+'), ' ').trim();

/// Digits only — so "+63 917 123 4567", "0917-123-4567", and "09171234567"
/// all normalize identically for the duplicate-contact-number check.
String normalizePhoneForMatch(String value) => value.replaceAll(RegExp(r'\D'), '');

class OrgDuplicateMatch {
  final String organizationId;
  final String name;
  final bool exact;
  const OrgDuplicateMatch({required this.organizationId, required this.name, required this.exact});
}

/// One city/service-area entry — {name, normalizedName} per the spec's own
/// suggested shape, so display casing is preserved while de-duplication
/// still compares normalized values. [placeId]/[administrativeArea]/
/// [countryCode] are additive (nullable, default empty) so legacy entries
/// saved before location-service validation existed (free-text, no place
/// data) still parse and render — they just can't be deduplicated by
/// [placeId] against a newly-added area the way two validated entries can.
class ServiceArea {
  final String name;
  final String normalizedName;
  final String? placeId;
  final String? administrativeArea;
  final String? countryCode;
  const ServiceArea({
    required this.name,
    required this.normalizedName,
    this.placeId,
    this.administrativeArea,
    this.countryCode,
  });

  factory ServiceArea.fromMap(Map<String, dynamic> map) => ServiceArea(
        name: map['name'] as String? ?? '',
        normalizedName: map['normalizedName'] as String? ?? '',
        placeId: map['placeId'] as String?,
        administrativeArea: map['administrativeArea'] as String?,
        countryCode: map['countryCode'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'normalizedName': normalizedName,
        if (placeId != null) 'placeId': placeId,
        if (administrativeArea != null) 'administrativeArea': administrativeArea,
        if (countryCode != null) 'countryCode': countryCode,
      };
}

/// Everything an "Organization" account needs beyond the existing public
/// `Organization` model (lib/features/organization/organization_model.dart)
/// — reuses that same top-level `organizations/{orgId}` collection and its
/// existing fields (name/location/phone/email/facebookUrl/description/
/// avatarUrl, plus the shelter*/acceptedSpecies fields already written
/// elsewhere in this codebase) rather than a second organization
/// collection. Every field this class adds is additive.
class OrganizationRepository {
  OrganizationRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _organizations => _db.collection('organizations');
  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  /// Returns the organization the given uid already owns/belongs to, if
  /// any — checked via `users/{uid}.organizationId`, the same pointer field
  /// `OrgMembershipService` already uses. Used at the top of every signup
  /// step to make the whole flow idempotent: reopening "About Your
  /// Organization" (back navigation, app restart, retry) resumes the same
  /// draft doc instead of ever creating a second one.
  Future<DocumentSnapshot<Map<String, dynamic>>?> currentOrganizationFor(String uid) async {
    final userDoc = await _users.doc(uid).get();
    final orgId = userDoc.data()?['organizationId'] as String?;
    if (orgId == null || orgId.isEmpty) return null;
    final orgDoc = await _organizations.doc(orgId).get();
    return orgDoc.exists ? orgDoc : null;
  }

  /// Exact-normalized-name/address/phone matches (blocks submission) vs.
  /// possible matches (name-only substring, shown as a warning) — never a
  /// fuzzy/typo-tolerant match, since that needs real string-distance
  /// scoring this client-side pass doesn't attempt. This check runs against
  /// whatever the client can read, which today (see this app's existing
  /// wide-open Firestore rules) is every organization document — it is NOT
  /// a secure server-side check and can be bypassed by a modified client;
  /// the uploaded verification documents remain the real basis for
  /// approval, same as the spec requires.
  Future<List<OrgDuplicateMatch>> findPossibleDuplicates({
    required String name,
    required String address,
    required String contactNumber,
  }) async {
    final normName = normalizeForMatch(name);
    final normAddress = normalizeForMatch(address);
    final normPhone = normalizePhoneForMatch(contactNumber);

    // Bounded window, filtered client-side — same tradeoff
    // OrganizationDirectoryRepository.search already makes at this app's
    // scale (dozens-to-low-hundreds of orgs, not thousands).
    final snap = await _organizations.limit(300).get();
    final matches = <OrgDuplicateMatch>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final docName = normalizeForMatch(data['name'] as String? ?? '');
      final docAddress = normalizeForMatch((data['location'] as String?) ?? (data['shelterAddress'] as String?) ?? '');
      final docPhone = normalizePhoneForMatch(data['phone'] as String? ?? data['contactNumber'] as String? ?? '');
      if (docName.isEmpty) continue;

      final exact = docName == normName && (docAddress == normAddress || (docPhone.isNotEmpty && docPhone == normPhone));
      final possible = !exact && (docName == normName || (normAddress.isNotEmpty && docAddress == normAddress));
      if (exact || possible) {
        matches.add(OrgDuplicateMatch(organizationId: doc.id, name: data['name'] as String? ?? '', exact: exact));
      }
    }
    return matches;
  }

  /// Creates the organization draft on first submission of "About Your
  /// Organization", or updates the existing one if this uid already has a
  /// draft (see [currentOrganizationFor]) — never creates a second
  /// document for the same account. Also grants the submitting account
  /// Admin org-membership via the existing [OrgMembershipService] (never a
  /// second membership model) and sets `users/{uid}.role = 'organization'`
  /// so AuthWrapper's routing takes over from here.
  Future<String> createOrUpdateDraft({
    required String uid,
    required String name,
    required String contactNumber,
    required String address,
  }) async {
    final normalizedName = normalizeForMatch(name);
    final normalizedAddress = normalizeForMatch(address);
    final normalizedPhone = normalizePhoneForMatch(contactNumber);

    final existing = await currentOrganizationFor(uid);
    final orgRef = existing?.reference ?? _organizations.doc();

    await orgRef.set({
      'name': name,
      'normalizedName': normalizedName,
      'contactNumber': contactNumber,
      'phone': contactNumber, // mirrors the existing public Organization model's field name
      'location': address,
      'normalizedAddress': normalizedAddress,
      'normalizedPhone': normalizedPhone,
      'ownerId': uid,
      if (existing == null) 'verificationStatus': OrgVerificationStatus.draft.name,
      if (existing == null) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _users.doc(uid).set({'role': 'organization'}, SetOptions(merge: true));
    await OrgMembershipService(firestore: _db).setMember(organizationId: orgRef.id, uid: uid, role: OrgRole.admin);
    // setMember only writes {role, updatedAt} — the owner's email is added
    // here (display purposes on the Staff Members list) rather than
    // widening that shared method's signature for every other caller.
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email != null && email.isNotEmpty) {
      await _organizations.doc(orgRef.id).collection('members').doc(uid).set(
        {'email': email, 'status': 'active', 'joinedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }

    return orgRef.id;
  }

  /// Appends newly-uploaded URLs onto whichever verification document group
  /// they belong to (never overwriting previously-uploaded files in the
  /// other groups) and, once all three groups have at least one file,
  /// leaves the actual `pending` transition to [submitVerification] — this
  /// method alone never changes verificationStatus, so partial uploads
  /// during a still-in-progress session never look "submitted".
  Future<void> addVerificationFiles({
    required String organizationId,
    required String group, // 'registration' | 'permits' | 'shelterPhotos'
    required List<String> urls,
  }) async {
    await _organizations.doc(organizationId).set({
      'verification': {group: FieldValue.arrayUnion(urls)},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeVerificationFile({
    required String organizationId,
    required String group,
    required String url,
  }) async {
    await _organizations.doc(organizationId).set({
      'verification': {group: FieldValue.arrayRemove([url])},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> submitVerification(String organizationId) async {
    await _organizations.doc(organizationId).set({
      'verificationStatus': OrgVerificationStatus.pending.name,
      'verificationSubmittedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Temporary standalone-admin bootstrap (spec §7) — lets an existing admin
  /// account with no `organizationId` and no pending invitation create a
  /// minimal organization directly from Organization Profile, until full
  /// Organization signup/verification is the only path. Deliberately skips
  /// [createOrUpdateDraft]'s verification pipeline entirely (no
  /// `verificationStatus`, and — unlike that method — never touches
  /// `users/{uid}.role`, so a standalone admin stays routed into the normal
  /// admin shell rather than being redirected into the separate
  /// organization-role flow). Reuses the exact same `organizations/{orgId}`
  /// collection and [OrgMembershipService] membership model as every other
  /// organization entry point — this is not a second organization system.
  ///
  /// Idempotent against repeated taps: re-checks [currentOrganizationFor]
  /// inside the same transaction that creates the document, so two rapid
  /// calls for the same uid can never both create a document — the second
  /// one always resolves to the first one's id instead.
  Future<String> createBootstrapOrganization({
    required String uid,
    required String name,
    required String location,
    String? description,
    String? email,
    String? phone,
    String? facebookUrl,
    String? website,
    List<ServiceArea> serviceAreas = const [],
    required List<String> acceptedSpecies,
    String? avatarUrl,
  }) async {
    final existing = await currentOrganizationFor(uid);
    if (existing != null) return existing.id;

    final orgRef = _organizations.doc();
    try {
      await _db.runTransaction((tx) async {
        final userSnap = await tx.get(_users.doc(uid));
        final alreadyLinked = userSnap.data()?['organizationId'] as String?;
        if (alreadyLinked != null && alreadyLinked.isNotEmpty) {
          throw StateError('already-linked');
        }
        tx.set(orgRef, {
          'name': name,
          'normalizedName': normalizeForMatch(name),
          'description': description,
          'location': location,
          'normalizedAddress': normalizeForMatch(location),
          if (email != null && email.isNotEmpty) 'email': email,
          if (phone != null && phone.isNotEmpty) ...{
            'phone': phone,
            'contactNumber': phone,
            'normalizedPhone': normalizePhoneForMatch(phone),
          },
          if (facebookUrl != null && facebookUrl.isNotEmpty) 'facebookUrl': facebookUrl,
          if (website != null && website.isNotEmpty) 'website': website,
          if (avatarUrl != null && avatarUrl.isNotEmpty) 'avatarUrl': avatarUrl,
          'serviceAreas': serviceAreas.map((s) => s.toMap()).toList(),
          'acceptedSpecies': acceptedSpecies,
          'ownerId': uid,
          // Marks this org as created via the temporary bootstrap path
          // rather than the full signup/verification pipeline — purely
          // informational (e.g. for a future admin audit), never read by
          // any gating logic today.
          'bootstrapped': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(_users.doc(uid), {'organizationId': orgRef.id}, SetOptions(merge: true));
        tx.set(orgRef.collection('members').doc(uid), {
          'role': OrgRole.admin.name,
          'status': 'active',
          'joinedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });
    } on StateError {
      // Lost a race against a second in-flight tap (or the account was
      // linked by some other flow in the meantime) — resolve to whichever
      // organization actually won rather than erroring the UI.
      final afterRace = await currentOrganizationFor(uid);
      if (afterRace != null) return afterRace.id;
      rethrow;
    }
    return orgRef.id;
  }

  /// Profile-management fields only — deliberately never touches
  /// `verification`/`verificationStatus`/`verification*At` so editing the
  /// public profile can never silently invalidate an existing approval.
  /// Changing legal-identity fields (name/location) that should require
  /// re-verification is a reported policy limitation, not enforced here —
  /// see this session's final report.
  Future<void> updateProfile({
    required String organizationId,
    String? name,
    String? description,
    String? avatarUrl,
    String? location,
    String? email,
    String? phone,
    String? facebookUrl,
    String? website,
    List<ServiceArea>? serviceAreas,
    List<String>? acceptedSpecies,
  }) async {
    final update = <String, dynamic>{'updatedAt': FieldValue.serverTimestamp()};
    if (name != null) {
      update['name'] = name;
      update['normalizedName'] = normalizeForMatch(name);
    }
    if (description != null) update['description'] = description;
    if (avatarUrl != null) update['avatarUrl'] = avatarUrl;
    if (location != null) {
      update['location'] = location;
      update['normalizedAddress'] = normalizeForMatch(location);
    }
    if (email != null) update['email'] = email;
    if (phone != null) {
      update['phone'] = phone;
      update['contactNumber'] = phone;
      update['normalizedPhone'] = normalizePhoneForMatch(phone);
    }
    if (facebookUrl != null) update['facebookUrl'] = facebookUrl;
    if (website != null) update['website'] = website;
    if (serviceAreas != null) update['serviceAreas'] = serviceAreas.map((s) => s.toMap()).toList();
    if (acceptedSpecies != null) update['acceptedSpecies'] = acceptedSpecies;

    await _organizations.doc(organizationId).set(update, SetOptions(merge: true));
  }
}
