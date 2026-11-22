import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/widgets/image_source_sheet.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/clinic_search_result.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/features/organization/signup/organization_verification_pending_page.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/account/account_page.dart';

/// Step 2 of the Organization signup flow (spec §4) — reuses the same
/// image_picker + Firebase Storage stack the pet-transporter verification
/// screen uses (lib/features/pettransporter/transporter_verification_screen.dart),
/// but as genuine multi-file groups (that screen only ever picks one file
/// per field) with its own storage path
/// `organizations/{organizationId}/verification/{group}/...` — never mixed
/// with animal images, adoption home photos, treatment media, or
/// transporter documents, each of which already has its own path.
///
/// Two ways in:
///  - [OrganizationVerificationScreen.signup] from About Your Organization:
///    the organization doesn't exist yet. Submit writes it (with [details]),
///    uploads the photos and sends it for review in one go, so a signup
///    abandoned before Submit leaves nothing behind.
///  - [OrganizationVerificationScreen] for an organization that already
///    exists (resubmitting after a rejection or a request for changes).
class OrganizationVerificationScreen extends StatefulWidget {
  final String? organizationId;
  final OrganizationSignupDetails? details;

  const OrganizationVerificationScreen({super.key, required String this.organizationId}) : details = null;

  /// [draftOrganizationId]: a draft left by an earlier submit that failed
  /// part-way; its uploaded photos are shown and it is reused.
  const OrganizationVerificationScreen.signup({
    super.key,
    required OrganizationSignupDetails this.details,
    String? draftOrganizationId,
  }) : organizationId = draftOrganizationId;

  @override
  State<OrganizationVerificationScreen> createState() => _OrganizationVerificationScreenState();
}

/// What About Your Organization collected, held in memory until Submit.
class OrganizationSignupDetails {
  const OrganizationSignupDetails({
    required this.name,
    required this.contactNumber,
    required this.address,
    required this.pin,
    this.kind = OrgKind.shelter,
  });

  final String name;
  final String contactNumber;
  final String address;
  final ClinicSearchResult pin;

  /// An independent rescuer: [address] is a general area and [pin] their
  /// home or foster location (kept private).
  final OrgKind kind;
}

/// One group of verification photos.
class _DocGroup {
  const _DocGroup(this.key, this.title, this.hint, {this.required = true});
  final String key;
  final String title;
  final String hint;
  final bool required;
}

const _shelterGroups = [
  _DocGroup('registration', 'Registration Document(s)', 'e.g. SEC/DTI registration, business permit cover page'),
  _DocGroup('permits', 'Permit or Accreditation', 'e.g. animal welfare accreditation, LGU permit'),
  _DocGroup('shelterPhotos', 'Shelter / Office Photos', 'Multiple photos of your facility are encouraged'),
];

const _independentGroups = [
  _DocGroup('validId', 'Valid ID', 'A government-issued ID of the person applying (front and back)'),
  _DocGroup('proofOfAddress', 'Proof of Address', 'e.g. a utility bill or barangay certificate. Never shown to the public.'),
  _DocGroup('rescueHistory', 'Rescue History or References',
      'Photos of past rescues, vet receipts, or a reference letter from a shelter, vet or barangay'),
  _DocGroup('barangayClearance', 'Barangay Clearance (optional)', 'Helps your application be approved faster',
      required: false),
];

/// Account (switch account) and Log out on a signup screen (they have no
/// other way out when opened as the first screen). Unsubmitted details and
/// photos are discarded.
class SignupLogOutButton extends StatelessWidget {
  const SignupLogOutButton({super.key});

  Future<void> _logOut(BuildContext context) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final ok = await showConfirmActionDialog(
      context,
      title: 'Log out?',
      message: "Anything you haven't submitted yet will be discarded. "
          'Log in again to continue your organization sign-up.',
      confirmLabel: 'Log out',
      destructive: true,
    );
    if (!ok) return;
    await authService.value.signOut();
    // AuthWrapper (the first route) shows the login screen once signed out.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AccountButton(color: AppColors.background),
          TextButton(
            onPressed: () => _logOut(context),
            child: Text('Log out', style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.background)),
          ),
        ],
      );
}

class _OrganizationVerificationScreenState extends State<OrganizationVerificationScreen> {
  final _repo = OrganizationRepository();
  final _picker = ImagePicker();
  bool _loading = true;
  String? _loadError;
  bool _submitting = false;
  // "Uploading 2 of 5..." while Submit is sending the picked files.
  String? _progressLabel;
  // Null until Submit creates the organization (new signups only).
  late String? _orgId = widget.organizationId;

  late OrgKind _kind = widget.details?.kind ?? OrgKind.shelter;
  List<_DocGroup> get _groups => _kind == OrgKind.independent ? _independentGroups : _shelterGroups;

  final Map<String, List<String>> _existingUrls = {
    for (final g in [..._shelterGroups, ..._independentGroups]) g.key: <String>[],
  };
  final Map<String, List<File>> _pendingFiles = {
    for (final g in [..._shelterGroups, ..._independentGroups]) g.key: <File>[],
  };

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final orgId = _orgId;
    if (orgId == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final doc = await FirebaseFirestore.instance.collection('organizations').doc(orgId).get();
      final verification = (doc.data()?['verification'] as Map?) ?? const {};
      if (!mounted) return;
      setState(() {
        _kind = OrgKind.fromName(doc.data()?['kind'] as String?);
        for (final group in _existingUrls.keys) {
          _existingUrls[group] = List<String>.from(verification[group] ?? const []);
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = 'Could not load your uploaded documents. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _pickFor(String group) async {
    final picked = await pickImagesWithSource(context, _picker, imageQuality: 85);
    if (picked.isEmpty) return;
    setState(() => _pendingFiles[group]!.addAll(picked.map((x) => File(x.path))));
  }

  Future<void> _removeExisting(String group, String url) async {
    final orgId = _orgId;
    if (orgId == null) return;
    setState(() => _existingUrls[group]!.remove(url));
    await _repo.removeVerificationFile(organizationId: orgId, group: group, url: url);
  }

  void _removePending(String group, int index) => setState(() => _pendingFiles[group]!.removeAt(index));

  /// Every required group has a file, already uploaded or picked and waiting.
  bool get _hasAllGroups => _groups
      .where((g) => g.required)
      .every((g) => _existingUrls[g.key]!.isNotEmpty || _pendingFiles[g.key]!.isNotEmpty);

  /// Uploads every picked file, group by group, recording each group's
  /// URLs on the organization as soon as that group finishes so a failure
  /// part-way keeps what already went up (and isn't uploaded twice).
  Future<void> _uploadAllPending(String orgId, void Function(String step) at) async {
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
        final ref = FirebaseStorage.instance.ref('organizations/$orgId/verification/$group/$filename');
        at('upload');
        await ref.putFile(file);
        urls.add(await ref.getDownloadURL());
        done++;
      }
      at('record');
      await _repo.addVerificationFiles(organizationId: orgId, group: group, urls: urls);
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
          _kind == OrgKind.independent
              ? 'A valid ID, proof of address and your rescue history or references are required.'
              : 'Registration document(s), permit, and shelter photos are all required.',
          kind: AppMessageKind.error,
        ),
      );
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Your session expired. Please sign in again.', kind: AppMessageKind.error),
      );
      return;
    }
    setState(() {
      _submitting = true;
      _progressLabel = 'Saving organization...';
    });
    // Which step failed, so an error says whether it was saving the
    // organization (Firestore) or uploading a photo (Storage).
    var step = 'save';
    try {
      // New signups: the organization is written only now. Reuses a draft
      // from an earlier failed submit rather than making a second one.
      final details = widget.details;
      if (details != null) {
        _orgId = await _repo.createOrUpdateDraft(
          uid: uid,
          name: details.name,
          contactNumber: details.contactNumber,
          address: details.address,
          pinName: details.pin.name,
          pinPlaceId: details.pin.placeId,
          pinLat: details.pin.lat,
          pinLng: details.pin.lng,
          kind: details.kind,
        );
      }
      final orgId = _orgId!;
      // Storage only accepts verification uploads from an Admin member of
      // the organization (storage.rules isOrgAdminOf). Drafts whose owner
      // membership never got written were denied, so recreate it first.
      step = 'membership';
      await _repo.ensureOwnerMembership(orgId);
      await _uploadAllPending(orgId, (s) => step = s);
      if (mounted) setState(() => _progressLabel = 'Submitting...');
      step = 'submit';
      // Platform staff review the submission (OrganizationReviewPage), so
      // the owner waits on the pending page, which follows the status live
      // and moves on once approved. `pushAndRemoveUntil` clears the signup
      // stack so Back can never return to this completed form and risk a
      // second submission.
      await _repo.submitVerification(orgId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Organization set up. Verification documents submitted for review.'),
        );
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => OrganizationVerificationPendingPage(organizationId: orgId)),
          (route) => false,
        );
      }
    } on FirebaseException catch (e) {
      debugPrint('[OrganizationVerification] $step failed: ${e.plugin}/${e.code} ${e.message}');
      if (mounted) {
        setState(() {
          _submitting = false;
          _progressLabel = null;
        });
        final what = switch (step) {
          'save' => 'save your organization',
          'membership' => 'set you up as the organization Admin',
          'upload' => 'upload your photos',
          'record' => 'record your uploaded photos',
          _ => 'submit for review',
        };
        final denied = e.code == 'unauthorized' || e.code == 'permission-denied';
        final message = denied
            ? "Couldn't $what: permission denied (${e.plugin}). Photos already sent are kept; try again in a few minutes."
            : "Couldn't $what: ${e.message ?? e.code}";
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
        title: Text(_kind == OrgKind.independent ? 'Rescuer Verification' : 'Organization Verification', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
        iconTheme: const IconThemeData(color: AppColors.background),
        actions: const [SignupLogOutButton()],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_loadError!, textAlign: TextAlign.center,
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _loadExisting, child: const Text('Retry')),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text('Upload verification documents',
                    style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(
                    _kind == OrgKind.independent
                        ? 'JPG or PNG only. A system admin reviews them; they are never shown on your profile. '
                            'Your photos upload when you tap Submit.'
                        : 'JPG or PNG only. All three groups are required. Your photos upload when you tap Submit.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                for (final g in _groups) ...[
                  const SizedBox(height: 20),
                  _uploadGroup(g.key, g.title, g.hint),
                ],
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
