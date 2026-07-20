import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_detail_page.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

enum _SortOption { recent, oldest, applicantName, animalName, interviewDate, status, fitAssessment }

extension on _SortOption {
  String get label => switch (this) {
        _SortOption.recent => 'Recently Submitted',
        _SortOption.oldest => 'Oldest Submitted',
        _SortOption.applicantName => 'Applicant Name',
        _SortOption.animalName => 'Animal Name',
        _SortOption.interviewDate => 'Interview Date',
        _SortOption.status => 'Application Status',
        _SortOption.fitAssessment => 'Fit Assessment',
      };
}

/// Application Review — six phases (see AdoptionStatus): Pending, Interview,
/// Approved, Adopted as one horizontally scrollable tab row, Rejected and
/// Withdrawn kept distinguishable as their own tabs too (not merged) so an
/// admin can always tell which closed applications ended which way.
///
/// [animalId]/[animalName] pre-filter the list to one animal — the entry
/// point from AnimalProfileTab's "View Applications".
class AdoptionApplicationReviewPage extends ConsumerStatefulWidget {
  final String? animalId;
  final String? animalName;
  final AdoptionStatus initialStatus;
  const AdoptionApplicationReviewPage({super.key, this.animalId, this.animalName, this.initialStatus = AdoptionStatus.pending});

  @override
  ConsumerState<AdoptionApplicationReviewPage> createState() => _AdoptionApplicationReviewPageState();
}

class _AdoptionApplicationReviewPageState extends ConsumerState<AdoptionApplicationReviewPage> {
  late AdoptionStatus _tab = widget.initialStatus;
  _SortOption _sort = _SortOption.recent;
  String? _animalFilterId;
  String? _animalFilterName;
  final _animalSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animalFilterId = widget.animalId;
    _animalFilterName = widget.animalName;
  }

  @override
  void dispose() {
    _animalSearchController.dispose();
    super.dispose();
  }

  List<AdoptionApplication> _sorted(List<AdoptionApplication> apps) {
    final list = [...apps];
    switch (_sort) {
      case _SortOption.recent:
        list.sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        break;
      case _SortOption.oldest:
        list.sort((a, b) => (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)));
        break;
      case _SortOption.applicantName:
        list.sort((a, b) => a.adopterName.toLowerCase().compareTo(b.adopterName.toLowerCase()));
        break;
      case _SortOption.animalName:
        list.sort((a, b) => a.animalName.toLowerCase().compareTo(b.animalName.toLowerCase()));
        break;
      case _SortOption.interviewDate:
        list.sort((a, b) => (b.appointmentDate ?? DateTime(0)).compareTo(a.appointmentDate ?? DateTime(0)));
        break;
      case _SortOption.status:
        list.sort((a, b) => a.status.label.compareTo(b.status.label));
        break;
      case _SortOption.fitAssessment:
        list.sort((a, b) => a.fitAssessment.label.compareTo(b.fitAssessment.label));
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final appsAsync = ref.watch(adoptionsByStatusesProvider([_tab]));
    final apps = appsAsync.asData?.value ?? const <AdoptionApplication>[];
    final filtered = _animalFilterId == null ? apps : apps.where((a) => a.animalId == _animalFilterId).toList();
    final sorted = _sorted(filtered);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Adoption Applications', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.background)),
        actions: [
          PopupMenuButton<_SortOption>(
            icon: const Icon(Icons.sort, color: AppColors.background),
            onSelected: (s) => setState(() => _sort = s),
            itemBuilder: (context) =>
                _SortOption.values.map((s) => PopupMenuItem(value: s, child: Text(s.label))).toList(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_animalFilterId != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.yellowrspwn.withValues(alpha: 0.25),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Animal: ${_animalFilterName ?? ''} · Applications: ${apps.where((a) => a.animalId == _animalFilterId).length}',
                        style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _animalFilterId = null;
                      _animalFilterName = null;
                    }),
                    child: Text('Clear', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _animalSearchController,
                decoration: InputDecoration(
                  hintText: 'Filter by animal name…',
                  hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
                  prefixIcon: const Icon(Icons.pets_outlined, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
                ),
                onChanged: (v) => setState(() => _animalFilterName = v.trim().isEmpty ? null : v.trim()),
              ),
            ),

          const SizedBox(height: 8),

          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final s in AdoptionStatus.values) _TabChip(status: s, selected: _tab == s, onTap: () => setState(() => _tab = s)),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: appsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                  child: Text('Could not load applications: $e', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))),
              data: (_) {
                final visible = _animalFilterId == null && (_animalFilterName ?? '').isNotEmpty
                    ? sorted.where((a) => a.animalName.toLowerCase().contains(_animalFilterName!.toLowerCase())).toList()
                    : sorted;
                if (visible.isEmpty) {
                  return Center(
                    child: Text('No applications in ${_tab.label}.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: visible.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _ApplicationCard(application: visible[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final AdoptionStatus status;
  final bool selected;
  final VoidCallback onTap;
  const _TabChip({required this.status, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? AppColors.yellowrspwn : AppColors.slaterspwn),
          ),
          child: Center(
            child: Text(status.label,
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  final AdoptionApplication application;
  const _ApplicationCard({required this.application});

  Color _statusColor(AdoptionStatus s) => switch (s) {
        AdoptionStatus.pending => AppColors.slaterspwn,
        AdoptionStatus.interview => AppColors.yellowrspwn,
        AdoptionStatus.approved => AppColors.greenrspwn,
        AdoptionStatus.adopted => AppColors.lavenderrspwn,
        AdoptionStatus.rejected => const Color(0xFFE05353),
        AdoptionStatus.withdrawn => AppColors.tearspwn,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animal = ref.watch(animalRecordProvider(application.animalId)).asData?.value;
    final photoUrl = animal?.photoUrls.isNotEmpty == true ? animal!.photoUrls.first : null;
    final dateStr = application.createdAt != null
        ? '${application.createdAt!.month}/${application.createdAt!.day}/${application.createdAt!.year}'
        : '-';

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdoptionApplicationDetailPage(applicationId: application.id))),
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
              child: photoUrl != null
                  ? Image.network(photoUrl, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
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
                        child: Text(application.adopterName,
                            style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _statusColor(application.status), borderRadius: BorderRadius.circular(20)),
                        child: Text(application.status.label,
                            style: GoogleFonts.zain(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  Text('${application.animalName} · Submitted $dateStr',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if ((application.adopterCity ?? '').isNotEmpty)
                    Text(application.adopterCity!, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  if (application.appointmentDate != null)
                    Text(
                        'Interview: ${application.appointmentDate!.month}/${application.appointmentDate!.day}/${application.appointmentDate!.year}'
                        '${application.appointmentTime != null ? ' · ${application.appointmentTime}' : ''}',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: application.fitAssessment == FitAssessmentValue.notReviewed
                          ? AppColors.slaterspwn
                          : AppColors.yellowrspwn,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(application.fitAssessment.label,
                        style: GoogleFonts.zain(fontSize: 10, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.pets, color: AppColors.textSecondary),
      );
}
