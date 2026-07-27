import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/services/transfer_export_service.dart';

/// Shared "Export Transfer Details" entry point (Transfer/Export spec) —
/// the ONE place that offers animal selection (single/multiple/all) plus
/// destination info before handing off to [TransferExportService]. Any
/// admin screen that needs an export action should open this same sheet
/// rather than building its own animal picker.
Future<void> showExportTransferSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required String transferredByUid,
  required String transferredByName,
  int? preselectedAnimalIndex,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ExportTransferSheet(
      rescueCase: rescueCase,
      transferredByUid: transferredByUid,
      transferredByName: transferredByName,
      preselectedAnimalIndex: preselectedAnimalIndex,
    ),
  );
}

class _ExportTransferSheet extends StatefulWidget {
  final RescueCase rescueCase;
  final String transferredByUid;
  final String transferredByName;
  final int? preselectedAnimalIndex;

  const _ExportTransferSheet({
    required this.rescueCase,
    required this.transferredByUid,
    required this.transferredByName,
    this.preselectedAnimalIndex,
  });

  @override
  State<_ExportTransferSheet> createState() => _ExportTransferSheetState();
}

class _ExportTransferSheetState extends State<_ExportTransferSheet> {
  late Set<int> _selectedIndexes;
  String _destinationType = 'Clinic';
  final _destinationController = TextEditingController();
  bool _busy = false;

  static const _destinationTypes = ['Clinic', 'Organization', 'Authorized Volunteer'];

  @override
  void initState() {
    super.initState();
    // Defaults to "All animals" unless opened from a specific animal's
    // context (spec: single/multiple/all selection).
    _selectedIndexes = widget.preselectedAnimalIndex != null
        ? {widget.preselectedAnimalIndex!}
        : {for (var i = 0; i < widget.rescueCase.animals.length; i++) i};
    if (_selectedIndexes.isEmpty && widget.rescueCase.animals.isEmpty) {
      // Legacy single-animal case with no animals[] array at all.
      _selectedIndexes = {0};
    }
  }

  @override
  void dispose() {
    _destinationController.dispose();
    super.dispose();
  }

  int get _animalCount => widget.rescueCase.animals.isEmpty ? 1 : widget.rescueCase.animals.length;

  Future<void> _run(Future<void> Function(TransferExportService) action) async {
    if (_selectedIndexes.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select at least one animal.'), backgroundColor: Colors.redAccent));
      return;
    }
    if (_destinationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a destination name.'), backgroundColor: Colors.redAccent));
      return;
    }
    setState(() => _busy = true);
    try {
      await action(TransferExportService());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.redAccent));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            Text('Export Transfer Details',
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('Only the selected animals\' rescue, treatment, and animal record information is included.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            Text('Animals', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _animalCount; i++)
                  FilterChip(
                    label: Text('Animal ${i + 1}'),
                    selected: _selectedIndexes.contains(i),
                    onSelected: (sel) => setState(() => sel ? _selectedIndexes.add(i) : _selectedIndexes.remove(i)),
                  ),
                ActionChip(
                  label: const Text('Select All'),
                  onPressed: () => setState(() => _selectedIndexes = {for (var i = 0; i < _animalCount; i++) i}),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Destination type', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final t in _destinationTypes)
                  ChoiceChip(
                    label: Text(t),
                    selected: _destinationType == t,
                    onSelected: (_) => setState(() => _destinationType = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Destination name', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            TextField(
              controller: _destinationController,
              decoration: InputDecoration(
                hintText: 'e.g. City Animal Clinic',
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.slaterspwn)),
              ),
            ),
            const SizedBox(height: 20),
            if (_busy)
              const Center(child: CircularProgressIndicator())
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _run((s) => s.preview(
                            rescueCase: widget.rescueCase,
                            animalIndexes: _selectedIndexes.toList()..sort(),
                            destinationType: _destinationType,
                            destinationName: _destinationController.text.trim(),
                            transferredByName: widget.transferredByName,
                          )),
                      child: const Text('Preview'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => _run((s) => s.exportAndShare(
                            rescueCase: widget.rescueCase,
                            animalIndexes: _selectedIndexes.toList()..sort(),
                            destinationType: _destinationType,
                            destinationName: _destinationController.text.trim(),
                            transferredByUid: widget.transferredByUid,
                            transferredByName: widget.transferredByName,
                          )),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Share'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _run((s) => s.saveToDevice(
                            rescueCase: widget.rescueCase,
                            animalIndexes: _selectedIndexes.toList()..sort(),
                            destinationType: _destinationType,
                            destinationName: _destinationController.text.trim(),
                            transferredByName: widget.transferredByName,
                          )),
                      child: const Text('Save to Device'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
