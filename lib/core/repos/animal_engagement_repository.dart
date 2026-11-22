import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Adoption listing engagement for analytics (Reports by area → Adoptions,
/// promotion funnel): per animal, per Manila day, how many people opened
/// its adoption profile (`views`) and saved it as a favorite (`saves`).
///
/// `animals/{animalId}/engagement/{yyyy-MM-dd}` = {organizationId, day,
/// views, saves}. firestore.rules lets a signed-in user add exactly 1 to
/// one counter per write, and only staff of the animal's organization read
/// them. A person is counted at most once per animal per day for each
/// counter, and the organization's own staff are not counted, so these are
/// unique daily viewers / savers, not page loads.
class AnimalEngagementRepository {
  AnimalEngagementRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  /// Counted this app session (backed by SharedPreferences across restarts).
  static final Set<String> _counted = {};
  static String? _myOrgId;
  static String? _myOrgUid;

  static String dayKey(DateTime now) {
    // Manila has no daylight saving time.
    final m = now.toUtc().add(const Duration(hours: 8));
    return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
  }

  Future<void> recordView({required String animalId, required String organizationId}) =>
      _record(animalId: animalId, organizationId: organizationId, field: 'views');

  Future<void> recordSave({required String animalId, required String organizationId}) =>
      _record(animalId: animalId, organizationId: organizationId, field: 'saves');

  Future<void> _record({required String animalId, required String organizationId, required String field}) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || animalId.isEmpty || organizationId.isEmpty) return;
    final day = dayKey(DateTime.now());
    final key = 'engagement:$uid:$animalId:$field:$day';
    if (_counted.contains(key)) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(key) == true) {
        _counted.add(key);
        return;
      }
      if (await _isStaffOf(uid, organizationId)) return;
      _counted.add(key);
      await _db.collection('animals').doc(animalId).collection('engagement').doc(day).set({
        'organizationId': organizationId,
        'day': day,
        field: FieldValue.increment(1),
      }, SetOptions(merge: true));
      await prefs.setBool(key, true);
    } catch (e) {
      // Analytics only: never block the adoption profile.
      debugPrint('[AnimalEngagement] not recorded: $e');
    }
  }

  Future<bool> _isStaffOf(String uid, String organizationId) async {
    if (_myOrgUid != uid) {
      final me = await _db.collection('users').doc(uid).get();
      _myOrgId = me.data()?['organizationId'] as String?;
      _myOrgUid = uid;
    }
    return _myOrgId == organizationId;
  }
}
