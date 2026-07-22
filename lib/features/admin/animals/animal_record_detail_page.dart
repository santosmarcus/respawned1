import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/admin/animals/create_animal_record_page.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/animal_management_tab.dart';
import 'package:respawnd1/features/admin/animals/widgets/animal_medical_tab.dart';
import 'package:respawnd1/features/admin/animals/widgets/animal_profile_tab.dart';

const String kNA = 'Not provided';

/// One animal record, not one rescue case — rescue history and every later
/// medical admission all live under this same record (see AnimalRecord /
/// MedicalEpisode). Three tabs: Profile, Medical, Management, behind one
/// consistent header.
class AnimalRecordDetailPage extends ConsumerStatefulWidget {
  final String animalId;
  final Map<String, dynamic> data;

  const AnimalRecordDetailPage({
    super.key,
    required this.animalId,
    required this.data,
  });

  @override
  ConsumerState<AnimalRecordDetailPage> createState() => _AnimalRecordDetailPageState();
}

class _AnimalRecordDetailPageState extends ConsumerState<AnimalRecordDetailPage> {
  int _tabIndex = 0;

  void _editProfile(AnimalRecord animal) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAnimalRecordPage(
          existingAnimalId: animal.id,
          existingData: animal.raw,
          linkedCaseId: animal.linkedCaseId.isEmpty ? null : animal.linkedCaseId,
        ),
      ),
    );
  }

  void _share(AnimalRecord animal) {
    final lines = [
      animal.name.isNotEmpty ? animal.name : animal.species,
      if (animal.species.isNotEmpty) animal.species,
      if (animal.breed.isNotEmpty) animal.breed,
      'Animal Record ID: ${shortCaseId(animal.id)}',
      if (animal.hasSourceCase) 'Rescue Case: #${shortCaseId(animal.linkedCaseId)}',
    ];
    SharePlus.instance.share(ShareParams(text: lines.join('\n')));
  }

  void _viewLogs(String animalId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ManagementLogsSheet(animalId: animalId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final liveAnimal = ref.watch(animalRecordProvider(widget.animalId)).asData?.value;
    final animal = liveAnimal ?? AnimalRecord.fromMap(widget.animalId, widget.data);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(animal.name.isNotEmpty ? animal.name : (animal.species.isNotEmpty ? animal.species : 'Animal Record'),
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppColors.background),
            onPressed: null,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppColors.background),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editProfile(animal);
                  break;
                case 'share':
                  _share(animal);
                  break;
                case 'logs':
                  _viewLogs(animal.id);
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit Profile')),
              PopupMenuItem(value: 'share', child: Text('Share')),
              PopupMenuItem(value: 'logs', child: Text('View Logs')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          _AnimalRecordHeader(
            animal: animal,
            tabIndex: _tabIndex,
            onTabChanged: (i) => setState(() => _tabIndex = i),
          ),
          Expanded(
            child: switch (_tabIndex) {
              0 => AnimalProfileTab(animal: animal),
              1 => AnimalMedicalTab(animal: animal),
              _ => AnimalManagementTab(animal: animal),
            },
          ),
        ],
      ),
    );
  }
}

/// Consistent across all three tabs — name, photo, species icon, current
/// status as supporting text, and the tab selector. Never the rescue Case
/// ID as the primary title (that's secondary, shown inside Profile/Medical
/// where relevant instead).
class _AnimalRecordHeader extends StatelessWidget {
  final AnimalRecord animal;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  const _AnimalRecordHeader({required this.animal, required this.tabIndex, required this.onTabChanged});

  String get _statusText {
    if (animal.archived) return 'Archived';
    if (animal.isDeceased) return 'Deceased';
    if (animal.isAdopted) return 'Adopted';
    if (animal.isReserved) return 'Reserved';
    if (animal.currentCaseId != null) return 'In Treatment';
    if (animal.isAdoptable) return 'Adoptable';
    return 'Not Ready for Adoption';
  }

  IconData get _speciesIcon => switch (animal.species.toLowerCase()) {
        'cat' => Icons.cruelty_free_outlined,
        'dog' => Icons.pets_outlined,
        _ => Icons.pets_outlined,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: animal.photoUrls.isNotEmpty
                        ? Image.network(animal.photoUrls.first,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatarPlaceholder())
                        : _avatarPlaceholder(),
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(color: AppColors.yellowrspwn, shape: BoxShape.circle),
                      child: Icon(_speciesIcon, size: 12, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(animal.name.isNotEmpty ? animal.name : animal.species,
                        style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary)),
                    Text(_statusText, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(50)),
            child: Row(
              children: [
                _TabButton(label: 'Profile', index: 0, selected: tabIndex == 0, onTap: onTabChanged),
                _TabButton(label: 'Medical', index: 1, selected: tabIndex == 1, onTap: onTabChanged),
                _TabButton(label: 'Management', index: 2, selected: tabIndex == 2, onTap: onTabChanged),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarPlaceholder() => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(14)),
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );
}

class _TabButton extends StatelessWidget {
  final String label;
  final int index;
  final bool selected;
  final ValueChanged<int> onTap;
  const _TabButton({required this.label, required this.index, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(label,
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

class _ManagementLogsSheet extends ConsumerWidget {
  final String animalId;
  const _ManagementLogsSheet({required this.animalId});

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
            if (logsAsync.isLoading && logs.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (logs.isEmpty)
              Text('No management actions recorded yet.',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 16),
                  itemBuilder: (context, i) {
                    final log = logs[i];
                    final ts = log['timestamp'];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log['action'] as String? ?? '-',
                                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              if ((log['details'] as String?)?.isNotEmpty ?? false)
                                Text(log['details'] as String,
                                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        if (ts != null)
                          Text('${ts.toDate().month}/${ts.toDate().day}/${ts.toDate().year}',
                              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
