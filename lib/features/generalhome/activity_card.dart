import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/adoption/adoption_process.dart';
import 'package:respawnd1/features/adoption/adoption_page.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import '../../app_theme.dart';
import 'activity_item.dart';
import 'activity_feed.dart';

class ActivityCard extends StatelessWidget{
  final ActivityItem item;

  const ActivityCard({super.key, required this.item});

  Color get _accentColor => item.type == ActivityType.rescue
      ? AppColors.lavenderrspwn
      : AppColors.greenrspwn;

  IconData get _icon => item.type == ActivityType.rescue
      ? Icons.pets_outlined
      : Icons.favorite_border;

  String get _dateLabel{
    final d = item.createdAt;
    if (d == null) return '-';
    final months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
      'Sep', 'Oct', 'Nov', 'Dec'
    ];

    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${months[d.month]} ${d.day}, ${d.year} $h:$min $ampm';
  }

  /*Future<void> _viewAdoption(BuildContext context) async {
    try {
      final adoptionDoc = await FirebaseFirestore.instance
          .collection('adoptions')
          .doc(item.docId)
          .get();

      final adoptionData = adoptionDoc.data();
      if (adoptionData == null) return;

      final animalId = adoptionData['animalId'] as String?;
      if (animalId == null) return;

      final animalDoc = await FirebaseFirestore.instance
          .collection('animals')
          .doc(animalId)
          .get();

      final animalData = animalDoc.data();
      if (animalData == null) return;

      final animal = Animal(
        id: animalDoc.id,
        name: animalData['name'] as String? ?? '',
        breed: animalData['breed'] as String? ?? '',
        age: animalData['age'] as String? ?? '',
        description: animalData['description'] as String? ?? '',
        imageUrl: animalData['imageUrl'] as String? ?? '',
      );

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => AdoptionProcess(animal: animal)),
        );
      }
    } catch (_) {
      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdoptionPage()),
        );
      }
    }
  }*/

  @override
  Widget build(BuildContext context) {
    return  GestureDetector(
      onTap: () {
        if(item.type == ActivityType.rescue){
          Navigator.push(context,
          MaterialPageRoute(
            builder: (_) => TrackCasePage(caseId: item.docId),
          ),
          );
        }//else if (item.type == ActivityType.adoption){
           // _viewAdoption(context);
        //}
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(color: AppColors.slaterspwn,
            blurRadius: 1,
            offset: const Offset(0, 3),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        Container(
        decoration: BoxDecoration(
        color: _accentColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: 12, vertical: 9),
        child: Row(
            children: [
            Icon(_icon, size: 16, color: AppColors.textPrimary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            item.title,
            style: GoogleFonts.tiltWarp(
                fontSize: 13,
                color: AppColors.textPrimary),
          ),
        ),
      ],
        ),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.access_time,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(_dateLabel,
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textSecondary)),
            ]),

            const SizedBox(height: 6),

            // Address / subtitle
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.textPrimary),
                ),
              ),
            ]),

            // Animal type row (rescue only)
            if (item.type == ActivityType.rescue &&
                item.animalType.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.pets,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(item.animalType,
                    style: GoogleFonts.zain(
                        fontSize: 12,
                        color: AppColors.textPrimary)),
              ]),
            ],

            const SizedBox(height: 8),

            // Status row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    item.status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                if (item.type == ActivityType.rescue)
                  Text(
                    'View details →',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
              ],
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