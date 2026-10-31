import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/volunteer_event_repository.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'event_detail_page.dart';

export 'package:respawnd1/core/models/volunteer/volunteer_event.dart' show VolunteerEvent;

// VolunteerPage
class VolunteerPage extends StatefulWidget {
  const VolunteerPage({super.key});

  @override
  State<VolunteerPage> createState() => _VolunteerPageState();
}

class _VolunteerPageState extends State<VolunteerPage> {
  final TextEditingController _searchController = TextEditingController();
  final _repo = VolunteerEventRepository();
  String _searchQuery = '';
  List<VolunteerEvent> _events = [];
  Set<String> _joinedIds = {};
  Set<String> _favoriteIds = {};
  bool _loading = true;
  bool _loadFailed = false;
  StreamSubscription<List<VolunteerEvent>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Events stream live from `events`; the viewer's joined/favorite ids are
  // read once and refreshed when returning from an event.
  Future<void> _load() async {
    try {
      final mine = await _repo.loadMyEventIds();
      _joinedIds = mine.joined;
      _favoriteIds = mine.favorites;
    } catch (_) {
      // Lists still render; joined/favorite markers just won't show.
    }
    _eventsSub ??= _repo.streamAllEvents().listen(
      (events) {
        if (!mounted) return;
        setState(() {
          _events = events;
          _applyViewerState();
          _loading = false;
          _loadFailed = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      },
    );
    if (mounted) setState(_applyViewerState);
  }

  void _applyViewerState() {
    for (final event in _events) {
      event.joined = _joinedIds.contains(event.id);
      event.favorited = _favoriteIds.contains(event.id);
    }
  }

  //Favorite toggle
  Future<void> _toggleFavorite(VolunteerEvent event) async {
    final newVal = !event.favorited;
    setState(() {
      event.favorited = newVal;
      newVal ? _favoriteIds.add(event.id) : _favoriteIds.remove(event.id);
    });
    await _repo.setFavorite(event, newVal);
  }

  bool _matchesSearch(VolunteerEvent e) {
    final q = _searchQuery.toLowerCase();
    return q.isEmpty || e.title.toLowerCase().contains(q) || e.organizer.toLowerCase().contains(q);
  }

  // Filtered lists. Cancelled events only stay visible to people who joined
  // them, so they can see the cancellation.
  List<VolunteerEvent> get _upcoming =>
      _events.where((e) => !e.joined && !e.isCancelled && !e.isPast && _matchesSearch(e)).toList();

  List<VolunteerEvent> get _joined => _events.where((e) => e.joined && !e.isPast).toList();


  // Build
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
          'Volunteer',
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
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : _loadFailed
          ? Center(
          child: Text('Could not load events.',
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textSecondary)))
          : SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // Search bar
            Row(
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
                      onChanged: (v) =>
                          setState(() => _searchQuery = v),
                      style: GoogleFonts.zain(
                          fontSize: 15, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: GoogleFonts.zain(
                            fontSize: 15,
                            color: AppColors.textPrimary
                                .withValues(alpha: 0.6)),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textPrimary, size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                            vertical: 12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 44,
                  height: 44,
                  child: const Icon(Icons.tune,
                      color: AppColors.textPrimary, size: 20),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Joined events
            if (_joined.isNotEmpty) ...[
              Text('Joined',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              ..._joined.map((event) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EventCard(
                  event: event,
                  onFavorite: () => _toggleFavorite(event),
                  onTap: () => _openDetail(event),
                ),
              )),
              const SizedBox(height: 8),
            ],

            // Upcoming events
            Text('Upcoming',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 10),

            if (_upcoming.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('No upcoming events found.',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textSecondary)),
                ),
              )
            else
              ..._upcoming.map((event) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _EventCard(
                  event: event,
                  onFavorite: () => _toggleFavorite(event),
                  onTap: () => _openDetail(event),
                ),
              )),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _openDetail(VolunteerEvent event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VolunteerEventDetailPage(
          event: event,
          onFavorite: () => _toggleFavorite(event),
        ),
      ),
    ).then((_) {
      if (event.joined) _joinedIds.add(event.id);
      if (mounted) setState(_applyViewerState);
    });
  }
}


// Event card
class _EventCard extends StatelessWidget {
  final VolunteerEvent event;
  final VoidCallback onFavorite;
  final VoidCallback onTap;

  const _EventCard({
    required this.event,
    required this.onFavorite,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Container(
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.tearspwn,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              Positioned(
                top: 10,
                right: 12,
                child: GestureDetector(
                  onTap: onFavorite,
                  behavior: HitTestBehavior.opaque,
                  child: Icon(
                    event.favorited
                        ? Icons.favorite
                        : Icons.favorite_border,
                    size: 22,
                    color: event.favorited
                        ? const Color(0xFFE05C5C)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(event.title,
                          style: GoogleFonts.tiltWarp(
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text('Organized by ${event.organizer}',
                          style: GoogleFonts.zain(
                              fontSize: 12,
                              color: AppColors.textPrimary)),
                      if (event.isCancelled)
                        Text('Cancelled',
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.redAccent))
                      else if (event.isFull && !event.joined)
                        Text('Full',
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InfoRow(
                        icon: Icons.calendar_today_outlined,
                        text: event.date),
                    const SizedBox(height: 4),
                    _InfoRow(
                        icon: Icons.access_time_outlined,
                        text: event.time),
                    const SizedBox(height: 4),
                    _InfoRow(
                        icon: Icons.location_on_outlined,
                        text: event.location),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.textPrimary),
        const SizedBox(width: 3),
        Text(text,
            style: GoogleFonts.zain(
                fontSize: 11, color: AppColors.textPrimary)),
      ],
    );
  }
}