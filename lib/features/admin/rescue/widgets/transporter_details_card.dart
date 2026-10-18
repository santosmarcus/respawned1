import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Shared transporter-details card shown on Track Case, in both ongoing
/// rescue tracking and intake clinic-to-shelter tracking, directly below
/// the map/route — matching the card styling already used on the Assign
/// Transporter screen rather than inventing a new look. Only ever rendered
/// once an assignment has actually been accepted (never during the
/// pending-response modal) — callers are responsible for that gating, this
/// widget assumes [assignment] is accepted or completed.
///
/// Listens to the live accepted assignment (via [transporterProfileProvider],
/// keyed off `assignment.riderId`) rather than only the constructor data —
/// so if the case is reassigned to a different transporter, the caller
/// passing a fresh `assignment` on rebuild is what refreshes this card; it
/// never caches a stale transporter across rebuilds itself.
class TransporterDetailsCard extends ConsumerWidget {
  final TransportAssignment assignment;
  final double? distanceKm;
  final Duration? etaDuration;

  const TransporterDetailsCard({
    super.key,
    required this.assignment,
    this.distanceKm,
    this.etaDuration,
  });

  // Reuses the exact tel: launch pattern already established in
  // transit_progress_page.dart's own _launchCall — not a second approach.
  Future<void> _launchCall(BuildContext context, String? phone) async {
    final number = phone?.trim();
    if (number == null || number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No phone number available.')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(transporterProfileProvider((
      uid: assignment.riderId,
      fallbackName: assignment.riderName,
      type: assignment.riderType,
      isDemo: assignment.isDemo,
    )));

    final profile = profileAsync.asData?.value ??
        TransporterProfile(
          uid: assignment.riderId,
          name: assignment.riderName,
          type: assignment.riderType,
          vehicle: 'Not provided',
          plate: 'Not provided',
          isDemo: assignment.isDemo,
        );

    // Exactly one chip — Busy while the assignment is active, Completed
    // once transport for this leg is done. Never a "Selected" chip and
    // never doubled up with a separate availability indicator.
    final isCompleted = assignment.status == TransportAssignmentStatus.completed;
    final chipLabel = isCompleted ? 'Completed' : 'Busy';
    final chipColor = isCompleted ? AppColors.slaterspwn : AppColors.yellowrspwn;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transporter',
              style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Avatar(photoUrl: profile.photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.zain(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: chipColor, borderRadius: BorderRadius.circular(20)),
                          child: Text(chipLabel,
                              style: GoogleFonts.zain(
                                  fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                    Text(profile.type, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(
                      '${profile.plate} · ${profile.vehicle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (distanceKm != null)
                      Text(
                        '${distanceKm!.toStringAsFixed(1)} km away'
                        '${etaDuration != null ? ' · ${_formatEta(etaDuration!)} ETA' : ''}',
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Message removed — redundant with the shared case-level Messages
          // thread on this same Track Case page (the "Tracking Detail" tab);
          // only Call stays on the card itself.
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: (profile.phone == null || profile.phone!.isEmpty)
                  ? 'No phone number on file'
                  : 'Call ${profile.name}',
              child: OutlinedButton.icon(
                onPressed: (profile.phone == null || profile.phone!.isEmpty)
                    ? null
                    : () => _launchCall(context, profile.phone),
                icon: const Icon(Icons.phone_outlined, size: 16),
                label: Text('Call', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  disabledForegroundColor: AppColors.textSecondary,
                  side: BorderSide(
                      color: (profile.phone == null || profile.phone!.isEmpty)
                          ? AppColors.slaterspwn
                          : AppColors.textPrimary),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatEta(Duration d) {
    if (d.inMinutes < 1) return '<1 min';
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inMinutes ~/ 60;
    final m = d.inMinutes % 60;
    return '${h}h ${m}min';
  }
}

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  const _Avatar({required this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          photoUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.directions_car, color: AppColors.textSecondary),
      );
}
