import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'animal_record_detail_page.dart';
import 'create_animal_record_page.dart';

enum _SortOption {
  recentlyUpdated,
  nameAsc,
  nameDesc,
  newestIntake,
  oldestIntake,
  age,
  species,
  adoptionStatus,
}

extension on _SortOption {
  String get label => switch (this) {
        _SortOption.recentlyUpdated => 'Recently Updated',
        _SortOption.nameAsc => 'Name A–Z',
        _SortOption.nameDesc => 'Name Z–A',
        _SortOption.newestIntake => 'Newest Intake',
        _SortOption.oldestIntake => 'Oldest Intake',
        _SortOption.age => 'Age',
        _SortOption.species => 'Species',
        _SortOption.adoptionStatus => 'Adoption Status',
      };
}

class AnimalRecordsPage extends ConsumerStatefulWidget {
  const AnimalRecordsPage({super.key});

  @override
  ConsumerState<AnimalRecordsPage> createState() => _AnimalRecordsPageState();
}

class _AnimalRecordsPageState extends ConsumerState<AnimalRecordsPage> {
  String _speciesFilter = 'All';
  String _statusFilter = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();
  _SortOption _sort = _SortOption.recentlyUpdated;

  // Extra filters (spec section 12) — surfaced via the tune icon's sheet
  // rather than the compact chip row, since the row is already used for
  // species/status.
  bool? _adoptableOnly;
  bool? _inTreatmentOnly;
  bool? _vaccinatedOnly;
  bool? _hasRescueBackground;
  bool _includeArchived = false;

  final List<String> _statusFilters = [
    'All', 'Adoptable', 'In Treatment', 'Adopted', 'Deceased', 'Closed'
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'Adoptable':     return AppColors.yellowrspwn;
      case 'In Treatment':  return AppColors.pinkrspwn;
      case 'Adopted':       return AppColors.lavenderrspwn;
      case 'Deceased':      return AppColors.slaterspwn;
      case 'Closed':        return AppColors.tearspwn;
      default:              return AppColors.slaterspwn;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesSearch(AnimalRecord a, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return a.name.toLowerCase().contains(q) ||
        a.species.toLowerCase().contains(q) ||
        a.breed.toLowerCase().contains(q) ||
        a.tags.any((t) => t.toLowerCase().contains(q)) ||
        (a.hasSourceCase && shortCaseId(a.linkedCaseId).toLowerCase().contains(q)) ||
        shortCaseId(a.id).toLowerCase().contains(q) ||
        a.rescuedBy.toLowerCase().contains(q);
  }

  bool _matchesFilters(AnimalRecord a) {
    if (!_includeArchived && a.archived) return false;
    if (_speciesFilter != 'All' && a.species != (_speciesFilter == 'Dogs' ? 'Dog' : 'Cat')) return false;
    if (_statusFilter != 'All') {
      final want = _statusFilter.toLowerCase().replaceAll(' ', '_');
      if (want == 'in_treatment') {
        if (a.currentCaseId == null) return false;
      } else if (a.adoptionStatus != want) {
        return false;
      }
    }
    if (_adoptableOnly == true && !a.isAdoptable) return false;
    if (_inTreatmentOnly == true && a.currentCaseId == null) return false;
    if (_vaccinatedOnly == true && !a.vaccinated) return false;
    if (_hasRescueBackground == true && a.rescueBackground.isEmpty) return false;
    return true;
  }

  int? _leadingNumber(String s) {
    final match = RegExp(r'\d+').firstMatch(s);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  List<AnimalRecord> _sorted(List<AnimalRecord> records) {
    final list = [...records];
    int byDateDesc(DateTime? a, DateTime? b) => (b ?? DateTime(0)).compareTo(a ?? DateTime(0));
    switch (_sort) {
      case _SortOption.recentlyUpdated:
        list.sort((a, b) => byDateDesc(a.updatedAt ?? a.createdAt, b.updatedAt ?? b.createdAt));
        break;
      case _SortOption.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortOption.nameDesc:
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _SortOption.newestIntake:
        list.sort((a, b) => byDateDesc(a.createdAt, b.createdAt));
        break;
      case _SortOption.oldestIntake:
        list.sort((a, b) => byDateDesc(b.createdAt, a.createdAt));
        break;
      case _SortOption.age:
        list.sort((a, b) {
          final an = _leadingNumber(a.age);
          final bn = _leadingNumber(b.age);
          if (an == null && bn == null) return 0;
          if (an == null) return 1;
          if (bn == null) return -1;
          return an.compareTo(bn);
        });
        break;
      case _SortOption.species:
        list.sort((a, b) => a.species.toLowerCase().compareTo(b.species.toLowerCase()));
        break;
      case _SortOption.adoptionStatus:
        list.sort((a, b) => a.adoptionStatus.compareTo(b.adoptionStatus));
        break;
    }
    return list;
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filter & Sort', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Text('Sort by', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _SortOption.values
                      .map((s) => ChoiceChip(
                            label: Text(s.label),
                            selected: _sort == s,
                            selectedColor: AppColors.yellowrspwn,
                            onSelected: (_) => setSheetState(() => _sort = s),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                Text('Filters', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Adoptable only'),
                  value: _adoptableOnly ?? false,
                  onChanged: (v) => setSheetState(() => _adoptableOnly = v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('In treatment only'),
                  value: _inTreatmentOnly ?? false,
                  onChanged: (v) => setSheetState(() => _inTreatmentOnly = v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Vaccinated (on file) only'),
                  value: _vaccinatedOnly ?? false,
                  onChanged: (v) => setSheetState(() => _vaccinatedOnly = v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Has rescue background'),
                  value: _hasRescueBackground ?? false,
                  onChanged: (v) => setSheetState(() => _hasRescueBackground = v),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include archived'),
                  value: _includeArchived,
                  onChanged: (v) => setSheetState(() => _includeArchived = v ?? false),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {});
                      Navigator.pop(ctx);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    ),
                    child: Text('Apply', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(allAnimalRecordsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.background),
          onPressed: () {},
        ),
        title: Text('Animal Records',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search name, species, breed, tag, case ID…',
                        hintStyle: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textPrimary
                                .withValues(alpha: 0.6)),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textPrimary, size: 20),
                        border: InputBorder.none,
                        contentPadding:
                        const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _openFilterSheet,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.tune,
                        color: AppColors.textPrimary, size: 20),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Species + Status filters row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Species filter
                _FilterChip(
                  label: 'Dogs',
                  selected: _speciesFilter == 'Dogs',
                  onTap: () => setState(() =>
                  _speciesFilter =
                  _speciesFilter == 'Dogs' ? 'All' : 'Dogs'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Cats',
                  selected: _speciesFilter == 'Cats',
                  onTap: () => setState(() =>
                  _speciesFilter =
                  _speciesFilter == 'Cats' ? 'All' : 'Cats'),
                ),
                const Spacer(),
                // Status filter dropdown
                PopupMenuButton<String>(
                  onSelected: (val) =>
                      setState(() => _statusFilter = val),
                  color: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (_) => _statusFilters
                      .map((s) => PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        if (s != 'All')
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _statusColor(s),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(s,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ))
                      .toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusFilter == 'All'
                          ? AppColors.greenrspwn
                          : _statusColor(_statusFilter),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_statusFilter,
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down,
                            size: 16, color: AppColors.textPrimary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Animal list
          Expanded(
            child: recordsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('Could not load animal records: $e',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ),
              data: (all) {
                final filtered = all.where((a) => _matchesFilters(a) && _matchesSearch(a, _searchQuery)).toList();
                final sorted = _sorted(filtered);

                if (sorted.isEmpty) {
                  return Center(
                    child: Text('No animal records found.',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sorted.length,
                  separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final a = sorted[index];
                    return _AnimalCard(
                      animal: a,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnimalRecordDetailPage(
                            animalId: a.id,
                            data: a.raw,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Create Animal Record button
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const CreateAnimalRecordPage()),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                minimumSize: const Size(double.infinity, 50),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: Text('Create Animal Record',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final AnimalRecord animal;
  final VoidCallback onTap;

  const _AnimalCard({
    required this.animal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Cheap, doc-level-only attention signals — no extra subcollection
    // watches on the list page (see animal_record_repository.dart's
    // streamAllAnimalRecords doc comment on why this stays client-side and
    // bounded to what's already loaded).
    final needsAttention = <String>[
      if (!animal.vaccinated) 'Vaccine',
      if (animal.currentCaseId != null) 'In Treatment',
    ];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: animal.photoUrls.isNotEmpty
                  ? Image.network(animal.photoUrls.first,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _photoPlaceholder())
                  : _photoPlaceholder(),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(animal.name.isNotEmpty ? animal.name : animal.species,
                            style: GoogleFonts.tiltWarp(
                                fontSize: 15,
                                color: AppColors.textPrimary)),
                      ),
                      Icon(
                        animal.sex == 'Female' ? Icons.female : Icons.male,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  Text(animal.breed.isNotEmpty ? animal.breed : animal.species,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                  if (animal.age.isNotEmpty)
                    Text(animal.age,
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  Text(animal.description,
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final t in needsAttention)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.yellowrspwn.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(t, style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
                        ),
                      if (animal.isReserved)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.lavenderrspwn,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Reserved', style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
                        ),
                      if (animal.archived)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.slaterspwn,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('Archived', style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoPlaceholder() => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppColors.tearspwn,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.pets,
            size: 32, color: AppColors.textSecondary),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.greenrspwn
              : AppColors.lavenderrspwn,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ),
    );
  }
}
