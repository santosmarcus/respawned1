import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/transporter_application.dart';
import 'package:respawnd1/core/repos/transporter_application_repository.dart';

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
          SnackBar(content: Text(approve ? 'Transporter approved.' : 'Application not approved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save the review: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        iconTheme: const IconThemeData(color: AppColors.background),
        title: Text('Transporter applications',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in TransporterApplicationStatus.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(s.label, maxLines: 1, softWrap: false),
                        selected: _tab == s,
                        showCheckmark: false,
                        selectedColor: AppColors.yellowrspwn,
                        onSelected: (_) => setState(() => _tab = s),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<TransporterApplication>>(
              stream: _repo.watchByStatus(_tab),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Could not load applications.', style: GoogleFonts.zain()));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
                }
                final apps = snap.data!;
                if (apps.isEmpty) {
                  return Center(
                    child: Text('No applications here.',
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                  );
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
    final dateFmt = DateFormat('MMM d, y');

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
          line('Submitted', app.submittedAt == null ? null : dateFmt.format(app.submittedAt!)),
          if (app.status != TransporterApplicationStatus.pending)
            line('Reviewed', app.reviewedAt == null ? null : dateFmt.format(app.reviewedAt!)),
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
