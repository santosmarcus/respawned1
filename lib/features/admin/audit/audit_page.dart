import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/audit/audit_log_entry.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/features/admin/audit/state/audit_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

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
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.audit),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text('Audit', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : !_allowed
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'You do not have permission to view Audit. Only organization admins can access this page.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  ),
                )
              : DefaultTabController(
                  length: AuditCategory.values.length,
                  child: Column(
                    children: [
                      Material(
                        color: AppColors.textPrimary,
                        child: TabBar(
                          isScrollable: true,
                          labelColor: AppColors.background,
                          unselectedLabelColor: AppColors.background.withValues(alpha: 0.6),
                          indicatorColor: AppColors.yellowrspwn,
                          labelStyle: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700),
                          tabs: [for (final c in AuditCategory.values) Tab(text: c.label)],
                        ),
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            for (final c in AuditCategory.values) _AuditCategoryTab(category: c, organizationId: _organizationId),
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
  const _AuditCategoryTab({required this.category, required this.organizationId});

  @override
  ConsumerState<_AuditCategoryTab> createState() => _AuditCategoryTabState();
}

class _AuditCategoryTabState extends ConsumerState<_AuditCategoryTab> {
  @override
  Widget build(BuildContext context) {
    // Donations has no real write path anywhere in this codebase (no
    // Donation model/repository, nothing ever writes a `donations` doc —
    // confirmed by inspection) — shown as an honest empty state rather
    // than fabricated entries, same convention admin_adoption_page.dart
    // already uses for the same reason.
    if (widget.category == AuditCategory.donations) {
      return _EmptyState(
        message: 'No donation events recorded yet. Donations does not have a data-writing workflow in this build.',
      );
    }
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
        return _ErrorState(message: 'Could not load audit records.', onRetry: onRetry);
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }
    if (rows.isEmpty) {
      return const _EmptyState(message: 'No audit records yet.');
    }
    return Column(
      children: [
        if (hasError)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
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
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 20),
            itemBuilder: (context, i) => _AuditRowTile(row: rows[i]),
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

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _fmt(DateTime? d) {
    if (d == null) return 'Undated';
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year}, $hour12:$minute $ampm';
  }

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
            Text(_fmt(r.createdAt), style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
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

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(message, textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      );
}
