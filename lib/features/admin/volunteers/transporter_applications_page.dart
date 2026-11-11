import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/transporter_application.dart';
import 'package:respawnd1/core/repos/transporter_application_repository.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Staff review of pet transporter verification applications — same layout
/// and flow as VolunteerApplicationsPage. Approving or rejecting also sets
/// the transporter's `users/{uid}.isVerified` (see
/// TransporterApplicationRepository.review).
class TransporterApplicationsPage extends StatefulWidget {
  const TransporterApplicationsPage({super.key});

  @override
  State<TransporterApplicationsPage> createState() => _TransporterApplicationsPageState();
}

class _TransporterApplicationsPageState extends State<TransporterApplicationsPage> {
  final _repo = TransporterApplicationRepository();
  TransporterApplicationStatus _tab = TransporterApplicationStatus.pending;

  Future<void> _review(TransporterApplication app, {required bool approve}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve this transporter?' : 'Not approve this application?'),
        content: approve
            ? Text('${app.name.isEmpty ? 'This applicant' : app.name} will be marked verified and can '
                'receive transport requests.')
            : TextField(
                controller: ctrl,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Reason shown to the applicant (optional)'),
              ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? 'Approve' : 'Not approve')),
        ],
      ),
    );
    final note = ctrl.text;
    ctrl.dispose();
    if (ok != true) return;
    try {
      await _repo.review(
        uid: app.uid,
        approve: approve,
        reviewerUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        note: approve ? null : note,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar(approve ? 'Transporter approved.' : 'Application not approved.'),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not save the review: $e', kind: AppMessageKind.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    void selectTab(int index) => setState(() => _tab = TransporterApplicationStatus.values[index]);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AdminAppBar(
        title: 'Transporter Applications',
        showDrawerButton: false,
        bottom: AdminTabBar(
          tabs: [for (final s in TransporterApplicationStatus.values) AdminTab(s.label)],
          selectedIndex: _tab.index,
          onSelected: selectTab,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: AdminTabSwipe(
              index: _tab.index,
              count: TransporterApplicationStatus.values.length,
              onSelected: selectTab,
              child: StreamBuilder<List<TransporterApplication>>(
              stream: _repo.watchByStatus(_tab),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const AdminListMessage('Could not load applications.');
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
                }
                final apps = snap.data!;
                if (apps.isEmpty) {
                  return const AdminListMessage('No applications here.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: apps.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => TransporterApplicationCard(
                    app: apps[i],
                    onApprove: _tab == TransporterApplicationStatus.approved
                        ? null
                        : () => _review(apps[i], approve: true),
                    onReject: _tab == TransporterApplicationStatus.rejected
                        ? null
                        : () => _review(apps[i], approve: false),
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

/// One application: applicant details, vehicle, and tappable thumbnails of
/// the submitted documents. Also used read-only on the transporter detail
/// page (no approve/reject callbacks).
class TransporterApplicationCard extends StatelessWidget {
  const TransporterApplicationCard({super.key, required this.app, this.onApprove, this.onReject});

  final TransporterApplication app;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String? value) => (value == null || value.trim().isEmpty)
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('$label: $value', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          );
    final vehicle = [app.vehicleType, app.licensePlate].whereType<String>().join(' · ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(app.name.isEmpty ? 'Unnamed applicant' : app.name,
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
              if (app.mobileNumber.isNotEmpty)
                IconButton(
                  tooltip: 'Call',
                  icon: const Icon(Icons.call, size: 18),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: app.mobileNumber)),
                ),
            ],
          ),
          line('Mobile', app.mobileNumber),
          line('Vehicle', vehicle),
          line('Submitted', app.submittedAt == null ? null : formatDate(app.submittedAt!)),
          if (app.status != TransporterApplicationStatus.pending)
            line('Reviewed', app.reviewedAt == null ? null : formatDate(app.reviewedAt!)),
          line('Review note', app.reviewNote),
          if (app.documents.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: app.documents.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) => _DocumentThumb(doc: app.documents[i]),
              ),
            ),
          ] else
            line('Documents', 'None uploaded'),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onReject != null) TextButton(onPressed: onReject, child: const Text('Not approve')),
                if (onApprove != null) TextButton(onPressed: onApprove, child: const Text('Approve')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DocumentThumb extends StatelessWidget {
  const _DocumentThumb({required this.doc});

  final ({String label, String url}) doc;

  void _open(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.network(doc.url, fit: BoxFit.contain)),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Text(doc.label, style: GoogleFonts.zain(fontSize: 14, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 96,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                doc.url,
                width: 96,
                height: 66,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 96,
                  height: 66,
                  color: AppColors.slaterspwn,
                  child: const Icon(Icons.broken_image_outlined, color: AppColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(doc.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
