import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/widgets/animal_basic_info_row.dart';
import 'package:respawnd1/core/widgets/animal_image_gallery.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart' show genderIconFor;
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/animal_medical_tab.dart' show MedicalProfileSection, SpecialNeedsSection, VaccineSection;
import 'adoption_page.dart';
import 'package:respawnd1/core/repos/adoption_application_repository.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

class _AnimalDetail {
  final String size;
  final String coatLength;
  final List<String> keyCharacteristics;
  final List<String> rescueBackground;
  final String description;
  final String organization;
  final String orgSubtitle;

  const _AnimalDetail({
    required this.size,
    required this.coatLength,
    required this.keyCharacteristics,
    required this.rescueBackground,
    required this.description,
    required this.organization,
    required this.orgSubtitle,
  });
}

// Animal page — Profile / Medical tabs (spec section 8), same tab design
// language as the admin Animal Record page's pill selector, but entirely
// read-only: no Edit actions anywhere on this page.
class AnimalPage extends ConsumerStatefulWidget {
  final Animal animal;
  final VoidCallback onFavoriteToggle;

  const AnimalPage({
    super.key,
    required this.animal,
    required this.onFavoriteToggle,});

  @override
  ConsumerState<AnimalPage> createState() => _AnimalPageState();
}

class _AnimalPageState extends ConsumerState<AnimalPage> {
  late bool _favorited;
  bool _checkingAdoption = false;
  int _tabIndex = 0; // 0 = Profile, 1 = Medical

  _AnimalDetail get _detail {
    final animal = widget.animal;
    return _AnimalDetail(
      size: animal.size,
      coatLength: animal.coatLength,
      keyCharacteristics: animal.keyCharacteristics.isNotEmpty
          ? animal.keyCharacteristics
          : (animal.badge != null ? [animal.badge!] : []),
      rescueBackground: animal.rescueBackground,
      description: animal.description,
      organization: 'ResPAWnd Partner',
      orgSubtitle: 'Verified rescue organization',
    );
  }

  @override
  void initState() {
    super.initState();
    _favorited = widget.animal.favorited;
  }

  void _showUnavailableDialog({required String title, required String message}) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(title,
            style: GoogleFonts.tiltWarp(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        content: Text(message, style: GoogleFonts.zain(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }

  /// Multiple people may have a pending/interview/under-review application
  /// for the same animal at once — that alone must never block anyone else
  /// from applying. Only the animal's own reserved/adopted state (see
  /// AdoptionApplicationRepository.checkAvailability) can do that. The
  /// current user's OWN application (any status) always takes priority:
  /// a completed one routes to post-adoption monitoring, an in-progress
  /// one resumes directly — neither ever shows an availability dialog.
  Future<void> _handleAdoptTap() async {
    if (_checkingAdoption) return;
    setState(() => _checkingAdoption = true);

    final animal = widget.animal;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      final legacySnap = await FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalId', isEqualTo: '${animal.id}')
          .where('personal.adopterId', isEqualTo: uid)
          .get();
      final byRecordIdSnap = animal.animalRecordId.isEmpty
          ? null
          : await FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalRecordId', isEqualTo: animal.animalRecordId)
          .where('personal.adopterId', isEqualTo: uid)
          .get();

      final docsById = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in legacySnap.docs) {
        docsById[d.id] = d;
      }
      if (byRecordIdSnap != null) {
        for (final d in byRecordIdSnap.docs) {
          docsById[d.id] = d;
        }
      }

      QueryDocumentSnapshot? myActiveDoc;
      QueryDocumentSnapshot? myCompletedDoc;

      for (final doc in docsById.values) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status == 'rejected' || status == 'withdrawn') continue;

        if (status == 'completed' || status == 'return_requested' || status == 'return_approved') {
          myCompletedDoc = doc;
        } else {
          myActiveDoc = doc;
        }
      }

      if (!mounted) return;

      if (myCompletedDoc != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PostAdoptionMonitoringPage(adoptionId: myCompletedDoc!.id),
          ),
        );
        return;
      }

      if (myActiveDoc != null) {
        // Already have an in-progress application of my own — resume it
        // directly, never a blocking dialog.
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdoptionProcess(animal: animal, existingAdoptionId: myActiveDoc!.id),
          ),
        );
        return;
      }

      // No application of my own — the only thing that can stop a fresh
      // one is the animal's own reserved/adopted state.
      final result = await AdoptionApplicationRepository().checkAvailability(
        legacyAnimalId: '${animal.id}',
        animalRecordId: animal.animalRecordId,
        uid: uid ?? '',
      );
      if (!mounted) return;

      switch (result.availability) {
        case AnimalAdoptionAvailability.reservedForOther:
          _showUnavailableDialog(
            title: 'Reserved',
            message: 'This animal is currently reserved for another approved applicant.',
          );
          break;
        case AnimalAdoptionAvailability.adopted:
          _showUnavailableDialog(title: 'Adopted', message: 'This animal has already been adopted.');
          break;
        case AnimalAdoptionAvailability.unavailable:
          _showUnavailableDialog(
            title: 'Unavailable',
            message: 'This animal is not currently accepting applications.',
          );
          break;
        case AnimalAdoptionAvailability.available:
        case AnimalAdoptionAvailability.ownApplicationActive:
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AdoptionProcess(animal: animal),
            ),
          );
          break;
      }
    } catch (_) {
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AdoptionProcess(animal: animal),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingAdoption = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final detail = _detail;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          AnimalImageGallery(
            photoUrls: animal.photoUrls,
            height: 260,
            backgroundColor: animal.cardColor,
            overlays: [
              // Back button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                left: 12,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(
                    Icons.chevron_left,
                    size: 32,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),

              // Share button
              Positioned(
                top: MediaQuery.of(context).padding.top + 10,
                right: 50,
                child: const Icon(
                  Icons.ios_share,
                  size: 22,
                  color: AppColors.textPrimary,
                ),
              ),

              // Favorite button
              Positioned(
                top: MediaQuery.of(context).padding.top + 8,
                right: 14,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _favorited = !_favorited;
                    });
                    widget.onFavoriteToggle();
                  },
                  child: Icon(
                    _favorited ? Icons.favorite : Icons.favorite_border,
                    size: 26,
                    color: _favorited
                        ? const Color(0xFFE05C5C)
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),

          // content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        animal.name,
                        style: GoogleFonts.tiltWarp(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),

                      if (genderIconFor(animal.sex) != null) ...[
                        const SizedBox(width: 8),
                        Icon(genderIconFor(animal.sex), size: 22, color: AppColors.textPrimary),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  _ProfileMedicalTabs(
                    tabIndex: _tabIndex,
                    onTabChanged: (i) => setState(() => _tabIndex = i),
                  ),

                  const SizedBox(height: 16),

                  if (_tabIndex == 0)
                    _ProfileTabContent(animal: animal, detail: detail)
                  else
                    _MedicalTabContent(animalRecordId: animal.animalRecordId),

                  const SizedBox(height: 28),

                  _AdoptOrViewStatusButton(
                    animal: animal,
                    checking: _checkingAdoption,
                    onAdoptTap: _handleAdoptTap,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill-style Profile/Medical selector — same visual language as the admin
/// Animal Record page's tab pill (animal_record_detail_page.dart), kept as
/// a separate local implementation since that one isn't a shared/exported
/// widget. Only two tabs here (no Management — this page is read-only).
class _ProfileMedicalTabs extends StatelessWidget {
  final int tabIndex;
  final ValueChanged<int> onTabChanged;
  const _ProfileMedicalTabs({required this.tabIndex, required this.onTabChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(50)),
      child: Row(
        children: [
          _TabPillButton(label: 'Profile', index: 0, selected: tabIndex == 0, onTap: onTabChanged),
          _TabPillButton(label: 'Medical', index: 1, selected: tabIndex == 1, onTap: onTabChanged),
        ],
      ),
    );
  }
}

class _TabPillButton extends StatelessWidget {
  final String label;
  final int index;
  final bool selected;
  final ValueChanged<int> onTap;
  const _TabPillButton({required this.label, required this.index, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(label, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

/// Profile tab (spec section 8) — general animal information only:
/// species/breed/sex/size/age/color-markings, Description (above
/// Temperament), Temperament/Compatibility/Training/Rescue Background,
/// Organization info, Sponsors. No Health/medical block — that content
/// lives only on the Medical tab now, never duplicated here.
class _ProfileTabContent extends StatelessWidget {
  final Animal animal;
  final _AnimalDetail detail;
  const _ProfileTabContent({required this.animal, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'Animal Information'),
        const SizedBox(height: 10),
        AnimalBasicInfoRow(fields: [
          InfoField('Species', animal.species.isNotEmpty ? animal.species : 'Not provided'),
          InfoField('Age', animal.age.isNotEmpty ? animal.age : 'Not provided'),
          InfoField('Size', detail.size),
          InfoField('Breed', animal.breed.isNotEmpty ? animal.breed : 'Not provided'),
          InfoField('Coat Length', detail.coatLength),
          const InfoField('Color / Markings', 'Not provided'),
        ]),

        const SizedBox(height: 20),

        // Description above Temperament (spec section 7).
        _SectionHeader(label: 'Description'),
        const SizedBox(height: 6),
        Text(
          detail.description,
          style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary, height: 1.5),
        ),

        const SizedBox(height: 20),

        for (final group in [
          ('Temperament', detail.keyCharacteristics.where(kTemperamentValues.contains).toList()),
          ('Compatibility', detail.keyCharacteristics.where(kCompatibilityValues.contains).toList()),
          ('Training', detail.keyCharacteristics.where(kTrainingValues.contains).toList()),
          ('Rescue Background', detail.rescueBackground),
        ])
          if (group.$2.isNotEmpty) ...[
            _SectionHeader(label: group.$1),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: group.$2.map((t) => _YellowTag(label: t)).toList(),
            ),
            const SizedBox(height: 20),
          ],

        // Organization Info
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(22)),
              child: const Icon(Icons.groups_2_outlined, size: 22, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(detail.organization, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                Text(detail.orgSubtitle, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),

        const SizedBox(height: 20),

        _SponsorsRow(animalId: animal.id),
      ],
    );
  }
}

/// Medical tab (spec section 8) — Medical Profile (read-only) + Vaccines +
/// Special Needs (only when meaningful). No admin Edit affordances. Needs
/// the real `animals/{id}` AnimalRecord (not just the lighter `Animal`
/// display model this page otherwise uses) for health/vaccination data —
/// `animal.animalRecordId` is the reliable join key (see AdoptionApplication
/// / animalRecordToCard's own doc comments on why the legacy `animal.id`
/// int hash can't be used to look this up).
class _MedicalTabContent extends ConsumerWidget {
  final String animalRecordId;
  const _MedicalTabContent({required this.animalRecordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (animalRecordId.isEmpty) {
      return Text('Medical information is unavailable for this record.',
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
    }
    final recordAsync = ref.watch(animalRecordProvider(animalRecordId));
    final record = recordAsync.asData?.value;
    if (recordAsync.isLoading && record == null) {
      return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
    }
    if (record == null) {
      return Text('Medical information is unavailable for this record.',
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MedicalProfileSection(animal: record, readOnly: true),
        if (record.hasMeaningfulSpecialNeedsInfo) ...[
          const SizedBox(height: 20),
          SpecialNeedsSection(animal: record),
        ],
        const SizedBox(height: 20),
        VaccineSection(animal: record, readOnly: true),
      ],
    );
  }
}

class _AdoptOrViewStatusButton extends StatelessWidget {
  final Animal animal;
  final bool checking;
  final VoidCallback onAdoptTap;
  const _AdoptOrViewStatusButton({required this.animal, required this.checking, required this.onAdoptTap});

  Widget _button({required String label, required VoidCallback? onTap}) => SizedBox(
    width: double.infinity,
    height: 52,
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.yellowrspwn,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(label, style: GoogleFonts.tiltWarp(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return _button(label: 'Adopt Me', onTap: checking ? null : onAdoptTap);

    final hasRecordId = animal.animalRecordId.isNotEmpty;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('adoptions')
          .where(hasRecordId ? 'personal.animalRecordId' : 'personal.animalId',
          isEqualTo: hasRecordId ? animal.animalRecordId : '${animal.id}')
          .where('personal.adopterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _button(label: checking ? 'Checking...' : 'Adopt Me', onTap: checking ? null : onAdoptTap);
        }

        QueryDocumentSnapshot? activeDoc;
        QueryDocumentSnapshot? completedDoc;
        for (final doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? '';
          if (status == 'rejected' || status == 'withdrawn') continue;
          if (status == 'completed' ||
              status == 'return_requested' ||
              status == 'return_approved') {
            completedDoc = doc;
          } else {
            activeDoc = doc;
          }
        }

        final targetDoc = completedDoc ?? activeDoc;

        if (targetDoc == null) return _button(label: checking ? 'Checking...' : 'Adopt Me', onTap: checking ? null : onAdoptTap);
        final isCompleted = completedDoc != null;

        return _button(
          label: 'View Status',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => isCompleted
                    ? PostAdoptionMonitoringPage(adoptionId: targetDoc.id)
                    : AdoptionProcess(animal: animal, existingAdoptionId: targetDoc.id),
              ),
            );
          },
        );
      },
    );
  }
}

// Shared sub-widgets
class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: GoogleFonts.tiltWarp(
        fontSize: 15,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }
}

class _YellowTag extends StatelessWidget {
  final String label;
  const _YellowTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: GoogleFonts.zain(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
// Sponsors row
class _SponsorsRow extends StatelessWidget {
  final int animalId;
  const _SponsorsRow({required this.animalId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sponsors')
          .where('animalId', isEqualTo: animalId)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        final label = count == 0
            ? 'Available for Sponsorships'
            : (count == 1 ? '1 sponsor' : '$count sponsors');

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _SectionHeader(label: 'Sponsors'),
            Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 15,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        );
      },
    );
  }
}