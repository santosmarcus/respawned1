import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../donation/models.dart';

final historyProvider = NotifierProvider<HistoryNotifier, List<HistoryItem>>(
  HistoryNotifier.new,
);

class HistoryNotifier extends Notifier<List<HistoryItem>> {
  @override
  List<HistoryItem> build() {
    return [];
  }

  void addHistoryItem(HistoryItem item) {
    state = [item, ...state];
  }

  void updateStatus(String id, InKindStatus status) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(status: status) else item
    ];
  }

  void cancelSponsorship(String id) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(sponsorshipStatus: 'cancelled') else item
    ];
  }

  void unCancelSponsorship(String id) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(sponsorshipStatus: 'active') else item
    ];
  }

  void updateSponsorshipAmount(String id, double amount) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(nextChargeAmount: amount) else item
    ];
  }

  void requestRefund(String id) {
    state = [
      for (final item in state)
        if (item.id == id) item.copyWith(refundStatus: RefundStatus.pending) else item
    ];
  }
}
