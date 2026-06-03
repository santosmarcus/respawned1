import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'event_detail_page.dart';

typedef MarkJoinedCallback = Future<void> Function({
required VolunteerEvent event,
required String participantName,
required String participantEmail,
required String participantMobileNumber,
required String participantNumber,
});


// Data model
class VolunteerEvent {
  final int id;
  final String title;
  final String organizer;
  final String date;
  final String time;
  final String location;
  final String description;
  final String organizerName;
  final String addressFull;
  final int goingCount;
  bool favorited;
  bool joined;

  VolunteerEvent({
    required this.id,
    required this.title,
    required this.organizer,
    required this.date,
    required this.time,
    required this.location,
    required this.description,
    required this.organizerName,
    required this.addressFull,
    required this.goingCount,
    this.favorited = false,
    this.joined = false,
  });
}

final List<VolunteerEvent> _allEvents = [
  VolunteerEvent(
    id: 1,
    title: 'Stray Dog Walking',
    organizer: 'Loved by the Gapz',
    date: 'Saturday, March 21, 2026',
    time: '9:00 AM - 10:30 AM',
    location: 'General Trias, Cavite',
    description:
    'Join our Volunteer Stray Dog Walking Event and help give rescued dogs '
        'the care, exercise, and attention they need. Spend time walking and '
        'bonding with friendly dogs while supporting local animal welfare efforts. '
        'No experience needed—just bring comfortable clothes and a love for dogs!',
    organizerName: 'Loved by the Gapz',
    addressFull: 'General Trias, Cavite',
    goingCount: 15,
  ),
  VolunteerEvent(
    id: 2,
    title: 'Stray Feeding Drive',
    organizer: 'Loved by the Gapz',
    date: 'Sunday, March 22, 2026',
    time: '9:00 AM - 10:30 AM',
    location: 'General Trias, Cavite',
    description:
    'Help us feed stray animals in the community. Volunteers will distribute '
        'food across designated areas.',
    organizerName: 'Loved by the Gapz',
    addressFull: 'General Trias, Cavite',
    goingCount: 8,
  ),
];

// VolunteerPage
class VolunteerPage extends StatefulWidget {
  const VolunteerPage({super.key});

  @override
  State<VolunteerPage> createState() => _VolunteerPageState();
}

class _VolunteerPageState extends State<VolunteerPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late List<VolunteerEvent> _events;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _events = _allEvents
        .map((e) => VolunteerEvent(
      id: e.id,
      title: e.title,
      organizer: e.organizer,
      date: e.date,
      time: e.time,
      location: e.location,
      description: e.description,
      organizerName: e.organizerName,
      addressFull: e.addressFull,
      goingCount: e.goingCount,
    ))
        .toList();
    _loadFromFirestore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Firestore refs
  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _registrationsRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('volunteerRegistrations');

  CollectionReference<Map<String, dynamic>> get _favoritesRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('volunteerFavorites');

  CollectionReference<Map<String, dynamic>> _globalRegistrationsRef(
      int eventId) =>
      FirebaseFirestore.instance
          .collection('volunteers')
          .doc(eventId.toString())
          .collection('registrations');


  // Load joined and favorites state from Firestore
  Future<void> _loadFromFirestore() async {
    try {
      final results = await Future.wait([
        _registrationsRef.get(),
        _favoritesRef.get(),
      ]);

      final joinedIds = results[0].docs.map((d) => int.parse(d.id)).toSet();
      final favIds = results[1].docs.map((d) => int.parse(d.id)).toSet();

      if (mounted) {
        setState(() {
          for (final event in _events) {
            event.joined = joinedIds.contains(event.id);
            event.favorited = favIds.contains(event.id);
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }


  // Mark joined
  Future<void> markJoined({
    required VolunteerEvent event,
    required String participantName,
    required String participantEmail,
    required String participantMobileNumber,
    required String participantNumber,
  }) async {
    final now = FieldValue.serverTimestamp();

    await _registrationsRef.doc(event.id.toString()).set({
      'eventId': event.id,
      'title': event.title,
      'organizer': event.organizer,
      'date': event.date,
      'time': event.time,
      'location': event.location,
      'participantName': participantName,
      'participantEmail': participantEmail,
      'participantMobileNumber': participantMobileNumber,
      'participantNumber': participantNumber,
      'registeredAt': now,
    });

    await _globalRegistrationsRef(event.id).doc(_uid).set({
      'uid': _uid,
      'eventId': event.id,
      'eventTitle': event.title,
      'participantName': participantName,
      'participantEmail': participantEmail,
      'participantMobileNumber': participantMobileNumber,
      'participantNumber': participantNumber,
      'registeredAt': now,
    });

    if (mounted) setState(() => event.joined = true);
  }


  //Favorite toggle
  Future<void> _toggleFavorite(VolunteerEvent event) async {
    final newVal = !event.favorited;
    setState(() => event.favorited = newVal);

    final doc = _favoritesRef.doc(event.id.toString());
    if (newVal) {
      await doc.set({
        'eventId': event.id,
        'title': event.title,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await doc.delete();
    }
  }

  // Filtered lists
  List<VolunteerEvent> get _upcoming => _events.where((e) {
    final q = _searchQuery.toLowerCase();
    return !e.joined &&
        (q.isEmpty ||
            e.title.toLowerCase().contains(q) ||
            e.organizer.toLowerCase().contains(q));
  }).toList();

  List<VolunteerEvent> get _joined =>
      _events.where((e) => e.joined).toList();


  // Build
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
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const HomeScreen()));
          } else if (index == 1) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()));
          } else if (index == 2) {
            Navigator.pushReplacement(context,
                MaterialPageRoute(builder: (_) => const UserProfile()));
          }
        },
      ),
      body: _loading
          ? const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn))
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
                                .withOpacity(0.6)),
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
          onMarkJoined: markJoined,
        ),
      ),
    ).then((_) => setState(() {}));
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