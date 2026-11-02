import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';

/// Thrown when a sign-up can't go through (cancelled, full, already joined).
class EventRegistrationException implements Exception {
  final String message;
  const EventRegistrationException(this.message);
  @override
  String toString() => message;
}

/// Organization-managed volunteer events (`events/{id}`) and their sign-ups
/// (`events/{id}/registrations/{uid}`). Each sign-up is mirrored to
/// `users/{uid}/volunteerRegistrations/{eventId}` so the user's own e-ticket
/// and joined list read from their own document tree.
class VolunteerEventRepository {
  VolunteerEventRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _events => _db.collection('events');
  DocumentReference<Map<String, dynamic>> _eventDoc(String id) => _events.doc(id);
  CollectionReference<Map<String, dynamic>> _registrationsOf(String eventId) =>
      _eventDoc(eventId).collection('registrations');
  CollectionReference<Map<String, dynamic>> _myRegistrations(String uid) =>
      _db.collection('users').doc(uid).collection('volunteerRegistrations');
  CollectionReference<Map<String, dynamic>> _myFavorites(String uid) =>
      _db.collection('users').doc(uid).collection('volunteerFavorites');

  static List<VolunteerEvent> _sorted(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(VolunteerEvent.fromFirestore).toList()..sort((a, b) => a.startAt.compareTo(b.startAt));

  // ---- Reads -----------------------------------------------------------------

  /// Every organization's events, soonest first, including cancelled and
  /// past ones — the user list filters them, keeping cancelled events
  /// visible to people who joined them.
  Stream<List<VolunteerEvent>> streamAllEvents() => _events.snapshots().map(_sorted);

  /// Every event an organization owns, including cancelled and past ones.
  Stream<List<VolunteerEvent>> streamOrganizationEvents(String organizationId) => _events
      .where('organizationId', isEqualTo: organizationId)
      .snapshots()
      .map(_sorted);

  Stream<VolunteerEvent?> streamEvent(String eventId) =>
      _eventDoc(eventId).snapshots().map((d) => d.exists ? VolunteerEvent.fromFirestore(d) : null);

  /// Organization staff only (enforced by firestore.rules).
  Stream<List<EventRegistration>> streamRegistrations(String eventId) =>
      _registrationsOf(eventId).snapshots().map((snap) {
        final list = snap.docs.map(EventRegistration.fromFirestore).toList();
        list.sort((a, b) => (a.registeredAt ?? DateTime(0)).compareTo(b.registeredAt ?? DateTime(0)));
        return list;
      });

  /// The signed-in user's joined and favorited event ids.
  Future<({Set<String> joined, Set<String> favorites})> loadMyEventIds() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return (joined: <String>{}, favorites: <String>{});
    final results = await Future.wait([_myRegistrations(uid).get(), _myFavorites(uid).get()]);
    return (
      joined: results[0].docs.map((d) => d.id).toSet(),
      favorites: results[1].docs.map((d) => d.id).toSet(),
    );
  }

  Future<Map<String, dynamic>?> getMyRegistration(String eventId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _myRegistrations(uid).doc(eventId).get();
    return doc.data();
  }

  // ---- Organization management ----------------------------------------------

  Future<String> createEvent({required String organizationId, required VolunteerEvent draft}) async {
    final ref = _events.doc();
    await ref.set({
      ...draft.toEditableMap(),
      'organizationId': organizationId,
      'status': VolunteerEvent.statusPublished,
      'goingCount': 0,
      'createdBy': _auth.currentUser?.uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Future<void> updateEvent({required String eventId, required VolunteerEvent draft}) {
    return _eventDoc(eventId).update({
      ...draft.toEditableMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Kept, not deleted, so sign-ups and e-tickets still resolve.
  Future<void> cancelEvent(String eventId, {String? reason}) {
    return _eventDoc(eventId).update({
      'status': VolunteerEvent.statusCancelled,
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelledBy': _auth.currentUser?.uid,
      if (reason != null && reason.isNotEmpty) 'cancellationReason': reason,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ---- Sign-up ---------------------------------------------------------------

  /// Creates the sign-up and bumps [VolunteerEvent.goingCount] in one
  /// transaction, so the count can't drift and capacity can't be overrun.
  Future<void> register({
    required VolunteerEvent event,
    required String participantName,
    required String participantEmail,
    required String participantMobileNumber,
    required String participantNumber,
  }) async {
    final uid = _auth.currentUser!.uid;
    final eventRef = _eventDoc(event.id);
    final regRef = _registrationsOf(event.id).doc(uid);

    await _db.runTransaction((tx) async {
      final eventSnap = await tx.get(eventRef);
      if (!eventSnap.exists) throw const EventRegistrationException('This event no longer exists.');
      final live = VolunteerEvent.fromFirestore(eventSnap);
      if (live.isCancelled) throw const EventRegistrationException('This event has been cancelled.');
      if (live.isPast) throw const EventRegistrationException('This event has already ended.');
      if (live.isFull) throw const EventRegistrationException('This event is already full.');
      final regSnap = await tx.get(regRef);
      if (regSnap.exists) throw const EventRegistrationException('You have already signed up for this event.');

      final registration = {
        'uid': uid,
        'eventId': event.id,
        'participantName': participantName,
        'participantEmail': participantEmail,
        'participantMobileNumber': participantMobileNumber,
        'participantNumber': participantNumber,
        'registeredAt': FieldValue.serverTimestamp(),
      };
      tx.set(regRef, registration);
      tx.update(eventRef, {'goingCount': live.goingCount + 1});
      tx.set(_myRegistrations(uid).doc(event.id), {
        ...registration,
        'organizationId': live.organizationId,
        'title': live.title,
        'organizer': live.organizerName,
        'date': live.date,
        'time': live.time,
        'location': live.location,
      });
    });
  }

  Future<void> setFavorite(VolunteerEvent event, bool favorite) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final doc = _myFavorites(uid).doc(event.id);
    if (favorite) {
      await doc.set({
        'eventId': event.id,
        'title': event.title,
        'organizationId': event.organizationId,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.delete();
    }
  }
}
