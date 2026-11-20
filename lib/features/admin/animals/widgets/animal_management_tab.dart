import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/animals/facebook_share_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/animal_logs_section.dart';
import 'package:respawnd1/features/admin/animals/widgets/animal_record_export_sheet.dart';
import 'package:respawnd1/features/admin/animals/widgets/transfer_animal_record_sheet.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';
import 'package:respawnd1/features/collartag/animal_tag_scan.dart' show kAnimalTagPrefix;

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
          appSnackBar('Action failed: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _actorId => FirebaseAuth.instance.currentUser?.uid;
  String? get _actorEmail => FirebaseAuth.instance.currentUser?.email;
  String get _actorName {
    final n = FirebaseAuth.instance.currentUser?.displayName?.trim();
    return (n != null && n.isNotEmpty) ? n : 'Admin Staff';
  }

  // Firestore completes a write only once the server confirms it, so with a
  // bad connection Add QR would otherwise wait with no sign of progress.
  static const _qrSaveTimeout = Duration(seconds: 20);
  bool _qrSaving = false;

  /// Runs a QR tag write, showing what went wrong instead of failing
  /// silently. Returns null when it failed.
  Future<T?> _saveQr<T>(Future<T> Function() action) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _qrSaving = true;
    });
    try {
      return await action().timeout(_qrSaveTimeout);
    } catch (e) {
      final message = switch (e) {
        TimeoutException() =>
          "The QR tag hasn't reached the server yet. Check your connection: it finishes saving once you're back online.",
        FirebaseException(code: 'permission-denied') =>
          "You don't have permission to change this animal's QR tag. Ask an Organization Admin for animal records access.",
        FirebaseException(:final message) => 'Couldn’t save the QR tag: ${message ?? e}',
        _ => 'Couldn’t save the QR tag: $e',
      };
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(message, kind: AppMessageKind.error));
      }
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _qrSaving = false;
        });
      }
    }
  }

  Future<void> _showQrTag() async {
    if (_busy) return;
    final animal = widget.animal;
    final repo = ref.read(animalRecordRepositoryProvider);
    final name = animal.name.isEmpty ? 'this animal' : animal.name;
    var code = animal.qrTagId;
    if (code == null || code.isEmpty) {
      code = await _saveQr(() => repo.ensureQrTag(
            animalId: animal.id,
            existing: null,
            actorId: _actorId,
            actorName: _actorName,
            actorEmail: _actorEmail,
          ));
      if (code == null) return;
    }

    while (true) {
      if (!mounted) return;
      final shown = code!;
      final choice = await showDialog<_QrTagAction>(
        context: context,
        builder: (_) => _QrTagDialog(title: 'QR tag for $name', code: shown),
      );
      if (!mounted) return;
      switch (choice) {
        case _QrTagAction.regenerate:
          final ok = await showConfirmActionDialog(
            context,
            title: 'Replace this QR code?',
            message: 'A new code replaces $shown. Tags already printed with $shown will stop opening '
                '$name, so reprint and replace them. Use this when a tag was lost, damaged or misused.',
            confirmLabel: 'Replace Code',
            destructive: true,
          );
          if (!ok || !mounted) continue;
          final next = await _saveQr(() => repo.regenerateQrTag(
                animalId: animal.id,
                previous: shown,
                actorId: _actorId,
                actorName: _actorName,
                actorEmail: _actorEmail,
              ));
          if (next != null) code = next;
        case _QrTagAction.remove:
          final ok = await showConfirmActionDialog(
            context,
            title: 'Remove this QR code?',
            message: 'Tags already printed with $shown will stop opening $name. '
                'You can add a new QR tag later. The old code stays in View Logs.',
            confirmLabel: 'Remove Code',
            destructive: true,
          );
          if (!ok || !mounted) continue;
          final removed = await _saveQr(() async {
            await repo.removeQrTag(
              animalId: animal.id,
              previous: shown,
              actorId: _actorId,
              actorName: _actorName,
              actorEmail: _actorEmail,
            );
            return true;
          });
          if (removed == true && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(appSnackBar('QR tag removed.'));
          }
          return;
        case null:
          return;
      }
    }
  }

  Future<void> _togglePublicProfile() async {
    final animal = widget.animal;
    await _run(() => ref.read(animalRecordRepositoryProvider).setPublicProfileHidden(
          animalId: animal.id,
          hidden: !animal.publicProfileHidden,
          actorId: _actorId,
          actorName: _actorName,
          actorEmail: _actorEmail,
        ));
  }

  Future<void> _setCareStatus() async {
    final animal = widget.animal;
    final result = await showReasonPicker<CareStatus>(
      context,
      title: 'Shelter status',
      subtitle: 'How ${animal.name.isEmpty ? 'this animal' : animal.name} is being cared for right now.',
      options: [for (final s in CareStatus.values) ReasonOption(s, '${s.label} · ${s.help}')],
      initial: animal.careStatus,
      confirmLabel: 'Save status',
      destructive: false,
      noteLabel: 'Note',
    );
    if (result == null) return;
    await _run(() => ref.read(animalRecordRepositoryProvider).setCareStatus(
          animalId: animal.id,
          status: result.value,
          previous: animal.careStatus,
          note: result.note,
          actorId: _actorId,
          actorName: _actorName,
          actorEmail: _actorEmail,
        ));
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
    await _run(() => ref.read(animalRecordRepositoryProvider).setArchived(
          animalId: animal.id,
          archived: !animal.archived,
          actorId: _actorId,
          actorName: _actorName,
          actorEmail: _actorEmail,
        ));
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
          actorId: _actorId,
          actorName: _actorName,
          actorEmail: _actorEmail,
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
    await _run(() => ref.read(animalRecordRepositoryProvider).markAdopted(
          animalId: widget.animal.id,
          actorId: _actorId,
          actorName: _actorName,
          actorEmail: _actorEmail,
        ));
  }

  Future<void> _exportRecord() async {
    await showAnimalRecordExportSheet(context, animal: widget.animal);
  }

  void _generateTag() {
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar('QR/NFC tag generation is not available yet.'),
    );
  }

  // Composer: pick details, photos and descriptions, then post to the
  // organization's Page (owner/Admin or Staff with facebookPublish, which
  // the Cloud Function re-checks) or share through any app (anyone here).
  Future<void> _shareToFacebook() => openFacebookShare(context, [widget.animal]);

  void _viewLogs() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => AnimalLogsSheet(animalId: widget.animal.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final isTerminal = animal.isAdopted || animal.isDeceased;
    // Once the animal has actually left this shelter's custody (adopted or
    // transferred out), marking it deceased here would rewrite a since-
    // closed record instead of correcting anything real — see
    // AnimalRecordRepository.markDeceased's own re-read guard, which
    // enforces this same rule server-side so a stale UI can never bypass
    // it.
    final deceasedBlocked = animal.isDeceased || animal.isAdopted || animal.isTransferredOut;
    final canPublishToFacebook =
        ref.watch(currentOrganizationCapabilitiesProvider).asData?.value.canPublishToFacebook ?? false;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ActionTile(
            icon: Icons.health_and_safety_outlined,
            label: 'Shelter Status: ${animal.careStatus?.label ?? 'Not set'}',
            subtitle: 'In Shelter, Isolation or Recovering',
            enabled: !_busy && !isTerminal && !animal.archived,
            onTap: _setCareStatus,
          ),
          _ActionTile(
            icon: animal.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
            label: animal.archived ? 'Restore Record' : 'Archive',
            enabled: !_busy,
            onTap: _toggleArchive,
          ),
          _ActionTile(
            icon: Icons.qr_code_2,
            label: (animal.qrTagId ?? '').isEmpty ? 'Add QR Tag' : 'Show QR Tag',
            subtitle: _qrSaving ? 'Saving QR tag…' : null,
            enabled: !_busy,
            onTap: _showQrTag,
          ),
          _ActionTile(
            icon: animal.publicProfileHidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            label: animal.publicProfileHidden ? 'Show on Public Profile' : 'Hide from Public Profile',
            enabled: !_busy,
            onTap: _togglePublicProfile,
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
            enabled: !_busy && !deceasedBlocked,
            subtitle: (!animal.isDeceased && deceasedBlocked)
                ? 'Unavailable after the animal has been transferred or adopted.'
                : null,
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
            icon: Icons.facebook,
            label: 'Share to Facebook',
            enabled: !_busy,
            subtitle: canPublishToFacebook
                ? 'Post to the Page, or share a link to the full profile'
                : 'Share a link to the full profile. Posting to the Page needs permission from an Organization Admin.',
            onTap: _shareToFacebook,
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

enum _QrTagAction { regenerate, remove }

/// Shows an animal's QR tag, with Replace and Remove. Pops a [_QrTagAction],
/// or null for Close.
class _QrTagDialog extends StatelessWidget {
  final String title;
  final String code;
  const _QrTagDialog({required this.title, required this.code});

  static const double _qrSize = 220;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // AlertDialog sizes itself from its content's intrinsic width, and
          // QrImageView is a LayoutBuilder, which can't report one: unsized,
          // the dialog throws during layout and only its dimmed barrier
          // shows. A fixed-size box answers the question for it.
          SizedBox.square(
            dimension: _qrSize,
            child: QrImageView(
              data: '$kAnimalTagPrefix$code',
              size: _qrSize,
              backgroundColor: Colors.white,
              errorStateBuilder: (_, _) => Center(
                child: Text('Couldn’t draw this QR code.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(code, style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Print or attach this code to the animal’s kennel or collar.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _QrTagAction.remove),
          child: Text('Remove', style: GoogleFonts.zain(color: AppColors.error, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _QrTagAction.regenerate),
          child: Text('New Code', style: GoogleFonts.zain(color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close', style: GoogleFonts.zain(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ),
      ],
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
                  Text(_date == null ? 'Date (optional)' : formatDate(_date!),
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
          style: AppButtons.danger,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}

