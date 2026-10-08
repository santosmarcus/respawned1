import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/transfer_animal_record_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/confirm_action_dialog.dart';

/// Organization-management actions — deliberately separate from the
/// Medical tab's clinical content. Only enabled when they make sense for
/// the animal's current status (see each button's own guard below).
class AnimalManagementTab extends ConsumerStatefulWidget {
  final AnimalRecord animal;
  const AnimalManagementTab({super.key, required this.animal});

  @override
  ConsumerState<AnimalManagementTab> createState() => _AnimalManagementTabState();
}

class _AnimalManagementTabState extends ConsumerState<AnimalManagementTab> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Action failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleArchive() async {
    final animal = widget.animal;
    final confirmed = await showConfirmActionDialog(
      context,
      title: animal.archived ? 'Restore this record?' : 'Archive this record?',
      message: animal.archived
          ? 'This animal will reappear in normal active lists. Its rescue, treatment, adoption, return, and intake history is preserved.'
          : 'This hides the animal from normal active lists without deleting anything — it can be restored later.',
      confirmLabel: animal.archived ? 'Restore Record' : 'Archive',
    );
    if (!confirmed) return;
    await _run(() => ref.read(animalRecordRepositoryProvider).setArchived(animalId: animal.id, archived: !animal.archived));
  }

  Future<void> _transfer() async {
    await showTransferAnimalRecordSheet(context, animal: widget.animal);
  }

  Future<void> _markDeceased() async {
    final result = await showDialog<_DeceasedResult>(
      context: context,
      builder: (_) => _MarkDeceasedDialog(),
    );
    if (result == null) return;
    await _run(() => ref.read(animalRecordRepositoryProvider).markDeceased(
          animalId: widget.animal.id,
          date: result.date,
          cause: result.cause,
          notes: result.notes,
        ));
  }

  Future<void> _markAdopted() async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Mark as Adopted?',
      message: 'Only confirm this once the adoption application for this animal has actually been approved — '
          'this does not check application status itself.',
      confirmLabel: 'Mark Adopted',
    );
    if (!confirmed) return;
    await _run(() => ref.read(animalRecordRepositoryProvider).markAdopted(animalId: widget.animal.id));
  }

  void _exportRecord() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Export Record (PDF) is not available yet.')),
    );
  }

  void _generateTag() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('QR/NFC tag generation is not available yet.')),
    );
  }

  void _viewLogs() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _LogsSheet(animalId: widget.animal.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final isTerminal = animal.isAdopted || animal.isDeceased;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionTile(
            icon: animal.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            label: animal.archived ? 'Restore Record' : 'Archive',
            enabled: !_busy,
            onTap: _toggleArchive,
          ),
          _ActionTile(
            icon: Icons.compare_arrows,
            label: 'Transfer',
            enabled: !_busy && !isTerminal && !animal.archived,
            onTap: _transfer,
          ),
          _ActionTile(
            icon: Icons.pets_outlined,
            label: 'Mark as Deceased',
            enabled: !_busy && !animal.isDeceased,
            onTap: _markDeceased,
          ),
          _ActionTile(
            icon: Icons.home_outlined,
            label: 'Mark as Adopted',
            enabled: !_busy && !isTerminal && !animal.archived,
            onTap: _markAdopted,
          ),
          _ActionTile(
            icon: Icons.picture_as_pdf_outlined,
            label: 'Export Record (PDF)',
            enabled: !_busy,
            onTap: _exportRecord,
          ),
          _ActionTile(
            icon: Icons.qr_code_2_outlined,
            label: 'Generate Tag',
            enabled: false,
            subtitle: 'Not available yet',
            onTap: _generateTag,
          ),
          _ActionTile(
            icon: Icons.history,
            label: 'View Logs',
            enabled: !_busy,
            onTap: _viewLogs,
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final String? subtitle;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        leading: Icon(icon, color: enabled ? AppColors.textPrimary : AppColors.textSecondary),
        title: Text(label,
            style: GoogleFonts.zain(
                fontSize: 14, fontWeight: FontWeight.w600, color: enabled ? AppColors.textPrimary : AppColors.textSecondary)),
        subtitle: subtitle != null ? Text(subtitle!, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)) : null,
        trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ),
    );
  }
}

class _DeceasedResult {
  final DateTime? date;
  final String? cause;
  final String? notes;
  const _DeceasedResult({this.date, this.cause, this.notes});
}

class _MarkDeceasedDialog extends StatefulWidget {
  @override
  State<_MarkDeceasedDialog> createState() => _MarkDeceasedDialogState();
}

class _MarkDeceasedDialogState extends State<_MarkDeceasedDialog> {
  DateTime? _date;
  final _causeController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void dispose() {
    _causeController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Mark as Deceased', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This does not delete the animal record — it stays in Medical/Management history.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2010),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _date = picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.textPrimary))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_date == null ? 'Date (optional)' : '${_date!.month}/${_date!.day}/${_date!.year}',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                  const Icon(Icons.calendar_today_outlined, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _causeController,
            decoration: const InputDecoration(hintText: 'Cause (optional)', isDense: true),
            style: GoogleFonts.zain(fontSize: 13),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notesController,
            maxLines: 2,
            decoration: const InputDecoration(hintText: 'Notes (optional)', isDense: true),
            style: GoogleFonts.zain(fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel', style: GoogleFonts.zain(color: AppColors.textSecondary)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(
              context,
              _DeceasedResult(
                date: _date,
                cause: _causeController.text.trim().isEmpty ? null : _causeController.text.trim(),
                notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
              )),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE05353), foregroundColor: Colors.white),
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

class _LogsSheet extends ConsumerWidget {
  final String animalId;
  const _LogsSheet({required this.animalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(managementLogsProvider(animalId));
    final logs = logsAsync.asData?.value ?? const <Map<String, dynamic>>[];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Management Logs', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            if (logs.isEmpty)
              Text('No management actions recorded yet.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) => Text(logs[i]['action'] as String? ?? '-',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
