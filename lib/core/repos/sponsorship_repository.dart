import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:respawnd1/core/models/donation/sponsorship.dart';

/// The signed-in user's sponsorships, read from where they are actually
/// recorded: `donations` docs with `type: 'sponsorship'`, written by the
/// backend when a sponsorship payment is confirmed (functions/paymongo.js).
/// The animal comes from the sponsorship listing (`campaigns/{id}.animalId`).
class SponsorshipRepository {
  SponsorshipRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Only THIS user's currently-active sponsorships, one per animal (a
  /// renewal creates a new record for the same listing; the newest period
  /// wins and "since" goes back to the first one still running). Cancelled
  /// and ended sponsorships are left out.
  Stream<List<Sponsorship>> streamActiveSponsorshipsForUser(String uid) {
    return _db
        .collection('donations')
        .where('userId', isEqualTo: uid)
        .snapshots()
        .asyncMap((snap) => _toActiveSponsorships(uid, snap.docs));
  }

  Future<List<Sponsorship>> _toActiveSponsorships(
      String uid, List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) async {
    final now = DateTime.now();
    DateTime? ts(dynamic v) => v is Timestamp ? v.toDate() : null;

    // Group this user's sponsorship records by listing.
    final byCampaign = <String, List<Map<String, dynamic>>>{};
    final idOf = <Map<String, dynamic>, String>{};
    for (final doc in docs) {
      final d = doc.data();
      if (d['type'] != 'sponsorship') continue;
      final campaignId = d['campaignId'] as String?;
      if (campaignId == null || campaignId.isEmpty) continue;
      idOf[d] = doc.id;
      byCampaign.putIfAbsent(campaignId, () => []).add(d);
    }

    final result = <Sponsorship>[];
    for (final entry in byCampaign.entries) {
      final active = entry.value.where((d) {
        final until = ts(d['nextChargeDate']);
        return d['sponsorshipStatus'] == 'active' && (until == null || until.isAfter(now));
      }).toList();
      if (active.isEmpty) continue;
      active.sort((a, b) => (ts(b['nextChargeDate']) ?? now).compareTo(ts(a['nextChargeDate']) ?? now));
      final current = active.first;

      // "Since": the earliest record of this continuous sponsorship.
      DateTime? since;
      for (final d in entry.value) {
        if (d['sponsorshipStatus'] != 'active' && d['sponsorshipStatus'] != 'renewed') continue;
        final t = ts(d['timestamp']) ?? ts(d['createdAt']);
        if (t != null && (since == null || t.isBefore(since))) since = t;
      }

      Map<String, dynamic>? campaign;
      try {
        campaign = (await _db.collection('campaigns').doc(entry.key).get()).data();
      } catch (_) {
        // Listing unreadable: still show the sponsorship with what we have.
      }

      result.add(Sponsorship(
        id: idOf[current]!,
        userId: uid,
        organizationId: campaign?['organizationId'] as String? ?? '',
        organizationName: current['organizer'] as String? ?? campaign?['organizer'] as String? ?? '',
        animalRecordId: campaign?['animalId'] as String? ?? '',
        animalName: campaign?['animalName'] as String? ?? current['campaignName'] as String? ?? '',
        status: SponsorshipStatus.active,
        startDate: since,
        nextContributionDate: ts(current['nextChargeDate']),
        createdAt: ts(current['createdAt']),
      ));
    }
    result.sort((a, b) => a.animalName.toLowerCase().compareTo(b.animalName.toLowerCase()));
    return result;
  }
}