import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'animal_record_detail_page.dart';
import 'create_animal_record_page.dart';

class AnimalRecordsPage extends StatefulWidget {
  const AnimalRecordsPage({super.key});

  @override
  State<AnimalRecordsPage> createState() => _AnimalRecordsPageState();
}

class _AnimalRecordsPageState extends State<AnimalRecordsPage> {
  String _speciesFilter = 'All';
  String _statusFilter = 'All';
  String _searchQuery = '';
  final _searchController = TextEditingController();

  final List<String> _statusFilters = [
    'All', 'Adoptable', 'In Treatment', 'Adopted', 'Deceased', 'Closed'
  ];

  Color _statusColor(String status) {
    switch (status) {
      case 'Adoptable':     return AppColors.yellowrspwn;
      case 'In Treatment':  return AppColors.pinkrspwn;
      case 'Adopted':       return AppColors.lavenderrspwn;
      case 'Deceased':      return AppColors.slaterspwn;
      case 'Closed':        return AppColors.tearspwn;
      default:              return AppColors.slaterspwn;
    }
  }

  Query _buildQuery() {
    Query q = FirebaseFirestore.instance.collection('animals');
    if (_speciesFilter != 'All') {
      q = q.where('species',
          isEqualTo: _speciesFilter == 'Dogs' ? 'Dog' : 'Cat');
    }
    if (_statusFilter != 'All') {
      q = q.where('adoptionStatus',
          isEqualTo: _statusFilter.toLowerCase().replaceAll(' ', '_'));
    }
    return q.orderBy('createdAt', descending: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.background),
          onPressed: () {},
        ),
        title: Text('Animal Records',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),

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
                      onChanged: (v) => setState(() => _searchQuery = v),
                      style: GoogleFonts.zain(
                          fontSize: 14, color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        hintStyle: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textPrimary
                                .withValues(alpha: 0.6)),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.textPrimary, size: 20),
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
                  child: const Icon(Icons.tune,
                      color: AppColors.textPrimary, size: 20),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Species + Status filters row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                // Species filter
                _FilterChip(
                  label: 'Dogs',
                  selected: _speciesFilter == 'Dogs',
                  onTap: () => setState(() =>
                  _speciesFilter =
                  _speciesFilter == 'Dogs' ? 'All' : 'Dogs'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Cats',
                  selected: _speciesFilter == 'Cats',
                  onTap: () => setState(() =>
                  _speciesFilter =
                  _speciesFilter == 'Cats' ? 'All' : 'Cats'),
                ),
                const Spacer(),
                // Status filter dropdown
                PopupMenuButton<String>(
                  onSelected: (val) =>
                      setState(() => _statusFilter = val),
                  color: AppColors.background,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (_) => _statusFilters
                      .map((s) => PopupMenuItem(
                    value: s,
                    child: Row(
                      children: [
                        if (s != 'All')
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: _statusColor(s),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(s,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: AppColors.textPrimary)),
                      ],
                    ),
                  ))
                      .toList(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _statusFilter == 'All'
                          ? AppColors.greenrspwn
                          : _statusColor(_statusFilter),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_statusFilter,
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down,
                            size: 16, color: AppColors.textPrimary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Animal list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery().snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('No animal records found.',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                  );
                }

                final docs = snapshot.data!.docs.where((doc) {
                  if (_searchQuery.isEmpty) return true;
                  final d = doc.data() as Map<String, dynamic>;
                  final name =
                  (d['name'] ?? '').toString().toLowerCase();
                  final breed =
                  (d['breed'] ?? '').toString().toLowerCase();
                  return name.contains(_searchQuery.toLowerCase()) ||
                      breed.contains(_searchQuery.toLowerCase());
                }).toList();

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: docs.length,
                  separatorBuilder: (context, index) =>
                  const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _AnimalCard(
                      animalId: doc.id,
                      data: data,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AnimalRecordDetailPage(
                            animalId: doc.id,
                            data: data,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Create Animal Record button
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
    );
  }
}

class _AnimalCard extends StatelessWidget {
  final String animalId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const _AnimalCard({
    required this.animalId,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = false; // highlight logic if needed
    final healthTags = List<String>.from(data['health'] ?? []);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isSelected
              ? Border.all(color: AppColors.textPrimary, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 6)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.tearspwn,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.pets,
                  size: 32, color: AppColors.textSecondary),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(data['name'] ?? 'Unnamed',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 15,
                              color: AppColors.textPrimary)),
                      const SizedBox(width: 6),
                      Icon(
                        data['sex'] == 'Female'
                            ? Icons.female
                            : Icons.male,
                        size: 16,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  Text(data['breed'] ?? data['species'] ?? '',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(
                    data['age'] != null
                        ? '${data['age']} year old'
                        : '',
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  Text(data['description'] ?? '',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: healthTags
                        .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.slaterspwn),
                      ),
                      child: Text(t,
                          style: GoogleFonts.zain(
                              fontSize: 10,
                              color: AppColors.textPrimary)),
                    ))
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
        padding:
        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.greenrspwn
              : AppColors.lavenderrspwn,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ),
    );
  }
}