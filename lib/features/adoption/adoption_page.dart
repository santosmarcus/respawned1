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
  });
}

final List<Animal> _allAnimals = [
  Animal(
    id: 1,
    name: 'Brownie',
    breed: 'Aspin',
    age: '2 year old',
    description: 'Playful brown dog',
    healthTags: ['Vaccinated', 'Neutered'],
    gender: AnimalGender.male,
    category: AnimalCategory.dog,
    cardColor: AppColors.greenrspwn,
  ),
  Animal(
    id: 2,
    name: 'Minnie',
    breed: 'Aspin',
    age: '3 year old',
    description: 'Playful white dog',
    healthTags: ['Vaccinated'],
    gender: AnimalGender.female,
    category: AnimalCategory.dog,
    cardColor: AppColors.lavenderrspwn,
    badge: 'Good with other pets',
  ),
  Animal(
    id: 3,
    name: 'Whiskers',
    breed: 'Puspin',
    age: '2 year old',
    description: 'Curious orange cat',
    healthTags: ['Vaccinated', 'Dewormed'],
    gender: AnimalGender.male,
    category: AnimalCategory.cat,
    cardColor: AppColors.pinkrspwn,
  ),
  Animal(
    id: 4,
    name: 'Luna',
    breed: 'Puspin',
    age: '1 year old',
    description: 'Gentle black cat',
    healthTags: ['Vaccinated'],
    gender: AnimalGender.female,
    category: AnimalCategory.cat,
    cardColor: AppColors.tearspwn,
    badge: 'Good with children',
  ),
];

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

  @override
  void initState() {
    super.initState();
    _animals = List.from(_allAnimals);
    _loadFavorites();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Animal> get _filtered {
    return _animals.where((p) {
      final matchCategory = _filterIndex == 0 ||
          (_filterIndex == 1 && p.category == AnimalCategory.dog) ||
          (_filterIndex == 2 && p.category == AnimalCategory.cat);
      final q = _searchQuery.toLowerCase();
      final matchSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.breed.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
      return matchCategory && matchSearch;
    }).toList();
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
        automaticallyImplyLeading: false,
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          else if (index == 2) {
            Navigator.pushReplacement(
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
            child: ListView.separated(
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
                        builder: (context) => AnimalPage(animal: animal, onFavoriteToggle: () => _toggleFavorite(animal),),
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