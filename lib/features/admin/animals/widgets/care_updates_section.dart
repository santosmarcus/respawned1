import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/care_update.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/media_attachments.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart';

/// Notes from the people looking after an animal: observations, vet
/// follow-ups and feeding, each with optional photos or videos. Carers and
/// staff both add them; the admin's Medical tab and the carer's home show
/// the same list.
class CareUpdatesSection extends ConsumerWidget {
  const CareUpdatesSection({super.key, required this.animal, this.limit});

  final AnimalRecord animal;

  /// Show only the newest few (carer home); null shows all loaded.
  final int? limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updatesAsync = ref.watch(careUpdatesProvider(animal.id));
    final updates = updatesAsync.asData?.value ?? const <CareUpdate>[];
    final shown = limit == null ? updates : updates.take(limit!).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Care updates', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
            ),
            TextButton.icon(
              onPressed: () => showAddCareUpdateSheet(context, animal),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add update'),
            ),
          ],
        ),
        if (updatesAsync.hasError)
          Text('Could not load care updates.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.error))
        else if (updatesAsync.isLoading && updates.isEmpty)
          const Padding(
            padding: EdgeInsets.all(8),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (updates.isEmpty)
          Text('No care updates yet.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
        else
          for (final u in shown) _CareUpdateTile(update: u),
        if (limit != null && updates.length > limit!)
          Text('${updates.length - limit!} older updates on the animal record.',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _CareUpdateTile extends StatelessWidget {
  const _CareUpdateTile({required this.update});

  final CareUpdate update;

  @override
  Widget build(BuildContext context) {
    final when = update.createdAt == null ? 'Just now' : formatDateTime(update.createdAt!);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(20)),
                child: Text(update.type.label,
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${update.authorName ?? 'Carer'} · $when',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(update.note, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
          if (update.media.isNotEmpty) ...[
            const SizedBox(height: 8),
            MediaThumbStrip(media: update.media, size: 56),
          ],
        ],
      ),
    );
  }
}

/// Up to this many photos or videos per update.
const int _kMaxMedia = 3;

Future<void> showAddCareUpdateSheet(BuildContext context, AnimalRecord animal) {
  return showReasonSheet<void>(context, builder: (_) => _AddCareUpdateSheet(animal: animal));
}

class _AddCareUpdateSheet extends ConsumerStatefulWidget {
  const _AddCareUpdateSheet({required this.animal});

  final AnimalRecord animal;

  @override
  ConsumerState<_AddCareUpdateSheet> createState() => _AddCareUpdateSheetState();
}

class _AddCareUpdateSheetState extends ConsumerState<_AddCareUpdateSheet> {
  CareUpdateType _type = CareUpdateType.observation;
  final _note = TextEditingController();
  final _unusedOther = TextEditingController();
  final List<PickedMedia> _media = [];
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    _unusedOther.dispose();
    super.dispose();
  }

  Future<void> _addMedia() async {
    final picked = await pickPhotoOrVideo(context);
    if (picked != null && mounted) setState(() => _media.add(picked));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final uploaded = <MediaRef>[
        for (var i = 0; i < _media.length; i++)
          await uploadMedia(_media[i], folder: 'animalRecords/${widget.animal.id}/careUpdates', name: '${stamp}_$i'),
      ];
      await ref.read(animalMedicationRepositoryProvider).addCareUpdate(
            animalId: widget.animal.id,
            type: _type,
            note: _note.text,
            media: uploaded,
          );
      navigator.pop();
      messenger.showSnackBar(appSnackBar('Care update saved.', kind: AppMessageKind.success));
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(appSnackBar('Could not save the update: $e', kind: AppMessageKind.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.animal.name.isEmpty ? 'this animal' : widget.animal.name;
    return ReasonSheetFrame(
      title: 'Care update',
      subtitle: 'For $name. Staff and other carers will see it on the animal record.',
      confirmLabel: 'Save update',
      destructive: false,
      busy: _saving,
      onConfirm: _note.text.trim().isEmpty ? null : _save,
      children: [
        ReasonChoiceList<CareUpdateType>(
          options: [for (final t in CareUpdateType.values) ReasonOption(t, t.label)],
          selected: [_type],
          otherController: _unusedOther,
          onChanged: (v) => setState(() => _type = v.first),
        ),
        const SizedBox(height: 8),
        ReasonTextField(
          controller: _note,
          label: 'What did you see or do?',
          hint: switch (_type) {
            CareUpdateType.observation => 'e.g. Eating well, limping less on the left leg',
            CareUpdateType.vetFollowUp => 'e.g. Wound checked at the clinic, stitches out next Friday',
            CareUpdateType.feeding => 'e.g. Finished breakfast, refused the wet food',
          },
          maxLines: 3,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < _media.length; i++)
              InputChip(
                avatar: Icon(_media[i].isVideo ? Icons.videocam_outlined : Icons.photo_outlined, size: 18),
                label: Text(_media[i].isVideo ? 'Video ${i + 1}' : 'Photo ${i + 1}'),
                onDeleted: _saving ? null : () => setState(() => _media.removeAt(i)),
              ),
            if (_media.length < _kMaxMedia)
              OutlinedButton.icon(
                onPressed: _saving ? null : _addMedia,
                style: AppButtons.outline,
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Photo or video'),
              ),
          ],
        ),
      ],
    );
  }
}
