import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_pending_page.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Step 2 of the Organization signup flow (spec §4) — reuses the same
/// image_picker + Firebase Storage stack the pet-transporter verification
/// screen uses (lib/features/pettransporter/transporter_verification_screen.dart),
/// but as genuine multi-file groups (that screen only ever picks one file
/// per field) with its own storage path
/// `organizations/{organizationId}/verification/{group}/...` — never mixed
/// with animal images, adoption home photos, treatment media, or
/// transporter documents, each of which already has its own path.
class OrganizationVerificationScreen extends StatefulWidget {
  final String organizationId;
  const OrganizationVerificationScreen({super.key, required this.organizationId});

  @override
  State<OrganizationVerificationScreen> createState() => _OrganizationVerificationScreenState();
}

class _OrganizationVerificationScreenState extends State<OrganizationVerificationScreen> {
  final _repo = OrganizationRepository();
  final _picker = ImagePicker();
  bool _loading = true;
  bool _submitting = false;
  // "Uploading 2 of 5..." while Submit is sending the picked files.
  String? _progressLabel;

  final Map<String, List<String>> _existingUrls = {'registration': [], 'permits': [], 'shelterPhotos': []};
  final Map<String, List<File>> _pendingFiles = {'registration': [], 'permits': [], 'shelterPhotos': []};

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final doc = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
    final verification = (doc.data()?['verification'] as Map?) ?? const {};
    if (mounted) {
      setState(() {
        for (final group in _existingUrls.keys) {
          _existingUrls[group] = List<String>.from(verification[group] ?? const []);
        }
        _loading = false;
      });
    }
  }

  Future<void> _pickFor(String group) async {
    final picked = await pickImagesWithSource(context, _picker, imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() => _pendingFiles[group]!.addAll(picked.map((x) => File(x.path))));
  }

  Future<void> _removeExisting(String group, String url) async {
    setState(() => _existingUrls[group]!.remove(url));
    await _repo.removeVerificationFile(organizationId: widget.organizationId, group: group, url: url);
  }

  void _removePending(String group, int index) => setState(() => _pendingFiles[group]!.removeAt(index));

  /// Every group has a file, already uploaded or picked and waiting.
  bool get _hasAllGroups =>
      _existingUrls.keys.every((g) => _existingUrls[g]!.isNotEmpty || _pendingFiles[g]!.isNotEmpty);

  /// Uploads every picked file, group by group, recording each group's
  /// URLs on the organization as soon as that group finishes so a failure
  /// part-way keeps what already went up (and isn't uploaded twice).
  Future<void> _uploadAllPending() async {
    final total = _pendingFiles.values.fold<int>(0, (n, files) => n + files.length);
    if (total == 0) return;
    var done = 0;
    for (final group in _pendingFiles.keys) {
      final files = List<File>.from(_pendingFiles[group]!);
      if (files.isEmpty) continue;
      final urls = <String>[];
      for (var i = 0; i < files.length; i++) {
        if (mounted) setState(() => _progressLabel = 'Uploading ${done + 1} of $total...');
        final file = files[i];
        final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
        final filename = '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        final ref = FirebaseStorage.instance.ref('organizations/${widget.organizationId}/verification/$group/$filename');
        await ref.putFile(file);
        urls.add(await ref.getDownloadURL());
        done++;
      }
      await _repo.addVerificationFiles(organizationId: widget.organizationId, group: group, urls: urls);
      if (mounted) {
        setState(() {
          _existingUrls[group]!.addAll(urls);
          _pendingFiles[group]!.clear();
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_hasAllGroups) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar(
          'Registration document(s), permit, and shelter photos are all required.',
          kind: AppMessageKind.error,
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      // Storage only accepts verification uploads from an Admin member of
      // the organization (storage.rules isOrgAdminOf). Drafts whose owner
      // membership never got written were denied, so recreate it first.
      await _repo.ensureOwnerMembership(widget.organizationId);
      await _uploadAllPending();
      if (mounted) setState(() => _progressLabel = 'Submitting...');
      // Platform staff review the submission (OrganizationReviewPage), so
      // the owner waits on the pending page, which follows the status live
      // and moves on once approved. `pushAndRemoveUntil` clears the signup
      // stack so Back can never return to this completed form and risk a
      // second submission.
      await _repo.submitVerification(widget.organizationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Organization set up. Verification documents submitted for review.'),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => OrganizationVerificationPendingPage(organizationId: widget.organizationId)),
          (route) => false,
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progressLabel = null;
        });
        final message = e.code == 'unauthorized' || e.code == 'permission-denied'
            ? "Upload not allowed for this account. Make sure you're signed in as the organization's owner, then try again."
            : 'Could not submit: ${e.message ?? e.code}';
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(message, kind: AppMessageKind.error));
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _progressLabel = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not submit: $e', kind: AppMessageKind.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        title: Text('Organization Verification', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Upload verification documents',
                    style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text('JPG or PNG only. All three groups are required. Your photos upload when you tap Submit.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                _uploadGroup('registration', 'Registration Document(s)', 'e.g. SEC/DTI registration, business permit cover page'),
                const SizedBox(height: 20),
                _uploadGroup('permits', 'Permit or Accreditation', 'e.g. animal welfare accreditation, LGU permit'),
                const SizedBox(height: 20),
                _uploadGroup('shelterPhotos', 'Shelter / Office Photos', 'Multiple photos of your facility are encouraged'),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: AppButtons.primary,
                    child: _submitting
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary)),
                              if (_progressLabel != null) ...[
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(_progressLabel!,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                                ),
                              ],
                            ],
                          )
                        : Text('Submit for Verification', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _uploadGroup(String group, String title, String hint) {
    final existing = _existingUrls[group]!;
    final pending = _pendingFiles[group]!;
    final busy = _submitting;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(hint, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final url in existing)
                _thumb(image: Image.network(url, fit: BoxFit.cover), onRemove: busy ? null : () => _removeExisting(group, url)),
              for (var i = 0; i < pending.length; i++)
                _thumb(image: Image.file(pending[i], fit: BoxFit.cover), onRemove: busy ? null : () => _removePending(group, i)),
              GestureDetector(
                onTap: busy ? null : () => _pickFor(group),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.greenrspwn, width: 1.5), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.greenrspwn),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _thumb({required Widget image, required VoidCallback? onRemove}) => Stack(
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(width: 72, height: 72, child: image)),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      );
}
