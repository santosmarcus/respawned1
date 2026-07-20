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


// Check-in interval schedule
// 1st month  - every week      (4 check-ins)
// 2nd month  - every 2 weeks   (2 check-ins)
// Months 3-6 - every month     (4 check-ins)

class Checkpoint {
  final String id;
  final String label;
  final DateTime dueDate;
  const Checkpoint(this.id, this.label, this.dueDate);

  // Each check-in stays open for a 3-day window starting on its due date,
  // instead of a single-day deadline.
  static const int windowDays = 3;

  DateTime get windowEnd => dueDate.add(const Duration(days: windowDays));

  bool isOpen(DateTime now) => !dueDate.isAfter(now);

  bool isWithinWindow(DateTime now) =>
      isOpen(now) && !now.isAfter(windowEnd);

  bool isOverdue(DateTime now) => isOpen(now) && now.isAfter(windowEnd);
}

DateTime _addMonths(DateTime d, int months) {
  final totalMonths = d.month - 1 + months;
  final year = d.year + totalMonths ~/ 12;
  final month = totalMonths % 12 + 1;
  final lastDayOfMonth = DateTime(year, month + 1, 0).day;
  final day = d.day > lastDayOfMonth ? lastDayOfMonth : d.day;
  return DateTime(year, month, day);
}

List<Checkpoint> buildCheckinSchedule(DateTime adoptionDate) {
  final month1 = _addMonths(adoptionDate, 1);
  return [
    Checkpoint('wk1', 'Week 1 Check-in',
        adoptionDate.add(const Duration(days: 7))),
    Checkpoint('wk2', 'Week 2 Check-in',
        adoptionDate.add(const Duration(days: 14))),
    Checkpoint('wk3', 'Week 3 Check-in',
        adoptionDate.add(const Duration(days: 21))),
    Checkpoint('m1', 'Month 1 Check-in', month1),
    Checkpoint(
        'm2a', 'Month 2 Check-in', month1.add(const Duration(days: 14))),
    Checkpoint(
        'm2b', 'Month 2 Check-in', month1.add(const Duration(days: 28))),
    Checkpoint('m3', 'Month 3 Check-in', _addMonths(adoptionDate, 3)),
    Checkpoint('m4', 'Month 4 Check-in', _addMonths(adoptionDate, 4)),
    Checkpoint('m5', 'Month 5 Check-in', _addMonths(adoptionDate, 5)),
    Checkpoint('m6', 'Month 6 Check-in', _addMonths(adoptionDate, 6)),
  ];
}

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

class _PickupSchedule {
  final DateTime date;
  final String time;
  const _PickupSchedule(this.date, this.time);
}

const List<String> _pickupTimeSlots = [
  '9:00 AM',
  '10:00 AM',
  '11:00 AM',
  '1:00 PM',
  '2:00 PM',
  '3:00 PM',
  '4:00 PM',
];

Future<_PickupSchedule?> _pickPickupDateTime(
    BuildContext context, {
      DateTime? initialDate,
      String? initialTime,
    }) {
  return showModalBottomSheet<_PickupSchedule>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _PickupSchedulerSheet(
      initialDate: initialDate,
      initialTime: initialTime,
    ),
  );
}

class _PickupSchedulerSheet extends StatefulWidget {
  final DateTime? initialDate;
  final String? initialTime;

  const _PickupSchedulerSheet({this.initialDate, this.initialTime});

  @override
  State<_PickupSchedulerSheet> createState() => _PickupSchedulerSheetState();
}

class _PickupSchedulerSheetState extends State<_PickupSchedulerSheet> {
  DateTime? _date;
  String? _time;

  @override
  void initState() {
    super.initState();
    _date = widget.initialDate;
    _time = widget.initialTime;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              'Select Pick-up Date & Time',
              style: GoogleFonts.tiltWarp(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // calendar
            Container(
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withOpacity(0.25),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.greenrspwn, width: 1.2),
              ),
              child: CalendarDatePicker(
                initialDate:
                _date ?? DateTime.now().add(const Duration(days: 2)),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 90)),
                onDateChanged: (picked) {
                  setState(() {
                    _date = picked;
                    _time = null;
                  });
                },
              ),
            ),

            const SizedBox(height: 16),

            Text(
              'Available times',
              style: GoogleFonts.tiltWarp(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            if (_date == null)
              Text(
                'Select a date above to see available times.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textPrimary),
              )
            else
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _pickupTimeSlots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final slot = _pickupTimeSlots[i];
                    final selected = _time == slot;
                    return GestureDetector(
                      onTap: () => setState(() => _time = slot),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.greenrspwn
                              : AppColors.background,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected
                                ? AppColors.greenrspwn
                                : AppColors.slaterspwn,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          slot,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

            // summary
            if (_date != null && _time != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.yellowrspwn.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_available,
                        color: AppColors.greenrspwn, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Pick Up Visit  ·  ${_formatDate(_date!)}  ·  $_time',
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
            ],

            const SizedBox(height: 20),
            _PrimaryBtn(
              label: 'Confirm',
              onTap: (_date == null || _time == null)
                  ? null
                  : () => Navigator.pop(
                  context, _PickupSchedule(_date!, _time!)),
            ),
          ],
        ),
      ),
    );
  }
}


// Post-Adoption Monitoring page
class PostAdoptionMonitoringPage extends StatelessWidget {
  final String adoptionId;

  const PostAdoptionMonitoringPage({super.key, required this.adoptionId});

  // ---------- for testing only!!
  Future<void> _approveReturn(BuildContext context, String adoptionId) async {
    final scheduled = await _pickPickupDateTime(context);
    if (scheduled == null || !context.mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(adoptionId)
          .update({
        'status': 'return_approved',
        'returnPickup': {
          'date': Timestamp.fromDate(scheduled.date),
          'time': scheduled.time,
          'scheduledAt': Timestamp.now(),
          'confirmedByAdopter': false,
        },
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Return request approved.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to approve return: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

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
            final isReturnRequested = data['status'] == 'return_requested';
            final isReturnApproved = data['status'] == 'return_approved';

            return StreamBuilder<QuerySnapshot>(
              stream: adoptionRef.collection('checkins').snapshots(),
              builder: (context, checkinSnap) {
                final submittedIds = <String>{
                  for (final d in checkinSnap.data?.docs ?? []) d.id
                };

                final schedule = adoptedDate != null
                    ? buildCheckinSchedule(adoptedDate)
                    : <Checkpoint>[];

                final now = DateTime.now();
                Checkpoint? currentDue;
                for (final c in schedule) {
                  if (!submittedIds.contains(c.id) && c.isOpen(now)) {
                    currentDue = c;
                    break;
                  }
                }
                final allDone = schedule.isNotEmpty &&
                    schedule.every((c) => submittedIds.contains(c.id));

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

                            // ---------- for testing only!! (simulates the
                            // organization approving a submitted return) ----
                            if (isReturnRequested) ...[
                              _SecondaryBtn(
                                label: 'Approve Return (test)',
                                onTap: () =>
                                    _approveReturn(context, adoptionId),
                              ),
                              const SizedBox(height: 6),
                            ],
                            // ---------- for testing only ^^^^

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

                            if (schedule.isEmpty)
                              Text(
                                'Your monitoring schedule will appear here once your adoption is finalized.',
                                style: GoogleFonts.zain(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              ),

                            ...schedule.map((c) {
                              final done = submittedIds.contains(c.id);
                              final isCurrent = currentDue?.id == c.id;
                              final overdue = !done && c.isOverdue(now);
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
                                            '${c.label} - ${_formatDate(c.dueDate)}',
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
                                              overdue
                                                  ? 'Overdue since ${_formatDate(c.windowEnd)}'
                                                  : 'Available until ${_formatDate(c.windowEnd)}',
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
                                          checkpoint: currentDue!,
                                        ),
                                  ),
                                );
                              },
                            ),
                            if (currentDue != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                currentDue.isOverdue(now)
                                    ? 'This check-in is overdue — please submit as soon as possible.'
                                    : 'Available until ${_formatDate(currentDue.windowEnd)} (${Checkpoint.windowDays}-day window).',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.zain(
                                  fontSize: 11,
                                  color: currentDue.isOverdue(now)
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
  final Checkpoint checkpoint;

  const PostAdoptionCheckinForm({
    super.key,
    required this.adoptionId,
    required this.animalName,
    required this.checkpoint,
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
            'adoptions/${widget.adoptionId}/checkins/${widget.checkpoint.id}/img_$i.jpg');
        await ref.putFile(_images[i]);
        urls.add(await ref.getDownloadURL());
      }

      final adoptionRef = FirebaseFirestore.instance
          .collection('adoptions')
          .doc(widget.adoptionId);

      await adoptionRef
          .collection('checkins')
          .doc(widget.checkpoint.id)
          .set({
        'label': widget.checkpoint.label,
        'dueDate': Timestamp.fromDate(widget.checkpoint.dueDate),
        'howIsPetDoing': _howIsPet,
        'healthConcerns': _healthConcerns.toList(),
        'healthConcernsOther': _otherHealthCtrl.text.trim(),
        'vaccinated': _vaccinated,
        'images': urls,
        'notes': _notesCtrl.text.trim(),
        'submittedBy': FirebaseAuth.instance.currentUser?.uid,
        'submittedAt': FieldValue.serverTimestamp(),
      });

      await adoptionRef.update({
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': '${widget.checkpoint.label} submitted.',
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
                      '${widget.checkpoint.label} - ${_formatDate(widget.checkpoint.dueDate)}',
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

      final adoptionRef = FirebaseFirestore.instance
          .collection('adoptions')
          .doc(widget.adoptionId);

      await adoptionRef.update({
        'returnRequest': {
          'reason': _reason,
          'reasonOther':
          _reason == 'Other' ? _otherReasonCtrl.text.trim() : null,
          'urgency': _urgency,
          'explanation': _explanationCtrl.text.trim(),
          'images': urls,
          'requestedBy': FirebaseAuth.instance.currentUser?.uid,
          'requestedAt': Timestamp.now(),
        },
        'status': 'return_requested',
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Return requested.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

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

  Future<void> _requestOtherDate(DateTime? currentDate, String? currentTime) async {
    final scheduled = await _pickPickupDateTime(
      context,
      initialDate: currentDate,
      initialTime: currentTime,
    );
    if (scheduled == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _adoptionRef.update({
        'returnPickup': {
          'date': Timestamp.fromDate(scheduled.date),
          'time': scheduled.time,
          'scheduledAt': Timestamp.now(),
          'confirmedByAdopter': false,
        },
        'statusHistory': FieldValue.arrayUnion([
          {
            'status':
            'Adopter requested a new pick-up date: ${_formatDate(scheduled.date)} ${scheduled.time}.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });
      if (mounted) {
        _showSnack('Your requested date has been sent to the organization.');
      }
    } catch (e) {
      _showSnack('Failed to request a new date: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _accept() async {
    setState(() => _isSaving = true);
    try {
      await _adoptionRef.update({
        'returnPickup.confirmedByAdopter': true,
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

            final pickup = (data['returnPickup'] as Map?) ?? {};
            final pickupTs = pickup['date'];
            final pickupDate =
            pickupTs is Timestamp ? pickupTs.toDate() : null;
            final pickupTime = pickup['time'] as String? ?? '';
            final isConfirmed = pickup['confirmedByAdopter'] == true;

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
                                  'Pick Up Visit  ·  ${_formatDate(pickupDate)}  ·  $pickupTime',
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
                        const SizedBox(height: 14),
                        GestureDetector(
                          onTap: _isSaving
                              ? null
                              : () =>
                              _requestOtherDate(pickupDate, pickupTime),
                          child: Text(
                            'Request Other Date',
                            style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              decoration: TextDecoration.underline,
                              decorationColor: AppColors.textPrimary,
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
                    onTap: _isSaving ? null : _accept,
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
          final status = data['status'];
          return status == 'completed' ||
              status == 'return_requested' ||
              status == 'return_approved';
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

class _SecondaryBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _SecondaryBtn({required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.greenrspwn, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}