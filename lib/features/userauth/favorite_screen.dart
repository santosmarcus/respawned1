import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/animal_page.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/volunteer_event_repository.dart';
import 'package:respawnd1/core/widgets/event_cover_image.dart';
import 'package:respawnd1/features/volunteerevent/event_detail_page.dart';

/// Favorites — same header/tab shell as History, but for saved items.
///
/// Adoption lists favorited adoptable animals and Volunteer lists saved
/// (hearted) volunteer events. Donation is a placeholder until there's
/// something to favorite there. There's no Rescue
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
                _ => const _SavedEventsTab(),
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
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final animal = _favorites[index];

        return _FavoriteCard(
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

/// A favorited animal is stored as a lightweight snapshot (name/breed/age/
/// description/gender/category — no photo, no live status), not a live
/// AnimalRecord, so this can't reuse the shared AnimalRecordCard (which
/// requires one). Kept minimal and local to this screen rather than
/// reviving a second general-purpose card widget.
class _FavoriteCard extends StatelessWidget {
  final Animal animal;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const _FavoriteCard({required this.animal, required this.onFavorite, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: animal.photoUrl != null
                  ? Image.network(animal.photoUrl!, width: 80, height: 80, fit: BoxFit.cover, errorBuilder: (_, _, _) => _placeholder())
                  : _placeholder(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(animal.name,
                            style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Icon(animal.gender == AnimalGender.male ? Icons.male : Icons.female, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      GestureDetector(
                        onTap: onFavorite,
                        behavior: HitTestBehavior.opaque,
                        child: const Icon(Icons.favorite, size: 20, color: AppColors.error),
                      ),
                    ],
                  ),
                  if (animal.breed.isNotEmpty) Text(animal.breed, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if (animal.age.isNotEmpty) Text(animal.age, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if (animal.description.isNotEmpty)
                    Text(animal.description,
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, size: 32, color: AppColors.textSecondary),
      );
}

/// The volunteer events the user saved, soonest first; tapping one opens it
/// to view or join, and the heart removes it.
class _SavedEventsTab extends StatefulWidget {
  const _SavedEventsTab();

  @override
  State<_SavedEventsTab> createState() => _SavedEventsTabState();
}

class _SavedEventsTabState extends State<_SavedEventsTab> {
  final _repo = VolunteerEventRepository();
  List<VolunteerEvent>? _events;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final events = await _repo.loadMyFavoriteEvents();
      if (mounted) setState(() => _events = events);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _toggle(VolunteerEvent event) async {
    final next = !event.favorited;
    setState(() => event.favorited = next);
    await _repo.setFavorite(event, next);
  }

  @override
  Widget build(BuildContext context) {
    final events = _events;
    if (_failed) {
      return Center(
        child: Text('Could not load saved events.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );
    }
    if (events == null) {
      return const Center(child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }
    final saved = events.where((e) => e.favorited).toList();
    if (saved.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Tap the heart on an event to save it here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: saved.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        final event = saved[i];
        final status = event.isCancelled
            ? 'Cancelled'
            : event.isPast
                ? 'Ended'
                : event.joined
                    ? "You're going"
                    : event.isFull
                        ? 'Full'
                        : null;
        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VolunteerEventDetailPage(event: event, onFavorite: () => _toggle(event)),
            ),
          ).then((_) {
            if (mounted) setState(() {});
          }),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                EventCoverImage(
                    imageUrl: event.imageUrl, width: 80, height: 80, borderRadius: 10, placeholderColor: AppColors.tearspwn),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(event.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                          ),
                          GestureDetector(
                            onTap: () => _toggle(event),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.only(left: 6),
                              child: Icon(Icons.favorite, size: 20, color: AppColors.error),
                            ),
                          ),
                        ],
                      ),
                      Text(event.date, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      Text(event.time, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      if (event.location.isNotEmpty)
                        Text(event.location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      if (status != null)
                        Text(status,
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: event.isCancelled ? AppColors.error : AppColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
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