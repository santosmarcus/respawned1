import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../donation/models.dart';

final historyProvider = NotifierProvider<HistoryNotifier, List<HistoryItem>>(HistoryNotifier.new);

class HistoryNotifier extends Notifier<List<HistoryItem>> {
  @override
  List<HistoryItem> build() {
    _loadHistory();
    return [];
  }

  Future<void> _loadHistory() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance.collection('users').doc(uid).collection('history').orderBy('timestamp', descending: true).get();
      final items = snapshot.docs.map((doc) => HistoryItem.fromFirestore(doc)).toList();
      
      // Merge with current state to preserve local additions that might not be in Firestore yet
      final Map<String, HistoryItem> merged = {for (var item in state) item.id: item};
      for (var item in items) {
        merged[item.id] = item;
      }
      state = merged.values.toList()..sort((a, b) => b.dateTime.compareTo(a.dateTime));
    } catch (e) {
      print('Error loading history: $e');
    }
  }

  void addHistoryItem(HistoryItem item) {
    state = [item, ...state];
  }

  void updateStatus(String id, InKindStatus status) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(status: status) else item,
    ];
  }

  void cancelInKindDonation(String id) {
    state = [
      for (final item in state)
        if (item.id == id && item.type == HistoryType.inKindDonation)
          item.copyWith(status: InKindStatus.cancelled)
        else
          item,
    ];
    _updateFirestoreDonation(id, {'status': 'cancelled'});
  }

  void cancelSponsorship(String id) {
    state = [
      for (final item in state)
        if (item.id == id && item.type == HistoryType.sponsorship)
          item.copyWith(sponsorshipStatus: 'cancelled')
        else
          item,
    ];
    _updateFirestoreDonation(id, {'sponsorshipStatus': 'cancelled'});
  }

  void unCancelSponsorship(String id) {
    state = [
      for (final item in state)
        if (item.id == id && item.type == HistoryType.sponsorship)
          item.copyWith(sponsorshipStatus: 'active')
        else
          item,
    ];
    _updateFirestoreDonation(id, {'sponsorshipStatus': 'active'});
  }

  void updateSponsorshipAmount(String id, double newAmount) {
    state = [
      for (final item in state)
        if (item.id == id && item.type == HistoryType.sponsorship)
          item.copyWith(nextChargeAmount: newAmount)
        else
          item,
    ];
    _updateFirestoreDonation(id, {'nextChargeAmount': newAmount});
  }

  Future<void> _updateFirestoreDonation(String id, Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Update in global donations and user history in parallel
      await Future.wait([
        FirebaseFirestore.instance.collection('donations').doc(id).update(data),
        FirebaseFirestore.instance.collection('users').doc(uid).collection('history').doc(id).update(data),
      ]);
    } catch (e) {
      print('Error updating donation in Firestore: $e');
    }
  }
}
