import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
  final String name;
  final String breed;
  final String age;
  final String description;
  final List<String> healthTags;
  final AnimalGender gender;
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

  Animal({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    required this.description,
    required this.healthTags,
    required this.gender,
    required this.category,
    required this.cardColor,
    this.badge,
    this.favorited = false,
    this.size = 'Medium',
    this.coatLength = 'Short',
    this.keyCharacteristics = const [],
    this.rescueBackground = const [],
  });
}

final List<Animal> _allAnimals = [
  Animal(
    id: 1,
    name: 'Brownie',
    breed: 'Aspin',
    age: '2 year old',
    description: 'Playful brown dog',
    healthTags: const ['Vaccinated', 'Spayed/Neutered'],
    gender: AnimalGender.male,
    category: AnimalCategory.dog,
    cardColor: AppColors.greenrspwn,
    size: 'Medium',
    coatLength: 'Short',
    keyCharacteristics: const [
      'Good With Children',
      'Knows Commands',
      'First-Time Owner Friendly',
      'Low Maintenance',
    ],
    rescueBackground: const ['Rescued From Street'],
  ),
  Animal(
    id: 2,
    name: 'Minnie',
    breed: 'Aspin',
    age: '3 year old',
    description: 'Playful white dog',
    healthTags: const ['Vaccinated'],
    gender: AnimalGender.female,
    category: AnimalCategory.dog,
    cardColor: AppColors.lavenderrspwn,
    badge: 'Good with other pets',
    size: 'Small',
    coatLength: 'Medium',
    keyCharacteristics: const [
      'Good With Other Animals',
      'Calm',
      'Leash Trained',
    ],
    rescueBackground: const ['Rescued From Street'],
  ),
  Animal(
    id: 3,
    name: 'Whiskers',
    breed: 'Puspin',
    age: '2 year old',
    description: 'Curious orange cat',
    healthTags: const ['Vaccinated', 'Dewormed'],
    gender: AnimalGender.male,
    category: AnimalCategory.cat,
    cardColor: AppColors.pinkrspwn,
    size: 'Small',
    coatLength: 'Short',
    keyCharacteristics: const ['Playful', 'Shy'],
    rescueBackground: const ['Abandoned'],
  ),
  Animal(
    id: 4,
    name: 'Luna',
    breed: 'Puspin',
    age: '1 year old',
    description: 'Gentle black cat',
    healthTags: const ['Vaccinated'],
    gender: AnimalGender.female,
    category: AnimalCategory.cat,
    cardColor: AppColors.tearspwn,
    badge: 'Good with children',
    size: 'Small',
    coatLength: 'Short',
    keyCharacteristics: const ['Good With Children', 'Calm'],
    rescueBackground: const ['Surrendered By Owner'],
  ),
];

// Options offered in the adoption filter sheet, mirroring the fields
// captured on the animal intake form.
const List<String> kSizeOptions = ['Small', 'Medium', 'Large'];
const List<String> kCoatLengthOptions = ['Short', 'Medium', 'Long'];
const List<String> kHealthOptions = [
  'Vaccinated',
  'Spayed/Neutered',
  'Dewormed',
];
const List<String> kKeyCharacteristicOptions = [
  'Good With Children',
  'Knows Commands',
  'First-Time Owner Friendly',
  'Low Maintenance',
  'Shy',
  'Playful',
  'Calm',
  'Good With Other Animals',
  'Special Needs',
  'Leash Trained',
  'Crate Trained',
  'Protective',
];
const List<String> kRescueBackgroundOptions = [
  'Rescued From Street',
  'Abandoned',
  'Rescued From Abuse',
  'Surrendered By Owner',
  'Transferred From Shelter',
];

// Holds the currently selected filter values. An empty set for a given
// field means "no preference" (that field is not filtered on).
class AdoptionFilters {
  final Set<String> breeds;
  final Set<String> sizes;
  final Set<String> coatLengths;
  final Set<String> health;
  final Set<String> keyCharacteristics;
  final Set<String> rescueBackground;

  const AdoptionFilters({
    this.breeds = const {},
    this.sizes = const {},
    this.coatLengths = const {},
    this.health = const {},
    this.keyCharacteristics = const {},
    this.rescueBackground = const {},
  });

  bool get isEmpty =>
      breeds.isEmpty &&
          sizes.isEmpty &&
          coatLengths.isEmpty &&
          health.isEmpty &&
          keyCharacteristics.isEmpty &&
          rescueBackground.isEmpty;

  int get activeCount =>
      breeds.length +
          sizes.length +
          coatLengths.length +
          health.length +
          keyCharacteristics.length +
          rescueBackground.length;

  AdoptionFilters copyWith({
    Set<String>? breeds,
    Set<String>? sizes,
    Set<String>? coatLengths,
    Set<String>? health,
    Set<String>? keyCharacteristics,
    Set<String>? rescueBackground,
  }) {
    return AdoptionFilters(
      breeds: breeds ?? this.breeds,
      sizes: sizes ?? this.sizes,
      coatLengths: coatLengths ?? this.coatLengths,
      health: health ?? this.health,
      keyCharacteristics: keyCharacteristics ?? this.keyCharacteristics,
      rescueBackground: rescueBackground ?? this.rescueBackground,
    );
  }

  // A single-valued attribute (breed/size/coat length) matches if the
  // animal's value is among the ones the user selected, or if the user
  // didn't select any (no preference).
  bool _matchesAny(Set<String> selected, String value) =>
      selected.isEmpty || selected.contains(value);

  // A multi-valued attribute (health/characteristics/background) matches if
  // the animal has every one of the selected tags.
  bool _matchesAll(Set<String> selected, List<String> values) =>
      selected.isEmpty || selected.every(values.contains);

  bool matches(Animal animal) {
    return _matchesAny(breeds, animal.breed) &&
        _matchesAny(sizes, animal.size) &&
        _matchesAny(coatLengths, animal.coatLength) &&
        _matchesAll(health, animal.healthTags) &&
        _matchesAll(keyCharacteristics, animal.keyCharacteristics) &&
        _matchesAll(rescueBackground, animal.rescueBackground);
  }
}

// AdoptionPage

class AdoptionPage extends StatefulWidget {
  const AdoptionPage({super.key});

  @override
  State<AdoptionPage> createState() => _AdoptionPageState();
}

class _AdoptionPageState extends State<AdoptionPage> {
  int _filterIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late List<Animal> _animals;

  // Statuses that mean the animal is no longer up for adoption: either the
  // adoption has fully completed, or the animal is currently placed with an
  // adopter (a pending return doesn't free it up again automatically).
  static const List<String> _adoptedStatuses = [
    'completed',
    'return_requested',
    'return_approved',
  ];

  // Animal ids that are already adopted, kept in sync in real time so the
  // list updates the moment an adoption is finalized elsewhere in the app.
  Set<int> _adoptedAnimalIds = {};
  StreamSubscription<QuerySnapshot>? _adoptionsSub;

  // Preference-based filters (breed, size, coat length, health, key
  // characteristics, rescue background) applied on top of the category tabs
  // and search bar.
  AdoptionFilters _activeFilters = const AdoptionFilters();

  @override
  void initState() {
    super.initState();
    _animals = List.from(_allAnimals);
    _loadFavorites();
    _listenAdoptedAnimals();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _adoptionsSub?.cancel();
    super.dispose();
  }

  // Listens to the 'adoptions' collection and tracks which animalIds are
  // already adopted, so they can be excluded from the adoption page.
  void _listenAdoptedAnimals() {
    _adoptionsSub = FirebaseFirestore.instance
        .collection('adoptions')
        .where('status', whereIn: _adoptedStatuses)
        .snapshots()
        .listen((snapshot) {
      final ids = <int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final personal = (data['personal'] as Map?) ?? {};
        final animalId = personal['animalId'];
        if (animalId is int) {
          ids.add(animalId);
        } else if (animalId is num) {
          ids.add(animalId.toInt());
        }
      }
      if (mounted) {
        setState(() => _adoptedAnimalIds = ids);
      }
    }, onError: (_) {
      // If the listener fails (e.g. offline), keep whatever list we already
      // have instead of crashing the page.
    });
  }

  List<Animal> get _filtered {
    return _animals.where((p) {
      // Already-adopted animals are removed from the adoption page entirely.
      if (_adoptedAnimalIds.contains(p.id)) return false;

      final matchCategory = _filterIndex == 0 ||
          (_filterIndex == 1 && p.category == AnimalCategory.dog) ||
          (_filterIndex == 2 && p.category == AnimalCategory.cat);
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.breed.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
      final matchPreferences = _activeFilters.matches(p);
      return matchCategory && matchSearch && matchPreferences;
    }).toList();
  }

  // Distinct breeds currently available, used to populate the breed filter
  // so the sheet never offers a breed nothing in the list actually has.
  List<String> get _availableBreeds =>
      _allAnimals.map((a) => a.breed).toSet().toList()..sort();

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

  Future<void> _toggleFavorite(Animal animal) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(animal.id.toString());

    setState(() {
      animal.favorited = !animal.favorited;
    });

    if(animal.favorited){
      await favRef.set({
        'animalId': animal.id,
        'name': animal.name,
        'breed': animal.breed,
        'age': animal.age,
        'description': animal.description,
        'gender': animal.gender.name,
        'category': animal.category.name,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }else{
      await favRef.delete();
    }
  }

  Future<void> _loadFavorites() async{
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();

    final favId = snapshot.docs.map((d) => int.parse(d.id)).toSet();

    setState(() {
      for(var animal in _animals){
        animal.favorited = favId.contains(animal.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                          color: AppColors.textPrimary.withOpacity(0.6),
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

          // Animal list
          Expanded(
            child: _filtered.isEmpty
                ? _EmptyState(
              filterIndex: _filterIndex,
              hasActiveFilters: _activeFilters.activeCount > 0 ||
                  _searchQuery.isNotEmpty,
              onClearFilters: () {
                setState(() {
                  _activeFilters = const AdoptionFilters();
                  _searchQuery = '';
                  _searchController.clear();
                });
              },
            )
                : ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final animal = _filtered[index];
                return AnimalCard(
                  animal: animal,
                  onFavorite: () => _toggleFavorite(animal),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AnimalPage(
                          animal: animal,
                          onFavoriteToggle: () => _toggleFavorite(animal),
                        ),
                      ),
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

// Animal card

class AnimalCard extends StatelessWidget {
  final Animal animal;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const AnimalCard({
    required this.animal,
    required this.onFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: animal.cardColor,
              borderRadius: BorderRadius.circular(20),
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo placeholder
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    color: AppColors.background.withOpacity(0.55),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.pets,
                    size: 36,
                    color: AppColors.textSecondary,
                  ),
                ),

                const SizedBox(width: 14),

                // Details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name + gender icon
                      Row(
                        children: [
                          Text(
                            animal.name,
                            style: GoogleFonts.tiltWarp(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            animal.gender == AnimalGender.male
                                ? Icons.male
                                : Icons.female,
                            size: 16,
                            color: AppColors.textPrimary,
                          ),
                        ],
                      ),

                      const SizedBox(height: 2),

                      Text(
                        animal.breed,
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        animal.age,
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        animal.description,
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // Health tags
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: animal.healthTags
                            .map((tag) => _Tag(label: tag))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Favorite button
          Positioned(
            top: 10,
            right: 12,
            child: GestureDetector(
              onTap: onFavorite,
              behavior: HitTestBehavior.opaque,
              child: Icon(
                animal.favorited ? Icons.favorite : Icons.favorite_border,
                size: 22,
                color: animal.favorited
                    ? const Color(0xFFE05C5C)
                    : AppColors.textPrimary,
              ),
            ),
          ),

          // badge
          if (animal.badge != null)
            Positioned(
              bottom: -10,
              left: 12,
              child: Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.yellowrspwn,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  animal.badge!,
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Health tag

class _Tag extends StatelessWidget {
  final String label;
  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.zain(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
// Empty state — shown when no dogs/cats match the current tab, search
// query, or preference filters.

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
                color: AppColors.yellowrspwn.withOpacity(0.4),
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
              hasActiveFilters
                  ? 'No $_subject match your search'
                  : 'No $_subject available right now',
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
                  : 'Check back soon — new rescues are added all the time!',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary.withOpacity(0.7),
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

// Adoption preference filter sheet — lets adopters narrow the list down by
// breed, size, coat length, health, key characteristics, and rescue
// background, mirroring the fields captured on the intake form.

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
  late Set<String> _health;
  late Set<String> _keyCharacteristics;
  late Set<String> _rescueBackground;

  @override
  void initState() {
    super.initState();
    _breeds = {...widget.initialFilters.breeds};
    _sizes = {...widget.initialFilters.sizes};
    _coatLengths = {...widget.initialFilters.coatLengths};
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
                          color: AppColors.textPrimary.withOpacity(0.7),
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
                    _FilterSection(
                      label: 'Health',
                      child: _CheckboxGroup(
                        options: kHealthOptions,
                        selected: _health,
                        onToggle: (v) => _toggle(_health, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Key Characteristics',
                      child: _CheckboxGroup(
                        options: kKeyCharacteristicOptions,
                        selected: _keyCharacteristics,
                        onToggle: (v) => _toggle(_keyCharacteristics, v),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _FilterSection(
                      label: 'Rescue Background',
                      child: _CheckboxGroup(
                        options: kRescueBackgroundOptions,
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

// Multi-select pill chips — used for single-valued attributes (breed, size,
// coat length) where matching any selected value is sufficient.
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
                  : AppColors.lavenderrspwn.withOpacity(0.5),
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

// Checkbox list — used for multi-valued attributes (health, key
// characteristics, rescue background) where an animal must have every
// selected tag to match.
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