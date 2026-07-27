import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:respawnd1/app_theme.dart';
import 'transparency_report.dart';

import 'organization_model.dart';

class OrganizationProfilePage extends StatefulWidget {
  final String organizationId;

  const OrganizationProfilePage({super.key, required this.organizationId});

  @override
  State<OrganizationProfilePage> createState() =>
      _OrganizationProfilePageState();
}

class _OrganizationProfilePageState extends State<OrganizationProfilePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _orgFavorited = false;
  bool _loadingFavorite = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _loadFavoriteState();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  DocumentReference<Map<String, dynamic>> get _orgFavRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('favoriteOrganizations')
      .doc(widget.organizationId);

  Future<void> _loadFavoriteState() async {
    try {
      final doc = await _orgFavRef.get();
      if (mounted) {
        setState(() {
          _orgFavorited = doc.exists;
          _loadingFavorite = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingFavorite = false);
    }
  }

  Future<void> _toggleOrgFavorite(Organization org) async {
    final newVal = !_orgFavorited;
    setState(() => _orgFavorited = newVal);
    if (newVal) {
      await _orgFavRef.set({
        'organizationId': org.id,
        'name': org.name,
        'savedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await _orgFavRef.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('organizations')
              .doc(widget.organizationId)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: Text('Could not load this organization.',
                    style: GoogleFonts.zain(color: AppColors.textSecondary)),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                  child:
                  CircularProgressIndicator(color: AppColors.greenrspwn));
            }
            if (!snapshot.data!.exists) {
              return Center(
                child: Text('Organization not found.',
                    style: GoogleFonts.zain(color: AppColors.textSecondary)),
              );
            }

            final org = Organization.fromFirestore(snapshot.data!,
                favorited: _orgFavorited);

            return Column(
              children: [
                _buildHeader(context, org),
                TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.textPrimary,
                  labelStyle: GoogleFonts.zain(
                      fontSize: 15, fontWeight: FontWeight.w700),
                  unselectedLabelStyle: GoogleFonts.zain(fontSize: 15),
                  tabs: const [
                    Tab(text: 'Adoptions'),
                    Tab(text: 'Donations'),
                    Tab(text: 'Events'),
                    Tab(text: 'Reviews'),
                    Tab(text: 'About'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _AdoptionsTab(organizationId: org.id),
                      _DonationsTab(organizationId: org.id),
                      _EventsTab(organizationId: org.id),
                      _ReviewsTab(organizationId: org.id),
                      _AboutTab(organization: org),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Organization org) {
    return Container(
      width: double.infinity,
      color: AppColors.yellowrspwn,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.arrow_back,
                    color: AppColors.textPrimary),
              ),
              const Spacer(),
              const Icon(Icons.ios_share, color: AppColors.textPrimary),
              const SizedBox(width: 16),
              _loadingFavorite
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textPrimary),
              )
                  : GestureDetector(
                onTap: () => _toggleOrgFavorite(org),
                child: Icon(
                  org.favorited ? Icons.favorite : Icons.favorite_border,
                  color: org.favorited
                      ? const Color(0xFFE05C5C)
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CircleAvatar(
            radius: 34,
            backgroundColor: AppColors.background.withOpacity(0.6),
            backgroundImage: org.avatarUrl != null && org.avatarUrl!.isNotEmpty
                ? NetworkImage(org.avatarUrl!)
                : null,
            child: org.avatarUrl == null || org.avatarUrl!.isEmpty
                ? const Icon(Icons.corporate_fare,
                size: 30, color: AppColors.textSecondary)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            org.name,
            style: GoogleFonts.tiltWarp(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatItem(value: org.rescuesCount, label: 'rescues'),
              const SizedBox(width: 24),
              _StatItem(value: org.adopteesCount, label: 'adoptees'),
              const SizedBox(width: 24),
              _StatItem(value: org.eventsCount, label: 'events'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SocialIcon(icon: Icons.call, enabled: org.phone != null),
              const SizedBox(width: 10),
              _SocialIcon(
                  icon: Icons.facebook, enabled: org.facebookUrl != null),
              const SizedBox(width: 10),
              _SocialIcon(
                  icon: Icons.mail_outline, enabled: org.email != null),
              const SizedBox(width: 10),
              _SocialIcon(
                  icon: Icons.location_on_outlined,
                  enabled: org.mapUrl != null),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => TransparencyReportPage(
                    organizationId: org.id,
                    organizationName: org.name,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.analytics_outlined, size: 18),
            label: Text(
              'View Transparency Report',
              style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.9),
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final int value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$value',
            style: GoogleFonts.tiltWarp(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        Text(label,
            style: GoogleFonts.zain(
                fontSize: 12, color: AppColors.textPrimary)),
      ],
    );
  }
}

class _SocialIcon extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  const _SocialIcon({required this.icon, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: AppColors.background.withOpacity(enabled ? 0.9 : 0.4),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 16, color: AppColors.textPrimary),
    );
  }
}

class _OrgAnimal {
  final String id;
  final String name;
  final String breed;
  final String age;
  final String description;
  final List<String> healthTags;
  final String gender;
  final String? imageUrl;
  final String? badge;
  final Color cardColor;
  final bool favorited;

  _OrgAnimal({
    required this.id,
    required this.name,
    required this.breed,
    required this.age,
    required this.description,
    required this.healthTags,
    required this.gender,
    required this.cardColor,
    this.imageUrl,
    this.badge,
    this.favorited = false,
  });

  factory _OrgAnimal.fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      bool favorited,
      Color cardColor,
      ) {
    final data = doc.data();
    return _OrgAnimal(
      id: doc.id,
      name: data['name'] as String? ?? '',
      breed: data['breed'] as String? ?? '',
      age: data['age'] as String? ?? '',
      description: data['description'] as String? ?? '',
      healthTags: List<String>.from(data['healthTags'] ?? const []),
      gender: data['gender'] as String? ?? 'male',
      imageUrl: data['imageUrl'] as String?,
      badge: data['badge'] as String?,
      cardColor: cardColor,
      favorited: favorited,
    );
  }
}

class _AdoptionsTab extends StatefulWidget {
  final String organizationId;
  const _AdoptionsTab({required this.organizationId});

  @override
  State<_AdoptionsTab> createState() => _AdoptionsTabState();
}

class _AdoptionsTabState extends State<_AdoptionsTab> {
  static const _cardColors = [
    AppColors.greenrspwn,
    AppColors.lavenderrspwn,
    AppColors.pinkrspwn,
    AppColors.tearspwn,
  ];

  Set<String> _favoriteIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _favRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('favorites');

  Future<void> _loadFavorites() async {
    try {
      final snap = await _favRef.get();
      if (mounted) {
        setState(() {
          _favoriteIds = snap.docs.map((d) => d.id).toSet();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite(_OrgAnimal animal) async {
    final isFav = _favoriteIds.contains(animal.id);
    setState(() {
      isFav ? _favoriteIds.remove(animal.id) : _favoriteIds.add(animal.id);
    });
    final doc = _favRef.doc(animal.id);
    if (isFav) {
      await doc.delete();
    } else {
      await doc.set({
        'animalId': animal.id,
        'name': animal.name,
        'breed': animal.breed,
        'age': animal.age,
        'description': animal.description,
        'gender': animal.gender,
        'organizationId': widget.organizationId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('animals')
          .where('organizationId', isEqualTo: widget.organizationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No animals listed yet.',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          );
        }

        final animals = [
          for (var i = 0; i < docs.length; i++)
            _OrgAnimal.fromFirestore(
              docs[i],
              _favoriteIds.contains(docs[i].id),
              _cardColors[i % _cardColors.length],
            ),
        ];

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: animals.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final animal = animals[index];
            return _OrgAnimalCard(
              animal: animal,
              onFavorite: () => _toggleFavorite(animal),
            );
          },
        );
      },
    );
  }
}

class _OrgAnimalCard extends StatelessWidget {
  final _OrgAnimal animal;
  final VoidCallback onFavorite;
  const _OrgAnimalCard({required this.animal, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return Stack(
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
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppColors.background.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(14),
                  image: animal.imageUrl != null && animal.imageUrl!.isNotEmpty
                      ? DecorationImage(
                      image: NetworkImage(animal.imageUrl!),
                      fit: BoxFit.cover)
                      : null,
                ),
                child: animal.imageUrl == null || animal.imageUrl!.isEmpty
                    ? const Icon(Icons.pets,
                    size: 36, color: AppColors.textSecondary)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(animal.name,
                            style: GoogleFonts.tiltWarp(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 6),
                        Icon(
                          animal.gender == 'male' ? Icons.male : Icons.female,
                          size: 16,
                          color: AppColors.textPrimary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(animal.breed,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary)),
                    Text(animal.age,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary)),
                    Text(animal.description,
                        style: GoogleFonts.zain(
                            fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: animal.healthTags
                          .map((tag) => _MiniTag(label: tag))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
                      offset: const Offset(0, 2)),
                ],
              ),
              child: Text(
                animal.badge!,
                style: GoogleFonts.zain(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  const _MiniTag({required this.label});

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
            color: AppColors.textPrimary),
      ),
    );
  }
}

// Donations tab

class _OrgDonation {
  final String id;
  final String title;
  final int target;
  final int collected;
  final int dateleft;
  final String? imageUrl;
  final bool favorited;

  _OrgDonation({
    required this.id,
    required this.title,
    required this.target,
    required this.collected,
    required this.dateleft,
    this.imageUrl,
    this.favorited = false,
  });

  int get percentage =>
      target == 0 ? 0 : ((collected / target) * 100).clamp(0, 100).round();

  factory _OrgDonation.fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      bool favorited,
      ) {
    final data = doc.data();
    return _OrgDonation(
      id: doc.id,
      title: data['title'] as String? ?? '',
      target: (data['target'] as num?)?.toInt() ?? 0,
      collected: (data['collected'] as num?)?.toInt() ?? 0,
      dateleft: (data['dateleft'] as num?)?.toInt() ?? 0,
      imageUrl: data['imageUrl'] as String?,
      favorited: favorited,
    );
  }
}

class _DonationsTab extends StatefulWidget {
  final String organizationId;
  const _DonationsTab({required this.organizationId});

  @override
  State<_DonationsTab> createState() => _DonationsTabState();
}

class _DonationsTabState extends State<_DonationsTab> {
  Set<String> _favoriteIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _favRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('donationFavorites');

  Future<void> _loadFavorites() async {
    try {
      final snap = await _favRef.get();
      if (mounted) {
        setState(() {
          _favoriteIds = snap.docs.map((d) => d.id).toSet();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite(_OrgDonation donation) async {
    final isFav = _favoriteIds.contains(donation.id);
    setState(() {
      isFav
          ? _favoriteIds.remove(donation.id)
          : _favoriteIds.add(donation.id);
    });
    final doc = _favRef.doc(donation.id);
    if (isFav) {
      await doc.delete();
    } else {
      await doc.set({
        'donationId': donation.id,
        'title': donation.title,
        'organizationId': widget.organizationId,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('organizationId', isEqualTo: widget.organizationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No active donation drives.',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          );
        }

        final donations = docs
            .map((d) =>
            _OrgDonation.fromFirestore(d, _favoriteIds.contains(d.id)))
            .toList();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: donations.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final donation = donations[index];
            return _OrgDonationCard(
              donation: donation,
              onFavorite: () => _toggleFavorite(donation),
            );
          },
        );
      },
    );
  }
}

class _OrgDonationCard extends StatelessWidget {
  final _OrgDonation donation;
  final VoidCallback onFavorite;
  const _OrgDonationCard(
      {required this.donation, required this.onFavorite});

  String _fmt(num value) => NumberFormat('#,##0').format(value);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.tearspwn,
                borderRadius: BorderRadius.circular(16),
                image: donation.imageUrl != null &&
                    donation.imageUrl!.isNotEmpty
                    ? DecorationImage(
                    image: NetworkImage(donation.imageUrl!),
                    fit: BoxFit.cover)
                    : null,
              ),
            ),
            Positioned(
              top: 10,
              right: 12,
              child: GestureDetector(
                onTap: onFavorite,
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  donation.favorited ? Icons.favorite : Icons.favorite_border,
                  size: 22,
                  color: donation.favorited
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
                    Text(donation.title,
                        style: GoogleFonts.tiltWarp(
                            fontSize: 16, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '₱ ${_fmt(donation.target)}  ',
                            style: GoogleFonts.zain(
                                fontSize: 16,
                                color: AppColors.greenrspwn,
                                fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text:
                            'Funds collected: ₱ ${_fmt(donation.collected)}  |  ',
                            style: GoogleFonts.zain(
                                fontSize: 16, color: AppColors.textPrimary),
                          ),
                          TextSpan(
                            text: '${donation.dateleft} days left!',
                            style: GoogleFonts.zain(
                                fontSize: 16, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _OrgPercentCircle(percent: donation.percentage),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrgPercentCircle extends StatelessWidget {
  final int percent;
  const _OrgPercentCircle({required this.percent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent / 100,
            strokeWidth: 4,
            backgroundColor: AppColors.textPrimary,
            valueColor:
            const AlwaysStoppedAnimation<Color>(AppColors.yellowrspwn),
          ),
          Text(
            '$percent%',
            style: GoogleFonts.zain(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// Events tab

class _OrgEvent {
  final String id;
  final String title;
  final String organizer;
  final String date;
  final String time;
  final String location;
  final bool favorited;

  _OrgEvent({
    required this.id,
    required this.title,
    required this.organizer,
    required this.date,
    required this.time,
    required this.location,
    this.favorited = false,
  });

  factory _OrgEvent.fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc,
      bool favorited,
      ) {
    final data = doc.data();
    return _OrgEvent(
      id: doc.id,
      title: data['title'] as String? ?? '',
      organizer: data['organizer'] as String? ?? '',
      date: data['date'] as String? ?? '',
      time: data['time'] as String? ?? '',
      location: data['location'] as String? ?? '',
      favorited: favorited,
    );
  }
}

class _EventsTab extends StatefulWidget {
  final String organizationId;
  const _EventsTab({required this.organizationId});

  @override
  State<_EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends State<_EventsTab> {
  Set<String> _favoriteIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  String get _uid => FirebaseAuth.instance.currentUser!.uid;

  CollectionReference<Map<String, dynamic>> get _favRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(_uid)
      .collection('volunteerFavorites');

  Future<void> _loadFavorites() async {
    try {
      final snap = await _favRef.get();
      if (mounted) {
        setState(() {
          _favoriteIds = snap.docs.map((d) => d.id).toSet();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFavorite(_OrgEvent event) async {
    final isFav = _favoriteIds.contains(event.id);
    setState(() {
      isFav ? _favoriteIds.remove(event.id) : _favoriteIds.add(event.id);
    });
    final doc = _favRef.doc(event.id);
    if (isFav) {
      await doc.delete();
    } else {
      await doc.set({
        'eventId': event.id,
        'title': event.title,
        'organizationId': widget.organizationId,
        'savedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.greenrspwn));
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('volunteers')
          .where('organizationId', isEqualTo: widget.organizationId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No events scheduled yet.',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          );
        }

        final events = docs
            .map((d) => _OrgEvent.fromFirestore(d, _favoriteIds.contains(d.id)))
            .toList();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: events.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) {
            final event = events[index];
            return _OrgEventCard(
              event: event,
              onFavorite: () => _toggleFavorite(event),
            );
          },
        );
      },
    );
  }
}

class _OrgEventCard extends StatelessWidget {
  final _OrgEvent event;
  final VoidCallback onFavorite;
  const _OrgEventCard({required this.event, required this.onFavorite});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            Container(
              height: 120,
              width: double.infinity,
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
                  event.favorited ? Icons.favorite : Icons.favorite_border,
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
                            fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text('Organized by ${event.organizer}',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrgInfoRow(
                      icon: Icons.calendar_today_outlined, text: event.date),
                  const SizedBox(height: 4),
                  _OrgInfoRow(
                      icon: Icons.access_time_outlined, text: event.time),
                  const SizedBox(height: 4),
                  _OrgInfoRow(
                      icon: Icons.location_on_outlined, text: event.location),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrgInfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _OrgInfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: AppColors.textPrimary),
        const SizedBox(width: 3),
        Text(text,
            style:
            GoogleFonts.zain(fontSize: 11, color: AppColors.textPrimary)),
      ],
    );
  }
}

// Reviews tab

class _OrgReview {
  final String id;
  final String userName;
  final int rating;
  final String comment;

  _OrgReview({
    required this.id,
    required this.userName,
    required this.rating,
    required this.comment,
  });

  factory _OrgReview.fromFirestore(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return _OrgReview(
      id: doc.id,
      userName: data['userName'] as String? ?? 'Anonymous',
      rating: (data['rating'] as num?)?.toInt() ?? 0,
      comment: data['comment'] as String? ?? '',
    );
  }
}

class _ReviewsTab extends StatelessWidget {
  final String organizationId;
  const _ReviewsTab({required this.organizationId});

  CollectionReference<Map<String, dynamic>> get _reviewsRef =>
      FirebaseFirestore.instance
          .collection('organizations')
          .doc(organizationId)
          .collection('reviews');

  Future<void> _submitReview(
      BuildContext context, int rating, String comment) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc =
    await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userName = (userDoc.data()?['name'] as String?) ?? 'Anonymous';

    await _reviewsRef.doc(uid).set({
      'uid': uid,
      'userName': userName,
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Recompute aggregate rating for the organization doc.
    final allReviews = await _reviewsRef.get();
    final ratings =
    allReviews.docs.map((d) => (d.data()['rating'] as num? ?? 0)).toList();
    final avg = ratings.isEmpty
        ? 0.0
        : ratings.reduce((a, b) => a + b) / ratings.length;

    await FirebaseFirestore.instance
        .collection('organizations')
        .doc(organizationId)
        .update({
      'averageRating': avg,
      'reviewCount': ratings.length,
    });
  }

  void _openAddReviewSheet(BuildContext context) {
    int rating = 5;
    final commentController = TextEditingController();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Add a Review',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 18, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  Row(
                    children: List.generate(5, (i) {
                      final starIndex = i + 1;
                      return GestureDetector(
                        onTap: () =>
                            setSheetState(() => rating = starIndex),
                        child: Icon(
                          starIndex <= rating
                              ? Icons.star
                              : Icons.star_border,
                          color: AppColors.yellowrspwn,
                          size: 32,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    style: GoogleFonts.zain(color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'Share your experience...',
                      filled: true,
                      fillColor: AppColors.yellowrspwn.withOpacity(0.3),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(context);
                        await _submitReview(
                            context, rating, commentController.text.trim());
                      },
                      child: Text('Submit Review',
                          style: GoogleFonts.zain(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _reviewsRef.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        final reviews = snapshot.hasData
            ? snapshot.data!.docs.map(_OrgReview.fromFirestore).toList()
            : <_OrgReview>[];

        return Column(
          children: [
            Expanded(
              child: reviews.isEmpty
                  ? Center(
                child: Text('No Reviews Yet.',
                    style: GoogleFonts.zain(
                        fontSize: 15, color: AppColors.textSecondary)),
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: reviews.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  final review = reviews[index];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(review.userName,
                              style: GoogleFonts.tiltWarp(
                                  fontSize: 14,
                                  color: AppColors.textPrimary)),
                          const SizedBox(width: 8),
                          Row(
                            children: List.generate(
                              5,
                                  (i) => Icon(
                                i < review.rating
                                    ? Icons.star
                                    : Icons.star_border,
                                size: 14,
                                color: AppColors.yellowrspwn,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(review.comment,
                          style: GoogleFonts.zain(
                              fontSize: 13,
                              color: AppColors.textPrimary)),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  onPressed: () => _openAddReviewSheet(context),
                  child: Text('Add Review',
                      style: GoogleFonts.zain(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// About tab

class _AboutTab extends StatelessWidget {
  final Organization organization;
  const _AboutTab({required this.organization});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (organization.description.isNotEmpty) ...[
            Text(
              organization.description,
              style: GoogleFonts.zain(
                  fontSize: 14, color: AppColors.textPrimary, height: 1.4),
            ),
            const SizedBox(height: 16),
          ],
          GestureDetector(
            onTap: () {
              if (organization.bookVisitUrl == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('No booking link available yet.')),
                );
                return;
              }
            },
            child: Row(
              children: [
                Text('Book a visit',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(width: 6),
                const Icon(Icons.arrow_forward,
                    size: 16, color: AppColors.textPrimary),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 260,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(16),
              image: organization.coverImageUrl != null &&
                  organization.coverImageUrl!.isNotEmpty
                  ? DecorationImage(
                  image: NetworkImage(organization.coverImageUrl!),
                  fit: BoxFit.cover)
                  : null,
            ),
            child: organization.coverImageUrl == null ||
                organization.coverImageUrl!.isEmpty
                ? const Center(
              child: Icon(Icons.image_outlined,
                  size: 40, color: AppColors.textSecondary),
            )
                : null,
          ),
        ],
      ),
    );
  }
}