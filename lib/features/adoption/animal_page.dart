import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_characteristics.dart';
import 'package:respawnd1/core/widgets/animal_basic_info_row.dart';
import 'package:respawnd1/core/widgets/animal_image_gallery.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart' show genderIconFor;
import 'adoption_page.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

// Extended detail data — no longer keyed by a hardcoded per-name map (that
// was fabricated demo data unrelated to any real Animal Record field, e.g.
// a "date of birth" for whichever four names happened to exist in the old
// static catalog). AnimalRecord has no date-of-birth field at all, so this
// honestly shows "Unknown" for every animal instead of inventing one.
class _AnimalDetail {
  final String size;
  final String coatLength;
  final List<String> health;
  final List<String> keyCharacteristics;
  final List<String> rescueBackground;
  final String description;
  final String organization;
  final String orgSubtitle;

  const _AnimalDetail({
    required this.size,
    required this.coatLength,
    required this.health,
    required this.keyCharacteristics,
    required this.rescueBackground,
    required this.description,
    required this.organization,
    required this.orgSubtitle,
  });
}

// Animal page
class AnimalPage extends StatefulWidget {
  final Animal animal;
  final VoidCallback onFavoriteToggle;

  const AnimalPage({
    super.key,
    required this.animal,
    required this.onFavoriteToggle,});

  @override
  State<AnimalPage> createState() => _AnimalPageState();
}

class _AnimalPageState extends State<AnimalPage> {
  late bool _favorited;
  bool _checkingAdoption = false;

  _AnimalDetail get _detail {
    final animal = widget.animal;
    return _AnimalDetail(
      size: animal.size,
      coatLength: animal.coatLength,
      health: animal.healthTags,
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

  Future<void> _handleAdoptTap() async {
    if (_checkingAdoption) return;
    setState(() => _checkingAdoption = true);

    final animal = widget.animal;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    try {
      // Checked by both keys — personal.animalId was previously compared
      // against the raw int animal.id while the field is actually stored
      // as a string (adoption_process.dart writes '${animal.id}'), so this
      // never matched anything; fixed to compare like-for-like. Also
      // checks personal.animalRecordId (the real animal doc id) so
      // applications submitted after that field was added are found too —
      // neither key alone covers every application for this animal.
      final legacySnap = await FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalId', isEqualTo: '${animal.id}')
          .get();
      final byRecordIdSnap = animal.animalRecordId.isEmpty
          ? null
          : await FirebaseFirestore.instance
              .collection('adoptions')
              .where('personal.animalRecordId', isEqualTo: animal.animalRecordId)
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

      QueryDocumentSnapshot? blockingDoc;
      QueryDocumentSnapshot? myActiveDoc;
      QueryDocumentSnapshot? myCompletedDoc;

      for (final doc in docsById.values) {
        final data = doc.data() as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';
        if (status == 'rejected') continue; // doesn't block re-adoption

        final personal = (data['personal'] as Map?) ?? {};
        final adopterId = personal['adopterId'] as String?;

        if (adopterId == uid) {
          if (status == 'completed' ||
              status == 'return_requested' ||
              status == 'return_approved') {
            myCompletedDoc = doc;
          } else {
            myActiveDoc = doc;
          }
        } else {
          blockingDoc = doc;
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

      if (blockingDoc != null) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.background,
            title: Text('Not Available',
                style: GoogleFonts.tiltWarp(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            content: Text(
              '${animal.name} already has an ongoing or completed adoption and isn\'t available right now.',
              style: GoogleFonts.zain(color: AppColors.textPrimary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('OK',
                    style: GoogleFonts.zain(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
            ],
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdoptionProcess(
            animal: animal,
            existingAdoptionId: myActiveDoc?.id,
          ),
        ),
      );
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
          // Animal photo gallery — swipeable when there's more than one
          // image, same paw placeholder as before when there are none.
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
                      // Reflects the animal's actual sex, hidden entirely
                      // (not defaulted to Male) when Unknown/unset — same
                      // genderIconFor rule the shared AnimalRecordCard and
                      // the admin detail header use.
                      if (genderIconFor(animal.sex) != null) ...[
                        const SizedBox(width: 8),
                        Icon(genderIconFor(animal.sex), size: 22, color: AppColors.textPrimary),
                      ],
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Animal Information — gender lives next to the name
                  // above (icon only); it's deliberately not repeated here.
                  // Species/Age/Size, Breed/Coat Length/Color-Markings — the
                  // same six-field structure and order as the admin Profile
                  // tab (animal_profile_tab.dart).
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

                  // Health
                  _SectionHeader(label: 'Health'),
                  const SizedBox(height: 6),
                  Text(
                    detail.health.join(', '),
                    style: GoogleFonts.zain(
                        fontSize: 15, color: AppColors.textPrimary),
                  ),

                  const SizedBox(height: 20),

                  // Temperament / Compatibility / Training / Rescue
                  // Background — same categorization + data mapping as the
                  // admin Profile tab (animal_profile_tab.dart), which
                  // partitions the same flat keyCharacteristics array via
                  // the shared kTemperamentValues/kCompatibilityValues/
                  // kTrainingValues lists (animal_characteristics.dart).
                  // Presentation (chip size/padding, spacing) stays this
                  // page's own _YellowTag/_SectionHeader, unchanged — only
                  // the grouping logic is reused, not the admin's styling.
                  // Empty categories are skipped rather than shown blank.
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

                  // Description
                  _SectionHeader(label: 'Description'),
                  const SizedBox(height: 6),
                  Text(
                    detail.description,
                    style: GoogleFonts.zain(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                        height: 1.5),
                  ),

                  const SizedBox(height: 20),

                  // Organization Info
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: const Icon(Icons.groups_2_outlined,
                            size: 22, color: AppColors.textPrimary),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.organization,
                            style: GoogleFonts.tiltWarp(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            detail.orgSubtitle,
                            style: GoogleFonts.zain(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  _SponsorsRow(animalId: animal.id),

                  const SizedBox(height: 28),

                  // Adopt Me / View Status — one button, not two: both used
                  // to lead to the exact same place (AdoptionProcess /
                  // PostAdoptionMonitoringPage), so a user who'd already
                  // applied saw a redundant "Adopt Me" sitting right above
                  // "View Status". The label now reflects which action is
                  // actually about to happen.
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

    // Prefers the real animalRecordId join key (reliable for every
    // application submitted after it was added); previously compared the
    // raw int animal.id against the stored string field, which never
    // matched anything. Falls back to the corrected legacy string compare
    // only if this Animal has no animalRecordId at all.
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
        // No open/completed application after all (e.g. every match was
        // rejected/withdrawn) — back to a normal Adopt Me.
        if (targetDoc == null) return _button(label: checking ? 'Checking...' : 'Adopt Me', onTap: checking ? null : onAdoptTap);
        final isCompleted = completedDoc != null;

        // Both used to lead to the exact same place as Adopt Me itself
        // (_handleAdoptTap resolves this same target) — the label now says
        // what actually happens instead of implying a fresh application.
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
        final label = count == 1 ? '1 sponsor' : '$count sponsors';

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