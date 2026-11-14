import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';

/// The one review flow for applications people send the organization
/// (volunteers, pet transporters): the same tabs, card, approve and
/// not-approve steps, and note rules for every kind.

/// What an application card shows.
class ApplicationSummary {
  const ApplicationSummary({
    required this.name,
    this.phone = '',
    this.lines = const [],
    this.extra,
    this.submittedAt,
    this.reviewedAt,
    this.reviewNote,
  });

  final String name;
  final String phone;

  /// Label and value pairs; empty values are skipped.
  final List<(String, String?)> lines;

  /// Anything else to show under the lines (document thumbnails).
  final Widget? extra;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String? reviewNote;
}

/// Which tab an application sits in.
enum ApplicationTab {
  pending('Under review'),
  approved('Approved'),
  rejected('Not approved');

  const ApplicationTab(this.label);
  final String label;
}

/// Asks to confirm an approval, or for an optional note to the applicant on
/// a refusal, then saves it. Returns true when the decision was saved.
Future<bool> reviewApplication(
  BuildContext context, {
  required bool approve,
  required String approveMessage,
  required Future<void> Function(String reviewerUid, String? note) save,
}) async {
  String? note;
  if (approve) {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Approve this application?',
      message: approveMessage,
      confirmLabel: 'Approve',
    );
    if (!ok) return false;
  } else {
    note = await showTextInputDialog(
      context,
      title: 'Not approve this application?',
      message: 'The applicant sees this status and your note.',
      label: 'Note to the applicant',
      confirmLabel: 'Not approve',
      destructive: true,
    );
    if (note == null) return false;
  }
  if (!context.mounted) return false;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await save(FirebaseAuth.instance.currentUser?.uid ?? '', note);
    messenger.showSnackBar(appSnackBar(
      approve ? 'Application approved.' : 'Application not approved.',
      kind: AppMessageKind.success,
    ));
    return true;
  } catch (e) {
    messenger.showSnackBar(appSnackBar('Could not save the review: $e', kind: AppMessageKind.error));
    return false;
  }
}

/// A tabbed, searchable list of applications with approve / not-approve on
/// each card.
class ApplicationReviewPage<A> extends StatefulWidget {
  const ApplicationReviewPage({
    super.key,
    required this.title,
    required this.noun,
    required this.watch,
    required this.summarize,
    required this.approveMessage,
    required this.save,
  });

  final String title;

  /// Plural, lower case: "volunteers".
  final String noun;
  final Stream<List<A>> Function(ApplicationTab tab) watch;
  final ApplicationSummary Function(A app) summarize;
  final String Function(A app) approveMessage;
  final Future<void> Function(A app, bool approve, String reviewerUid, String? note) save;

  @override
  State<ApplicationReviewPage<A>> createState() => _ApplicationReviewPageState<A>();
}

class _ApplicationReviewPageState<A> extends State<ApplicationReviewPage<A>> {
  ApplicationTab _tab = ApplicationTab.pending;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _select(int i) => setState(() => _tab = ApplicationTab.values[i]);

  Future<void> _review(A app, bool approve) => reviewApplication(
        context,
        approve: approve,
        approveMessage: widget.approveMessage(app),
        save: (reviewer, note) => widget.save(app, approve, reviewer, note),
      );

  bool _matches(ApplicationSummary s) {
    if (_query.isEmpty) return true;
    return s.name.toLowerCase().contains(_query) ||
        s.phone.contains(_query) ||
        s.lines.any((l) => (l.$2 ?? '').toLowerCase().contains(_query));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AdminAppBar(
        title: widget.title,
        showDrawerButton: false,
        bottom: AdminTabBar(
          tabs: [for (final t in ApplicationTab.values) AdminTab(t.label)],
          selectedIndex: _tab.index,
          onSelected: _select,
        ),
      ),
      body: Column(
        children: [
          AdminSearchBar(
            controller: _search,
            hintText: 'Search name, phone or area…',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          Expanded(
            child: AdminTabSwipe(
              index: _tab.index,
              count: ApplicationTab.values.length,
              onSelected: _select,
              child: StreamBuilder<List<A>>(
                stream: widget.watch(_tab),
                builder: (context, snap) {
                  if (snap.hasError) return const AdminListMessage('Could not load applications.');
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
                  }
                  final items = [
                    for (final a in snap.data!)
                      if (_matches(widget.summarize(a))) a,
                  ];
                  if (items.isEmpty) {
                    return AdminListMessage(_query.isEmpty
                        ? 'No ${_tab.label.toLowerCase()} ${widget.noun}.'
                        : 'No ${widget.noun} match your search.');
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => ApplicationCard(
                      summary: widget.summarize(items[i]),
                      onApprove: _tab == ApplicationTab.approved ? null : () => _review(items[i], true),
                      onReject: _tab == ApplicationTab.rejected ? null : () => _review(items[i], false),
                    ),
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

/// One application. With no callbacks it is read-only (a transporter's
/// detail page).
class ApplicationCard extends StatelessWidget {
  const ApplicationCard({super.key, required this.summary, this.onApprove, this.onReject});

  final ApplicationSummary summary;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    Widget line(String label, String? value) => (value == null || value.trim().isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('$label: $value', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(s.name.isEmpty ? 'Unnamed applicant' : s.name,
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
              if (s.phone.isNotEmpty)
                IconButton(
                  tooltip: 'Call',
                  icon: const Icon(Icons.call, size: 18),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: s.phone)),
                ),
            ],
          ),
          line('Phone', s.phone),
          for (final (label, value) in s.lines) line(label, value),
          line('Submitted', s.submittedAt == null ? null : formatDate(s.submittedAt!)),
          line('Reviewed', s.reviewedAt == null ? null : formatDate(s.reviewedAt!)),
          line('Review note', s.reviewNote),
          if (s.extra != null) ...[const SizedBox(height: 10), s.extra!],
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onReject != null)
                  Expanded(
                    child: OutlinedButton(onPressed: onReject, style: AppButtons.dangerOutline, child: const Text('Not approve')),
                  ),
                if (onReject != null && onApprove != null) const SizedBox(width: 10),
                if (onApprove != null)
                  Expanded(
                    child: ElevatedButton(onPressed: onApprove, style: AppButtons.primary, child: const Text('Approve')),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
