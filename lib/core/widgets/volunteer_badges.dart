import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_stats.dart';

/// A volunteer's badges and the progress to the next one, live from
/// `users/{uid}.volunteerStats`. Shows [fallback] while there are no stats
/// yet (never attended, or not backfilled).
class VolunteerBadgesCard extends StatelessWidget {
  const VolunteerBadgesCard({super.key, required this.uid, this.fallback = const SizedBox.shrink()});

  final String uid;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        final stats = VolunteerStats.fromUserData(snap.data?.data());
        if (stats == null || stats.attendedCount == 0) return fallback;
        final next = stats.nextEventBadge;
        final toGo = stats.eventsToNextBadge;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You attended ${stats.attendedCount} event${stats.attendedCount == 1 ? '' : 's'}. Thank you for helping!',
                style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [for (final b in stats.badges) VolunteerBadgeChip(badge: b)],
              ),
              if (next != null) ...[
                const SizedBox(height: 10),
                Text(
                  '$toGo more event${toGo == 1 ? '' : 's'} to ${next.label}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One badge: icon and name; long-press or hover shows what it is for.
class VolunteerBadgeChip extends StatelessWidget {
  const VolunteerBadgeChip({super.key, required this.badge, this.compact = false});

  final VolunteerBadge badge;

  /// Icon only, for list rows.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '${badge.label}: ${badge.description}',
      child: Container(
        padding: compact ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(badge.icon, size: compact ? 14 : 16, color: AppColors.textPrimary),
            if (!compact) ...[
              const SizedBox(width: 5),
              Text(badge.label,
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}
