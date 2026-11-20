import 'package:respawnd1/features/admin/widgets/view_only.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart' show RescueVolunteerListing;
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/volunteers/transporter_applications_page.dart';
import 'package:respawnd1/features/admin/volunteers/transporter_detail_page.dart';
import 'package:respawnd1/features/admin/volunteers/volunteer_applications_page.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_drawer.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_stats.dart';
import 'package:respawnd1/core/widgets/volunteer_badges.dart';

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

/// Rescue Volunteers: approved rescue volunteers (organizations with kind
/// 'independent'). Also serves the drawer's Transporters entry
/// ([transporters]): `pet_transporter` accounts, with their verification.
class VolunteersPage extends ConsumerStatefulWidget {
  final bool transporters;
  const VolunteersPage({super.key, this.transporters = false});

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
            Text('Sort $_title', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            RadioGroup<VolunteerSortOption>(
              groupValue: _sort,
              onChanged: (v) => Navigator.pop(context, v),
              child: Column(
                children: [
                  for (final option in VolunteerSortOption.values)
                    RadioListTile<VolunteerSortOption>(
                      contentPadding: EdgeInsets.zero,
                      value: option,
                      activeColor: AppColors.textPrimary,
                      title: Text(option.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _sort = picked);
  }

  String get _title => widget.transporters ? 'Transporters' : 'Rescue Volunteers';
  String get _noun => widget.transporters ? 'transporters' : 'rescue volunteers';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      drawer: AdminDrawer(active: widget.transporters ? AdminModule.transporters : AdminModule.volunteers),
      appBar: AdminAppBar(
        title: _title,
        menuActions: [
          AdminMenuAction(
            label: 'Applications',
            icon: Icons.assignment_ind_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    widget.transporters ? const TransporterApplicationsPage() : const VolunteerApplicationsPage(),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const ViewOnlyBanner(perms: [OrgPermission.volunteers]),
          AdminSearchBar(
            controller: _searchController,
            hintText: 'Search $_noun…',
            onChanged: (v) => setState(() => _searchText = v),
            filterIcon: Icons.sort,
            filterTooltip: 'Sort',
            onFilter: _openSortSheet,
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
            child: !widget.transporters
                ? _rescueVolunteers()
                : ref.watch(petTransportersProvider).when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text('Could not load $_noun.',
                    style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
              ),
              data: (volunteers) {
                final list = _applyFilters(volunteers);
                if (list.isEmpty) {
                  return Center(
                    child: Text(
                      volunteers.isEmpty
                          ? (widget.transporters ? 'No pet transporters yet.' : 'No rescue volunteers yet.')
                          : 'No $_noun match your search.',
                      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _VolunteerCard(
                    volunteer: list[i],
                    showVerification: widget.transporters,
                    onTap: widget.transporters
                        ? () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => TransporterDetailPage(uid: list[i].uid)),
                            )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Approved rescue volunteers (organizations with kind 'independent').
  /// Availability = taking cases: not paused and under their limits.
  Widget _rescueVolunteers() {
    return ref.watch(approvedRescueVolunteersProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => Center(
            child: Text('Could not load rescue volunteers.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
          ),
          data: (all) {
            final list = all.where((v) => v.matches(_searchText)).toList();
            int byName(RescueVolunteerListing a, RescueVolunteerListing b) =>
                a.name.toLowerCase().compareTo(b.name.toLowerCase());
            switch (_sort) {
              case VolunteerSortOption.availability:
                list.sort((a, b) => a.isAvailable != b.isAvailable ? (a.isAvailable ? -1 : 1) : byName(a, b));
              case VolunteerSortOption.nameAZ:
                list.sort(byName);
              case VolunteerSortOption.nameZA:
                list.sort((a, b) => byName(b, a));
            }
            if (list.isEmpty) {
              return Center(
                child: Text(
                  all.isEmpty ? 'No approved rescue volunteers yet.' : 'No rescue volunteers match your search.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) => _RescueVolunteerCard(volunteer: list[i]),
            );
          },
        );
  }
}

class _RescueVolunteerCard extends StatelessWidget {
  const _RescueVolunteerCard({required this.volunteer});

  final RescueVolunteerListing volunteer;

  Future<void> _call() async {
    if (volunteer.phone.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: volunteer.phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final v = volunteer;
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
            backgroundImage: v.avatarUrl != null ? NetworkImage(v.avatarUrl!) : null,
            child: v.avatarUrl == null ? const Icon(Icons.volunteer_activism_outlined, color: AppColors.textSecondary) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.name,
                    style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  [
                    if (v.area.isNotEmpty) v.area,
                    v.memberCount > 1 ? 'Team of ${v.memberCount}' : 'Solo',
                  ].join(' · '),
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    v.isAvailable
                        ? _pill('Taking cases', AppColors.greenrspwn)
                        : _pill(v.unavailableReason!, AppColors.slaterspwn),
                    _pill('${v.activeCases}/${v.maxActiveCases} cases', AppColors.textSecondary),
                    _pill('${v.animalsInCare}/${v.maxAnimalsInCare} animals', AppColors.textSecondary),
                  ],
                ),
              ],
            ),
          ),
          if (v.phone.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.call_outlined, color: AppColors.textPrimary),
              onPressed: _call,
            ),
        ],
      ),
    );
  }
}

class _VolunteerCard extends StatelessWidget {
  final PetTransporter volunteer;
  final bool showVerification;
  final VoidCallback? onTap;
  const _VolunteerCard({required this.volunteer, this.showVerification = false, this.onTap});

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
    final card = Container(
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
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _pill(volunteer.isOnline ? 'Online' : 'Offline',
                        volunteer.isOnline ? AppColors.greenrspwn : AppColors.slaterspwn),
                    if (showVerification) transporterVerificationPill(volunteer),
                    if ((volunteer.volunteerStats?.attendedCount ?? 0) > 0)
                      _pill('${volunteer.volunteerStats!.attendedCount} attended', AppColors.textSecondary),
                    for (final b in volunteer.volunteerStats?.badges ?? const <VolunteerBadge>[])
                      VolunteerBadgeChip(badge: b, compact: true),
                  ],
                ),
              ],
            ),
          ),
          if (hasPhone)
            IconButton(
              icon: const Icon(Icons.call_outlined, color: AppColors.textPrimary),
              onPressed: _call,
            ),
          if (onTap != null) const Icon(Icons.chevron_right, color: AppColors.textSecondary),
        ],
      ),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: card);
  }
}

Widget _pill(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
    );

/// Verified / Under review / Rejected / Not submitted, from the
/// transporter's users doc.
Widget transporterVerificationPill(PetTransporter t) {
  if (t.isVerified || t.verificationStatus == 'approved') return _pill('Verified', AppColors.greenrspwn);
  return switch (t.verificationStatus) {
    'pending' => _pill('Under review', const Color(0xFFE0A800)),
    'rejected' => _pill('Rejected', AppColors.error),
    _ => _pill('Not submitted', AppColors.slaterspwn),
  };
}
