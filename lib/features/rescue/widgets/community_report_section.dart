import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/geo.dart';
import 'package:respawnd1/features/collartag/lost_pet_location_picker.dart';

/// Community sighting-update section — "Animal still here" / "Animal
/// moved" / "Animal rescued" / "No animal present", with an optional photo,
/// comment, and (for "moved") a new location. Writes to the existing
/// `cases/{caseId}/communityReports` subcollection and appends a matching
/// `activityLogs` entry — the single shared implementation for every
/// screen that needs this (reporter Track Case, Community Adoption
/// tracking), replacing what used to be a private class copied wholesale
/// between them.
///
/// Deliberately never touches the case's own `status` — submitting a
/// sighting report is purely additive information, never an automatic
/// close/complete of the case (a Community-Adoption-eligible case in
/// particular must stay open until its own completion rule is met, not
/// because someone reported "still here"/"moved").
class CommunityReportSection extends StatefulWidget {
  final String caseId;
  const CommunityReportSection({super.key, required this.caseId});

  @override
  State<CommunityReportSection> createState() => _CommunityReportSectionState();
}

class _CommunityReportSectionState extends State<CommunityReportSection> {
  bool _sectionExpanded = false;
  bool _expanded = false;
  String? _selectedType;
  XFile? _pickedImage;
  bool _submitting = false;
  final _commentController = TextEditingController();
  final _picker = ImagePicker();

  // Community Location Validation spec §4 — a "moved" update is only valid
  // once the user has confirmed a real map pin (via LastSeenLocationPicker,
  // the same shared picker collar-tag lost-pet reports already use), never
  // from freeform typed text. Null means no location has been confirmed yet.
  double? _pickedLat;
  double? _pickedLng;
  String? _pickedAddress;

  /// Beyond this distance from the case's original reported location, the
  /// user must explicitly confirm the new pin rather than have it accepted
  /// silently — animals/reports can legitimately move far, so this is a
  /// confirmation, never an automatic rejection.
  static const double _farMoveThresholdKm = 5.0;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _reportsRef => FirebaseFirestore
      .instance
      .collection('cases')
      .doc(widget.caseId)
      .collection('communityReports');

  Future<void> _openLocationPicker() async {
    // Compare against the case's own original lat/lng (its Rescue Report
    // location) so "unusually far" is judged against where the animal was
    // first reported, not a previous community update.
    double? originalLat;
    double? originalLng;
    try {
      final caseDoc = await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .get();
      originalLat = (caseDoc.data()?['lat'] as num?)?.toDouble();
      originalLng = (caseDoc.data()?['lng'] as num?)?.toDouble();
    } catch (_) {
      // Falls through with nulls — the far-move confirmation is simply
      // skipped rather than blocking the picker from opening at all.
    }

    if (!mounted) return;
    final picked = await Navigator.push<PickedLostLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => const LastSeenLocationPicker(
          title: 'Where is the animal now?',
          instructionText:
              'Tap anywhere on the map to drop a pin, or search an address below. This becomes the animal\'s new known location.',
          pinLabel: 'New location',
          confirmLabel: 'Confirm New Location',
        ),
      ),
    );
    if (picked == null || !mounted) return;

    if (originalLat != null && originalLng != null) {
      final distanceKm = haversineDistanceKm(
        originalLat,
        originalLng,
        picked.lat,
        picked.lng,
      );
      if (distanceKm > _farMoveThresholdKm) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text('Confirm New Location'),
            content: const Text(
              "This location is far from the animal's last known position. Confirm that the new pin is correct.",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
        // Keeps the previously-confirmed location (if any) untouched when
        // the admin backs out — never silently applies an unconfirmed pin.
        if (confirmed != true) return;
      }
    }

    if (!mounted) return;
    setState(() {
      _pickedLat = picked.lat;
      _pickedLng = picked.lng;
      _pickedAddress = picked.address;
    });
  }

  String _typeLabel(String? t) => switch (t) {
    'still_here' => 'Animal still here',
    'moved' => 'Animal moved',
    'rescued' => 'Animal rescued',
    'no_animal' => 'No animal present',
    _ => 'Update',
  };

  String _typeIconAsset(String? t) => switch (t) {
    'still_here' => 'assets/icons/animalstillhere.png',
    'moved' => 'assets/icons/animalmoved.png',
    'rescued' => 'assets/icons/animalrescued.png',
    'no_animal' => 'assets/icons/noanimal.png',
    _ => 'assets/icons/info.png',
  };

  String _typeDescription(String? t) => switch (t) {
    'still_here' =>
      'Upload a recent photo to confirm the animal is still at the reported location.',
    'moved' =>
      'The animal is no longer at the original location. Upload a recent photo and share the new location so rescuers can keep monitoring safely.',
    'rescued' =>
      'This animal has already been rescued by a rescuer, bystander, or partner organization. Add a photo or other proof to help verify the report.',
    'no_animal' =>
      'No animal was found at the reported location. Add a recent photo of the area to confirm the report may no longer be accurate.',
    _ => '',
  };

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file != null && mounted) {
      setState(() => _pickedImage = file);
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null || _submitting) return;
    // Community Location Validation spec §4 — requires an actually
    // confirmed map pin (lat/lng set by _openLocationPicker), never just
    // non-empty freeform text. Reject invalid/unresolved coordinates by
    // simply not allowing submission — nothing is written, so the
    // previous location (if any) is untouched.
    if (_selectedType == 'moved' &&
        (_pickedLat == null || _pickedLng == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select the new location on the map.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final name =
          '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
              .trim();

      final reportRef = _reportsRef.doc();

      String? photoUrl;
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance.ref().child(
          'cases/${widget.caseId}/communityReports/${reportRef.id}.jpg',
        );
        await ref.putFile(
          File(_pickedImage!.path),
          SettableMetadata(contentType: 'image/jpeg'),
        );
        photoUrl = await ref.getDownloadURL();
      }

      // Deliberately never touches the parent case's own `status` — a
      // sighting update is purely additive, never an automatic close.
      await reportRef.set({
        'caseId': widget.caseId,
        'reporterId': uid,
        'reporterName': name.isEmpty ? 'A community member' : name,
        'type': _selectedType,
        'comment': _commentController.text.trim(),
        'newAddress': _selectedType == 'moved' ? _pickedAddress : null,
        'newLat': _selectedType == 'moved' ? _pickedLat : null,
        'newLng': _selectedType == 'moved' ? _pickedLng : null,
        // Community Location Approval spec §9 — an "Animal moved" update
        // starts pending; the case's own official address/lat/lng are
        // never touched until an admin explicitly approves it
        // (RescueCaseRepository.approveLocationUpdate). Every other report
        // type has no approval concept at all (null, not 'pending').
        'approvalStatus': _selectedType == 'moved' ? 'pending' : null,
        if (_selectedType == 'moved') 'locationScope': 'case',
        'photoUrl': photoUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .collection('activityLogs')
          .add({
            'action': 'community_report_submitted',
            'actorUid': uid,
            'actorName': name.isEmpty ? 'A community member' : name,
            'actorRole': null,
            'details': {'type': _selectedType},
            'timestamp': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        setState(() {
          _selectedType = null;
          _pickedImage = null;
          _pickedLat = null;
          _pickedLng = null;
          _pickedAddress = null;
          _expanded = false;
        });
        _commentController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thanks! Your report has been submitted.'),
            backgroundColor: AppColors.greenrspwn,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not submit report: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _optionButton(String type, String iconAsset, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = type),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: Image.asset(iconAsset, width: 10, height: 10),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 4),
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Image.asset(
                  _typeIconAsset(_selectedType),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _typeLabel(_selectedType),
              style: GoogleFonts.tiltWarp(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _typeDescription(_selectedType),
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slaterspwn),
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.background,
                ),
                child: _pickedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.file(
                          File(_pickedImage!.path),
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(
                        Icons.add_a_photo_outlined,
                        color: AppColors.textSecondary,
                        size: 26,
                      ),
              ),
            ),
            const SizedBox(height: 14),
            if (_selectedType == 'moved') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Location Found',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // Community Location Validation spec §4 — a real, confirmed
              // map pin only; never a freeform-typed address. Tapping opens
              // the shared LastSeenLocationPicker (map + reverse geocoding),
              // same widget the collar-tag "last seen" flow already uses.
              GestureDetector(
                onTap: _openLocationPicker,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.slaterspwn),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _pickedLat != null
                            ? Icons.location_on
                            : Icons.add_location_alt_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _pickedAddress ??
                              'Tap to select the new location on the map',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            color: _pickedAddress != null
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                          ),
                        ),
                      ),
                      Text(
                        _pickedAddress != null ? 'Change' : 'Select',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select a map pin so the new location is accurate — the address is filled in for you.',
                style: GoogleFonts.zain(
                  fontSize: 10.5,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _commentController,
              maxLines: 2,
              style: GoogleFonts.zain(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Comment',
                hintStyle: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : Text(
                        'Report',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => setState(() => _selectedType = null),
            child: const Icon(
              Icons.close,
              size: 20,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _formatDate(DateTime d) {
    const months = [
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

  // Community Location Approval spec §9 — never implies the case's
  // official location changed while still pending.
  Widget? _approvalBadge(Map<String, dynamic> r) {
    final status = r['approvalStatus'] as String?;
    if (status == null) return null;
    final (label, color) = switch (status) {
      'approved' => ('Location change approved', AppColors.greenrspwn),
      'rejected' => ('Location change rejected', Colors.redAccent),
      _ => ('Pending approval', const Color(0xFF9C6B10)),
    };
    final approvedAt = r['approvedAt'] as Timestamp?;
    final approvedBy = r['approvedBy'] as String?;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
          if (status == 'approved' && approvedBy != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Approved by $approvedBy${approvedAt != null ? ' on ${_formatDate(approvedAt.toDate())}' : ''}',
                style: GoogleFonts.zain(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final ts = r['timestamp'] as Timestamp?;
    final date = ts?.toDate();
    final newAddress = r['newAddress'] as String?;
    final comment = r['comment'] as String?;
    final photoUrl = r['photoUrl'] as String?;
    final approvalBadge = _approvalBadge(r);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.textPrimary,
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Image.asset(
                    _typeIconAsset(r['type'] as String?),
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '${r['reporterName'] ?? 'Someone'} · ${_typeLabel(r['type'] as String?)}',
                            style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (date != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatTime(date),
                                style: GoogleFonts.zain(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Text(
                                _formatDate(date),
                                style: GoogleFonts.zain(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),

                    if (comment != null && comment.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          comment,
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Photo moved below the row and made full-width, per the design
          // mockup's large landscape placeholder (was a 36x36 side thumbnail).
          if (photoUrl != null && photoUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                photoUrl,
                width: double.infinity,
                height: 120,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: double.infinity,
                  height: 120,
                  color: AppColors.slaterspwn,
                ),
              ),
            ),
          ],
          if (newAddress != null && newAddress.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_outlined,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      newAddress,
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (approvalBadge != null) approvalBadge,
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _reportsRef.snapshots(),
                    builder: (context, snap) {
                      final count = snap.data?.docs.length;
                      return Text(
                        'Community Reports${count == null ? '' : '  $count'}',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      );
                    },
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      setState(() => _sectionExpanded = !_sectionExpanded),
                  child: Icon(
                    _sectionExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (_sectionExpanded) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(
                    _expanded ? Icons.close : Icons.add_circle_outline,
                    size: 18,
                  ),
                  label: Text(_expanded ? 'Cancel' : 'Add Community Report'),
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 10),
                if (_selectedType == null) ...[
                  Text(
                    'What is happening?',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Help keep rescue reports accurate by sharing timely updates on the animal\'s location, condition, and safety.',
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _optionButton(
                        'still_here',
                        'assets/icons/animalstillhere.png',
                        'Animal still here',
                      ),
                      _optionButton(
                        'moved',
                        'assets/icons/animalmoved.png',
                        'Animal moved',
                      ),
                      _optionButton(
                        'rescued',
                        'assets/icons/animalrescued.png',
                        'Animal rescued',
                      ),
                      _optionButton(
                        'no_animal',
                        'assets/icons/noanimal.png',
                        'No Animal Present',
                      ),
                    ],
                  ),
                ] else
                  _buildForm(),
              ],
              const SizedBox(height: 12),
              const Divider(color: AppColors.slaterspwn),
              const SizedBox(height: 4),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _reportsRef
                    .orderBy('timestamp', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Could not load community reports.',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No community reports yet.',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    );
                  }
                  return Column(
                    children: docs.map((d) => _reportTile(d.data())).toList(),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
