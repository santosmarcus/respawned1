import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Sender fields for a staff-written message on `cases/{caseId}/messages`.
///
/// Reporters see the organization's name (`senderName`), never a hardcoded
/// org. `senderId` is the staff member's uid so their own messages aren't
/// shown back to them as notifications, and `senderStaffName` keeps who on
/// the team actually wrote it.
class CaseMessageSender {
  CaseMessageSender._();

  static final Map<String, Map<String, Object?>> _cache = {};

  static Future<Map<String, Object?>> staffFields({FirebaseFirestore? firestore}) async {
    final db = firestore ?? FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;
    if (uid == null) {
      return {'senderId': 'admin', 'senderName': 'Rescue team', 'senderRole': 'organization'};
    }
    final cached = _cache[uid];
    if (cached != null) return cached;

    String? orgId;
    String? orgName;
    String staffName = user?.displayName?.trim() ?? '';
    try {
      final userData = (await db.collection('users').doc(uid).get()).data() ?? const {};
      orgId = (userData['organizationId'] as String?)?.trim();
      final first = (userData['firstName'] as String?)?.trim() ?? '';
      final last = (userData['lastName'] as String?)?.trim() ?? '';
      final full = '$first $last'.trim();
      if (full.isNotEmpty) staffName = full;
      if (orgId != null && orgId.isNotEmpty) {
        final orgData = (await db.collection('organizations').doc(orgId).get()).data();
        orgName = (orgData?['name'] as String?)?.trim();
      }
    } catch (_) {
      // Fall through to the generic label; sending the message matters more.
    }

    final fields = <String, Object?>{
      'senderId': uid,
      'senderName': (orgName == null || orgName.isEmpty) ? 'Rescue team' : orgName,
      'senderRole': 'organization',
      if (orgId != null && orgId.isNotEmpty) 'senderOrgId': orgId,
      if (staffName.isNotEmpty) 'senderStaffName': staffName,
    };
    if (orgName != null && orgName.isNotEmpty) _cache[uid] = fields;
    return fields;
  }
}
