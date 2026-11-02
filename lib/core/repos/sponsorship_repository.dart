import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/donation/sponsorship.dart';

/// Reads the existing `sponsors` collection (already queried, read-only,
/// by `_SponsorsRow` in lib/features/adoption/animal_page.dart for a bare
/// count) — never a second sponsorship collection.
class SponsorshipRepository {
  SponsorshipRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _sponsors => _db.collection('sponsors');

  /// Only THIS user's currently-active sponsorships (spec: "Do not show
  /// all animals receiving sponsorship" — user- and status-scoped, never
  /// the whole collection).
  Stream<List<Sponsorship>> streamActiveSponsorshipsForUser(String uid) {
    return _sponsors
        .where('userId', isEqualTo: uid)
        .where('status', isEqualTo: SponsorshipStatus.active.name)
        .snapshots()
        .map((snap) => snap.docs.map(Sponsorship.fromFirestore).toList());
  }
}
