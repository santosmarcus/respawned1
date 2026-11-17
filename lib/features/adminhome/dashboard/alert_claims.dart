import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// Dashboard gap 7: who is handling a Priority actions item.
///
/// Alerts stay derived: a claim never hides or clears one, it only shows
/// "Ana is on it" on the row, so two admins don't both act on it (or each
/// assume the other did). The alert still clears only when its record
/// changes. Stored at `organizations/{orgId}/alertClaims/{alertKey}`;
/// staff of the organization read them, claim for themselves and release
/// their own (admins may release anyone's). A claim older than
/// [kAlertClaimTtl] is treated as lapsed, and sendDashboardDigest
/// (functions/dashboard_ops.js) deletes lapsed claims.

/// Keep equal to ALERT_CLAIM_TTL_HOURS in functions/dashboard_digest_rules.js.
const Duration kAlertClaimTtl = Duration(hours: 24);

class AlertClaim {
  final String key;
  final String byUid;
  final String byName;
  final DateTime? at;
  const AlertClaim({required this.key, required this.byUid, required this.byName, this.at});

  bool isActive(DateTime now) => at == null || now.difference(at!) < kAlertClaimTtl;
  bool get isMine => byUid == FirebaseAuth.instance.currentUser?.uid;

  static AlertClaim? fromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    if (m == null) return null;
    final uid = m['byUid'];
    if (uid is! String || uid.isEmpty) return null;
    final at = m['at'];
    return AlertClaim(
      key: d.id,
      byUid: uid,
      byName: (m['byName'] as String?) ?? 'Staff',
      at: at is Timestamp ? at.toDate() : null,
    );
  }
}

/// A Firestore-safe document id for an alert key.
String alertClaimDocId(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9:_-]'), '_');

CollectionReference<Map<String, dynamic>> _claims(String orgId) =>
    FirebaseFirestore.instance.collection('organizations').doc(orgId).collection('alertClaims');

/// Active claims of the signed-in staff member's organization, by doc id.
final alertClaimsProvider = StreamProvider.autoDispose<Map<String, AlertClaim>>((ref) async* {
  final orgId = await ref.watch(dashboardOrgIdProvider.future);
  if (orgId == null) {
    yield const {};
    return;
  }
  yield* _claims(orgId).snapshots().map((s) {
    final now = DateTime.now();
    return {
      for (final d in s.docs)
        if (AlertClaim.fromDoc(d) case final c? when c.isActive(now)) d.id: c,
    };
  });
});

Future<void> claimAlert({required String orgId, required String key, required String title}) {
  final u = FirebaseAuth.instance.currentUser;
  if (u == null) throw StateError('Sign in first.');
  final name = (u.displayName?.trim().isNotEmpty ?? false) ? u.displayName!.trim() : (u.email ?? 'Staff');
  return _claims(orgId).doc(alertClaimDocId(key)).set({
    'byUid': u.uid,
    'byName': name,
    'title': title,
    'organizationId': orgId,
    'at': FieldValue.serverTimestamp(),
  });
}

Future<void> releaseAlert({required String orgId, required String key}) =>
    _claims(orgId).doc(alertClaimDocId(key)).delete();
