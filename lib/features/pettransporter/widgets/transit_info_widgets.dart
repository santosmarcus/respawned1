// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

// Online badge
class TransitOnlineBadge extends StatelessWidget {
  const TransitOnlineBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.circle, size: 10, color: Colors.green),
          const SizedBox(width: 6),
          Text(
            'Online',
            style: GoogleFonts.zain(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

// Address card
class TransitAddressCard extends StatelessWidget {
  final String pickup;
  final String dropoff;
  const TransitAddressCard({
    super.key,
    required this.pickup,
    required this.dropoff,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.circle_outlined,
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pickup,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: SizedBox(
                      height: 14,
                      child: VerticalDivider(
                        color: AppColors.slaterspwn,
                        thickness: 1.5,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on,
                        size: 13,
                        color: AppColors.textPrimary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          dropoff,
                          style: GoogleFonts.zain(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
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

// Contact row — name/label with a tappable call button
class TransitContactRow extends StatelessWidget {
  final String name;
  final VoidCallback onCall;
  const TransitContactRow({
    super.key,
    required this.name,
    required this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.tiltWarp(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: onCall,
              child: const Icon(
                Icons.call,
                size: 20,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ClinicHistoryNote extends StatelessWidget {
  final Future<Map<String, dynamic>?> future;
  const ClinicHistoryNote({super.key, required this.future});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final tally = Map<String, dynamic>.from(
          profile?['declineReasonTally'] ?? {},
        );
        if (tally.isEmpty) return const SizedBox.shrink();

        final topReasons = tally.entries.toList()
          ..sort(
            (a, b) =>
                ((b.value as num?) ?? 0).compareTo((a.value as num?) ?? 0),
          );
        final summary = topReasons
            .take(2)
            .map((e) => '${e.key} (${e.value}x)')
            .join(', ');

        return Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.history, size: 14, color: Colors.orange),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Previously declined treatment here: $summary',
                  style: GoogleFonts.zain(
                    fontSize: 11.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The tappable Reporter/Witness and Organization contact rows. Returned as
/// a list so callers can spread them into their own Column, as before.
List<Widget> buildTransitContactRows(
  Map<String, dynamic> data, {
  required void Function(String? phone) onCall,
}) {
  final reporterName = (data['reporterName'] as String?)?.trim() ?? '';
  final witnessName = (data['witnessName'] as String?)?.trim() ?? '';
  final reporterPhone = (data['reporterPhone'] as String?)?.trim() ?? '';
  final witnessPhone = (data['witnessPhone'] as String?)?.trim() ?? '';

  final contactName = reporterName.isNotEmpty
      ? reporterName
      : (witnessName.isNotEmpty ? witnessName : 'Reporter/Witness Name');
  final contactPhone = reporterPhone.isNotEmpty ? reporterPhone : witnessPhone;

  final organizationName = (data['organizationName'] as String?)?.trim() ?? '';
  final organizationPhone =
      (data['organizationPhone'] as String?)?.trim() ?? '';

  return [
    TransitContactRow(name: contactName, onCall: () => onCall(contactPhone)),
    TransitContactRow(
      name: organizationName.isNotEmpty
          ? organizationName
          : 'Loved by the Gapz',
      onCall: () => onCall(organizationPhone),
    ),
  ];
}
