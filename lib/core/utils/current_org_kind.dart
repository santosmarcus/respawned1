import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/models/organization/org_permission.dart';

/// The kind of organization the signed-in account (or [uid]) acts for:
/// [OrgKind.independent] for an independent rescuer, else [OrgKind.shelter]
/// (also when signed out, unlinked or offline). For screens that word things
/// or offer steps differently for independent rescuers; the backend enforces
/// their limits itself.
Future<OrgKind> currentOrgKind({String? uid, FirebaseFirestore? firestore}) async {
  final id = uid ?? FirebaseAuth.instance.currentUser?.uid;
  if (id == null || id.isEmpty) return OrgKind.shelter;
  try {
    final db = firestore ?? FirebaseFirestore.instance;
    final orgId = (await db.collection('users').doc(id).get()).data()?['organizationId'] as String? ?? '';
    if (orgId.isEmpty) return OrgKind.shelter;
    final org = await db.collection('organizations').doc(orgId).get();
    return OrgKind.fromName(org.data()?['kind'] as String?);
  } catch (_) {
    return OrgKind.shelter;
  }
}

Future<bool> currentOrgIsIndependent({String? uid}) async => await currentOrgKind(uid: uid) == OrgKind.independent;
