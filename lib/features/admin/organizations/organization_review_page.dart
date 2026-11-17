import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/volunteers/application_review.dart';
import 'package:respawnd1/features/admin/volunteers/transporter_applications_page.dart' show DocumentThumb;
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';

/// Platform staff's queue of organizations that submitted their
/// verification documents. Decisions are only possible while an
/// organization is "Under review"; they run in the reviewOrganization
/// callable, which also notifies the owner.
///
/// Pushed from the admin drawer (back arrow), or a tab of the system admin
/// console ([showBackButton] false, with the console's [menuActions]).
class OrganizationReviewPage extends StatefulWidget {
  const OrganizationReviewPage({
    super.key,
    this.repository,
    this.showBackButton = true,
    this.title = 'Organization approvals',
    this.menuActions = const [],
  });

  final OrganizationRepository? repository;
  final bool showBackButton;
  final String title;
  final List<AdminMenuAction> menuActions;

  @override
  State<OrganizationReviewPage> createState() => _OrganizationReviewPageState();
}

const _tabs = [
  (OrgVerificationStatus.pending, 'Under review'),
  (OrgVerificationStatus.requiresChanges, 'Needs changes'),
  (OrgVerificationStatus.approved, 'Approved'),
  (OrgVerificationStatus.rejected, 'Not approved'),
];

class _OrganizationReviewPageState extends State<OrganizationReviewPage> {
  late final OrganizationRepository _repo = widget.repository ?? OrganizationRepository();
  int _tab = 0;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _decide(OrganizationReviewItem org, OrgVerificationStatus decision) async {
    final name = org.name.isEmpty ? 'this organization' : org.name;
    String? note;
    switch (decision) {
      case OrgVerificationStatus.approved:
        final ok = await showConfirmActionDialog(
          context,
          title: 'Approve $name?',
          message: 'Its staff get the admin tools, and it starts receiving cases in its service areas.',
          confirmLabel: 'Approve',
        );
        if (!ok) return;
      case OrgVerificationStatus.requiresChanges:
        note = await showTextInputDialog(
          context,
          title: 'Ask for changes?',
          message: 'The owner sees your note and can upload new documents.',
          label: 'What needs to change',
          confirmLabel: 'Send',
          required: true,
        );
        if (note == null) return;
      case OrgVerificationStatus.rejected:
        note = await showTextInputDialog(
          context,
          title: 'Not approve $name?',
          message: 'The owner sees this status and your note.',
          label: 'Reason',
          confirmLabel: 'Not approve',
          required: true,
          destructive: true,
        );
        if (note == null) return;
      case OrgVerificationStatus.draft:
      case OrgVerificationStatus.pending:
        return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.review(organizationId: org.id, decision: decision, note: note?.trim());
      messenger.showSnackBar(appSnackBar(
        switch (decision) {
          OrgVerificationStatus.approved => 'Organization approved.',
          OrgVerificationStatus.requiresChanges => 'Changes requested.',
          _ => 'Organization not approved.',
        },
        kind: AppMessageKind.success,
      ));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(appSnackBar(e.message ?? 'Could not save the review.', kind: AppMessageKind.error));
    } catch (e) {
      messenger.showSnackBar(appSnackBar('Could not save the review: $e', kind: AppMessageKind.error));
    }
  }

  ApplicationSummary _summary(OrganizationReviewItem org) => ApplicationSummary(
        name: org.name,
        phone: org.phone,
        lines: [
          ('Email', org.email),
          ('Location', org.location),
          ('Reviewed by', org.reviewedByName),
          if (org.documents.isEmpty) ('Documents', 'None uploaded'),
        ],
        submittedAt: org.submittedAt,
        reviewedAt: org.reviewedAt,
        reviewNote: org.note,
        extra: org.documents.isEmpty
            ? null
            : SizedBox(
                height: 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: org.documents.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => DocumentThumb(doc: org.documents[i]),
                ),
              ),
      );

  bool _matches(OrganizationReviewItem org) {
    if (_query.isEmpty) return true;
    return org.name.toLowerCase().contains(_query) ||
        org.phone.contains(_query) ||
        org.email.toLowerCase().contains(_query) ||
        org.location.toLowerCase().contains(_query);
  }

  @override
  Widget build(BuildContext context) {
    final (status, label) = _tabs[_tab];
    final reviewable = status == OrgVerificationStatus.pending;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AdminAppBar(
        title: widget.title,
        showDrawerButton: false,
        showLeading: widget.showBackButton,
        menuActions: widget.menuActions,
        bottom: AdminTabBar(
          tabs: [for (final (_, l) in _tabs) AdminTab(l)],
          selectedIndex: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
      ),
      body: Column(
        children: [
          AdminSearchBar(
            controller: _search,
            hintText: 'Search name, phone, email or area…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          Expanded(
            child: AdminTabSwipe(
              index: _tab,
              count: _tabs.length,
              onSelected: (i) => setState(() => _tab = i),
              child: StreamBuilder<List<OrganizationReviewItem>>(
                key: ValueKey(status),
                stream: _repo.streamForReview(status),
                builder: (context, snap) {
                  if (snap.hasError) return const AdminListMessage('Could not load organizations.');
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
                  }
                  final items = snap.data!.where(_matches).toList();
                  if (items.isEmpty) {
                    return AdminListMessage(_query.isEmpty
                        ? 'No organizations ${label.toLowerCase()}.'
                        : 'No organizations match your search.');
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) {
                      final org = items[i];
                      return ApplicationCard(
                        summary: _summary(org),
                        onApprove: reviewable ? () => _decide(org, OrgVerificationStatus.approved) : null,
                        onReject: reviewable ? () => _decide(org, OrgVerificationStatus.rejected) : null,
                        onRequestChanges:
                            reviewable ? () => _decide(org, OrgVerificationStatus.requiresChanges) : null,
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
