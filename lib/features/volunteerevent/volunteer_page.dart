import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/volunteer_event_repository.dart';
import 'package:respawnd1/core/widgets/event_cover_image.dart';
import 'package:respawnd1/app_theme.dart';
import 'event_detail_page.dart';

export 'package:respawnd1/core/models/volunteer/volunteer_event.dart' show VolunteerEvent;

/// The home screen's Events page: every organization's volunteer events.
/// Signing up for an event makes the user an event volunteer for it; the
/// organization's own rescue volunteers (external `rescue_volunteer`
/// accounts) are a separate thing managed on the admin side.
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
  bool _savedOnly = false;
  bool _hideFull = false;
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
    await _loadMine();
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

  Future<void> _loadMine() async {
    try {
      final mine = await _repo.loadMyEventIds();
      _joinedIds = mine.joined;
      _favoriteIds = mine.favorites;
    } catch (_) {
      // Lists still render; joined/favorite markers just won't show.
    }
  }

  /// Pull to refresh: events are live already; this re-reads the viewer's
  /// own sign-ups and saved events.
  Future<void> _refresh() async {
    await _loadMine();
    if (mounted) setState(_applyViewerState);
  }

  bool get _filtering => _savedOnly || _hideFull;

  Future<void> _openFilters() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          void update(VoidCallback change) {
            setState(change);
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Filter events', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _savedOnly,
                    activeThumbColor: AppColors.greenrspwn,
                    onChanged: (v) => update(() => _savedOnly = v),
                    title: Text('Saved events only', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                    subtitle: Text('Events you tapped the heart on.',
                        style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _hideFull,
                    activeThumbColor: AppColors.greenrspwn,
                    onChanged: (v) => update(() => _hideFull = v),
                    title: Text('Hide full events', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                    subtitle: Text('Only show events with spots left.',
                        style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
                  if (_filtering)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => update(() {
                          _savedOnly = false;
                          _hideFull = false;
                        }),
                        child: Text('Clear filters', style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
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
  List<VolunteerEvent> get _upcoming => _events
      .where((e) =>
          !e.joined &&
          !e.isCancelled &&
          !e.isPast &&
          _matchesSearch(e) &&
          (!_savedOnly || e.favorited) &&
          (!_hideFull || !e.isFull))
      .toList();

  List<VolunteerEvent> get _joined => _events.where((e) => e.joined && !e.isPast).toList();

  /// Events the viewer signed up for that are over, most recent first.
  List<VolunteerEvent> get _pastJoined =>
      _events.where((e) => e.joined && e.isPast).toList()..sort((a, b) => b.startAt.compareTo(a.startAt));


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
          'Events',
          style: GoogleFonts.tiltWarp(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn))
          : _loadFailed
          ? Center(
          child: Text('Could not load events.',
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textSecondary)))
          : RefreshIndicator(
        color: AppColors.greenrspwn,
        onRefresh: _refresh,
        child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
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
                Badge(
                  isLabelVisible: _filtering,
                  smallSize: 8,
                  backgroundColor: AppColors.greenrspwn,
                  child: IconButton(
                    tooltip: 'Filter',
                    onPressed: _openFilters,
                    icon: const Icon(Icons.tune,
                        color: AppColors.textPrimary, size: 20),
                  ),
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
                  child: Text(
                      _filtering || _searchQuery.isNotEmpty
                          ? 'No events match your search or filters.'
                          : 'No upcoming events yet. Check back soon!',
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

            // Past sign-ups, so volunteers can look back at what they joined.
            if (_pastJoined.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Past events you joined',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              ..._pastJoined.take(5).map((event) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Opacity(
                  opacity: 0.7,
                  child: _EventCard(
                    event: event,
                    onFavorite: () => _toggleFavorite(event),
                    onTap: () => _openDetail(event),
                  ),
                ),
              )),
            ],

            const SizedBox(height: 24),
          ],
        ),
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
              EventCoverImage(
                imageUrl: event.imageUrl,
                height: 120,
                placeholderColor: AppColors.tearspwn,
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
                        ? AppColors.error
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
                                color: AppColors.error))
                      else if (event.joined && !event.isPast)
                        Text("You're going",
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.success))
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