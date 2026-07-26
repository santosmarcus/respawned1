import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'animal_page.dart';

//Data Model
enum AnimalGender { male, female }
enum AnimalCategory { dog, cat }

class Animal {
  final int id;
  final String animalRecordId;
  final String name;
  final String species;
  final String breed;
  final String age;
  final String description;
  final List<String> healthTags;
  final bool specialNeeds;
  final AnimalGender gender;
  final String sex;
  final AnimalCategory category;
  final Color cardColor;
  final String? badge;
  bool favorited;

  // Filterable attributes, sourced from the intake form (Size, Coat Length,
  // Key Characteristics, Rescue Background).
  final String size;
  final String coatLength;
  final List<String> keyCharacteristics;
  final List<String> rescueBackground;

  final String? publicStatus;
  final String? photoUrl;
  final List<String> photoUrls;

  Animal({
    required this.id,
    this.animalRecordId = '',
    required this.name,
    this.species = '',
    required this.breed,
    required this.age,
    required this.description,
    required this.healthTags,
    this.specialNeeds = false,
    required this.gender,
    this.sex = '',
    required this.category,
    required this.cardColor,
    this.badge,
    this.favorited = false,
    this.size = 'Medium',
    this.coatLength = 'Short',
    this.keyCharacteristics = const [],
    this.rescueBackground = const [],
    this.publicStatus,
    this.photoUrl,
    this.photoUrls = const [],
  });
}

int stableIntIdFor(String value) {
  var hash = 0x811C9DC5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash & 0x7FFFFFFF;
}


const List<Color> _cardColorRotation = [
  AppColors.greenrspwn,
  AppColors.lavenderrspwn,
  AppColors.pinkrspwn,
  AppColors.tearspwn,
];

String _publicStatusLabel(AnimalRecord r) {
  if (r.isAdopted) return 'Adopted';
  if (r.isReserved) return 'Reserved';
  if (r.isAdoptable) return 'Available';
  return 'Not Available';
}

bool isPubliclyVisible(AnimalRecord a) => !a.archived && !a.isDeceased && (a.isAdoptable || a.isReserved);

List<String> healthTagsOf(AnimalRecord r) => [
  if (r.vaccinated) 'Vaccinated',
  if (r.spayedNeutered) 'Spayed/Neutered',
  if (r.dewormed) 'Dewormed',
  if (r.specialNeeds) 'Special Needs',
];

String ageGroupOf(AnimalRecord r) {
  final match = RegExp(r'(\d+)\s*(week|month|year)s?', caseSensitive: false)
      .firstMatch(r.age);
  if (match == null) return 'Adult';
  final amount = int.tryParse(match.group(1)!) ?? 0;
  final unit = match.group(2)!.toLowerCase();

  if (unit == 'week') return 'Baby';
  if (unit == 'month') return amount <= 6 ? 'Baby' : 'Young';
  // years
  if (amount < 1) return 'Baby';
  if (amount <= 2) return 'Young';
  if (amount <= 7) return 'Adult';
  return 'Senior';
}


Animal animalRecordToCard(AnimalRecord r, int index) {
  final healthTags = healthTagsOf(r);
  final sexLower = r.sex.toLowerCase();
  final speciesLower = r.species.toLowerCase();

  return Animal(
    id: stableIntIdFor(r.id),
    animalRecordId: r.id,
    name: r.name.isNotEmpty ? r.name : r.species,
    species: r.species,
    breed: r.breed,
    age: r.age,
    description: r.description,
    healthTags: healthTags,
    specialNeeds: r.specialNeeds,
    gender: sexLower == 'female' ? AnimalGender.female : AnimalGender.male,
    sex: r.sex,
    category: speciesLower == 'cat' ? AnimalCategory.cat : AnimalCategory.dog,
    cardColor: _cardColorRotation[index % _cardColorRotation.length],
    size: r.size,
    coatLength: r.coatLength,
    keyCharacteristics: r.keyCharacteristics,
    rescueBackground: r.rescueBackground,
    publicStatus: _publicStatusLabel(r),
    photoUrl: r.photoUrls.isNotEmpty ? r.photoUrls.first : null,
    photoUrls: r.photoUrls,
  );
}

const List<String> kSizeOptions = ['Small', 'Medium', 'Large'];
const List<String> kCoatLengthOptions = ['Short', 'Medium', 'Long'];
const List<String> kAgeGroupOptions = ['Baby (0-6 months)', 'Young (6 months - 2 years)', 'Adult (2-7 years)', 'Senior (7+ years)'];

const List<String> kHealthOptions = [
  'Vaccinated',
  'Spayed/Neutered',
  'Dewormed',
];

const List<String> kSpecialNeedsOptions = ['Special Needs'];

class AdoptionFilters {
  final Set<String> breeds;
  final Set<String> sizes;
  final Set<String> coatLengths;
  final Set<String> ageGroups;
  final Set<String> health;
  final Set<String> keyCharacteristics;
  final Set<String> rescueBackground;

  const AdoptionFilters({
    this.breeds = const {},
    this.sizes = const {},
    this.coatLengths = const {},
    this.ageGroups = const {},
    this.health = const {},
    this.keyCharacteristics = const {},
    this.rescueBackground = const {},
  });

  bool get isEmpty =>
      breeds.isEmpty &&
          sizes.isEmpty &&
          coatLengths.isEmpty &&
          ageGroups.isEmpty &&
          health.isEmpty &&
          keyCharacteristics.isEmpty &&
          rescueBackground.isEmpty;

  int get activeCount =>
      breeds.length +
          sizes.length +
          coatLengths.length +
          ageGroups.length +
          health.length +
          keyCharacteristics.length +
          rescueBackground.length;

  AdoptionFilters copyWith({
    Set<String>? breeds,
    Set<String>? sizes,
    Set<String>? coatLengths,
    Set<String>? ageGroups,
    Set<String>? health,
    Set<String>? keyCharacteristics,
    Set<String>? rescueBackground,
  }) {
    return AdoptionFilters(
      breeds: breeds ?? this.breeds,
      sizes: sizes ?? this.sizes,
      coatLengths: coatLengths ?? this.coatLengths,
      ageGroups: ageGroups ?? this.ageGroups,
      health: health ?? this.health,
      keyCharacteristics: keyCharacteristics ?? this.keyCharacteristics,
      rescueBackground: rescueBackground ?? this.rescueBackground,
    );
  }


  bool _matchesAny(Set<String> selected, String value) =>
      selected.isEmpty || selected.contains(value);

  bool _matchesAll(Set<String> selected, List<String> values) =>
      selected.isEmpty || selected.every(values.contains);

  bool matches(AnimalRecord animal) {
    return _matchesAny(breeds, animal.breed) &&
        _matchesAny(sizes, animal.size) &&
        _matchesAny(coatLengths, animal.coatLength) &&
        _matchesAny(ageGroups, ageGroupOf(animal)) &&
        _matchesAll(health, healthTagsOf(animal)) &&
        _matchesAll(keyCharacteristics, animal.keyCharacteristics) &&
        _matchesAll(rescueBackground, animal.rescueBackground);
  }
}

// AdoptionPage

class AdoptionPage extends ConsumerStatefulWidget {
  const AdoptionPage({super.key});

  @override
  ConsumerState<AdoptionPage> createState() => _AdoptionPageState();
}

class _AdoptionPageState extends ConsumerState<AdoptionPage> {
  int _filterIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  Set<int> _favoriteIds = {};

  List<AnimalRecord> _lastLoadedRecords = const [];

  AdoptionFilters _activeFilters = const AdoptionFilters();

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AnimalRecord> _applyTabsSearchAndFilters(List<AnimalRecord> records) {
    final q = _searchQuery.toLowerCase();
    return records.where((p) {
      final species = p.species.toLowerCase();
      final matchCategory = _filterIndex == 0 ||
          (_filterIndex == 1 && species == 'dog') ||
          (_filterIndex == 2 && species == 'cat');
      final matchSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.breed.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
      final matchPreferences = _activeFilters.matches(p);
      return matchCategory && matchSearch && matchPreferences;
    }).toList();
  }

  List<String> get _availableBreeds =>
      _lastLoadedRecords.map((a) => a.breed).where((b) => b.isNotEmpty).toSet().toList()..sort();

  Future<void> _openFilterSheet() async {
    final result = await showModalBottomSheet<AdoptionFilters>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AdoptionFilterSheet(
        initialFilters: _activeFilters,
        breedOptions: _availableBreeds,
      ),
    );
    if (result != null) {
      setState(() => _activeFilters = result);
    }
  }

  Future<void> _toggleFavorite(AnimalRecord animal) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final id = stableIntIdFor(animal.id);

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(id.toString());

    final nowFavorited = !_favoriteIds.contains(id);
    setState(() {
      if (nowFavorited) {
        _favoriteIds = {..._favoriteIds, id};
      } else {
        _favoriteIds = {..._favoriteIds}..remove(id);
      }
    });

    if (nowFavorited) {
      await favRef.set({
        'animalId': id,
        'name': animal.name,
        'breed': animal.breed,
        'age': animal.age,
        'description': animal.description,
        'gender': animal.sex,
        'category': animal.species,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } else {
      await favRef.delete();
    }
  }

  Future<void> _loadFavorites() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();

    final favIds = snapshot.docs.map((d) => int.tryParse(d.id)).whereType<int>().toSet();

    if (mounted) setState(() => _favoriteIds = favIds);
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(allAnimalRecordsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: true,
        centerTitle: true,
        title: Text(
          'Adopt a Stray',
          style: GoogleFonts.tiltWarp(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'My Profile',
          ),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
          else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserProfile()),
            );
          }
        },
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),

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
                      style: GoogleFonts.zain(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: GoogleFonts.zain(
                          fontSize: 15,
                          color: AppColors.textPrimary.withValues(alpha: 0.6),
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
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
                        child: const Icon(
                          Icons.tune,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                      ),
                      if (_activeFilters.activeCount > 0)
                        Positioned(
                          top: -4,
                          right: -4,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE05C5C),
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: Text(
                              '${_activeFilters.activeCount}',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.zain(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // Filter tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filterIndex == 0,
                  onTap: () => setState(() => _filterIndex = 0),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Dogs',
                  selected: _filterIndex == 1,
                  onTap: () => setState(() => _filterIndex = 1),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Cats',
                  selected: _filterIndex == 2,
                  onTap: () => setState(() => _filterIndex = 2),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Expanded(
            child: recordsAsync.when(
              loading: () => const _LoadingState(),
              error: (error, _) => _ErrorState(
                onRetry: () => ref.invalidate(allAnimalRecordsProvider),
              ),
              data: (records) {
                final visible = records.where(isPubliclyVisible).toList();
                _lastLoadedRecords = visible;

                final filtered = _applyTabsSearchAndFilters(visible);

                if (filtered.isEmpty) {
                  return _EmptyState(
                    filterIndex: _filterIndex,
                    hasActiveFilters: _activeFilters.activeCount > 0 || _searchQuery.isNotEmpty,
                    onClearFilters: () {
                      setState(() {
                        _activeFilters = const AdoptionFilters();
                        _searchQuery = '';
                        _searchController.clear();
                      });
                    },
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final record = filtered[index];
                    return AnimalRecordCard(
                      animal: record,
                      favorited: _favoriteIds.contains(stableIntIdFor(record.id)),
                      onFavorite: () => _toggleFavorite(record),
                      publicStatusLabel: _publicStatusLabel(record),
                      extraChips: [for (final t in healthTagsOf(record)) CardChip(t)],
                      onTap: () {
                        final animal = animalRecordToCard(record, index)
                          ..favorited = _favoriteIds.contains(stableIntIdFor(record.id));
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AnimalPage(
                              animal: animal,
                              onFavoriteToggle: () => _toggleFavorite(record),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// Loading / error states

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Could not load animals available for adoption.',
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Please check your connection and try again.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              child: Text('Retry', style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

// Filter chip

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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.greenrspwn : AppColors.lavenderrspwn,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.zain(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final int filterIndex;
  final bool hasActiveFilters;
  final VoidCallback onClearFilters;

  const _EmptyState({
    required this.filterIndex,
    required this.hasActiveFilters,
    required this.onClearFilters,
  });

  String get _subject {
    switch (filterIndex) {
      case 1:
        return 'dogs';
      case 2:
        return 'cats';
      default:
        return 'dogs or cats';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppColors.yellowrspwn.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.pets,
                size: 40,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              hasActiveFilters ? 'No $_subject match your search' : 'No adoptions yet',
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasActiveFilters
                  ? 'Try adjusting your filters or search to see more pets.'
                  : 'There are currently no animals available for adoption. Please check again later.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary.withValues(alpha: 0.7),
              ),
            ),
            if (hasActiveFilters) ...[
              const SizedBox(height: 20),
              TextButton(
                onPressed: onClearFilters,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: Text(
                  'Clear Filters',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class AdoptionFilterSheet extends StatefulWidget {
  final AdoptionFilters initialFilters;
  final List<String> breedOptions;

  const AdoptionFilterSheet({
    super.key,
    required this.initialFilters,
    required this.breedOptions,
  });

  @override
  State<AdoptionFilterSheet> createState() => _AdoptionFilterSheetState();
}

class _AdoptionFilterSheetState extends State<AdoptionFilterSheet> {
  late Set<String> _breeds;
  late Set<String> _sizes;
  late Set<String> _coatLengths;
  late Set<String> _ageGroups;
  late Set<String> _health;
  late Set<String> _keyCharacteristics;
  late Set<String> _rescueBackground;

  @override
  void initState() {
    super.initState();
    _breeds = {...widget.initialFilters.breeds};
    _sizes = {...widget.initialFilters.sizes};
    _coatLengths = {...widget.initialFilters.coatLengths};
    _ageGroups = {...widget.initialFilters.ageGroups};
    _health = {...widget.initialFilters.health};
    _keyCharacteristics = {...widget.initialFilters.keyCharacteristics};
    _rescueBackground = {...widget.initialFilters.rescueBackground};
  }

  void _toggle(Set<String> set, String value) {
    setState(() {
      if (set.contains(value)) {
        set.remove(value);
      } else {
        set.add(value);
      }
    });
  }

  void _clearAll() {
    setState(() {
      _breeds.clear();
      _sizes.clear();
      _coatLengths.clear();
      _ageGroups.clear();
      _health.clear();
      _keyCharacteristics.clear();
      _rescueBackground.clear();
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      AdoptionFilters(
        breeds: _breeds,
        sizes: _sizes,
        coatLengths: _coatLengths,
        ageGroups: _ageGroups,
        health: _health,
        keyCharacteristics: _keyCharacteristics,
        rescueBackground: _rescueBackground,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filter Pets',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: _clearAll,
                      child: Text(
                        'Clear All',
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 20),

              // Scrollable filter sections
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  children: [
                    if (widget.breedOptions.isNotEmpty) ...[
                      _FilterSection(
                        label: 'Breed',
                        child: _ChipGroup(
                          options: widget.breedOptions,
                          selected: _breeds,
                          onToggle: (v) => _toggle(_breeds, v),
                        ),
                      ),
                      const SizedBox(height: 22),
                    ],
                    _FilterSection(
                      label: 'Size',
                      child: _ChipGroup(
                        options: kSizeOptions,
                        selected: _sizes,
                        onToggle: (v) => _toggle(_sizes, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Coat Length',
                      child: _ChipGroup(
                        options: kCoatLengthOptions,
                        selected: _coatLengths,
                        onToggle: (v) => _toggle(_coatLengths, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    // Lets adopters looking specifically for a puppy/kitten
                    // or a senior pet (or anything in between) filter by
                    // life stage directly, derived from each animal's own
                    // age (see ageGroupOf) rather than reading every age
                    // string one card at a time.
                    _FilterSection(
                      label: 'Age',
                      child: _ChipGroup(
                        options: kAgeGroupOptions,
                        selected: _ageGroups,
                        onToggle: (v) => _toggle(_ageGroups, v),
                      ),
                    ),
                    const SizedBox(height: 22),

                    _FilterSection(
                      label: 'Special Needs',
                      child: _CheckboxGroup(
                        options: kSpecialNeedsOptions,
                        selected: _health,
                        onToggle: (v) => _toggle(_health, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Health Status',
                      child: _CheckboxGroup(
                        options: kHealthOptions,
                        selected: _health,
                        onToggle: (v) => _toggle(_health, v),
                      ),
                    ),
                    const SizedBox(height: 22),

                    _FilterSection(
                      label: 'Temperament',
                      child: _CheckboxGroup(
                        options: kTemperamentValues,
                        selected: _keyCharacteristics,
                        onToggle: (v) => _toggle(_keyCharacteristics, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Compatibility',
                      child: _CheckboxGroup(
                        options: kCompatibilityValues,
                        selected: _keyCharacteristics,
                        onToggle: (v) => _toggle(_keyCharacteristics, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Training',
                      child: _CheckboxGroup(
                        options: kTrainingValues,
                        selected: _keyCharacteristics,
                        onToggle: (v) => _toggle(_keyCharacteristics, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Rescue Background',
                      child: _CheckboxGroup(
                        options: kRescueBackgroundValues,
                        selected: _rescueBackground,
                        onToggle: (v) => _toggle(_rescueBackground, v),
                      ),
                    ),
                  ],
                ),
              ),

              // Apply button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      'Apply Filters',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _FilterSection extends StatelessWidget {
  final String label;
  final Widget child;

  const _FilterSection({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.tiltWarp(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _ChipGroup extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _ChipGroup({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((o) {
        final isSelected = selected.contains(o);
        return GestureDetector(
          onTap: () => onToggle(o),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.greenrspwn
                  : AppColors.lavenderrspwn.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected
                    ? AppColors.greenrspwn
                    : AppColors.slaterspwn,
                width: 1.2,
              ),
            ),
            child: Text(
              o,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}


class _CheckboxGroup extends StatelessWidget {
  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  const _CheckboxGroup({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 0,
      children: options.map((o) {
        final isSelected = selected.contains(o);
        return SizedBox(
          width: 170,
          child: InkWell(
            onTap: () => onToggle(o),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggle(o),
                    activeColor: AppColors.greenrspwn,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      o,
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}