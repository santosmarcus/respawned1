import 'package:flutter/material.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';

/// An animal that needs continuing care, with a chip per need. Tapping it
/// opens the animal's record. Used by Rescue readiness and Shelter care.
class CareNeedRow extends StatelessWidget {
  final AnimalRecord animal;
  final List<CareNeed> needs;
  const CareNeedRow({super.key, required this.animal, required this.needs});

  @override
  Widget build(BuildContext context) {
    ChipTone toneOf(DashSeverity s) => switch (s) {
      DashSeverity.critical => ChipTone.red,
      DashSeverity.warning => ChipTone.amber,
      _ => ChipTone.info,
    };
    return InkWell(
      onTap: () => openAnimalRecord(context, animal),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            DashThumb(url: animal.photoUrls.isNotEmpty ? animal.photoUrls.first : null, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    animal.name.isNotEmpty ? animal.name : '${animal.species} (unnamed)',
                    style: dashBody(size: 14.5, weight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [for (final n in needs) StatusChip(n.label, tone: toneOf(n.severity), icon: n.icon)],
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
