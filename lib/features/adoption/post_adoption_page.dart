import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/collartag/collar_tag_data_model.dart';
import 'package:respawnd1/features/collartag/collar_id_tag_screen.dart';
import 'package:respawnd1/features/collartag/collar_tag_list_screen.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/follow_up_record.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';


String _formatDate(DateTime d) {
  const months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  return '${months[d.month]} ${d.day}, ${d.year}';
}

DateTime? extractAdoptionCompletedDate(Map<String, dynamic> data) {
  final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];
  for (final h in history) {
    final status = h['status'] as String?;
    if (status != null &&
        status.toLowerCase().contains('adoption completed')) {
      final ts = h['timestamp'];
      if (ts is Timestamp) return ts.toDate();
    }
  }
  final appt = data['appointmentDate'];
  if (appt is Timestamp) return appt.toDate();
  final created = data['createdAt'];
  if (created is Timestamp) return created.toDate();
  return null;
}


// Post-Adoption Monitoring page
class PostAdoptionMonitoringPage extends StatelessWidget {
  final String adoptionId;

  const PostAdoptionMonitoringPage({super.key, required this.adoptionId});

  @override
  Widget build(BuildContext context) {
    final adoptionRef =
    FirebaseFirestore.instance.collection('adoptions').doc(adoptionId);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: adoptionRef.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.greenrspwn),
              );
            }
            final data = snap.data!.data() as Map<String, dynamic>?;
            if (data == null) {
              return Column(
                children: [
                  _BackHeader(onTap: () => Navigator.pop(context)),
                  const Expanded(
                    child: Center(child: Text('Adoption record not found.')),
                  ),
                ],
              );
            }

            final personal = (data['personal'] as Map?) ?? {};
            final animalName = personal['animalName'] as String? ?? 'Your pet';
            final orgName = personal['organizationName'] as String?;
            final adopterName = personal['adopterName'] as String? ?? '';
            final adoptedDate = extractAdoptionCompletedDate(data);
            final returnRequest = ReturnRequest.fromMap(data['returnRequest'] as Map<String, dynamic>?);
            final isReturnRequested = returnRequest != null && returnRequest.status == ReturnRequestStatus.pendingReview;
            final isReturnApproved = returnRequest != null &&
                (returnRequest.status.isApprovedAwaitingSchedule ||
                    returnRequest.status == ReturnRequestStatus.retrievalScheduled ||
                    returnRequest.status == ReturnRequestStatus.retrieved);
            final noFollowUpsPlanned = data['noFollowUpsPlanned'] as bool? ?? false;

            return StreamBuilder<QuerySnapshot>(
              stream: adoptionRef.collection('followUps').orderBy('sequenceNumber').snapshots(),
              builder: (context, followUpSnap) {
                final schedule = (followUpSnap.data?.docs ?? [])
                    .map((d) => FollowUpRecord.fromFirestore(d as DocumentSnapshot<Map<String, dynamic>>))
                    .toList();

                final now = DateTime.now();
                FollowUpRecord? currentDue;
                for (final f in schedule) {
                  if (!f.isTerminal && f.submittedAt == null && !f.scheduledDate.isAfter(now)) {
                    currentDue = f;
                    break;
                  }
                }
                final allDone = schedule.isNotEmpty && schedule.every((f) => f.isTerminal);

                return SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Stack(
                        children: [
                          Container(
                            height: 150,
                            width: double.infinity,
                            color: AppColors.tearspwn,
                            child: const Center(
                              child: Icon(Icons.pets,
                                  size: 56, color: AppColors.textPrimary),
                            ),
                          ),
                          _BackHeader(onTap: () => Navigator.pop(context)),
                          _MoreOptionsButton(
                            onTap: () => _showPetOptionsDialog(
                              context,
                              adoptionId: adoptionId,
                              animalName: animalName,
                              data: data,
                              isReturnRequested: isReturnRequested,
                              isReturnApproved: isReturnApproved,
                              adopterName: adopterName,
                              adoptedDate: adoptedDate,
                            ),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  animalName,
                                  style: GoogleFonts.tiltWarp(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Icons.pets,
                                    size: 18, color: AppColors.textPrimary),
                                const SizedBox(width: 6),
                                const Icon(Icons.search,
                                    size: 18, color: AppColors.textPrimary),
                              ],
                            ),
                            const SizedBox(height: 18),

                            if (isReturnRequested || isReturnApproved) ...[
                              GestureDetector(
                                onTap: isReturnApproved
                                    ? () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ReturnApprovedPage(
                                              adoptionId: adoptionId),
                                    ),
                                  );
                                }
                                    : null,
                                child: Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: (isReturnApproved
                                        ? AppColors.greenrspwn
                                        : AppColors.pinkrspwn)
                                        .withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        isReturnApproved
                                            ? Icons.check_circle_outline
                                            : Icons.info_outline,
                                        size: 18,
                                        color: AppColors.textPrimary,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          isReturnApproved
                                              ? 'Your return request has been approved. Tap to view pick-up details.'
                                              : 'A return request has been submitted and is awaiting processing.',
                                          style: GoogleFonts.zain(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ),
                                      if (isReturnApproved)
                                        const Icon(Icons.chevron_right,
                                            size: 18,
                                            color: AppColors.textPrimary),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],

                            const SizedBox(height: 8),

                            Text(
                              'Details',
                              style: GoogleFonts.tiltWarp(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Adopted ${adoptedDate != null ? _formatDate(adoptedDate) : '-'}',
                              style: GoogleFonts.zain(
                                  fontSize: 14, color: AppColors.textPrimary),
                            ),
                            if (orgName != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'From',
                                style: GoogleFonts.zain(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                orgName,
                                style: GoogleFonts.zain(
                                    fontSize: 14, color: AppColors.textPrimary),
                              ),
                            ],

                            const SizedBox(height: 22),
                            Text(
                              'Post-Adoption Monitoring',
                              style: GoogleFonts.tiltWarp(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 10),

                            if (noFollowUpsPlanned)
                              Text(
                                'No post-adoption follow-ups were scheduled for this adoption.',
                                style: GoogleFonts.zain(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              )
                            else if (schedule.isEmpty)
                              Text(
                                'Your monitoring schedule will appear here once your adoption is finalized.',
                                style: GoogleFonts.zain(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              ),

                            ...schedule.map((f) {
                              final done = f.isTerminal;
                              final isCurrent = currentDue?.id == f.id;
                              final overdue = f.displayStatus(now) == 'Overdue';
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4),
                                child: Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.center,
                                  children: [
                                    Icon(
                                      done
                                          ? Icons.check_circle
                                          : Icons.circle,
                                      size: done ? 15 : 8,
                                      color: done
                                          ? AppColors.greenrspwn
                                          : (overdue
                                          ? Colors.redAccent
                                          : (isCurrent
                                          ? AppColors.textPrimary
                                          : AppColors.slaterspwn)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Follow-up ${f.sequenceNumber} - ${_formatDate(f.scheduledDate)}',
                                            style: GoogleFonts.zain(
                                              fontSize: 13,
                                              color: AppColors.textPrimary,
                                              fontWeight: isCurrent && !done
                                                  ? FontWeight.w700
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                          if (isCurrent && !done)
                                            Text(
                                              f.displayStatus(now),
                                              style: GoogleFonts.zain(
                                                fontSize: 11,
                                                color: overdue
                                                    ? Colors.redAccent
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),

                            const SizedBox(height: 26),

                            _PrimaryBtn(
                              label: allDone
                                  ? 'All check-ins complete'
                                  : (currentDue == null
                                  ? 'No check-in due yet'
                                  : 'Send Update'),
                              onTap: currentDue == null
                                  ? null
                                  : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PostAdoptionCheckinForm(
                                          adoptionId: adoptionId,
                                          animalName: animalName,
                                          followUpId: currentDue!.id,
                                          sequenceNumber: currentDue.sequenceNumber,
                                          dueDate: currentDue.scheduledDate,
                                        ),
                                  ),
                                );
                              },
                            ),
                            if (currentDue != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                currentDue.displayStatus(now) == 'Overdue'
                                    ? 'This check-in is overdue — please submit as soon as possible.'
                                    : 'Due ${_formatDate(currentDue.scheduledDate)}.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.zain(
                                  fontSize: 11,
                                  color: currentDue.displayStatus(now) == 'Overdue'
                                      ? Colors.redAccent
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ---- Pet options menu (three-dot button) ----

  void _showPetOptionsDialog(
      BuildContext context, {
        required String adoptionId,
        required String animalName,
        required Map<String, dynamic> data,
        required bool isReturnRequested,
        required bool isReturnApproved,
        required String adopterName,
        required DateTime? adoptedDate,
      }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          '$animalName Options',
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _DialogOptionButton(
              icon: Icons.error_outline,
              label: 'Report Lost Pet',
              onTap: () {
                Navigator.pop(dialogContext);
                _reportLostPet(
                  context,
                  adoptionId: adoptionId,
                  animalName: animalName,
                  data: data,
                );
              },
            ),
            const SizedBox(height: 10),
            _DialogOptionButton(
              icon: Icons.assignment_return_outlined,
              label: isReturnRequested
                  ? 'Return Already Requested'
                  : 'Request Return',
              enabled: !isReturnRequested && !isReturnApproved,
              onTap: () {
                Navigator.pop(dialogContext);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdoptionReturnForm(
                      adoptionId: adoptionId,
                      animalName: animalName,
                      adopterName: adopterName,
                      adoptionDate: adoptedDate,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  // ---- Report Lost Pet: reuses the collar/NFC tag + pet_found_chat
  // reunification flow instead of building a parallel one. An adopted pet
  // reported lost this way is linked to its registered tag (identity
  // already verified), which is what distinguishes it from a "fresh",
  // unidentified lost/stray report filed through the general Rescue form. ----

  // Single integration point for wiring in the animal-info-page → adoption
  // listing tag mirroring later. Not implemented yet (set aside per
  // requirements), but every read in this file goes through here so that
  // whichever convention the mirroring lands on, only this method needs to
  // change — nothing else in the report-lost flow does.
  //
  // Currently checked, in order:
  //   1. Top-level 'collarTagId' on the adoption doc — the simplest form of
  //      mirroring, written once when the animal's tag is linked.
  //   2. 'personal.collarTagId' — nested alongside the other animal fields
  //      already mirrored here (animalName, organizationName), in case the
  //      mirror write-path follows that existing convention instead.
  //
  // Deferred / not yet implemented:
  //   3. A live fallback lookup by animalId (e.g. reading
  //      'animals/{animalId}.collarTagId' directly) for the window before
  //      mirroring exists. Add it here — and only here — once the animal
  //      document's field name/collection is finalized; this would make the
  //      method async, so callers already `await` it in anticipation.
  String? _resolveCollarTagId(Map<String, dynamic> data) {
    final direct = data['collarTagId'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;

    final personal = (data['personal'] as Map?) ?? {};
    final nested = personal['collarTagId'] as String?;
    if (nested != null && nested.isNotEmpty) return nested;

    return null;
  }

  Future<void> _reportLostPet(
      BuildContext context, {
        required String adoptionId,
        required String animalName,
        required Map<String, dynamic> data,
      }) async {
    final collarTagId = _resolveCollarTagId(data);

    if (collarTagId == null || collarTagId.isEmpty) {
      _promptNoLinkedTag(
        context,
        adoptionId: adoptionId,
        animalName: animalName,
        data: data,
      );
      return;
    }

    try {
      final tagRef =
      FirebaseFirestore.instance.collection('collarTags').doc(collarTagId);
      final tagDoc = await tagRef.get();

      if (!tagDoc.exists) {
        if (context.mounted) {
          _promptNoLinkedTag(
            context,
            adoptionId: adoptionId,
            animalName: animalName,
            data: data,
          );
        }
        return;
      }

      final tag = CollarTagData.fromFirestore(tagDoc.data()!, tagDoc.id);

      // Already reported — just take them straight to the ID card, where
      // the "Pet Found!" banner and chat will surface automatically once
      // someone scans the tag.
      if (tag.status == 'lost') {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
              Text('$animalName is already reported lost — opening their ID card.'),
            ),
          );
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CollarIdTagCardScreen(tagData: tag),
            ),
          );
        }
        return;
      }

      if (!context.mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: AppColors.background,
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Report $animalName as lost?',
            style: GoogleFonts.tiltWarp(
                fontSize: 16, color: AppColors.textPrimary),
          ),
          content: Text(
            'This uses $animalName\'s registered ID tag. Their status '
                'switches to "Lost", your contact info becomes visible to '
                'anyone who scans the tag, and you\'ll be notified here to '
                'chat the moment someone finds them.',
            style:
            GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text('Cancel',
                  style: GoogleFonts.zain(color: AppColors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Report Lost',
                  style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

      if (confirmed != true || !context.mounted) return;

      final uid = FirebaseAuth.instance.currentUser?.uid;
      final ownerId = tag.ownerId ?? uid;

      final update = <String, dynamic>{
        'status': 'lost',
        // Marks this as originating from an already-identified adopted pet
        // (verified via its registered tag) rather than a fresh, unknown
        // sighting — admin/matching views can rely on the tag scan instead
        // of heuristic species/photo matching.
        'lastReportSource': 'adoption',
        'linkedAdoptionId': adoptionId,
      };

      await tagRef.set(update, SetOptions(merge: true));

      if (ownerId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('collarTags')
            .doc(collarTagId)
            .set(update, SetOptions(merge: true));
      }

      // Cross-post to the shared Lost & Found board so the community can
      // help keep an eye out too — flagged with the same 'adoption' source
      // so it's treated as identity-verified rather than a fresh report.
      final personal = (data['personal'] as Map?) ?? {};
      await FirebaseFirestore.instance.collection('petAlerts').add({
        'type': 'lost',
        'source': 'adoption',
        'collarTagId': collarTagId,
        'linkedAdoptionId': adoptionId,
        'reporterId': uid,
        'petName': tag.name.isNotEmpty ? tag.name : animalName,
        'species': personal['species'],
        'breed': tag.breed,
        'colorMarkings': tag.colorMarkings,
        'photoUrls': tag.petImageUrl != null && tag.petImageUrl!.isNotEmpty
            ? [tag.petImageUrl]
            : [],
        'status': 'open',
        'createdAt': Timestamp.now(),
        'serverCreatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$animalName reported lost. You\'ll be notified here the moment their tag is scanned.'),
            backgroundColor: AppColors.greenrspwn,
          ),
        );
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => CollarIdTagCardScreen(
              tagData: CollarTagData.fromFirestore(
                {...tagDoc.data()!, ...update},
                tagDoc.id,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not report lost pet: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _promptNoLinkedTag(
      BuildContext context, {
        required String adoptionId,
        required String animalName,
        required Map<String, dynamic> data,
      }) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'No ID tag linked yet',
          style: GoogleFonts.tiltWarp(
              fontSize: 16, color: AppColors.textPrimary),
        ),
        content: Text(
          '$animalName doesn\'t have a registered collar/NFC ID tag linked '
              'to this adoption yet. Linking one gives the fastest path to '
              'reunification if $animalName ever goes missing — anyone who '
              'scans the tag can reach you directly.\n\nYou can still file '
              'a basic lost report now, or link a tag first for the full '
              'scan-and-chat reunification flow.',
          style:
          GoogleFonts.zain(fontSize: 13.5, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _fileBasicLostReportWithoutTag(
                context,
                adoptionId: adoptionId,
                animalName: animalName,
                data: data,
              );
            },
            child: Text('File Basic Report',
                style: GoogleFonts.zain(color: AppColors.textPrimary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CollarTagHomeScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: Text('Link ID Tag',
                style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _fileBasicLostReportWithoutTag(
      BuildContext context, {
        required String adoptionId,
        required String animalName,
        required Map<String, dynamic> data,
      }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final personal = (data['personal'] as Map?) ?? {};

      await FirebaseFirestore.instance.collection('petAlerts').add({
        'type': 'lost',
        // No verified tag on file yet — matching still has to fall back to
        // manual/heuristic review, same as a fresh report, so this is kept
        // distinguishable from the tag-verified 'adoption' source above.
        'source': 'adoption_no_tag',
        'linkedAdoptionId': adoptionId,
        'reporterId': uid,
        'petName': animalName,
        'species': personal['species'],
        'status': 'open',
        'createdAt': Timestamp.now(),
        'serverCreatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$animalName has been reported lost. Consider linking an ID tag for faster reunification.'),
            backgroundColor: AppColors.greenrspwn,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not file lost report: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }
}

class _MoreOptionsButton extends StatelessWidget {
  final VoidCallback onTap;
  const _MoreOptionsButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      right: 10,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.more_vert,
              size: 26, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _DialogOptionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  const _DialogOptionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: enabled ? onTap : null,
        icon: Icon(
          icon,
          size: 18,
          color: enabled
              ? AppColors.textPrimary
              : AppColors.textPrimary.withOpacity(0.4),
        ),
        label: Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled
                ? AppColors.textPrimary
                : AppColors.textPrimary.withOpacity(0.4),
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: enabled ? AppColors.greenrspwn : AppColors.slaterspwn,
            width: 1.5,
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }
}

class _BackHeader extends StatelessWidget {
  final VoidCallback onTap;
  const _BackHeader({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 6,
      left: 10,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: AppColors.background,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.chevron_left,
              size: 26, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

// Post-Adoption Check-in form
class PostAdoptionCheckinForm extends StatefulWidget {
  final String adoptionId;
  final String animalName;
  final String followUpId;
  final int sequenceNumber;
  final DateTime dueDate;

  const PostAdoptionCheckinForm({
    super.key,
    required this.adoptionId,
    required this.animalName,
    required this.followUpId,
    required this.sequenceNumber,
    required this.dueDate,
  });

  @override
  State<PostAdoptionCheckinForm> createState() =>
      _PostAdoptionCheckinFormState();
}

class _PostAdoptionCheckinFormState extends State<PostAdoptionCheckinForm> {
  String? _howIsPet;
  final Set<String> _healthConcerns = {};
  final _otherHealthCtrl = TextEditingController();
  String? _vaccinated;
  final List<File> _images = [];
  final _notesCtrl = TextEditingController();
  final _picker = ImagePicker();
  bool _isSubmitting = false;

  static const _healthOptions = [
    'None',
    'Illness',
    'Injury',
    'Appetite issues',
    'Behavioral issues',
    'Other',
  ];

  @override
  void dispose() {
    _otherHealthCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _toggleHealth(String option) {
    setState(() {
      if (option == 'None') {
        _healthConcerns
          ..clear()
          ..add('None');
      } else {
        _healthConcerns.remove('None');
        if (_healthConcerns.contains(option)) {
          _healthConcerns.remove(option);
        } else {
          _healthConcerns.add(option);
        }
      }
    });
  }

  Future<void> _addImage() async {
    if (_images.length >= 5) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (picked != null) setState(() => _images.add(File(picked.path)));
  }

  void _showSnack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : AppColors.greenrspwn,
      ),
    );
  }

  Future<void> _submit() async {
    if (_howIsPet == null) {
      _showSnack('Please tell us how the pet is doing.');
      return;
    }
    if (_healthConcerns.isEmpty) {
      _showSnack('Please select any health concerns (or None).');
      return;
    }
    if (_vaccinated == null) {
      _showSnack('Please answer the vaccinations question.');
      return;
    }
    if (_images.isEmpty) {
      _showSnack('Please upload at least 1 image.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final urls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final ref = FirebaseStorage.instance.ref(
            'adoptions/${widget.adoptionId}/checkins/${widget.followUpId}/img_$i.jpg');
        await ref.putFile(_images[i]);
        urls.add(await ref.getDownloadURL());
      }

      final adoptionRef = FirebaseFirestore.instance
          .collection('adoptions')
          .doc(widget.adoptionId);
      final label = 'Follow-up ${widget.sequenceNumber}';
      final submittedAt = Timestamp.now();

      await adoptionRef
          .collection('checkins')
          .doc(widget.followUpId)
          .set({
        'label': label,
        'dueDate': Timestamp.fromDate(widget.dueDate),
        'howIsPetDoing': _howIsPet,
        'healthConcerns': _healthConcerns.toList(),
        'healthConcernsOther': _otherHealthCtrl.text.trim(),
        'vaccinated': _vaccinated,
        'images': urls,
        'notes': _notesCtrl.text.trim(),
        'submittedBy': FirebaseAuth.instance.currentUser?.uid,
        'submittedAt': submittedAt,
      });

      // Admin-facing scheduling/status record — see
      // core/models/adoption/follow_up_record.dart. Doc id matches the
      // checkins doc above 1:1; never overwrites the earlier `scheduled`/
      // `reminderSent` status history, just advances it to `submitted`.
      await adoptionRef.collection('followUps').doc(widget.followUpId).update({
        'status': 'submitted',
        'submittedAt': submittedAt,
      });

      await adoptionRef.update({
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': '$label submitted.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnack('Check-in submitted. Thank you!', error: false);
      }
    } catch (e) {
      _showSnack('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.chevron_left,
                    size: 30, color: AppColors.textPrimary),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Post-Adoption',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Follow-up ${widget.sequenceNumber} - ${_formatDate(widget.dueDate)}',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),

                    _RadioBlock(
                      label: 'How is the pet doing?',
                      value: _howIsPet,
                      options: const ['Excellent', 'Good', 'Fair', 'Need Assistance'],
                      onChanged: (v) => setState(() => _howIsPet = v),
                    ),
                    const SizedBox(height: 18),

                    Text(
                      'Health concerns?',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    ..._healthOptions.map((o) {
                      return InkWell(
                        onTap: () => _toggleHealth(o),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _healthConcerns.contains(o),
                                onChanged: (_) => _toggleHealth(o),
                                activeColor: AppColors.greenrspwn,
                                materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                o,
                                style: GoogleFonts.zain(
                                    fontSize: 14,
                                    color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (_healthConcerns.contains('Other')) ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: _otherHealthCtrl,
                        style: GoogleFonts.zain(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Please specify',
                          hintStyle: GoogleFonts.zain(fontSize: 13),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.slaterspwn),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    _RadioBlock(
                      label: 'Vaccinations?',
                      value: _vaccinated,
                      options: const ['Yes', 'No', 'Scheduled'],
                      onChanged: (v) => setState(() => _vaccinated = v),
                    ),
                    const SizedBox(height: 18),

                    Text(
                      'Image Upload (minimum 1, maximum 5)',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    _ImageGrid(images: _images, onAdd: _addImage,
                        onRemove: (i) => setState(() => _images.removeAt(i))),

                    const SizedBox(height: 18),
                    Text(
                      'Notes',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      style: GoogleFonts.zain(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Anything else you\'d like to share?',
                        hintStyle: GoogleFonts.zain(fontSize: 13),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: AppColors.slaterspwn),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    _PrimaryBtn(
                      label: _isSubmitting ? 'Submitting...' : 'Submit',
                      onTap: _isSubmitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Adoption Return form
class AdoptionReturnForm extends StatefulWidget {
  final String adoptionId;
  final String animalName;
  final String adopterName;
  final DateTime? adoptionDate;

  const AdoptionReturnForm({
    super.key,
    required this.adoptionId,
    required this.animalName,
    required this.adopterName,
    required this.adoptionDate,
  });

  @override
  State<AdoptionReturnForm> createState() => _AdoptionReturnFormState();
}

class _AdoptionReturnFormState extends State<AdoptionReturnForm> {
  String? _reason;
  final _otherReasonCtrl = TextEditingController();
  String? _urgency;
  final _explanationCtrl = TextEditingController();
  final List<File> _images = [];
  final _picker = ImagePicker();
  bool _confirmAccurate = false;
  bool _confirmCare = false;
  bool _isSubmitting = false;

  static const _reasonOptions = [
    'Financial Difficulties',
    'Housing Restrictions',
    'Allergies or Health Concerns',
    'Conflict with Existing Pets',
    'Behavioral Challenges',
    'Change in Personal Circumstances',
    'Other',
  ];

  static const _urgencyOptions = [
    'Within 24 Hours',
    'Within 1 Week',
    'Within 2 Weeks',
    'Within 1 Month',
  ];

  @override
  void dispose() {
    _otherReasonCtrl.dispose();
    _explanationCtrl.dispose();
    super.dispose();
  }

  Future<void> _addImage() async {
    if (_images.length >= 5) return;
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (picked != null) setState(() => _images.add(File(picked.path)));
  }

  void _showSnack(String msg, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : AppColors.greenrspwn,
      ),
    );
  }

  Future<void> _submit() async {
    if (_reason == null) {
      _showSnack('Please select a return reason.');
      return;
    }
    if (_reason == 'Other' && _otherReasonCtrl.text.trim().isEmpty) {
      _showSnack('Please specify the reason.');
      return;
    }
    if (_urgency == null) {
      _showSnack('Please select a retrieval urgency.');
      return;
    }
    if (_explanationCtrl.text.trim().isEmpty) {
      _showSnack('Please provide a detailed explanation.');
      return;
    }
    if (_images.isEmpty) {
      _showSnack('Please upload at least 1 image.');
      return;
    }
    if (!_confirmAccurate || !_confirmCare) {
      _showSnack('Please confirm both statements before submitting.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final urls = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final ref = FirebaseStorage.instance.ref(
            'adoptions/${widget.adoptionId}/returnRequest/img_$i.jpg');
        await ref.putFile(_images[i]);
        urls.add(await ref.getDownloadURL());
      }

      // Routed through AdoptionApplicationRepository.requestReturn so this
      // lands in returnRequest.status (spec's own state machine) instead of
      // overloading the top-level AdoptionStatus field — the application
      // stays "adopted" throughout the whole return process.
      await AdoptionApplicationRepository().requestReturn(
        applicationId: widget.adoptionId,
        reason: _reason!,
        reasonOther: _reason == 'Other' ? _otherReasonCtrl.text.trim() : null,
        urgency: _urgency!,
        explanation: _explanationCtrl.text.trim(),
        images: urls,
        actorUid: FirebaseAuth.instance.currentUser?.uid ?? '',
      );

      if (mounted) {
        Navigator.pop(context);
        _showSnack('Return request submitted.', error: false);
      }
    } catch (e) {
      _showSnack('Failed to submit: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.chevron_left,
                    size: 30, color: AppColors.textPrimary),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Return',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: _ReadonlyField(
                              label: 'Name', value: widget.adopterName),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _ReadonlyField(
                              label: 'Name', value: widget.animalName),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ReadonlyField(
                      label: 'Adoption Date',
                      value: widget.adoptionDate != null
                          ? _formatDate(widget.adoptionDate!)
                          : '-',
                    ),
                    const SizedBox(height: 18),

                    _RadioBlock(
                      label: 'Return Reason?',
                      value: _reason,
                      options: _reasonOptions,
                      onChanged: (v) => setState(() => _reason = v),
                    ),
                    if (_reason == 'Other') ...[
                      const SizedBox(height: 4),
                      TextField(
                        controller: _otherReasonCtrl,
                        style: GoogleFonts.zain(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Please specify',
                          hintStyle: GoogleFonts.zain(fontSize: 13),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: AppColors.slaterspwn),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),

                    _RadioBlock(
                      label: 'Retrieval Urgency?',
                      value: _urgency,
                      options: _urgencyOptions,
                      onChanged: (v) => setState(() => _urgency = v),
                    ),
                    const SizedBox(height: 18),

                    Text(
                      'Detailed Explanation',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _explanationCtrl,
                      maxLines: 3,
                      style: GoogleFonts.zain(fontSize: 14),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                          const BorderSide(color: AppColors.slaterspwn),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    Text(
                      'Image Upload (minimum 1, maximum 5)',
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 8),
                    _ImageGrid(
                        images: _images,
                        onAdd: _addImage,
                        onRemove: (i) => setState(() => _images.removeAt(i))),

                    const SizedBox(height: 18),
                    _ConfirmCheckbox(
                      value: _confirmAccurate,
                      label: 'I confirm that the information provided is accurate.',
                      onChanged: (v) => setState(() => _confirmAccurate = v),
                    ),
                    _ConfirmCheckbox(
                      value: _confirmCare,
                      label:
                      'I will continue providing reasonable care for the animal until further instructions are provided.',
                      onChanged: (v) => setState(() => _confirmCare = v),
                    ),

                    const SizedBox(height: 24),
                    _PrimaryBtn(
                      label: _isSubmitting ? 'Submitting...' : 'Submit',
                      onTap: _isSubmitting ? null : _submit,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Return Request Approved page
class ReturnApprovedPage extends StatefulWidget {
  final String adoptionId;

  const ReturnApprovedPage({super.key, required this.adoptionId});

  @override
  State<ReturnApprovedPage> createState() => _ReturnApprovedPageState();
}

class _ReturnApprovedPageState extends State<ReturnApprovedPage> {
  bool _isSaving = false;

  DocumentReference get _adoptionRef => FirebaseFirestore.instance
      .collection('adoptions')
      .doc(widget.adoptionId);

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.redAccent : AppColors.greenrspwn,
      ),
    );
  }

  // Rescheduling the retrieval is now an admin-only action (Return Details'
  // own "Reschedule" button, spec §18) — the adopter's role here is to view
  // and acknowledge the admin-set schedule, not propose a different one.
  Future<void> _accept() async {
    setState(() => _isSaving = true);
    try {
      await _adoptionRef.update({
        'returnRequest.confirmedByAdopter': true,
        'returnRequest.confirmedByAdopterAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Adopter confirmed the pick-up schedule.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      _showSnack('Failed to confirm: $e', error: true);
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: _adoptionRef.snapshots(),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.greenrspwn),
              );
            }
            final data = snap.data!.data() as Map<String, dynamic>?;
            if (data == null) {
              return const Center(child: Text('Return record not found.'));
            }

            final returnRequest = ReturnRequest.fromMap(data['returnRequest'] as Map<String, dynamic>?);
            final pickupDate = returnRequest?.retrievalDateTime;
            final pickupAddress = returnRequest?.retrievalAddress;
            final isConfirmed = returnRequest?.confirmedByAdopter == true;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.chevron_left,
                              size: 28, color: AppColors.textPrimary),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          'Return Request',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tiltWarp(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        const SizedBox(height: 32),
                        Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            color: AppColors.textPrimary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check,
                              size: 38, color: AppColors.background),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Your return request has been approved.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tiltWarp(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Your pet\'s pickup has been scheduled. Please review the date and time below. A representative from the organization will arrive as scheduled to collect the pet.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.yellowrspwn.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: pickupDate != null
                              ? Row(
                            children: [
                              const Icon(Icons.event_available,
                                  color: AppColors.greenrspwn,
                                  size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pick Up Visit  ·  ${_formatDate(pickupDate)} ${pickupDate.hour.toString().padLeft(2, '0')}:${pickupDate.minute.toString().padLeft(2, '0')}'
                                  '${pickupAddress != null && pickupAddress.isNotEmpty ? '  ·  $pickupAddress' : ''}',
                                  style: GoogleFonts.zain(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          )
                              : Text(
                            'Pick up details are being finalized.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.zain(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
                  child: isConfirmed
                      ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 18, color: AppColors.greenrspwn),
                      const SizedBox(width: 6),
                      Text(
                        'Pick-up schedule confirmed',
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  )
                      : _PrimaryBtn(
                    label: _isSaving ? 'Please wait...' : 'Accept',
                    onTap: (_isSaving || pickupDate == null) ? null : _accept,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Home-screen "Post Adoption
class PostAdoption extends StatelessWidget {
  const PostAdoption({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return _emptyState('Sign in to see your adopted pets.');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.adopterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn),
            ),
          );
        }

        final matching = (snap.data?.docs ?? []).where((d) {
          final data = d.data() as Map<String, dynamic>;
          // AdoptionStatus.adopted.queryValues also covers the legacy
          // 'completed'/'return_requested'/'return_approved' strings older
          // adoptions may still carry — the application stays "adopted"
          // through the whole post-adoption/return lifecycle now (see
          // ReturnRequest.status for the actual return sub-state).
          return AdoptionStatus.adopted.queryValues.contains(data['status'] as String?);
        }).toList();

        // Keep only the most recent adoption record per animal, so the same
        // pet can't show up twice
        final latestByAnimal = <String, QueryDocumentSnapshot>{};
        for (final doc in matching) {
          final data = doc.data() as Map<String, dynamic>;
          final personal = (data['personal'] as Map?) ?? {};
          final animalKey =
          (personal['animalId'] ?? personal['animalName'] ?? doc.id)
              .toString();

          final existing = latestByAnimal[animalKey];
          if (existing == null) {
            latestByAnimal[animalKey] = doc;
            continue;
          }

          final existingData = existing.data() as Map<String, dynamic>;
          final existingDate = extractAdoptionCompletedDate(existingData) ??
              DateTime(0);
          final thisDate = extractAdoptionCompletedDate(data) ?? DateTime(0);
          if (thisDate.isAfter(existingDate)) {
            latestByAnimal[animalKey] = doc;
          }
        }

        final docs = latestByAnimal.values.toList()
          ..sort((a, b) {
            final aDate = extractAdoptionCompletedDate(
                a.data() as Map<String, dynamic>) ??
                DateTime(0);
            final bDate = extractAdoptionCompletedDate(
                b.data() as Map<String, dynamic>) ??
                DateTime(0);
            return bDate.compareTo(aDate);
          });

        if (docs.isEmpty) {
          return _emptyState('No adopted pets yet.');
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data() as Map<String, dynamic>;
            final personal = (data['personal'] as Map?) ?? {};
            final animalName = personal['animalName'] as String? ?? 'Pet';
            final adoptedDate = extractAdoptionCompletedDate(data);

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PostAdoptionMonitoringPage(adoptionId: doc.id),
                  ),
                );
              },
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.slaterspwn,
                      blurRadius: 1,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.pets, color: AppColors.greenrspwn),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            animalName,
                            style: GoogleFonts.tiltWarp(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          if (adoptedDate != null)
                            Text(
                              'Adopted ${_formatDate(adoptedDate)}',
                              style: GoogleFonts.zain(
                                  fontSize: 12,
                                  color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        color: AppColors.textSecondary),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.slaterspwn,
              blurRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.slaterspwn),
        ),
      ),
    );
  }
}

// Shared small widgets
class _ReadonlyField extends StatelessWidget {
  final String label;
  final String value;
  const _ReadonlyField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
      ],
    );
  }
}

class _RadioBlock extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _RadioBlock({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 2),
        ...options.map((o) {
          return InkWell(
            onTap: () => onChanged(o),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Radio<String>(
                    value: o,
                    groupValue: value,
                    onChanged: onChanged,
                    activeColor: AppColors.greenrspwn,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      o,
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _ConfirmCheckbox extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const _ConfirmCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppColors.greenrspwn,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  label,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<File> images;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  const _ImageGrid({
    required this.images,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ...List.generate(images.length, (i) {
          return Stack(
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.greenrspwn, width: 1.2),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.file(images[i], fit: BoxFit.cover),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () => onRemove(i),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                      color: AppColors.textPrimary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close,
                        size: 12, color: AppColors.background),
                  ),
                ),
              ),
            ],
          );
        }),
        if (images.length < 5)
          InkWell(
            onTap: onAdd,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.greenrspwn.withOpacity(0.6), width: 1.2),
              ),
              child: const Center(
                child: Icon(Icons.add, size: 26, color: AppColors.greenrspwn),
              ),
            ),
          ),
      ],
    );
  }
}

class _PrimaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor:
          onTap == null ? AppColors.slaterspwn : AppColors.yellowrspwn,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.tiltWarp(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}