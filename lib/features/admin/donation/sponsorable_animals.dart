import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/donation_admin.dart';
import 'package:respawnd1/features/donation/models.dart';

import 'donation_admin_create.dart';
import 'donation_admin_info.dart';
import 'donation_admin_providers.dart';

/// Sponsorship listings that are still taking (or about to take) sponsors.
/// Same list as OPEN_SPONSORSHIP_STATUSES in functions/campaigns.js.
const kOpenSponsorshipStatuses = {'draft', 'active', 'paused'};

/// Why [a] can't get a new sponsorship listing, or null when it is ready to
/// be sponsored. Mirrors sponsorshipBlocker() in functions/campaigns.js,
/// which makes the real decision.
String? sponsorshipReadiness(AnimalRecord a) {
  if (a.isMalformed) return 'Record could not be read';
  if (a.archived) return 'Archived';
  if (a.isDeceased) return 'Deceased';
  if (a.isAdopted) return 'Already adopted';
  if (a.isTransferredOut) return 'Being transferred';
  return null;
}

/// animalId → its open sponsorship listing, so an animal is never listed twice.
final openSponsorshipsByAnimalProvider = Provider.autoDispose<Map<String, DonationListing>>((ref) {
  final all = ref.watch(adminCampaignsProvider).asData?.value ?? const <DonationListing>[];
  return {
    for (final l in all)
      if (l.type == 'sponsorship' && l.animalId != null && kOpenSponsorshipStatuses.contains(l.status)) l.animalId!: l,
  };
});

/// Only a Firebase Storage download URL passes saveCampaign's cover-image check.
String? sponsorshipCoverFor(AnimalRecord a) {
  for (final url in a.photoUrls) {
    if (url.startsWith('https://firebasestorage.googleapis.com/')) return url;
  }
  return null;
}

/// One line of what is already known about the animal: "Dog · Aspin · 2 yrs · Male".
String animalSubtitle(AnimalRecord a) => [a.species, a.breed, a.age, a.sex]
    .map((s) => s.trim())
    .where((s) => s.isNotEmpty)
    .join(' · ');

/// Suggested tags from the animal record (admins can still change them).
Set<String> suggestedSponsorshipTags(AnimalRecord a) {
  final h = a.health;
  final needsCare = a.currentCaseId != null ||
      a.hasSpecialNeeds ||
      (h.currentMedications?.trim().isNotEmpty ?? false) ||
      (h.chronicConditions?.trim().isNotEmpty ?? false);
  return {'Food and Supplies', if (needsCare) 'Medicine & Treatment'};
}

/// Suggested "Intended use of funds", built only from what the record says.
String suggestedIntendedUse(AnimalRecord a) {
  final h = a.health;
  final uses = <String>['food'];
  if (!a.vaccinated) uses.add('vaccinations');
  if (!a.spayedNeutered) uses.add('spay/neuter surgery');
  if (!a.dewormed) uses.add('deworming');
  if (a.currentCaseId != null || (h.currentMedications?.trim().isNotEmpty ?? false)) {
    uses.add('ongoing treatment and medication');
  }
  if (a.hasSpecialNeeds) uses.add('special-needs care');
  uses.add('routine vet check-ups');
  final list = uses.length == 1 ? uses.first : '${uses.sublist(0, uses.length - 1).join(', ')} and ${uses.last}';
  final name = a.name.trim().isEmpty ? 'this animal' : a.name.trim();
  return 'Monthly care for $name: $list.';
}

/// Suggested description: the record's own description when it has one.
String suggestedSponsorshipDescription(AnimalRecord a) {
  if (a.description.trim().isNotEmpty) return a.description.trim();
  final parts = [a.age, a.sex, a.breed, a.species].map((s) => s.trim()).where((s) => s.isNotEmpty).join(' ');
  final name = a.name.trim().isEmpty ? 'This animal' : a.name.trim();
  return parts.isEmpty ? '$name is waiting for a sponsor.' : '$name is a $parts waiting for a sponsor.';
}

/// "Sponsor an Animal": pick from the animals that are ready to be sponsored;
/// the sponsorship form then opens already filled from that animal's record.
class SponsorAnimalPickerPage extends ConsumerStatefulWidget {
  const SponsorAnimalPickerPage({super.key});

  @override
  ConsumerState<SponsorAnimalPickerPage> createState() => _SponsorAnimalPickerPageState();
}

class _SponsorAnimalPickerPageState extends ConsumerState<SponsorAnimalPickerPage> {
  String _query = '';
  String _species = 'All';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(AnimalRecord a) {
    if (_species != 'All' && a.species.toLowerCase() != _species.toLowerCase()) return false;
    if (_query.isEmpty) return true;
    return '${a.name} ${a.breed} ${a.species}'.toLowerCase().contains(_query);
  }

  void _sponsor(AnimalRecord a) => Navigator.pushReplacement(
    context,
    MaterialPageRoute(builder: (_) => DonationAdminCreatePage(initialType: 'sponsorship', initialAnimal: a)),
  );

  @override
  Widget build(BuildContext context) {
    final animals = ref.watch(linkableAnimalsProvider);
    final open = ref.watch(openSponsorshipsByAnimalProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          const DonationAdminHeader(
            title: 'Sponsor an Animal',
            helpText: 'Only animals that are ready to be sponsored are listed: not archived, deceased, adopted or '
                'being transferred, and without an open sponsorship. Choose one and the sponsorship form opens '
                'filled in from its animal record — photo, name, species, description and suggested use of funds. '
                'Review it, set the monthly amount and publish.',
          ),
          AdminSearchBar(
            controller: _searchController,
            hintText: 'Search by name or breed',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                for (final s in const ['All', 'Dog', 'Cat'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                      selected: _species == s,
                      selectedColor: AppColors.yellowrspwn,
                      backgroundColor: AppColors.surface,
                      onSelected: (_) => setState(() => _species = s),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: animals.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppColors.textPrimary)),
              error: (e, _) =>
                  Center(child: Text('Could not load animals: $e', style: GoogleFonts.zain(color: Colors.redAccent))),
              data: (all) {
                final ready = <AnimalRecord>[];
                final listed = <AnimalRecord>[];
                final notReady = <(AnimalRecord, String)>[];
                for (final a in all.where(_matches)) {
                  final blocker = sponsorshipReadiness(a);
                  if (blocker != null) {
                    notReady.add((a, blocker));
                  } else if (open.containsKey(a.id)) {
                    listed.add(a);
                  } else {
                    ready.add(a);
                  }
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
                  children: [
                    Text('Ready to be sponsored (${ready.length})',
                        style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    if (ready.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          all.isEmpty
                              ? 'No animal records yet. Add animals in Animal Records first.'
                              : 'No animals are waiting for a sponsor.',
                          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textSecondary),
                        ),
                      ),
                    for (final a in ready)
                      SponsorAnimalTile(
                        animal: a,
                        trailing: const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                        onTap: () => _sponsor(a),
                      ),
                    if (listed.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Already has a sponsorship listing',
                          style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      for (final a in listed)
                        SponsorAnimalTile(
                          animal: a,
                          dimmed: true,
                          trailing: CampaignStatusChip(open[a.id]!.status),
                          onTap: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => DonationAdminInfoPage(campaignId: open[a.id]!.id))),
                        ),
                    ],
                    if (notReady.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Text('Not ready', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      for (final (a, reason) in notReady)
                        SponsorAnimalTile(
                          animal: a,
                          dimmed: true,
                          trailing: Text(reason, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Photo, name and what the record already says about the animal.
class SponsorAnimalTile extends StatelessWidget {
  final AnimalRecord animal;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dimmed;
  const SponsorAnimalTile({super.key, required this.animal, this.trailing, this.onTap, this.dimmed = false});

  @override
  Widget build(BuildContext context) {
    final a = animal;
    final photo = a.photoUrls.isNotEmpty ? a.photoUrls.first : null;
    final h = a.health;
    final facts = [
      a.statusLabel,
      if (a.vaccinated) 'Vaccinated',
      if (a.spayedNeutered || (h.sterilized ?? false)) 'Spayed/Neutered',
      if (a.hasSpecialNeeds) 'Special needs',
    ].join(' · ');
    return Opacity(
      opacity: dimmed ? 0.6 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: photo == null
                      ? Container(
                    color: AppColors.tearspwn,
                    child: const Icon(Icons.pets, color: AppColors.textPrimary),
                  )
                      : Image.network(
                    photo,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: AppColors.tearspwn,
                      child: const Icon(Icons.pets, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name.isEmpty ? 'Unnamed animal' : a.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    if (animalSubtitle(a).isNotEmpty)
                      Text(animalSubtitle(a),
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
                    Text(facts,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}
