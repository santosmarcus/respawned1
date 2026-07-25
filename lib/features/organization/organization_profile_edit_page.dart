import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/organization/shelter_location_picker_page.dart';
import 'package:respawnd1/features/organization/staff_members_page.dart';

/// Admin-facing Organization Profile editor (spec §7-9) — distinct from
/// lib/features/organization/organization_profile_page.dart, which is the
/// public/donor-facing browse view over the same `organizations/{orgId}`
/// doc. Never touches verification*/verification fields (see
/// OrganizationRepository.updateProfile's own doc comment).
class OrganizationProfileEditPage extends StatefulWidget {
  final String organizationId;
  const OrganizationProfileEditPage({super.key, required this.organizationId});

  @override
  State<OrganizationProfileEditPage> createState() => _OrganizationProfileEditPageState();
}

class _OrganizationProfileEditPageState extends State<OrganizationProfileEditPage> {
  static const _speciesOptions = ['Dog', 'Cat']; // canonical values — matches AnimalRecord.species exactly

  final _repo = OrganizationRepository();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  String? _avatarUrl;
  File? _pendingAvatar;

  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _facebookController = TextEditingController();
  final _websiteController = TextEditingController();
  final _serviceAreaController = TextEditingController();

  List<ServiceArea> _serviceAreas = [];
  final Set<String> _acceptedSpecies = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
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
    _serviceAreaController.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _pendingAvatar = File(picked.path));
  }

  Future<void> _editLocation() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ShelterLocationPickerPage(organizationId: widget.organizationId)),
    );
    if (saved == true) {
      final doc = await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get();
      final address = doc.data()?['shelterAddress'] as String?;
      if (address != null && address.isNotEmpty && mounted) {
        setState(() => _locationController.text = address);
      }
    }
  }

  void _addServiceArea() {
    final raw = _serviceAreaController.text.trim();
    if (raw.isEmpty) return;
    final normalized = normalizeForMatch(raw);
    if (_serviceAreas.any((s) => s.normalizedName == normalized)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That service area is already added.'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    setState(() {
      _serviceAreas = [..._serviceAreas, ServiceArea(name: raw, normalizedName: normalized)];
      _serviceAreaController.clear();
    });
  }

  void _removeServiceArea(ServiceArea area) => setState(() => _serviceAreas = _serviceAreas.where((s) => s != area).toList());

  String? _websiteError(String v) {
    if (v.trim().isEmpty) return null; // optional
    final ok = RegExp(r'^https?://[\w.-]+\.[A-Za-z]{2,}.*$').hasMatch(v.trim());
    return ok ? null : 'Enter a valid URL starting with http:// or https://';
  }

  Future<void> _save() async {
    if (_saving) return;
    final emailError = AppValidators.email(_emailController.text, required: false);
    final phoneError = AppValidators.phFlexiblePhone(_phoneController.text, required: false);
    final websiteError = _websiteError(_websiteController.text);
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

    setState(() => _saving = true);
    try {
      var avatarUrl = _avatarUrl;
      if (_pendingAvatar != null) {
        final ref = FirebaseStorage.instance.ref('organizations/${widget.organizationId}/profile/avatar.jpg');
        await ref.putFile(_pendingAvatar!);
        avatarUrl = await ref.getDownloadURL();
      }

      await _repo.updateProfile(
        organizationId: widget.organizationId,
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        avatarUrl: avatarUrl,
        location: _locationController.text.trim(),
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
          IconButton(
            icon: const Icon(Icons.people_outline, color: AppColors.background),
            tooltip: 'Staff Members',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => StaffMembersPage(organizationId: widget.organizationId)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
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
                _label('Location'),
                Row(
                  children: [
                    Expanded(child: _readonlyish(_locationController)),
                    const SizedBox(width: 8),
                    OutlinedButton(onPressed: _editLocation, child: const Text('Edit')),
                  ],
                ),
                const SizedBox(height: 16),
                _label('Service Areas'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final area in _serviceAreas)
                      Chip(
                        label: Text(area.name),
                        onDeleted: () => _removeServiceArea(area),
                        backgroundColor: AppColors.lavenderrspwn,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _serviceAreaController,
                        decoration: const InputDecoration(hintText: 'Add a city, e.g. Quezon City'),
                        onSubmitted: (_) => _addServiceArea(),
                      ),
                    ),
                    IconButton(onPressed: _addServiceArea, icon: const Icon(Icons.add_circle_outline, color: AppColors.greenrspwn)),
                  ],
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
                        : Text('Save', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
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
