import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/core/widgets/animal_basic_info_row.dart';
import 'package:respawnd1/core/widgets/animal_image_gallery.dart';
import 'adoption_page.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/post_adoption_page.dart';

// Extended detail data — no longer keyed by a hardcoded per-name map (that
// was fabricated demo data unrelated to any real Animal Record field, e.g.
// a "date of birth" for whichever four names happened to exist in the old
// static catalog). AnimalRecord has no date-of-birth field at all, so this
// honestly shows "Unknown" for every animal instead of inventing one.
class _AnimalDetail {
  final String dateOfBirth;
  final String size;
  final String coatLength;
  final List<String> health;
  final List<String> keyCharacteristics;
  final List<String> rescueBackground;
  final String description;
  final String organization;
  final String orgSubtitle;

  const _AnimalDetail({
    required this.dateOfBirth,
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
      dateOfBirth: 'Unknown',
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
      final snap = await FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalId', isEqualTo: animal.id)
          .get();

      QueryDocumentSnapshot? blockingDoc;
      QueryDocumentSnapshot? myActiveDoc;
      QueryDocumentSnapshot? myCompletedDoc;

      for (final doc in snap.docs) {
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
                      const SizedBox(width: 8),
                      const Icon(Icons.male,
                          size: 22, color: AppColors.textPrimary),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Animal Information — gender lives next to the name
                  // above (icon only); it's deliberately not repeated here.
                  _SectionHeader(label: 'Animal Information'),
                  const SizedBox(height: 10),
                  AnimalBasicInfoRow(fields: [
                    InfoField('Breed', animal.breed.isNotEmpty ? animal.breed : 'Not provided'),
                    InfoField('Age', animal.age.isNotEmpty ? animal.age : 'Not provided'),
                    InfoField('Date of Birth', detail.dateOfBirth),
                    InfoField('Size', detail.size),
                    InfoField('Coat Length', detail.coatLength),
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

                  // Key Characteristics
                  _SectionHeader(label: 'Key Characteristics'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: detail.keyCharacteristics
                        .map((t) => _YellowTag(label: t))
                        .toList(),
                  ),

                  const SizedBox(height: 20),

                  // Rescue background tag
                  _SectionHeader(label: 'Rescue Background'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: detail.rescueBackground
                        .map((t) => _YellowTag(label: t))
                        .toList(),
                  ),

                  const SizedBox(height: 20),

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

                  // Adopt me button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _checkingAdoption
                          ? null
                          : () => _handleAdoptTap(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        _checkingAdoption ? 'Checking...' : 'Adopt Me',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  _ViewStatusButton(animal: animal),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewStatusButton extends StatelessWidget {
  final Animal animal;
  const _ViewStatusButton({required this.animal});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.animalId', isEqualTo: animal.id)
          .where('personal.adopterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
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
        if (targetDoc == null) return const SizedBox.shrink();
        final isCompleted = completedDoc != null;

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => isCompleted
                        ? PostAdoptionMonitoringPage(adoptionId: targetDoc.id)
                        : AdoptionProcess(
                      animal: animal,
                      existingAdoptionId: targetDoc.id,
                    ),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.greenrspwn, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(
                'View Status',
                style: GoogleFonts.tiltWarp(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
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