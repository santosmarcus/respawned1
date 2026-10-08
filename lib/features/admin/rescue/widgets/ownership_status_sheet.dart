import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

const List<String> kOwnershipStatusValues = ['Unknown', 'No known owner', 'Possible owner', 'Owner identified'];
const List<String> kOwnedAnimalCategoryValues = ['Lost animal', 'Neglect concern', 'Abandonment concern', 'Other'];

typedef OwnershipResult = ({
  String ownershipStatus,
  String? ownedAnimalCategory,
  String? ownerName,
  String? ownerContact,
  String? ownershipNotes,
});

/// Owner-identification form (spec §1). Never exposes another applicant's
/// or a different case's owner details — this only ever edits the single
/// case it was opened from. Owner contact fields are optional (a "Possible
/// owner" case may have no confirmed contact yet).
Future<OwnershipResult?> showOwnershipStatusSheet(
  BuildContext context, {
  String? currentOwnershipStatus,
  String? currentCategory,
  String? currentOwnerName,
  String? currentOwnerContact,
  String? currentNotes,
}) {
  return showModalBottomSheet<OwnershipResult>(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _OwnershipStatusSheetBody(
      currentOwnershipStatus: currentOwnershipStatus,
      currentCategory: currentCategory,
      currentOwnerName: currentOwnerName,
      currentOwnerContact: currentOwnerContact,
      currentNotes: currentNotes,
    ),
  );
}

class _OwnershipStatusSheetBody extends StatefulWidget {
  final String? currentOwnershipStatus;
  final String? currentCategory;
  final String? currentOwnerName;
  final String? currentOwnerContact;
  final String? currentNotes;
  const _OwnershipStatusSheetBody({
    this.currentOwnershipStatus,
    this.currentCategory,
    this.currentOwnerName,
    this.currentOwnerContact,
    this.currentNotes,
  });

  @override
  State<_OwnershipStatusSheetBody> createState() => _OwnershipStatusSheetBodyState();
}

class _OwnershipStatusSheetBodyState extends State<_OwnershipStatusSheetBody> {
  late String _status = widget.currentOwnershipStatus ?? kOwnershipStatusValues.first;
  String? _category;
  late final _nameController = TextEditingController(text: widget.currentOwnerName ?? '');
  late final _contactController = TextEditingController(text: widget.currentOwnerContact ?? '');
  late final _notesController = TextEditingController(text: widget.currentNotes ?? '');

  @override
  void initState() {
    super.initState();
    _category = widget.currentCategory;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOwnerFields = _status == 'Possible owner' || _status == 'Owner identified';
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ownership Status', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kOwnershipStatusValues
                  .map((s) => ChoiceChip(
                        label: Text(s),
                        selected: _status == s,
                        selectedColor: AppColors.yellowrspwn,
                        onSelected: (_) => setState(() => _status = s),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text('Case Type', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kOwnedAnimalCategoryValues
                  .map((c) => ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        selectedColor: AppColors.lavenderrspwn,
                        onSelected: (_) => setState(() => _category = _category == c ? null : c),
                      ))
                  .toList(),
            ),
            if (showOwnerFields) ...[
              const SizedBox(height: 16),
              Text('Owner Name', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              TextField(controller: _nameController, decoration: const InputDecoration(hintText: 'Optional')),
              const SizedBox(height: 12),
              Text('Owner Contact', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              TextField(controller: _contactController, decoration: const InputDecoration(hintText: 'Phone number or other contact')),
            ],
            const SizedBox(height: 12),
            Text('Notes / Evidence', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(controller: _notesController, maxLines: 3, decoration: const InputDecoration(hintText: 'Observations, evidence, context')),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, (
                  ownershipStatus: _status,
                  ownedAnimalCategory: _category,
                  ownerName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
                  ownerContact: _contactController.text.trim().isEmpty ? null : _contactController.text.trim(),
                  ownershipNotes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
                )),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Save Ownership Info'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
