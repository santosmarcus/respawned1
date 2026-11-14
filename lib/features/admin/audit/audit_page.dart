import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/features/admin/audit/state/audit_providers.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';

/// Read-only audit trail across six categories. Temporary Organization
/// Admin/Member Access Model spec — access is resolved via the centralized
/// OrganizationCapabilities model (Owner/Admin/Member all get parity
/// during this phase); only accounts with no active organization
/// relationship at all are blocked. Nothing in this page can edit or delete
/// an entry — every row is plain, non-interactive text.
class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  bool _loading = true;
  bool _allowed = true;
  String? _organizationId;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _resolveAccess();
  }

  Future<void> _resolveAccess() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final service = OrgMembershipService();
      final orgId = await service.resolveOrganizationId(uid);
      // Temporary Organization Admin/Member Access Model spec — Audits is
      // an equal-access module during this phase, resolved via the
      // centralized capability model instead of a direct admin-role check
      // so Owner/Admin/Member all get parity viewing audit records.
      final capabilities = await service.resolveCapabilities(uid);
      if (!mounted) return;
      setState(() {
        _organizationId = orgId;
        _allowed = capabilities.canViewAudits;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showTabs = !_loading && _allowed;
    return DefaultTabController(
      length: AuditCategory.values.length,
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: const AdminDrawer(active: AdminModule.audit),
        appBar: AdminAppBar(
          title: 'Audit',
          bottom: showTabs ? AdminTabBar(tabs: [for (final c in AuditCategory.values) AdminTab(c.label)]) : null,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn))
            : !_allowed
                ? const AdminListMessage(
                    'You do not have permission to view Audit. Only organization admins can access this page.')
                : Column(
                    children: [
                      AdminSearchBar(
                        controller: _searchController,
                        hintText: 'Search action, person or record…',
                        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            for (final c in AuditCategory.values)
                              _AuditCategoryTab(category: c, organizationId: _organizationId, query: _query),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _AuditCategoryTab extends ConsumerStatefulWidget {
  final AuditCategory category;
  final String? organizationId;

  /// Lower-cased search text; empty shows every row.
  final String query;
  const _AuditCategoryTab({required this.category, required this.organizationId, this.query = ''});

  @override
  ConsumerState<_AuditCategoryTab> createState() => _AuditCategoryTabState();
}

class _AuditCategoryTabState extends ConsumerState<_AuditCategoryTab> {
  bool _matches(AuditDisplayRow r) {
    final q = widget.query;
    if (q.isEmpty) return true;
    return [r.action, r.description, r.actorName, r.actorEmail, r.targetLabel]
        .any((v) => v != null && v.toLowerCase().contains(q));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.category == AuditCategory.animalRecords) {
      final rowsAsync = ref.watch(animalRecordAuditProvider);
      return _buildAuditSection(
        rows: rowsAsync.value,
        hasError: rowsAsync.hasError,
        onRetry: () => ref.invalidate(animalRecordAuditProvider),
      );
    }
    if (widget.category == AuditCategory.rescueCases) {
      final rowsAsync = ref.watch(rescueCaseAuditProvider);
      return _buildAuditSection(
        rows: rowsAsync.value,
        hasError: rowsAsync.hasError,
        onRetry: () => ref.invalidate(rescueCaseAuditProvider),
      );
    }
    final key = (category: widget.category, organizationId: widget.organizationId);
    final entriesAsync = ref.watch(auditCategoryLogsProvider(key));
    return _buildAuditSection(
      rows: entriesAsync.value?.map(AuditDisplayRow.fromAuditLog).toList(),
      hasError: entriesAsync.hasError,
      onRetry: () => ref.invalidate(auditCategoryLogsProvider(key)),
    );
  }

  // Audit Flicker spec §3/§4 — reads `.value` (Riverpod's AsyncValue keeps
  // the last successfully-received value accessible here even while the
  // provider is mid-refresh or has hit a transient error) instead of
  // pattern-matching purely via `.when()`, whose `loading`/`error`
  // branches never see that carried-over value. Loading only ever shows
  // before the very first result (`rows == null` with no error yet);
  // once data has arrived once, a later error shows a compact "Could not
  // refresh" banner ABOVE the still-visible previous rows rather than
  // replacing them with a spinner or empty state.
  Widget _buildAuditSection({
    required List<AuditDisplayRow>? rows,
    required bool hasError,
    required VoidCallback onRetry,
  }) {
    if (rows == null) {
      if (hasError) {
        return AdminListMessage('Could not load audit records.', onRetry: onRetry);
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }
    if (rows.isEmpty) {
      return const AdminListMessage('No audit records yet.');
    }
    final visible = rows.where(_matches).toList();
    if (visible.isEmpty) {
      return AdminListMessage('None of the ${rows.length} most recent records match your search.');
    }
    return Column(
      children: [
        if (hasError)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Could not refresh.',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ),
                TextButton(onPressed: onRetry, child: const Text('Retry')),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const Divider(height: 20),
            itemBuilder: (context, i) => _AuditRowTile(row: visible[i]),
          ),
        ),
      ],
    );
  }
}

class _AuditRowTile extends StatefulWidget {
  final AuditDisplayRow row;
  const _AuditRowTile({required this.row});

  @override
  State<_AuditRowTile> createState() => _AuditRowTileState();
}

class _AuditRowTileState extends State<_AuditRowTile> {
  bool _expanded = false;

  String? get _actorLine {
    final r = widget.row;
    final name = r.actorName?.trim();
    final email = r.actorEmail?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    if (hasName && hasEmail) return '$name · $email';
    if (hasName) return name;
    if (hasEmail) return email;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final hasValues = (r.oldValues?.isNotEmpty ?? false) || (r.newValues?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.action, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if ((r.description ?? '').isNotEmpty)
                    Text(r.description!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if (_actorLine != null)
                    Text(_actorLine!, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  if ((r.targetLabel ?? '').isNotEmpty)
                    Text(r.targetLabel!, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(formatDateTimeOr(r.createdAt, 'Undated'), style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        if (hasValues)
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_expanded ? 'Hide details' : 'View details',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.greenrspwn, decoration: TextDecoration.underline)),
            ),
          ),
        if (_expanded && hasValues)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r.oldValues?.isNotEmpty ?? false)
                  Text('Before — ${r.oldValues!.entries.map((e) => '${e.key}: ${e.value}').join('  ·  ')}',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                if (r.newValues?.isNotEmpty ?? false)
                  Text('After — ${r.newValues!.entries.map((e) => '${e.key}: ${e.value}').join('  ·  ')}',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
          ),
      ],
    );
  }
}
