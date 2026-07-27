import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/repos/audit_log_repository.dart';

final auditLogRepositoryProvider = Provider<AuditLogRepository>((ref) => AuditLogRepository());

/// Keyed by (category, organizationId) so switching organizations (or
/// resolving one asynchronously after the page first opens) never reuses a
/// stale listener for the wrong org.
final auditCategoryLogsProvider =
    StreamProvider.autoDispose.family<List<AuditLogEntry>, ({AuditCategory category, String? organizationId})>(
  (ref, key) => ref.watch(auditLogRepositoryProvider).streamCategory(key.category, organizationId: key.organizationId),
);

final animalRecordAuditProvider = StreamProvider.autoDispose<List<AuditDisplayRow>>(
  (ref) => ref.watch(auditLogRepositoryProvider).streamAnimalRecordChanges(),
);

final rescueCaseAuditProvider = StreamProvider.autoDispose<List<AuditDisplayRow>>(
  (ref) => ref.watch(auditLogRepositoryProvider).streamRescueCaseChanges(),
);
