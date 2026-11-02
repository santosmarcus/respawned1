import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) => AuditLogRepository());

// Audit Flicker spec §3 — root cause: these were `.autoDispose`. A
// `TabBarView` doesn't keep every tab's widget subtree alive once it's
// scrolled far enough off-screen (only nearby pages are kept built), so
// switching tabs away and back tore down the last listener on an
// autoDispose provider, which discarded its Firestore subscription
// entirely; returning to that tab started a brand-new stream from
// scratch, showing the ConnectionState-less "loading" gap before the
// first snapshot arrived — exactly the "appears -> disappears -> appears
// again" symptom. Keyed by (category, organizationId) so switching
// organizations (or resolving one asynchronously after the page first
// opens) still never reuses a stale listener for the wrong org, but the
// provider itself now stays alive for the app session once created,
// matching the identical fix already applied to
// admin_dashboard_home_widgets.dart's staleTransportOffersProvider/
// overdueFollowUpsProvider for the same class of dashboard-flicker bug.
final auditCategoryLogsProvider =
    StreamProvider.family<List<AuditLogEntry>, ({AuditCategory category, String? organizationId})>(
  (ref, key) => ref.watch(auditLogRepositoryProvider).streamCategory(key.category, organizationId: key.organizationId),
);

final animalRecordAuditProvider = StreamProvider<List<AuditDisplayRow>>(
  (ref) => ref.watch(auditLogRepositoryProvider).streamAnimalRecordChanges(),
);

final rescueCaseAuditProvider = StreamProvider<List<AuditDisplayRow>>(
  (ref) => ref.watch(auditLogRepositoryProvider).streamRescueCaseChanges(),
);
