import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';

class RescueRequest extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  // Set only when this request came from a specific admin assignment offer
  // (cases/{caseId}/transportAssignments/{assignmentId}, status 'pending') —
  // in that case Start Now / Decline go through
  // RescueCaseRepository.acceptAssignment/rejectAssignment instead of the
  // legacy direct case-field write, which is reserved for the open pickup
  // pool (a case nobody has been offered yet).
  final String? assignmentId;

  const RescueRequest({
    super.key,
    required this.caseId,
    required this.data,
    this.assignmentId,
  });

  @override
  State<RescueRequest> createState() =>
      _RescueRequestState();
}

class _RescueRequestState extends State<RescueRequest> {
  bool _isAccepting = false;
  bool _isDeclining = false;

  Future<void> _startNow() async {
    setState(() => _isAccepting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data();
      final riderName =
      '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
          .trim();

      final assignmentId = widget.assignmentId;
      if (assignmentId != null) {
        // A real admin-offered assignment — accept the specific offer so
        // the admin's Assign Rider screen (which listens on this exact
        // assignment doc) sees the acceptance, and the case's own
        // status/assignedVolunteer* fields get updated the same way the
        // legacy flow below always did.
        final verification =
        userData?['transporterVerification'] as Map<String, dynamic>?;
        await RescueCaseRepository().acceptAssignment(
          caseId: widget.caseId,
          assignmentId: assignmentId,
          riderId: uid,
          riderName: riderName.isEmpty ? 'A pet transporter' : riderName,
          riderVehicle: (verification?['vehicleType'] as String?) ?? '',
          riderPlate: (verification?['licensePlate'] as String?) ?? '',
        );
      } else {
        await FirebaseFirestore.instance
            .collection('cases')
            .doc(widget.caseId)
            .update({
          'status': 'accepted',
          'assignedVolunteerId': uid,
          'assignedVolunteerName':
          riderName.isEmpty ? (widget.data['assignedVolunteerName'] ?? '') : riderName,
          'statusHistory': FieldValue.arrayUnion([
            {
              'status': 'Rider accepted the rescue request.',
              'timestamp': Timestamp.now(),
            }
          ]),
        });
      }

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TransitProgressPage(caseId: widget.caseId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  Future<void> _decline(List<String> reasons) async {
    setState(() => _isDeclining = true);
    try {
      final assignmentId = widget.assignmentId;
      if (assignmentId != null) {
        // Reject the specific offer — the admin's Assign Rider screen picks
        // this up via its own listener and lets them choose another
        // transporter. Deliberately doesn't touch the case's own status:
        // it was never changed to offer this rider in the first place.
        await RescueCaseRepository().rejectAssignment(
          caseId: widget.caseId,
          assignmentId: assignmentId,
          reason: reasons.join('; '),
        );
        if (mounted) Navigator.pop(context);
        return;
      }

      final uid = FirebaseAuth.instance.currentUser!.uid;
      final caseRef =
      FirebaseFirestore.instance.collection('cases').doc(widget.caseId);
      final snap = await caseRef.get();
      final currentStatus = (snap.data() as Map<String, dynamic>?)?['status'];
      final wasAssignedToMe =
          (snap.data() as Map<String, dynamic>?)?['assignedVolunteerId'] == uid;

      final reasonText = reasons.join('; ');

      final updateData = <String, dynamic>{
        'declinedBy': FieldValue.arrayUnion([uid]),
        'declineReasons': FieldValue.arrayUnion([
          {
            'riderId': uid,
            'reasons': reasons,
            'timestamp': Timestamp.now(),
          }
        ]),
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': reasonText.isEmpty
                ? 'A rider declined this request.'
                : 'A rider declined this request: $reasonText.',
            'timestamp': Timestamp.now(),
          }
        ]),
      };

      if (wasAssignedToMe && currentStatus == 'assigned') {
        updateData['status'] = 'pending';
        updateData['assignedVolunteerId'] = null;
        updateData['assignedVolunteerName'] = null;
      }

      await caseRef.update(updateData);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to decline request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeclining = false);
    }
  }

  static const _declineReasonOptions = [
    'Already assigned to another pickup',
    'Pickup/Drop off location is too far',
    'Insufficient equipment (crate, leash, medical supplies)',
    'Capacity is full',
    'Total transaction time conflicts with schedule',
    'Road closure or heavy traffic prevents timely transit',
  ];

  Future<void> _showDeclineReasonSheet() async {
    final selected = <String>{};
    bool otherChecked = false;
    final otherController = TextEditingController();
    String? errorText;

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 12,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Decline Reason',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    for (final reason in _declineReasonOptions)
                      _DeclineReasonCheckbox(
                        label: reason,
                        value: selected.contains(reason),
                        onChanged: (v) => setModalState(() {
                          if (v == true) {
                            selected.add(reason);
                          } else {
                            selected.remove(reason);
                          }
                        }),
                      ),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Checkbox(
                            value: otherChecked,
                            side: const BorderSide(
                                color: AppColors.textPrimary, width: 1.5),
                            activeColor: AppColors.textPrimary,
                            materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                            onChanged: (v) => setModalState(
                                    () => otherChecked = v ?? false),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text('Other:',
                                    style: GoogleFonts.zain(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                              ),
                              if (otherChecked)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: TextField(
                                    controller: otherController,
                                    style: GoogleFonts.zain(fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: 'Please specify',
                                      hintStyle: GoogleFonts.zain(
                                          fontSize: 13,
                                          color: AppColors.textSecondary),
                                      contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius:
                                        BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: AppColors.slaterspwn),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(errorText!,
                            style: GoogleFonts.zain(
                                fontSize: 12, color: Colors.redAccent)),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.background,
                          side: BorderSide(
                              color: AppColors.slaterspwn, width: 1),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        onPressed: () {
                          final finalReasons = [...selected];
                          if (otherChecked &&
                              otherController.text.trim().isNotEmpty) {
                            finalReasons
                                .add('Other: ${otherController.text.trim()}');
                          }
                          if (finalReasons.isEmpty) {
                            setModalState(() => errorText =
                            'Please select or specify at least one reason.');
                            return;
                          }
                          Navigator.pop(ctx, finalReasons);
                        },
                        child: Text(
                          'Confirm',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    otherController.dispose();

    if (result != null && result.isNotEmpty) {
      _decline(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final urgency = d['urgency'] ?? '';
    final address = d['address'] ?? '';
    // vetClinicAddress is the admin's actual Select Clinic choice; dropoff*
    // is normally mirrored from it (see RescueCaseRepository.assignClinic),
    // but this fallback still shows the right clinic for any case assigned
    // before that mirroring existed. Deliberately never falls back further
    // to the pickup address — showing the pickup pin as the "drop off"
    // would misrepresent "no clinic assigned yet" as an actual destination.
    final rawDropoffAddress =
    (d['dropoffAddress'] as String?)?.trim().isNotEmpty == true
        ? d['dropoffAddress'] as String
        : (d['vetClinicAddress'] as String?)?.trim();
    final dropoffAddress = (rawDropoffAddress == null || rawDropoffAddress.isEmpty)
        ? 'Clinic not yet assigned'
        : rawDropoffAddress;
    final condition = d['condition'] ?? '';
    final animalType = d['animalType'] ?? '';
    final photoUrls = List<String>.from(d['photoUrls'] ?? []);
    // A pending admin offer (widget.assignmentId != null) leaves the
    // case's own raw status at 'accepted' while awaiting THIS rider's
    // response — that must never read as "already accepted" here.
    // 'assigned' is the status acceptAssignment() actually sets once
    // accepted, so it counts as already-accepted too.
    final alreadyAccepted = widget.assignmentId == null &&
        (d['status'] == 'assigned' ||
            d['status'] == 'accepted' ||
            d['status'] == 'ongoing');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header banner
          Container(
            width: double.infinity,
            color: AppColors.textPrimary,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.background),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Rescue Now',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.background,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Text(
                    '~4KM from you',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.background.withOpacity(0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_shipping_outlined,
                              size: 16, color: AppColors.background),
                          const SizedBox(width: 6),
                          Text('Transport',
                              style: GoogleFonts.zain(
                                  fontSize: 13, color: AppColors.background)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      if (urgency.toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: urgency == 'Critical'
                                ? Colors.red
                                : AppColors.yellowrspwn,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            urgency,
                            style: GoogleFonts.zain(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle_outlined,
                          size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(address,
                            style: GoogleFonts.zain(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(dropoffAddress,
                            style: GoogleFonts.zain(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Text('Case Media',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 10),

                  photoUrls.isEmpty
                      ? Row(
                    children: List.generate(
                      2,
                          (i) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.textPrimary, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.image_outlined,
                              color: AppColors.slaterspwn),
                        ),
                      ),
                    ),
                  )
                      : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: photoUrls.map((url) {
                      return GestureDetector(
                        onTap: () => _showFullImage(context, url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            url,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, _, __) => Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: AppColors.slaterspwn,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  Text('Type of Animal',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(animalType,
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textPrimary)),

                  const SizedBox(height: 16),

                  if (condition.toString().isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.message_outlined,
                            size: 16, color: AppColors.textPrimary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Found in $condition',
                            style: GoogleFonts.zain(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Start now / already accepted footer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: alreadyAccepted || _isAccepting || _isDeclining
                        ? null
                        : _startNow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                      elevation: 0,
                    ),
                    child: _isAccepting
                        ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.textPrimary),
                    )
                        : Text(
                      alreadyAccepted ? 'Already Accepted' : 'Start now',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.textPrimary),
                    ),
                  ),
                ),
                if (!alreadyAccepted) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _isAccepting || _isDeclining
                          ? null
                          : _showDeclineReasonSheet,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.yellowrspwn, width: 1.5),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: _isDeclining
                          ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: AppColors.textPrimary),
                      )
                          : Text(
                        'Decline',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 16, color: AppColors.textPrimary),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeclineReasonCheckbox extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool?> onChanged;

  const _DeclineReasonCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Checkbox(
                value: value,
                side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                activeColor: AppColors.textPrimary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: onChanged,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  label,
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textPrimary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}