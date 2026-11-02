import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/services/animal_record_export_service.dart';

/// Preview / Share / Save entry point for AnimalRecordExportService — the
/// bottom-sheet UI equivalent of ExportTransferSheet, for a single Animal
/// Record instead of a transfer packet.
Future<void> showAnimalRecordExportSheet(BuildContext context, {required AnimalRecord animal}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _AnimalRecordExportSheetBody(animal: animal),
  );
}

class _AnimalRecordExportSheetBody extends StatefulWidget {
  final AnimalRecord animal;
  const _AnimalRecordExportSheetBody({required this.animal});

  @override
  State<_AnimalRecordExportSheetBody> createState() => _AnimalRecordExportSheetBodyState();
}

class _AnimalRecordExportSheetBodyState extends State<_AnimalRecordExportSheetBody> {
  final _service = AnimalRecordExportService();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not export record: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Export Record PDF', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              'Profile, Medical Profile, Vaccines, Special Needs (if any), and a short history summary. '
              'Never includes adoption application, payment, or reporter contact details.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
              )
            else ...[
              _ExportOptionTile(
                icon: Icons.visibility_outlined,
                label: 'Preview',
                onTap: () => _run(() => _service.preview(widget.animal)),
              ),
              _ExportOptionTile(
                icon: Icons.ios_share_outlined,
                label: 'Share',
                onTap: () => _run(() => _service.share(widget.animal)),
              ),
              _ExportOptionTile(
                icon: Icons.save_alt_outlined,
                label: 'Save',
                onTap: () => _run(() => _service.saveToDevice(widget.animal)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExportOptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ExportOptionTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon, color: AppColors.textPrimary),
        title: Text(label, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ),
    );
  }
}
