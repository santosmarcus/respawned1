import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_application.dart';
import 'package:respawnd1/core/repos/volunteer_application_repository.dart';

/// Staff review of general volunteer applications (paper 1.4.5).
class VolunteerApplicationsPage extends StatefulWidget {
  const VolunteerApplicationsPage({super.key});

  @override
  State<VolunteerApplicationsPage> createState() => _VolunteerApplicationsPageState();
}

class _VolunteerApplicationsPageState extends State<VolunteerApplicationsPage> {
  final _repo = VolunteerApplicationRepository();
  VolunteerApplicationStatus _tab = VolunteerApplicationStatus.pending;

  Future<void> _review(VolunteerApplication app, {required bool approve}) async {
    String? note;
    if (!approve) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Not approve this application?'),
          content: TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note to the applicant (optional)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Not approve')),
          ],
        ),
      );
      note = ctrl.text;
      ctrl.dispose();
      if (ok != true) return;
    }
    try {
      await _repo.review(
        uid: app.uid,
        approve: approve,
        reviewerUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        note: note,
      );
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
        title: Text('Volunteer applications',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            // One non-wrapping row: scrolls sideways on narrow screens
            // instead of dropping a chip onto a second line.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final s in VolunteerApplicationStatus.values)
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
            child: StreamBuilder<List<VolunteerApplication>>(
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
                  itemBuilder: (context, i) => _ApplicationCard(
                    app: apps[i],
                    onApprove: _tab == VolunteerApplicationStatus.approved
                        ? null
                        : () => _review(apps[i], approve: true),
                    onReject: _tab == VolunteerApplicationStatus.rejected
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

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app, this.onApprove, this.onReject});

  final VolunteerApplication app;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, String value) => value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('$label: $value', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          );

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
              if (app.phone.isNotEmpty)
                IconButton(
                  tooltip: 'Call',
                  icon: const Icon(Icons.call, size: 18),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: app.phone)),
                ),
            ],
          ),
          line('Helps with', app.categories.map((c) => c.label).join(', ')),
          line('Available', app.availability),
          line('Area', app.serviceArea),
          line('Experience', app.experience),
          if ((app.reviewNote ?? '').isNotEmpty) line('Review note', app.reviewNote!),
          if (onApprove != null || onReject != null) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onReject != null)
                  TextButton(onPressed: onReject, child: const Text('Not approve')),
                if (onApprove != null)
                  TextButton(onPressed: onApprove, child: const Text('Approve')),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
