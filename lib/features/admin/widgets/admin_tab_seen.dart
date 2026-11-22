import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "New since you last looked" numbers for the step tabs of an admin screen
/// (Rescue Reports, Adoptions).
///
/// A tab's number counts the items in it that the signed-in account hasn't
/// seen there yet. Opening a tab marks everything in it as seen, so its
/// number goes away; it comes back only when something new arrives in that
/// step (a new report, or a case or application moving into it).
///
/// Stored per account at `users/{uid}/adminTabSeen/{screen}`:
/// `{tabs: {<tab name>: [item ids]}, updatedAt}`. Each tab's list is replaced
/// with the tab's current items whenever it's opened, so items that have left
/// a tab are forgotten and the document stays the size of the queues.
/// firestore.rules already lets a user read and write their own
/// subcollections (`match /users/{uid}/{sub}/{doc=**}`), so no rules change
/// is needed.
CollectionReference<Map<String, dynamic>>? _seenCollection() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance.collection('users').doc(uid).collection('adminTabSeen');
}

/// Tab name → ids already seen in that tab, for one admin [screen]
/// (e.g. `'rescue'`, `'adoption'`).
final adminTabSeenProvider = StreamProvider.autoDispose.family<Map<String, Set<String>>, String>((ref, screen) {
  final col = _seenCollection();
  if (col == null) return Stream.value(const <String, Set<String>>{});
  return col.doc(screen).snapshots().map((snap) {
    final tabs = snap.data()?['tabs'];
    if (tabs is! Map) return const <String, Set<String>>{};
    return {
      for (final e in tabs.entries)
        if (e.value is List) '${e.key}': {for (final id in e.value as List) if (id is String) id},
    };
  });
});

/// How many of [ids] haven't been seen in [tab] yet. Null (no number shown)
/// while either list is still loading, so a number doesn't flash up and
/// then disappear. If the seen record can't be read, every item counts.
int? unseenTabCount(AsyncValue<Map<String, Set<String>>> seen, String tab, Iterable<String>? ids) {
  if (ids == null) return null;
  if (seen.hasError) return ids.length;
  final seenByTab = seen.asData?.value;
  if (seenByTab == null) return null;
  final seenIds = seenByTab[tab] ?? const <String>{};
  return ids.where((id) => !seenIds.contains(id)).length;
}

/// Records what the person has seen in a tab. Keep one per screen State;
/// it skips writes that wouldn't change anything.
class AdminTabSeenMarker {
  AdminTabSeenMarker(this.screen);

  final String screen;
  String? _lastWritten;

  /// Marks [ids] as everything seen in [tab]. [alreadySeen] is that tab's
  /// current seen set (from [adminTabSeenProvider]); nothing is written when
  /// it already matches. Safe to call from build: the write happens after
  /// the frame.
  void markSeen(String tab, Iterable<String> ids, Set<String>? alreadySeen) {
    final current = ids.toSet();
    if (alreadySeen != null && alreadySeen.length == current.length && alreadySeen.containsAll(current)) return;
    final key = '$tab|${(current.toList()..sort()).join(',')}';
    if (key == _lastWritten) return;
    _lastWritten = key;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final col = _seenCollection();
      if (col == null) return;
      col.doc(screen).set({
        'tabs': {tab: current.toList()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).catchError((Object e) {
        // Let the next build try again.
        if (_lastWritten == key) _lastWritten = null;
        debugPrint('AdminTabSeenMarker: could not save seen $screen/$tab: $e');
      });
    });
  }
}
