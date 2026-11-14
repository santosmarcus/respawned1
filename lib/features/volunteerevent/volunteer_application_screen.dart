import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_application.dart';
import 'package:respawnd1/core/repos/volunteer_application_repository.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Banner on the Volunteer page: apply, or see where an application stands.
class VolunteerApplicationBanner extends StatelessWidget {
  const VolunteerApplicationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    return StreamBuilder<VolunteerApplication?>(
      stream: VolunteerApplicationRepository().watchMine(uid),
      builder: (context, snap) {
        final app = snap.data;
        final title = app == null ? 'Become a verified volunteer' : 'Volunteer application: ${app.status.label}';
        final body = app == null
            ? 'Apply to help with rescues, events or shelter care. The organization reviews every application.'
            : app.status == VolunteerApplicationStatus.rejected && (app.reviewNote ?? '').isNotEmpty
                ? app.reviewNote!
                : 'You can update your details at any time. Changes go back for review.';
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(body, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: AppButtons.primary,
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => VolunteerApplicationScreen(existing: app)),
                ),
                child: Text(app == null ? 'Apply' : 'Update',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class VolunteerApplicationScreen extends StatefulWidget {
  const VolunteerApplicationScreen({super.key, this.existing});

  final VolunteerApplication? existing;

  @override
  State<VolunteerApplicationScreen> createState() => _VolunteerApplicationScreenState();
}

class _VolunteerApplicationScreenState extends State<VolunteerApplicationScreen> {
  late final _name = TextEditingController(text: widget.existing?.name ?? FirebaseAuth.instance.currentUser?.displayName ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _availability = TextEditingController(text: widget.existing?.availability ?? '');
  late final _area = TextEditingController(text: widget.existing?.serviceArea ?? '');
  late final _experience = TextEditingController(text: widget.existing?.experience ?? '');
  late final Set<VolunteerCategory> _categories = {...?widget.existing?.categories};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _availability, _area, _experience]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final app = VolunteerApplication(
      uid: uid,
      name: _name.text,
      phone: _phone.text,
      categories: _categories,
      availability: _availability.text,
      serviceArea: _area.text,
      experience: _experience.text,
    );
    final problems = app.validate();
    if (problems.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(problems.first));
      return;
    }
    setState(() => _saving = true);
    try {
      await VolunteerApplicationRepository().submit(app);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Application sent. The organization will review it.'),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not send the application: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _field(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: Text('Volunteer application', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Only approved volunteers take part in physical rescues. Event and shelter-care help is arranged by the organization.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(controller: _name, decoration: _field('Full name')),
          const SizedBox(height: 10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: _field('Phone number')),
          const SizedBox(height: 16),
          Text('How would you like to help?', style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
          for (final c in VolunteerCategory.values)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _categories.contains(c),
              activeColor: AppColors.textPrimary,
              title: Text(c.label, style: GoogleFonts.zain(fontSize: 14)),
              onChanged: (v) => setState(() => v == true ? _categories.add(c) : _categories.remove(c)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _availability,
            decoration: _field('Availability', hint: 'e.g. weekends, weekday evenings'),
          ),
          const SizedBox(height: 10),
          TextField(controller: _area, decoration: _field('Area you can cover', hint: 'City or barangay')),
          const SizedBox(height: 10),
          TextField(
            controller: _experience,
            maxLines: 3,
            decoration: _field('Experience with animals (optional)'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _submit,
              style: AppButtons.primary,
              child: Text(_saving ? 'Sending…' : 'Send application',
                  style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}
