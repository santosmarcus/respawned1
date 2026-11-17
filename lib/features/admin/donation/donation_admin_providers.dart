import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/utils/org_list_scope.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/repos/general_expense_repository.dart';
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

/// Listings tied to one animal (sponsorships and animal/medical campaigns),
/// newest first. Backs "View Donations" on the admin animal profile.
final animalCampaignsProvider = StreamProvider.autoDispose.family<List<DonationListing>, String>((ref, animalId) {
  return _db.collection('campaigns').where('animalId', isEqualTo: animalId).snapshots().map((snap) {
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

// Donor records are readable by the campaign organization's staff only
// (firestore.rules), so staff queries filter on it; see OrgListScope.
final recentDonationsProvider = StreamProvider.autoDispose<List<DonationHistoryRecord>>((ref) {
  return OrgListScope.watch(
    _db.collection('donations').orderBy('createdAt', descending: true).limit(10),
    empty: const <DonationHistoryRecord>[],
    money: true,
    (s) => s.docs.map(DonationHistoryRecord.fromFirestore).toList(),
  );
});

/// All donation records (monetary, sponsorship, in-kind), newest first.
final allDonationsProvider = StreamProvider.autoDispose<List<DonationHistoryRecord>>((ref) {
  return OrgListScope.watch(
    _db.collection('donations').orderBy('createdAt', descending: true).limit(500),
    empty: const <DonationHistoryRecord>[],
    money: true,
    (s) => s.docs.map(DonationHistoryRecord.fromFirestore).toList(),
  );
});

final campaignDonationsProvider = StreamProvider.autoDispose.family<List<DonationHistoryRecord>, String>((ref, id) {
  return OrgListScope.watch(_db.collection('donations').where('campaignId', isEqualTo: id),
      empty: const <DonationHistoryRecord>[], money: true, (s) {
    final list = s.docs.map(DonationHistoryRecord.fromFirestore).toList();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    list.sort((a, b) => (b.when ?? epoch).compareTo(a.when ?? epoch));
    return list;
  });
});

/// The signed-in staff member's organization's listings (platform staff:
/// every organization's), for the analytics funds breakdown.
final orgCampaignsProvider = StreamProvider.autoDispose<List<DonationListing>>((ref) {
  return OrgListScope.watch(_db.collection('campaigns'), empty: const <DonationListing>[], (snap) {
    final list = <DonationListing>[];
    for (final doc in snap.docs) {
      try {
        list.add(DonationListing.fromFirestore(doc));
      } catch (_) {
        // A malformed legacy doc must not hide every other listing.
      }
    }
    return list;
  });
});

/// Spending recorded against the organization's campaigns, across all of
/// them (allocations carry the campaign's organizationId). Voided entries
/// are left out. Each entry is paired with its campaign id.
final orgAllocationsProvider = StreamProvider.autoDispose<List<({String campaignId, AllocationEntry entry})>>((ref) {
  return OrgListScope.watch(
    _db.collectionGroup('allocations'),
    empty: const <({String campaignId, AllocationEntry entry})>[],
    (snap) => [
      for (final d in snap.docs)
        if (d.data()['status'] != 'voided' && d.reference.parent.parent?.parent.id == 'campaigns')
          (campaignId: d.reference.parent.parent!.id, entry: AllocationEntry.fromFirestore(d)),
    ],
  );
});

final campaignAllocationsProvider = StreamProvider.autoDispose.family<List<AllocationEntry>, String>((ref, id) {
  return _db.collection('campaigns').doc(id).collection('allocations').snapshots().map((s) {
    // Voided spending (its bill was removed) is kept for history only.
    final list = s.docs.where((d) => d.data()['status'] != 'voided').map(AllocationEntry.fromFirestore).toList();
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

/// PayMongo attempts, any status, for the signed-in staff member's
/// organization. firestore.rules lets only the people who manage an
/// organization's money read its attempts (by `organizationId`); an account
/// with no organization sees none.
final paymentAttemptsProvider = StreamProvider.autoDispose<List<PaymentAttempt>>((ref) async* {
  final orgId = await ref.watch(currentOrganizationIdProvider.future);
  if (orgId == null || orgId.isEmpty) {
    yield const [];
    return;
  }
  yield* _db
      .collection('donationPayments')
      .where('organizationId', isEqualTo: orgId)
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

/// One organization's general (non-case) expenses, newest first.
final generalExpensesProvider = StreamProvider.autoDispose.family<List<Expense>, String>((ref, orgId) {
  return GeneralExpenseRepository().watch(orgId);
});

/// The signed-in staff member's organization's general expenses; empty when
/// the account has no organization (platform staff). Only watched by
/// finance-gated widgets, since firestore.rules limits orgExpenses to
/// financial administrators.
final myGeneralExpensesProvider = StreamProvider.autoDispose<List<Expense>>((ref) async* {
  final orgId = await ref.watch(currentOrganizationIdProvider.future);
  if (orgId == null || orgId.isEmpty) {
    yield const [];
    return;
  }
  yield* GeneralExpenseRepository().watch(orgId);
});

/// Record, allocate, refund and approve money; payments to verify; general
/// expenses and staff pay (the financeManage permission; Admins have it).
/// UI only: functions/campaigns.js and firestore.rules decide.
final canManageFinancesProvider = StreamProvider.autoDispose<bool>((ref) {
  return watchMyCapabilities(ref, (c) => c.canManageFinances);
});

/// See donor records, fund transfers and donation reports (financeView or
/// financeManage).
final canViewFinancesProvider = StreamProvider.autoDispose<bool>((ref) {
  return watchMyCapabilities(ref, (c) => c.canViewFinances);
});

/// Create and edit fundraising listings (the campaigns permission).
final canRunCampaignsProvider = StreamProvider.autoDispose<bool>((ref) {
  return watchMyCapabilities(ref, (c) => c.canRunCampaigns);
});
