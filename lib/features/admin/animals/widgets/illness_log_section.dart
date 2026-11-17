import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/illness_entry.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';

/// Analytics gap 5: the animal's illness log on its Medical tab. Staff
/// record an illness (condition, onset, contagious, isolated) and mark it
/// resolved; Analytics counts them per period.

CollectionReference<Map<String, dynamic>> _illnesses(String animalId) =>
    FirebaseFirestore.instance.collection('animals').doc(animalId).collection('illnesses');

final illnessesProvider = StreamProvider.autoDispose.family<List<IllnessEntry>, String>((ref, animalId) {
  return _illnesses(animalId).orderBy('onsetDate', descending: true).snapshots().map(
        (s) => s.docs.map((d) => IllnessEntry.fromFirestore(d, animalId)).whereType<IllnessEntry>().toList(),
      );
});

String get _actorName {
  final u = FirebaseAuth.instance.currentUser;
  return (u?.displayName?.trim().isNotEmpty ?? false) ? u!.displayName!.trim() : (u?.email ?? 'Staff');
}

class IllnessLogSection extends ConsumerWidget {
  const IllnessLogSection({super.key, required this.animal});
  final AnimalRecord animal;

  Future<void> _add(BuildContext context) async {
    final entry = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _AddIllnessDialog());
    if (entry == null) return;
    try {
      await _illnesses(animal.id).add({
        ...entry,
        'recordedBy': FirebaseAuth.instance.currentUser?.uid,
        'recordedByName': _actorName,
        'createdAt': FieldValue.serverTimestamp(),
        'organizationId': animal.raw['organizationId'],
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    }
  }

  Future<void> _resolve(BuildContext context, IllnessEntry e) async {
    try {
      await _illnesses(animal.id).doc(e.id).update({
        'resolvedAt': Timestamp.now(),
        'resolvedBy': FirebaseAuth.instance.currentUser?.uid,
        'resolvedByName': _actorName,
      });
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $err')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(illnessesProvider(animal.id));
    final entries = list.asData?.value ?? const <IllnessEntry>[];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Illness Log', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              TextButton(
                onPressed: () => _add(context),
                child: Text('Record Illness',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
          if (list.hasError)
            Text('Could not load the illness log.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.error))
          else if (entries.isEmpty)
            Text('No illness recorded.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
          else
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.condition,
                              style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          Text(
                            [
                              'Since ${formatDate(e.onset)}',
                              if (e.contagious) 'contagious',
                              if (e.isolated) 'isolated',
                              if (e.resolvedAt != null) 'resolved ${formatDate(e.resolvedAt!)}',
                              if ((e.notes ?? '').isNotEmpty) e.notes!,
                            ].join(' · '),
                            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (e.active)
                      TextButton(
                        onPressed: () => _resolve(context, e),
                        child: Text('Resolved',
                            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.greenrspwn)),
                      ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _AddIllnessDialog extends StatefulWidget {
  const _AddIllnessDialog();

  @override
  State<_AddIllnessDialog> createState() => _AddIllnessDialogState();
}

class _AddIllnessDialogState extends State<_AddIllnessDialog> {
  final _condition = TextEditingController();
  final _notes = TextEditingController();
  DateTime _onset = DateTime.now();
  bool _contagious = false;
  bool _isolated = false;

  @override
  void dispose() {
    _condition.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record illness'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _condition,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Condition (e.g. kennel cough, parvo, URI)'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Signs started'),
              subtitle: Text(formatDate(_onset)),
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _onset,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _onset = d);
              },
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _contagious,
              onChanged: (v) => setState(() => _contagious = v ?? false),
              title: const Text('Contagious to other animals'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _isolated,
              onChanged: (v) => setState(() => _isolated = v ?? false),
              title: const Text('Moved to isolation'),
            ),
            TextField(
              controller: _notes,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Notes (optional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final c = _condition.text.trim();
            if (c.isEmpty) return;
            Navigator.pop(context, {
              'condition': c,
              'onsetDate': Timestamp.fromDate(_onset),
              'contagious': _contagious,
              'isolated': _isolated,
              if (_notes.text.trim().isNotEmpty) 'notes': _notes.text.trim(),
              'resolvedAt': null,
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
