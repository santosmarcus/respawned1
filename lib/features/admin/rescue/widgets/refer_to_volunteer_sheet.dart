import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Refer to Rescue Volunteer: the independent rescuers whose area covers the
/// case, nearest first, with how much room each has. The referral works like
/// one to another organization (CaseReferralRepository.referToVolunteer):
/// they accept or decline, and it comes back after 48 hours unanswered.
/// Rescuers who are paused or at capacity are shown but can't be picked.
/// Returns true if a referral was sent.
Future<bool> showReferToVolunteerSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required OrganizationDirectoryRepository directory,
  required RescueCaseRepository caseRepository,
  required String actorUid,
  required String actorName,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReferToVolunteerBody(
      rescueCase: rescueCase,
      directory: directory,
      caseRepository: caseRepository,
      actorUid: actorUid,
      actorName: actorName,
    ),
  );
  return result ?? false;
}

class _ReferToVolunteerBody extends StatefulWidget {
  const _ReferToVolunteerBody({
    required this.rescueCase,
    required this.directory,
    required this.caseRepository,
    required this.actorUid,
    required this.actorName,
  });

  final RescueCase rescueCase;
  final OrganizationDirectoryRepository directory;
  final RescueCaseRepository caseRepository;
  final String actorUid;
  final String actorName;

  @override
  State<_ReferToVolunteerBody> createState() => _ReferToVolunteerBodyState();
}

class _ReferToVolunteerBodyState extends State<_ReferToVolunteerBody> {
  final _note = TextEditingController();
  late final Future<List<IndependentCandidate>> _candidates = _load();
  IndependentCandidate? _selected;
  bool _sending = false;

  Future<List<IndependentCandidate>> _load() {
    final c = widget.rescueCase;
    if (c.lat == null || c.lng == null) return Future.value(const []);
    return widget.directory.independentsNear(lat: c.lat!, lng: c.lng!);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final target = _selected;
    if (target == null) return;
    final ok = await showConfirmActionDialog(
      context,
      title: 'Refer to ${target.name}?',
      message: 'They can accept or decline. If they don\'t answer within 48 hours, the case comes back to you.',
      confirmLabel: 'Send Referral',
    );
    if (!ok || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.caseRepository.referToVolunteer(
        caseId: widget.rescueCase.id,
        targetOrgId: target.id,
        targetOrgName: target.name,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not send referral: $e', kind: AppMessageKind.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Refer to Rescue Volunteer', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Verified rescue volunteers whose area covers this case.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<List<IndependentCandidate>>(
                future: _candidates,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Text('Could not load rescuers.', style: GoogleFonts.zain(color: AppColors.textSecondary)),
                    );
                  }
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final list = snap.data!;
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          widget.rescueCase.lat == null
                              ? 'This case has no map location, so no rescuer can be matched.'
                              : 'No rescue volunteer covers this location yet.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: scroll,
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final r = list[i];
                      final blocked = r.refusal != null;
                      final selected = _selected?.id == r.id;
                      return InkWell(
                        onTap: blocked ? null : () => setState(() => _selected = r),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected ? AppColors.textPrimary : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.greenrspwn,
                                backgroundImage: r.avatarUrl == null ? null : NetworkImage(r.avatarUrl!),
                                child: r.avatarUrl == null ? const Icon(Icons.volunteer_activism, color: Colors.white) : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(r.name,
                                        style: GoogleFonts.zain(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: blocked ? AppColors.textSecondary : AppColors.textPrimary,
                                        )),
                                    Text(
                                      '${r.distanceKm.toStringAsFixed(1)} km away'
                                      '${r.area.isEmpty ? '' : ' · ${r.area}'}',
                                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                    Text(
                                      r.refusal ?? r.room,
                                      style: GoogleFonts.zain(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: blocked ? AppColors.error : AppColors.success,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (selected) const Icon(Icons.check_circle, color: AppColors.textPrimary),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Referral note (optional)',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
                isDense: true,
              ),
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_selected == null || _sending) ? null : _send,
                style: AppButtons.primary,
                child: _sending
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Send Referral', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
