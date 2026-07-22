import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
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

  // Extra filters — surfaced inside the Filter & Sort sheet, along with
  // _statusFilter (the old standalone "All ▾" dropdown next to the species
  // chips has been removed — this sheet is now the single filter/sort
  // entry point, per spec).
  bool? _adoptableOnly;
  bool? _inTreatmentOnly;
  bool? _vaccinatedOnly;
  bool? _hasRescueBackground;
  bool _includeArchived = false;

  // 'Closed' dropped — it never corresponded to any real AnimalRecord field
  // value (adoptionStatus is only not_ready/adoptable/reserved/adopted/
  // deceased).
  static const List<String> _statusFilters = ['All', 'Adoptable', 'In Treatment', 'Adopted', 'Deceased'];

  Color _statusColor(String status) {
    switch (status) {
      case 'Adoptable':     return AppColors.yellowrspwn;
      case 'In Treatment':  return AppColors.pinkrspwn;
      case 'Adopted':       return AppColors.lavenderrspwn;
      case 'Deceased':      return AppColors.slaterspwn;
      default:              return AppColors.slaterspwn;
    }
  }

  int get _sheetActiveFilterCount =>
      (_statusFilter != 'All' ? 1 : 0) +
      (_adoptableOnly == true ? 1 : 0) +
      (_inTreatmentOnly == true ? 1 : 0) +
      (_vaccinatedOnly == true ? 1 : 0) +
      (_hasRescueBackground == true ? 1 : 0) +
      (_includeArchived ? 1 : 0);

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
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) => SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Filter & Sort', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                      TextButton(
                        onPressed: () => setSheetState(() {
                          _statusFilter = 'All';
                          _adoptableOnly = null;
                          _inTreatmentOnly = null;
                          _vaccinatedOnly = null;
                          _hasRescueBackground = null;
                          _includeArchived = false;
                        }),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        Text('Sort by', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
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
                        Text('Status', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _statusFilters
                              .map((s) => ChoiceChip(
                                    label: Text(s),
                                    selected: _statusFilter == s,
                                    selectedColor: _statusFilter == 'All' ? AppColors.greenrspwn : _statusColor(s),
                                    onSelected: (_) => setSheetState(() => _statusFilter = s),
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
                      ],
                    ),
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
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(allAnimalRecordsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            tooltip: 'Menu',
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
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
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.yellowrspwn,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.tune,
                            color: AppColors.textPrimary, size: 20),
                      ),
                      if (_sheetActiveFilterCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Color(0xFFE05C5C), shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text(
                              '$_sheetActiveFilterCount',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Species quick chips — the standalone status dropdown that used
          // to sit here was removed; status is now one of the Filter & Sort
          // sheet's own options (see _openFilterSheet), with the badge
          // above showing how many sheet filters (including status) are
          // active.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
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
                    // Cheap, doc-level-only attention signals — no extra
                    // subcollection watches on the list page (see
                    // animal_record_repository.dart's streamAllAnimalRecords
                    // doc comment on why this stays client-side and bounded
                    // to what's already loaded).
                    final chips = <CardChip>[
                      if (!a.vaccinated) const CardChip('Vaccine'),
                      if (a.currentCaseId != null) const CardChip('In Treatment', color: AppColors.pinkrspwn),
                      if (a.isReserved) const CardChip('Reserved', color: AppColors.lavenderrspwn),
                      if (a.archived) const CardChip('Archived', color: AppColors.slaterspwn),
                    ];
                    return AnimalRecordCard(
                      animal: a,
                      extraChips: chips,
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
