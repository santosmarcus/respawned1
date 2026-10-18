import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';

/// Sort options for the Volunteers directory. Default is [availability]
/// (available/online volunteers first) — per explicit product direction,
/// since the spec that introduced this page said not to guess a default.
/// 'Nearest' and 'Most recently joined'/'Role or skill' from the spec's
/// suggested list are deliberately not offered: rescue_volunteer accounts
/// have no location field (they aren't tied to a case until assigned) and
/// no createdAt/role-skill field is written at signup — adding sorts for
/// data that doesn't exist would just silently no-op or fabricate ordering.
enum VolunteerSortOption {
  availability,
  nameAZ,
  nameZA;

  String get label => switch (this) {
        VolunteerSortOption.availability => 'Availability',
        VolunteerSortOption.nameAZ => 'Name A–Z',
        VolunteerSortOption.nameZA => 'Name Z–A',
      };
}

class VolunteersPage extends ConsumerStatefulWidget {
  const VolunteersPage({super.key});

  @override
  ConsumerState<VolunteersPage> createState() => _VolunteersPageState();
}

class _VolunteersPageState extends ConsumerState<VolunteersPage> {
  final _searchController = TextEditingController();
  String _searchText = '';
  VolunteerSortOption _sort = VolunteerSortOption.availability;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<PetTransporter> _applyFilters(List<PetTransporter> volunteers) {
    final query = _searchText.trim().toLowerCase();
    final filtered = query.isEmpty
        ? volunteers
        : volunteers
            .where((v) =>
                v.name.toLowerCase().contains(query) || (v.phone ?? '').toLowerCase().contains(query))
            .toList();

    final sorted = [...filtered];
    switch (_sort) {
      case VolunteerSortOption.availability:
        // Online first, then alphabetical within each group — never
        // reordered by anything the volunteer doesn't control.
        sorted.sort((a, b) {
          if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
      case VolunteerSortOption.nameAZ:
        sorted.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case VolunteerSortOption.nameZA:
        sorted.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
    }
    return sorted;
  }

  Future<void> _openSortSheet() async {
    final picked = await showModalBottomSheet<VolunteerSortOption>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Sort Volunteers', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            for (final option in VolunteerSortOption.values)
              RadioListTile<VolunteerSortOption>(
                contentPadding: EdgeInsets.zero,
                value: option,
                groupValue: _sort,
                activeColor: AppColors.textPrimary,
                title: Text(option.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                onChanged: (v) => Navigator.pop(context, v),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final volunteersAsync = ref.watch(rescueVolunteersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: const AdminDrawer(active: AdminModule.volunteers),
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: AppColors.background),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Text('Volunteers', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
      ),
      body: Column(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _searchText = v),
                            decoration: InputDecoration(
                              hintText: 'Search volunteers…',
                              hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _openSortSheet,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.slaterspwn),
                    ),
                    child: const Icon(Icons.sort, size: 20, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Sorted by: ${_sort.label}',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: volunteersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Could not load volunteers.',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              ),
              data: (volunteers) {
                final list = _applyFilters(volunteers);
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      volunteers.isEmpty ? 'No rescue volunteers yet.' : 'No volunteers match your search.',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _VolunteerCard(volunteer: list[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VolunteerCard extends StatelessWidget {
  final PetTransporter volunteer;
  const _VolunteerCard({required this.volunteer});

  Future<void> _call() async {
    final phone = volunteer.phone;
    if (phone == null || phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final hasPhone = (volunteer.phone ?? '').isNotEmpty;
    final hasVehicle = (volunteer.vehicleType ?? '').isNotEmpty || (volunteer.licensePlate ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.tearspwn,
            backgroundImage: (volunteer.photoUrl != null && volunteer.photoUrl!.isNotEmpty)
                ? NetworkImage(volunteer.photoUrl!)
                : null,
            child: (volunteer.photoUrl == null || volunteer.photoUrl!.isEmpty)
                ? const Icon(Icons.person_outline, color: AppColors.textSecondary)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(volunteer.name,
                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                if (hasVehicle)
                  Text('${volunteer.vehicleType ?? ''} ${volunteer.licensePlate ?? ''}'.trim(),
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: volunteer.isOnline ? AppColors.greenrspwn : AppColors.slaterspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    volunteer.isOnline ? 'Online' : 'Offline',
                    style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          if (hasPhone)
            IconButton(
              icon: const Icon(Icons.call_outlined, color: AppColors.textPrimary),
              onPressed: _call,
            ),
        ],
      ),
    );
  }
}
