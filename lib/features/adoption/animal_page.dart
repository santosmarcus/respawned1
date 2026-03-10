import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/home/home_screen.dart';
import '../../app_theme.dart';
import 'adoption_page.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';

// Extended detail data
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

const Map<String, _AnimalDetail> _detailMap = {
  'Brownie': _AnimalDetail(
    dateOfBirth: 'January 1, 2024',
    size: 'Medium',
    coatLength: 'Short',
    health: ['Vaccinated', 'Spayed', 'Neutered', 'Dewormed'],
    keyCharacteristics: [
      'Good with children',
      'Knows commands',
      'First-Time Owner Friendly',
      'Low maintenance',
    ],
    rescueBackground: ['Rescued from street'],
    description:
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation.',
    organization: 'Loved by the Gapz',
    orgSubtitle: 'Rescued by this organization since 2024',
  ),
  'Minnie': _AnimalDetail(
    dateOfBirth: 'March 5, 2022',
    size: 'Small',
    coatLength: 'Medium',
    health: ['Vaccinated'],
    keyCharacteristics: ['Good with other pets', 'Calm', 'Indoor-friendly'],
    rescueBackground: ['Rescued from street'],
    description: 'Playful white dog who loves cuddles and short walks.',
    organization: 'Loved by the Gapz',
    orgSubtitle: 'Rescued by this organization since 2022',
  ),
  'Whiskers': _AnimalDetail(
    dateOfBirth: 'June 10, 2023',
    size: 'Small',
    coatLength: 'Short',
    health: ['Vaccinated', 'Dewormed'],
    keyCharacteristics: ['Curious', 'Playful', 'Indoor-friendly'],
    rescueBackground: ['Rescued from street'],
    description: 'Curious orange cat who enjoys exploring and window-watching.',
    organization: 'Loved by the Gapz',
    orgSubtitle: 'Rescued by this organization since 2023',
  ),
  'Luna': _AnimalDetail(
    dateOfBirth: 'September 20, 2024',
    size: 'Small',
    coatLength: 'Short',
    health: ['Vaccinated'],
    keyCharacteristics: ['Good with children', 'Gentle', 'Quiet'],
    rescueBackground: ['Rescued from street'],
    description: 'Gentle black cat with a calm temperament, perfect for families.',
    organization: 'Loved by the Gapz',
    orgSubtitle: 'Rescued by this organization since 2024',
  ),
};

// Animal page
class AnimalPage extends StatefulWidget {
  final Animal animal;

  const AnimalPage({super.key, required this.animal});

  @override
  State<AnimalPage> createState() => _AnimalPageState();
}

class _AnimalPageState extends State<AnimalPage> {
  late bool _favorited;

  _AnimalDetail get _detail =>
      _detailMap[widget.animal.name] ??
          _AnimalDetail(
            dateOfBirth: 'Unknown',
            size: 'Medium',
            coatLength: 'Short',
            health: widget.animal.healthTags,
            keyCharacteristics:
            widget.animal.badge != null ? [widget.animal.badge!] : [],
            rescueBackground: ['Rescued from street'],
            description: widget.animal.description,
            organization: 'ResPAWnd Partner',
            orgSubtitle: 'Verified rescue organization',
          );

  @override
  void initState() {
    super.initState();
    _favorited = widget.animal.favorited;
  }

  @override
  Widget build(BuildContext context) {
    final animal = widget.animal;
    final detail = _detail;

    return Scaffold(
      backgroundColor: AppColors.background,
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
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
                  (route) => false,
            );
          }
        },
      ),
      body: Column(
        children: [
          // photo of animal
          Stack(
            children: [
              Container(
                height: 260,
                width: double.infinity,
                color: animal.cardColor,
                child: const Center(
                  child: Icon(Icons.pets, size: 80, color: AppColors.textSecondary),
                ),
              ),

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
                  onTap: () => setState(() => _favorited = !_favorited),
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

                  // Animal Information
                  _SectionHeader(label: 'Animal Information'),
                  const SizedBox(height: 10),
                  _InfoGrid(rows: [
                    _InfoRow(
                      left: _InfoCell(label: 'Breed', value: animal.breed),
                      center: _InfoCell(label: 'Age', value: animal.age),
                      right: _InfoCell(
                          label: 'Date of Birth', value: detail.dateOfBirth),
                    ),
                    _InfoRow(
                      left: _InfoCell(
                          label: 'Gender',
                          value: animal.gender == AnimalGender.male
                              ? 'Male'
                              : 'Female'),
                      center: _InfoCell(label: 'Size', value: detail.size),
                      right: _InfoCell(
                          label: 'Coat Length', value: detail.coatLength),
                    ),
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

                  const SizedBox(height: 28),

                  // Adopt me button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                AdoptionProcess(animal: animal),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        'Adopt Me',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
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

class _InfoCell {
  final String label;
  final String value;
  const _InfoCell({required this.label, required this.value});
}

class _InfoRow {
  final _InfoCell left;
  final _InfoCell center;
  final _InfoCell right;
  const _InfoRow({required this.left, required this.center, required this.right});
}

class _InfoGrid extends StatelessWidget {
  final List<_InfoRow> rows;
  const _InfoGrid({required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: rows.map((row) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Expanded(child: _InfoCellWidget(cell: row.left)),
              Expanded(child: _InfoCellWidget(cell: row.center)),
              Expanded(child: _InfoCellWidget(cell: row.right)),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _InfoCellWidget extends StatelessWidget {
  final _InfoCell cell;
  const _InfoCellWidget({required this.cell});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cell.label,
          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        ),
        Text(
          cell.value,
          style: GoogleFonts.zain(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
      ],
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