import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/constants/service_areas.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/repos/org_membership_service.dart';
import 'package:respawnd1/core/repos/organization_invitation_repository.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/utils/shelter_occupancy.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';
import 'package:respawnd1/features/organization/staff_members_page.dart';

/// Admin-facing Organization Profile editor (spec §7-9) — distinct from
/// lib/features/organization/organization_profile_page.dart, which is the
/// public/donor-facing browse view over the same `organizations/{orgId}`
/// doc. Never touches verification*/verification fields (see
/// OrganizationRepository.updateProfile's own doc comment).
///
/// [organizationId] is null for a standalone admin who isn't linked to an
/// organization yet (spec's temporary bootstrap + invitation-lookup
/// addition) — in that case this page first checks for a pending
/// invitation addressed to the signed-in email, and falls back to a blank
/// "set up your organization" form only when none exists. Once an
/// organization is joined or created, this becomes the exact same editor a
/// linked admin would see — no separate page, no separate save path beyond
/// which repository method [_save] calls.
class OrganizationProfileEditPage extends StatefulWidget {
  final String? organizationId;
  const OrganizationProfileEditPage({super.key, this.organizationId});

  @override
  State<OrganizationProfileEditPage> createState() => _OrganizationProfileEditPageState();
}

class _OrganizationProfileEditPageState extends State<OrganizationProfileEditPage> {
  static const _speciesOptions = ['Dog', 'Cat']; // canonical values — matches AnimalRecord.species exactly

  final _repo = OrganizationRepository();
  final _invitationRepo = OrganizationInvitationRepository();
  final _picker = ImagePicker();

  /// Resolved once known — either passed in directly (already-linked admin)
  /// or set after a successful Join/Create in the unlinked flow below.
  String? _organizationId;

  bool _loading = true;
  bool _saving = false;
  String? _avatarUrl;
  File? _pendingAvatar;

  // Unlinked-account states (spec's UI-states list): checking invitations /
  // pending invitation(s) found / no invitations / accepting / invitation
  // error. Only relevant while _organizationId == null.
  bool _checkingInvitations = false;
  bool _invitationCheckFailed = false;
  List<OrganizationInvitation> _invitations = const [];
  String? _acceptingInvitationId;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _facebookController = TextEditingController();
  final _websiteController = TextEditingController();
  // Shelter Capacity (spec §8) — the SAME field the dashboard Capacity
  // card reads (settings/shelter.maxCapacity, added when that card was
  // built) rather than a new/separate organization-level field, so the two
  // can never disagree about what "capacity" means.
  final _capacityController = TextEditingController();
  bool _isOrgAdmin = false;

  List<ServiceArea> _serviceAreas = [];
  final Set<String> _acceptedSpecies = {};

  bool get _isBootstrapping => _organizationId == null;

  @override
  void initState() {
    super.initState();
    _organizationId = widget.organizationId;
    if (_organizationId != null) {
      _load();
    } else {
      _checkInvitations();
    }
  }

  /// Pending invitations addressed to the signed-in email, across every
  /// organization (spec's invitation-lookup addition) — shown above the
  /// bootstrap-create form rather than jumping straight to it, so an admin
  /// who was actually invited to a real organization joins that one
  /// instead of accidentally creating a duplicate.
  Future<void> _checkInvitations() async {
    setState(() {
      _checkingInvitations = true;
      _invitationCheckFailed = false;
    });
    final email = FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    if (email == null || email.isEmpty) {
      if (mounted) setState(() { _checkingInvitations = false; _loading = false; });
      return;
    }
    try {
      final invites = await _invitationRepo.streamInvitationsForEmail(email).first;
      final valid = invites.where((i) => !i.isExpired).toList();
      if (mounted) {
        setState(() {
          _invitations = valid;
          _checkingInvitations = false;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingInvitations = false;
          _invitationCheckFailed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _joinInvitation(OrganizationInvitation invite) async {
    if (_acceptingInvitationId != null) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || currentUser.email == null) return;
    setState(() => _acceptingInvitationId = invite.id);
    try {
      await _invitationRepo.acceptInvitation(
        invitationId: invite.id,
        uid: currentUser.uid,
        signedInEmail: currentUser.email!,
        // This entry point is reached only by an already-authenticated
        // admin account — joining an organization here must never re-route
        // them out of the admin shell by overwriting users/{uid}.role.
        preserveAccountRole: true,
      );
      if (!mounted) return;
      setState(() {
        _organizationId = invite.organizationId;
        _invitations = const [];
        _loading = true;
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not join this organization: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingInvitationId = null);
    }
  }

  Future<void> _load() async {
    final orgId = _organizationId;
    if (orgId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final doc = await FirebaseFirestore.instance.collection('organizations').doc(orgId).get();
    final data = doc.data() ?? const <String, dynamic>{};
    _nameController.text = data['name'] as String? ?? '';
    _descriptionController.text = data['description'] as String? ?? '';
    _locationController.text = data['location'] as String? ?? '';
    _emailController.text = data['email'] as String? ?? '';
    _phoneController.text = (data['contactNumber'] as String?) ?? (data['phone'] as String?) ?? '';
    _facebookController.text = data['facebookUrl'] as String? ?? '';
    _websiteController.text = data['website'] as String? ?? '';
    _avatarUrl = data['avatarUrl'] as String?;
    _serviceAreas = (data['serviceAreas'] as List? ?? const [])
        .map((e) => ServiceArea.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
    _acceptedSpecies.addAll(List<String>.from(data['acceptedSpecies'] ?? const []));

    // Shelter Capacity is admin-only to edit (spec §8) — resolved via the
    // existing OrgMembershipService, never a second membership model.
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final membership = await OrgMembershipService().getMembership(uid);
      _isOrgAdmin = membership != null && membership.organizationId == orgId && membership.role == OrgRole.admin;
    }
    final shelterDoc = await FirebaseFirestore.instance.collection('settings').doc('shelter').get();
    final maxCapacity = (shelterDoc.data()?['maxCapacity'] as num?)?.toInt();
    _capacityController.text = maxCapacity?.toString() ?? '';

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _facebookController.dispose();
    _websiteController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _pendingAvatar = File(picked.path));
  }

  Future<void> _editLocation() async {
    final orgId = _organizationId;
    if (orgId == null) return; // no org yet during bootstrap — see the plain text field used instead
    // Read the currently-saved structured location first so the picker can
    // show it as already-selected on the map, instead of opening blank
    // every time (spec §12: "Show the current saved location on the map").
    final currentDoc = await FirebaseFirestore.instance.collection('organizations').doc(orgId).get();
    final currentData = currentDoc.data() ?? const <String, dynamic>{};
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ShelterLocationPickerPage(
          organizationId: orgId,
          initialName: currentData['shelterName'] as String?,
          initialAddress: currentData['shelterAddress'] as String?,
          initialPlaceId: currentData['shelterPlaceId'] as String?,
          initialLat: (currentData['shelterLat'] as num?)?.toDouble(),
          initialLng: (currentData['shelterLng'] as num?)?.toDouble(),
        ),
      ),
    );
    if (saved == true) {
      final doc = await FirebaseFirestore.instance.collection('organizations').doc(orgId).get();
      final address = doc.data()?['shelterAddress'] as String?;
      if (address != null && address.isNotEmpty && mounted) {
        setState(() => _locationController.text = address);
      }
    }
  }

  /// True when [area] matches one of the canonical, currently-supported
  /// cities/LGUs (lib/core/constants/service_areas.dart) — false for a
  /// legacy value saved before that controlled list existed (a free-text
  /// entry, or a Places-search pick outside the three supported regions).
  /// Legacy values are never silently dropped — they stay visible (clearly
  /// marked) until the admin explicitly removes/replaces them and saves.
  bool _isSupportedServiceArea(ServiceArea area) =>
      kSupportedServiceAreas.any((o) => normalizeForMatch(o.name) == area.normalizedName);

  void _removeServiceArea(ServiceArea area) => setState(() => _serviceAreas = _serviceAreas.where((s) => s != area).toList());

  /// Multi-select bottom sheet limited to [kSupportedServiceAreas] — the
  /// only way a new service area can be added (spec §3: no arbitrary
  /// free-text areas). Searchable (case-insensitive substring over name),
  /// grouped by region, duplicates blocked (existing/legacy selections are
  /// pre-checked and can't be re-added), and scrolls correctly for the
  /// full list. Applies all changes at once on "Done" so partial picks
  /// aren't saved if the admin backs out.
  Future<void> _openServiceAreaPicker() async {
    final selectedNames = _serviceAreas.map((s) => s.normalizedName).toSet();
    final workingSelection = Set<String>.from(selectedNames);
    final searchController = TextEditingController();

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final query = searchController.text.trim().toLowerCase();
          final filtered = query.isEmpty
              ? kSupportedServiceAreas
              : kSupportedServiceAreas.where((o) => o.name.toLowerCase().contains(query)).toList();

          return Padding(
            padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(sheetContext).viewInsets.bottom),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Service Areas', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: const InputDecoration(hintText: 'Search a supported city…', prefixIcon: Icon(Icons.search)),
                    onChanged: (_) => setSheetState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Text('No supported cities match your search.',
                                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                          )
                        : ListView(
                            children: [
                              for (final region in kSupportedServiceAreaRegions)
                                if (filtered.any((o) => o.region == region)) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Text(region,
                                        style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                                  ),
                                  for (final option in filtered.where((o) => o.region == region))
                                    CheckboxListTile(
                                      contentPadding: EdgeInsets.zero,
                                      controlAffinity: ListTileControlAffinity.leading,
                                      dense: true,
                                      activeColor: AppColors.greenrspwn,
                                      title: Text(option.name, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                                      value: workingSelection.contains(normalizeForMatch(option.name)),
                                      onChanged: (checked) => setSheetState(() {
                                        final normalized = normalizeForMatch(option.name);
                                        if (checked ?? false) {
                                          workingSelection.add(normalized);
                                        } else {
                                          workingSelection.remove(normalized);
                                        }
                                      }),
                                    ),
                                ],
                            ],
                          ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text('Done', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() {
      // Keep every legacy/unsupported entry that was already present and
      // still checked (removing one only happens via its own chip's
      // delete button, never implicitly by this sheet), plus every
      // canonical option the admin just selected.
      final keptLegacy = _serviceAreas.where((s) => !_isSupportedServiceArea(s) && workingSelection.contains(s.normalizedName));
      final newCanonical = kSupportedServiceAreas.where((o) => workingSelection.contains(normalizeForMatch(o.name))).map(
            (o) => ServiceArea(name: o.name, normalizedName: normalizeForMatch(o.name), administrativeArea: o.region),
          );
      _serviceAreas = [...keptLegacy, ...newCanonical];
    });
  }

  String? _websiteError(String v) {
    if (v.trim().isEmpty) return null; // optional
    final ok = RegExp(r'^https?://[\w.-]+\.[A-Za-z]{2,}.*$').hasMatch(v.trim());
    return ok ? null : 'Enter a valid URL starting with http:// or https://';
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameController.text.trim();
    final location = _locationController.text.trim();
    final emailError = AppValidators.email(_emailController.text, required: false);
    final phoneError = AppValidators.phFlexiblePhone(_phoneController.text, required: false);
    final websiteError = _websiteError(_websiteController.text);
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organization name is required.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location is required.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (emailError != null || phoneError != null || websiteError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(emailError ?? phoneError ?? websiteError!), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (_acceptedSpecies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one accepted species.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (_serviceAreas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one service area.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    // Shelter Capacity — whole positive number or unset; admin-only (the
    // field is read-only text for a non-admin, so this never triggers for
    // one). Over-capacity is allowed after an explicit confirmation, since
    // a real shelter can genuinely be over its configured capacity.
    int? capacityValue;
    bool clearCapacity = false;
    if (_isOrgAdmin) {
      final capacityText = _capacityController.text.trim();
      if (capacityText.isEmpty) {
        clearCapacity = true;
      } else {
        capacityValue = int.tryParse(capacityText);
        if (capacityValue == null || capacityValue < 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Shelter capacity must be a whole positive number.'), backgroundColor: Colors.redAccent),
          );
          return;
        }
        final occupancy = await currentShelterOccupancy();
        if (occupancy > capacityValue) {
          if (!mounted) return;
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.background,
              title: Text('Below Current Occupancy', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
              content: Text(
                'Current occupancy is $occupancy animals. Setting capacity to $capacityValue will place the shelter over capacity.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
                  child: const Text('Save Anyway'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
        }
      }
    }

    setState(() => _saving = true);
    try {
      if (_isOrgAdmin) {
        // settings/shelter is the single source both this field and the
        // dashboard Capacity card read/write — updating it here reflects
        // live on the dashboard immediately via shelterMaxCapacityProvider
        // (a Firestore StreamProvider), no separate refresh needed.
        // updatedBy/updatedAt is the only audit trail available — there is
        // no broader organization-level audit log in this codebase yet.
        await FirebaseFirestore.instance.collection('settings').doc('shelter').set({
          'maxCapacity': clearCapacity ? null : capacityValue,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': FirebaseAuth.instance.currentUser?.uid,
        }, SetOptions(merge: true));
      }

      if (_isBootstrapping) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid == null) throw StateError('Not signed in.');
        // Avatar upload needs a real organizationId as its storage path, so
        // for a brand-new org that doesn't exist yet, create the document
        // first and upload the picked photo as a follow-up update — never
        // blocks org creation on a photo pick, matching "Profile photo" not
        // being in the required-fields list.
        final orgId = await _repo.createBootstrapOrganization(
          uid: uid,
          name: name,
          location: location,
          description: _descriptionController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          facebookUrl: _facebookController.text.trim(),
          website: _websiteController.text.trim(),
          serviceAreas: _serviceAreas,
          acceptedSpecies: _acceptedSpecies.toList(),
        );
        String? avatarUrl;
        if (_pendingAvatar != null) {
          final ref = FirebaseStorage.instance.ref('organizations/$orgId/profile/avatar.jpg');
          await ref.putFile(_pendingAvatar!);
          avatarUrl = await ref.getDownloadURL();
          await _repo.updateProfile(organizationId: orgId, avatarUrl: avatarUrl);
        }
        if (mounted) {
          setState(() {
            _organizationId = orgId;
            _avatarUrl = avatarUrl;
            _pendingAvatar = null;
            _saving = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Organization created.')));
        }
        return;
      }

      var avatarUrl = _avatarUrl;
      if (_pendingAvatar != null) {
        final ref = FirebaseStorage.instance.ref('organizations/${_organizationId!}/profile/avatar.jpg');
        await ref.putFile(_pendingAvatar!);
        avatarUrl = await ref.getDownloadURL();
      }

      await _repo.updateProfile(
        organizationId: _organizationId!,
        name: name,
        description: _descriptionController.text.trim(),
        avatarUrl: avatarUrl,
        location: location,
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        facebookUrl: _facebookController.text.trim(),
        website: _websiteController.text.trim(),
        serviceAreas: _serviceAreas,
        acceptedSpecies: _acceptedSpecies.toList(),
      );

      if (mounted) {
        setState(() {
          _avatarUrl = avatarUrl;
          _pendingAvatar = null;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Organization profile saved.')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: AppColors.background), onPressed: () => Navigator.pop(context)),
        title: Text('Organization Profile', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
        actions: [
          // Only reachable once an organization actually exists — a
          // standalone admin with nothing to staff yet gets no dead-end
          // Staff Members button.
          if (_organizationId != null)
            IconButton(
              icon: const Icon(Icons.people_outline, color: AppColors.background),
              tooltip: 'Staff Members',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => StaffMembersPage(organizationId: _organizationId!)),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_checkingInvitations) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text('Checking invitations…', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    if (_invitationCheckFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 32, color: AppColors.textSecondary),
              const SizedBox(height: 10),
              Text('Could not check invitations.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 14),
              OutlinedButton(onPressed: _checkInvitations, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // A valid pending invitation takes priority over the bootstrap form —
    // an admin who was actually invited to a real organization should join
    // that one, not accidentally create a duplicate (spec's page-order
    // requirement).
    if (_isBootstrapping && _invitations.isNotEmpty) {
      return _buildInvitationsList();
    }
    return _buildForm();
  }

  Widget _buildInvitationsList() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text("You're invited to join an organization",
            style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
        const SizedBox(height: 4),
        Text(
          _invitations.length > 1
              ? 'You may accept only one — this app supports one organization per account.'
              : 'Accepting will link your account to this organization.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 16),
        for (final invite in _invitations) _InvitationCard(
          invitation: invite,
          accepting: _acceptingInvitationId == invite.id,
          disabled: _acceptingInvitationId != null && _acceptingInvitationId != invite.id,
          onJoin: () => _joinInvitation(invite),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_isBootstrapping) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.lavenderrspwn.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Set up your organization profile',
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        Text(
                          'Your account is not linked to an organization. Create one to manage organization '
                          'details and staff members, or ask an organization administrator to invite your email.',
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: AppColors.slaterspwn,
                          backgroundImage: _pendingAvatar != null
                              ? FileImage(_pendingAvatar!)
                              : (_avatarUrl != null ? NetworkImage(_avatarUrl!) : null) as ImageProvider?,
                          child: (_pendingAvatar == null && _avatarUrl == null)
                              ? const Icon(Icons.business_outlined, size: 36, color: AppColors.textSecondary)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: AppColors.yellowrspwn, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt_outlined, size: 16, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _sectionTitle('Organization Details'),
                _field('Organization Name', _nameController),
                _field('Description', _descriptionController, maxLines: 4, hint: 'Tell adopters and volunteers about your organization'),
                if (_isBootstrapping)
                  _field('Location', _locationController, hint: 'Full address')
                else ...[
                  _label('Location'),
                  Row(
                    children: [
                      Expanded(child: _readonlyish(_locationController)),
                      const SizedBox(width: 8),
                      OutlinedButton(onPressed: _editLocation, child: const Text('Edit')),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                _label('Service Areas'),
                Text('Limited to National Capital Region, CALABARZON, and Central Luzon.',
                    style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final area in _serviceAreas)
                      Chip(
                        label: Text(_isSupportedServiceArea(area) ? area.name : '${area.name} (Unsupported)'),
                        onDeleted: () => _removeServiceArea(area),
                        backgroundColor: _isSupportedServiceArea(area) ? AppColors.lavenderrspwn : const Color(0xFFE05353),
                        labelStyle: _isSupportedServiceArea(area) ? null : const TextStyle(color: Colors.white),
                        deleteIconColor: _isSupportedServiceArea(area) ? null : Colors.white,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _openServiceAreaPicker,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Select Service Areas'),
                ),
                const SizedBox(height: 16),
                _label('Accepted Species'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in _speciesOptions)
                      FilterChip(
                        label: Text(s == 'Dog' ? 'Dogs' : 'Cats'),
                        selected: _acceptedSpecies.contains(s),
                        selectedColor: AppColors.yellowrspwn,
                        onSelected: (v) => setState(() => v ? _acceptedSpecies.add(s) : _acceptedSpecies.remove(s)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _label('Shelter Capacity'),
                if (_isOrgAdmin) ...[
                  TextField(
                    controller: _capacityController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(hintText: 'Not configured'),
                  ),
                  Text('This is the same maximum shown on the dashboard Capacity card.',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                ] else
                  Text(_capacityController.text.isEmpty ? 'Not configured' : _capacityController.text,
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 24),
                _sectionTitle('Contact Details'),
                _field('Email Address', _emailController, hint: 'org@example.com'),
                _field('Mobile Number', _phoneController, hint: '09171234567'),
                _field('Facebook', _facebookController, hint: 'https://facebook.com/yourorg'),
                _field('Website', _websiteController, hint: 'https://yourorg.com'),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      disabledBackgroundColor: AppColors.slaterspwn,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                        : Text(_isBootstrapping ? 'Create Organization' : 'Save',
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      );

  Widget _field(String label, TextEditingController controller, {int maxLines = 1, String? hint}) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(label),
            TextField(controller: controller, maxLines: maxLines, decoration: InputDecoration(hintText: hint)),
          ],
        ),
      );

  Widget _readonlyish(TextEditingController controller) => TextField(
        controller: controller,
        readOnly: true,
        maxLines: 2,
        decoration: const InputDecoration(hintText: 'Not set'),
      );
}

/// One pending invitation shown above the bootstrap form (spec's
/// invitation-lookup addition) — organization name, invited email, role,
/// and a Join button. Multiple valid invitations render as separate cards
/// rather than picking one automatically.
class _InvitationCard extends StatelessWidget {
  final OrganizationInvitation invitation;
  final bool accepting;
  final bool disabled;
  final VoidCallback onJoin;
  const _InvitationCard({
    required this.invitation,
    required this.accepting,
    required this.disabled,
    required this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.yellowrspwn, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(invitation.organizationName.isNotEmpty ? invitation.organizationName : 'Organization',
              style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('Invited email: ${invitation.email}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          Text('Role: ${invitation.role.label}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (accepting || disabled) ? null : onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                disabledBackgroundColor: AppColors.slaterspwn,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: accepting
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                  : Text('Join Organization', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}
