import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';

/// Favorites — same header/tab shell as History, but for saved items.
///
/// Only the Adoption tab has real data right now (favorited adoptable
/// animals, same as before). Donation/Volunteer are placeholders until
/// there's something to favorite in those categories. There's no Rescue
/// tab here — you don't "favorite" a rescue case.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  // Adoption is first now that Rescue isn't a favorites category at all.
  int _tabIndex = 0;
  static const _tabs = ['Adoption', 'Donation', 'Volunteer'];

  List<Animal> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .get();
    final animals = snapshot.docs.map((doc) {
      final data = doc.data();

      return Animal(
        id: data['animalId'],
        name: data['name'],
        breed: data['breed'],
        age: data['age'],
        description: data['description'],
        healthTags: [],
        gender: data['gender'] == 'male'
            ? AnimalGender.male
            : AnimalGender.female,
        category: data['category'] == 'dog'
            ? AnimalCategory.dog
            : AnimalCategory.cat,
        cardColor: AppColors.greenrspwn,
        favorited: true,
      );
    }).toList();

    setState(() {
      _favorites = animals;
      _loading = false;
    });
  }

  Future<void> _toggleFavorite(Animal animal) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final favRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('favorites')
        .doc(animal.id.toString());

    await favRef.delete();

    setState(() {
      _favorites.removeWhere((a) => a.id == animal.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _HistoryFavoritesHeader(
              title: 'Favorites',
              tabs: _tabs,
              selectedIndex: _tabIndex,
              onTabSelected: (i) => setState(() => _tabIndex = i),
            ),
            Expanded(
              child: switch (_tabIndex) {
                0 => _buildAdoptionTab(),
                1 => const _ComingSoonTab(label: 'donations'),
                _ => const _ComingSoonTab(label: 'volunteer events'),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdoptionTab() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }
    if (_favorites.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No favorites yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _favorites.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final animal = _favorites[index];

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
    );
  }
}

class _ComingSoonTab extends StatelessWidget {
  final String label;
  const _ComingSoonTab({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Favorited $label will show up here.',
          textAlign: TextAlign.center,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
        ),
      ),
    );
  }
}

/// Same header used on the History page — kept as an identical private copy
/// here (rather than a shared import) since the two pages live in
/// different feature folders.
class _HistoryFavoritesHeader extends StatelessWidget {
  final String title;
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const _HistoryFavoritesHeader({
    required this.title,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.chevron_left,
                size: 28, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            title,
            style: GoogleFonts.tiltWarp(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final selected = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTabSelected(i),
                  child: Column(
                    children: [
                      Text(
                        tabs[i],
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 2,
                        color: selected
                            ? AppColors.textPrimary
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const Divider(height: 1, color: AppColors.slaterspwn),
        const SizedBox(height: 4),
      ],
    );
  }
}