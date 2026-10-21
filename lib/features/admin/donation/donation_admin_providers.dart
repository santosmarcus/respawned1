import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/repos/animal_record_repository.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';
import 'package:respawnd1/features/donation/models.dart';

final _db = FirebaseFirestore.instance;

DateTime _newestFirstKey(DonationListing l) => l.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

/// Every listing, newest first. Sorted client-side so legacy documents
/// without `createdAt` are not dropped by an orderBy.
final adminCampaignsProvider = StreamProvider.autoDispose<List<DonationListing>>((ref) {
  return _db.collection('campaigns').snapshots().map((snap) {
    final list = <DonationListing>[];
    for (final doc in snap.docs) {
      try {
        list.add(DonationListing.fromFirestore(doc));
      } catch (_) {
        // A malformed legacy doc must not hide every other listing.
      }
    }
    list.sort((a, b) => _newestFirstKey(b).compareTo(_newestFirstKey(a)));
    return list;
  });
});

final campaignProvider = StreamProvider.autoDispose.family<DonationListing?, String>((ref, id) {
  return _db.collection('campaigns').doc(id).snapshots().map((d) => d.exists ? DonationListing.fromFirestore(d) : null);
});

/// Campaigns whose deadline passed below goal and still need an admin decision.
final campaignsNeedingDecisionProvider = StreamProvider.autoDispose<List<DonationListing>>((ref) {
  return _db
      .collection('campaigns')
      .where('needsExtensionDecision', isEqualTo: true)
      .snapshots()
      .map((s) => s.docs.map(DonationListing.fromFirestore).toList());
});

final recentDonationsProvider = StreamProvider.autoDispose<List<DonationHistoryRecord>>((ref) {
  return _db
      .collection('donations')
      .orderBy('createdAt', descending: true)
      .limit(10)
      .snapshots()
      .map((s) => s.docs.map(DonationHistoryRecord.fromFirestore).toList());
});

/// All donation records (monetary, sponsorship, in-kind), newest first.
final allDonationsProvider = StreamProvider.autoDispose<List<DonationHistoryRecord>>((ref) {
  return _db
      .collection('donations')
      .orderBy('createdAt', descending: true)
      .limit(500)
      .snapshots()
      .map((s) => s.docs.map(DonationHistoryRecord.fromFirestore).toList());
});

final campaignDonationsProvider = StreamProvider.autoDispose.family<List<DonationHistoryRecord>, String>((ref, id) {
  return _db.collection('donations').where('campaignId', isEqualTo: id).snapshots().map((s) {
    final list = s.docs.map(DonationHistoryRecord.fromFirestore).toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => (b.when ?? epoch).compareTo(a.when ?? epoch));
    return list;
  });
});

final campaignAllocationsProvider = StreamProvider.autoDispose.family<List<AllocationEntry>, String>((ref, id) {
  return _db.collection('campaigns').doc(id).collection('allocations').snapshots().map((s) {
    final list = s.docs.map(AllocationEntry.fromFirestore).toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch));
    return list;
  });
});

final campaignHistoryProvider = StreamProvider.autoDispose.family<List<CampaignHistoryEntry>, String>((ref, id) {
  return _db
      .collection('campaigns')
      .doc(id)
      .collection('history')
      .orderBy('at', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(CampaignHistoryEntry.fromFirestore).toList());
});

/// PayMongo attempts, any status
final paymentAttemptsProvider = StreamProvider.autoDispose<List<PaymentAttempt>>((ref) {
  return _db
      .collection('donationPayments')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(PaymentAttempt.fromFirestore).toList());
});

/// Animals that can be linked to a listing (not archived, not deceased).
final linkableAnimalsProvider = StreamProvider.autoDispose<List<AnimalRecord>>((ref) {
  return AnimalRecordRepository().streamAllAnimalRecords().map((all) {
    final list = all.where((a) => !a.archived && a.status != 'deceased' && a.name.trim().isNotEmpty).toList();
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });
});

/// UI-only hint mirroring loadActor() in functions/campaigns.js: financial
/// actions are shown to users.role == 'admin' or org Admin members. The
/// backend makes the real decision.
final canManageFinancesProvider = StreamProvider.autoDispose<bool>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(false);
  final membership = ref.watch(currentOrgMembershipProvider).asData?.value;
  return _db.collection('users').doc(uid).snapshots().map((doc) {
    final role = doc.data()?['role'] as String?;
    return role == 'admin' || membership?.role.name == 'admin';
  });
});
