import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/models/rescue/rescue_status.dart';

/// Small rounded chip showing a [RescueStatus]. Reused on the rescue list,
/// detail page, and referral/merge history sections.
class RescueStatusChip extends StatelessWidget {
  final RescueStatus status;
  const RescueStatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: status.color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: GoogleFonts.zain(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Small rounded chip showing urgency ('Critical' / 'Medium' / 'Low').
/// Accepts the raw string still used throughout the data model so existing
/// call sites don't need to construct a [UrgencyLevel] just to render this.
class UrgencyChip extends StatelessWidget {
  final String? urgency;
  const UrgencyChip({super.key, required this.urgency});

  @override
  Widget build(BuildContext context) {
    final level = UrgencyLevel.fromFirestoreValue(urgency);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: level?.color ?? const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        (urgency == null || urgency!.isEmpty) ? 'Unrated' : urgency!,
        style: GoogleFonts.zain(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
