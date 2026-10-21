import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/features/adminhome/adminhome_screen.dart';

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
  String? _uploadingGroup;

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

  Future<void> _uploadPendingFor(String group) async {
    final files = _pendingFiles[group]!;
    if (files.isEmpty) return;
    setState(() => _uploadingGroup = group);
    try {
      final urls = <String>[];
      for (var i = 0; i < files.length; i++) {
        final file = files[i];
        final ext = file.path.contains('.') ? file.path.split('.').last : 'jpg';
        final filename = '${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        final ref = FirebaseStorage.instance.ref('organizations/${widget.organizationId}/verification/$group/$filename');
        await ref.putFile(file);
        urls.add(await ref.getDownloadURL());
      }
      await _repo.addVerificationFiles(organizationId: widget.organizationId, group: group, urls: urls);
      if (mounted) {
        setState(() {
          _existingUrls[group]!.addAll(urls);
          _pendingFiles[group]!.clear();
          _uploadingGroup = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploadingGroup = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  Future<void> _removeExisting(String group, String url) async {
    setState(() => _existingUrls[group]!.remove(url));
    await _repo.removeVerificationFile(organizationId: widget.organizationId, group: group, url: url);
  }

  void _removePending(String group, int index) => setState(() => _pendingFiles[group]!.removeAt(index));

  bool get _hasAllGroups => _existingUrls.values.every((v) => v.isNotEmpty);
  bool get _hasAnyPending => _pendingFiles.values.any((v) => v.isNotEmpty);

  Future<void> _submit() async {
    if (_submitting || _uploadingGroup != null) return;
    if (_hasAnyPending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Upload your selected files before submitting.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (!_hasAllGroups) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Registration document(s), permit, and shelter photos are all required.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      // Organization Admin Signup Completion spec §7-9 — no reviewer
      // interface exists anywhere in this codebase to ever act on
      // `verificationStatus: pending`, so leaving the admin on a waiting
      // screen after this write is a dead end, not a real pending state.
      // `submitVerification` still honestly records `verificationStatus:
      // pending` (never `approved` — see organization_repository.dart's
      // own doc comment) so a real manual review, if one is ever added or
      // done directly via the Firestore console, can still act on this
      // later; access to the admin interface is simply no longer gated on
      // that ever happening. `pushAndRemoveUntil` clears the entire
      // signup stack so Back can never return to this completed form and
      // risk a second submission.
      await _repo.submitVerification(widget.organizationId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Organization set up. Verification documents submitted for review.')),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not submit: $e'), backgroundColor: Colors.redAccent));
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
                Text('JPG or PNG only. All three groups are required before you can submit.',
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      disabledBackgroundColor: AppColors.slaterspwn,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _submitting
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
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
    final uploading = _uploadingGroup == group;

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
              for (final url in existing) _thumb(image: Image.network(url, fit: BoxFit.cover), onRemove: () => _removeExisting(group, url)),
              for (var i = 0; i < pending.length; i++)
                _thumb(image: Image.file(pending[i], fit: BoxFit.cover), onRemove: () => _removePending(group, i)),
              GestureDetector(
                onTap: uploading ? null : () => _pickFor(group),
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.greenrspwn, width: 1.5), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add_a_photo_outlined, color: AppColors.greenrspwn),
                ),
              ),
            ],
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: uploading ? null : () => _uploadPendingFor(group),
                child: uploading
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Upload ${pending.length} file${pending.length == 1 ? '' : 's'}'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thumb({required Widget image, required VoidCallback onRemove}) => Stack(
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
