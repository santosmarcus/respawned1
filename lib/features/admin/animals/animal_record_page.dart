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

// 'Recently Updated' removed — it overlapped with 'Newest Intake' (both
// ultimately read createdAt for most records, since updatedAt is only set
// on later edits) and added a confusing second "newest-first" option.
enum _SortOption {
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
  _SortOption _sort = _SortOption.newestIntake;

  // Extra filters — surfaced inside the Filter & Sort sheet, along with
  // _statusFilter (the old standalone "All ▾" dropdown next to the species
  // chips has been removed — this sheet is now the single filter/sort
  // entry point, per spec).
  bool? _adoptableOnly;
  bool? _inTreatmentOnly;
  bool? _vaccinatedOnly;
  bool? _hasRescueBackground;
  // Reuses the existing AnimalRecord.archived field — 'Active' (default)
  // excludes archived records the same way the old _includeArchived bool
  // did; 'Archived'/'All' are the new addition. Never a second archive
  // field.
  String _recordStatus = 'Active';
  static const List<String> _recordStatusOptions = ['Active', 'Archived', 'All'];

  // Long-press multi-select — keyed by the real AnimalRecord doc id, never
  // a list index, so a selection stays valid even if filtering/sorting
  // changes what's visible. No bulk actions wired up yet; this just makes
  // the selection system itself ready for them.
  final Set<String> _selectedIds = {};
  bool get _selecting => _selectedIds.isNotEmpty;

  // List/Grid — page-local (no persistence layer exists in this project to
  // remember it across sessions); switching never re-queries Firestore,
  // both layouts read the same `sorted` list computed once per build.
  bool _isGrid = false;

  void _openRecord(BuildContext context, AnimalRecord a) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => AnimalRecordDetailPage(animalId: a.id, data: a.raw)),
      );

  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() => setState(_selectedIds.clear);

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
      (_speciesFilter != 'All' ? 1 : 0) +
      (_statusFilter != 'All' ? 1 : 0) +
      (_adoptableOnly == true ? 1 : 0) +
      (_inTreatmentOnly == true ? 1 : 0) +
      (_vaccinatedOnly == true ? 1 : 0) +
      (_hasRescueBackground == true ? 1 : 0) +
      (_recordStatus != 'Active' ? 1 : 0);

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
    if (_recordStatus == 'Active' && a.archived) return false;
    if (_recordStatus == 'Archived' && !a.archived) return false;
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
      case _SortOption.nameAsc:
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SortOption.nameDesc:
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case _SortOption.newestIntake:
        // AnimalRecord has no field distinct from createdAt for "when this
        // animal actually entered the shelter" (see AnimalRecord.fromMap's
        // own doc comment: a legacy 'intakeDate' field is folded into
        // createdAt on parse for older docs) — createdAt is the real intake
        // signal for every current writer, not merely a fallback. Records
        // missing it (byDateDesc's `?? DateTime(0)`) sort last, never crash.
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
                          _speciesFilter = 'All';
                          _statusFilter = 'All';
                          _adoptableOnly = null;
                          _inTreatmentOnly = null;
                          _vaccinatedOnly = null;
                          _hasRescueBackground = null;
                          _recordStatus = 'Active';
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
                        // Species — used to be two standalone Dogs/Cats
                        // chips sitting above the list outside this sheet;
                        // folded in here with the rest of Filter & Sort so
                        // there's one filtering surface, not two.
                        Text('Species', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: ['All', 'Dogs', 'Cats']
                              .map((s) => ChoiceChip(
                                    label: Text(s),
                                    selected: _speciesFilter == s,
                                    selectedColor: AppColors.yellowrspwn,
                                    onSelected: (_) => setSheetState(() => _speciesFilter = s),
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
                        const SizedBox(height: 16),
                        Text('Record Status', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _recordStatusOptions
                              .map((s) => ChoiceChip(
                                    label: Text(s),
                                    selected: _recordStatus == s,
                                    selectedColor: AppColors.yellowrspwn,
                                    onSelected: (_) => setSheetState(() => _recordStatus = s),
                                  ))
                              .toList(),
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

    return PopScope(
      // Android/system back exits selection mode first instead of leaving
      // the page — only allowed to pop normally once nothing is selected.
      canPop: !_selecting,
      onPopInvoked: (didPop) {
        if (!didPop && _selecting) _clearSelection();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      drawer: _selecting ? null : const AdminDrawer(active: AdminModule.records),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        automaticallyImplyLeading: !_selecting,
        leading: _selecting
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: AppColors.background),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        title: _selecting
            ? Text('${_selectedIds.length} selected',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.background))
            : null,
        actions: [
          if (_selecting)
            // Visible text label, not just a close icon — an icon alone
            // reads ambiguous (could look like "close the page").
            TextButton(
              onPressed: _clearSelection,
              child: Text('Cancel',
                  style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.background)),
            )
          else
            IconButton(
              icon: const Icon(Icons.notifications_outlined,
                  color: AppColors.background),
              onPressed: () {},
            ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Animal Records',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),

          const SizedBox(height: 16),

          // Search + filter — same styling as Rescue Reports (white
          // background, slate border, rounded 24) instead of the old solid
          // yellow box.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Search name, species, breed, tag, case ID…',
                              hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
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
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _sheetActiveFilterCount > 0 ? AppColors.yellowrspwn : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.slaterspwn),
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
                const SizedBox(width: 10),
                // List/Grid toggle — page-local only; the project has no
                // shared_preferences (or similar) dependency yet to persist
                // it across sessions, so it just resets to List on reopen.
                GestureDetector(
                  onTap: () => setState(() => _isGrid = !_isGrid),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    child: Tooltip(
                      message: _isGrid ? 'Switch to list view' : 'Switch to grid view',
                      child: Icon(_isGrid ? Icons.view_list_outlined : Icons.grid_view_outlined,
                          color: AppColors.textPrimary, size: 20, semanticLabel: _isGrid ? 'List view' : 'Grid view'),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Animal list — same resolved AnimalRecord source and same
          // search/filter/sort computation feeds both layouts, and
          // selection (_selectedIds) is shared state untouched by which
          // layout is active, so switching view never loses or re-queries
          // anything.
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

                if (_isGrid) {
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    // Max-extent delegate: 2 columns at normal phone
                    // widths, more only once there's enough width for them
                    // (tablets/landscape) — no hardcoded column count.
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 190,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.72,
                    ),
                    itemCount: sorted.length,
                    itemBuilder: (context, index) {
                      final a = sorted[index];
                      return AnimalRecordGridTile(
                        animal: a,
                        selected: _selectedIds.contains(a.id),
                        onTap: _selecting ? () => _toggleSelect(a.id) : () => _openRecord(context, a),
                        onLongPress: () => _toggleSelect(a.id),
                      );
                    },
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sorted.length,
                  separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final a = sorted[index];
                    final isSelected = _selectedIds.contains(a.id);
                    // Compact admin card (spec §6): no description, no
                    // health/attention chips — just image, name+gender,
                    // species/breed, age. The user-facing adoption list
                    // keeps its own chips untouched.
                    return AnimalRecordCard(
                      animal: a,
                      compact: true,
                      selected: isSelected,
                      // Tapping while selecting toggles instead of
                      // navigating; long-press always enters/adds to
                      // selection, keyed by the real doc id, never index.
                      onTap: _selecting ? () => _toggleSelect(a.id) : () => _openRecord(context, a),
                      onLongPress: () => _toggleSelect(a.id),
                    );
                  },
                );
              },
            ),
          ),

          // Create Animal Record button — hidden while selecting so it
          // can't be mistaken for a selection action.
          if (!_selecting)
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
      ),
    );
  }
}

