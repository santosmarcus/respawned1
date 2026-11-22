import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

// The old dashboard overview widgets that lived here (ActionRequiredSection,
// TopMetricsRow, CurrentOperationsSection) were no longer shown anywhere
// and were removed; the Today and Analytics tabs replaced them. Only this
// provider is still used (dashboard_alerts.dart, dashboard_cache.dart).

/// Transport offers left pending too long.
///
/// Deliberately NOT .autoDispose: an autoDispose provider is rebuilt (with a
/// fresh Firestore listener) every time its last listener unmounts and a
/// new one appears, which made counts flicker on the dashboard. A plain
/// StreamProvider keeps one subscription for the session.
final staleTransportOffersProvider = StreamProvider<List<TransportAssignment>>((ref) {
  return ref.watch(rescueCaseRepositoryProvider).streamStalePendingAssignments();
});
