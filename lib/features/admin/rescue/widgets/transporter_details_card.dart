import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/models/rescue/transporter_profile.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/rescue/widgets/case_page_kit.dart';
import 'package:respawnd1/features/admin/widgets/view_only.dart';

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

  /// Opens the transport's live tracking; shown as a button under Call.
  final VoidCallback? onTrack;

  /// Actions behind the card's "more" button (Reassign Transporter, ...).
  /// Hidden for Staff who can only view rescue cases.
  final List<CaseAction> menuActions;

  const TransporterDetailsCard({
    super.key,
    required this.assignment,
    this.distanceKm,
    this.etaDuration,
    this.onTrack,
    this.menuActions = const [],
  });

  // Reuses the exact tel: launch pattern already established in
  // transit_progress_page.dart's own _launchCall — not a second approach.
  Future<void> _launchCall(BuildContext context, String? phone) async {
    final number = phone?.trim();
    if (number == null || number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('No phone number available.'),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Could not start the call.'),
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
    // This chip is the assignment's status (on this trip / trip done), not
    // the transporter's general availability.
    final chipLabel = isCompleted ? 'Trip completed' : 'On this trip';
    final chipColor = isCompleted ? AppColors.slaterspwn : AppColors.yellowrspwn;

    // Full width of its parent, like the other case cards: callers pad it
    // the same way as their neighbours.
    final canEdit = ref.watch(canEditProvider(OrgPermission.rescue));
    final menu = canEdit ? menuActions : const <CaseAction>[];
    final buttonStyle = OutlinedButton.styleFrom(
      foregroundColor: AppColors.textPrimary,
      disabledForegroundColor: AppColors.textSecondary,
      side: const BorderSide(color: AppColors.textPrimary),
      padding: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Assigned transporter',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
              if (menu.isNotEmpty)
                SizedBox(
                  height: 28,
                  width: 32,
                  child: PopupMenuButton<int>(
                    tooltip: 'Transporter actions',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz, size: 20, color: AppColors.textPrimary),
                    onSelected: (i) => menu[i].onPressed?.call(),
                    itemBuilder: (_) => [
                      for (var i = 0; i < menu.length; i++)
                        PopupMenuItem<int>(
                          value: i,
                          enabled: menu[i].onPressed != null,
                          child: Row(
                            children: [
                              if (menu[i].icon != null) ...[
                                Icon(menu[i].icon, size: 18,
                                    color: menu[i].destructive ? AppColors.error : AppColors.textPrimary),
                                const SizedBox(width: 10),
                              ],
                              Text(menu[i].label,
                                  style: GoogleFonts.zain(
                                      fontSize: 14,
                                      color: menu[i].destructive ? AppColors.error : AppColors.textPrimary)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
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
                    // Leave out "Not provided" parts rather than showing them.
                    if (_vehicleLine(profile).isNotEmpty)
                      Text(
                        _vehicleLine(profile),
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
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: (profile.phone == null || profile.phone!.isEmpty) ? 'No phone number on file' : 'Call ${profile.name}',
                  child: OutlinedButton.icon(
                    onPressed: (profile.phone == null || profile.phone!.isEmpty) ? null : () => _launchCall(context, profile.phone),
                    icon: const Icon(Icons.phone_outlined, size: 16),
                    label: Text((profile.phone == null || profile.phone!.isEmpty) ? 'No phone' : 'Call',
                        style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: buttonStyle.copyWith(
                      side: WidgetStatePropertyAll(BorderSide(
                          color: (profile.phone == null || profile.phone!.isEmpty) ? AppColors.slaterspwn : AppColors.textPrimary)),
                    ),
                  ),
                ),
              ),
              if (onTrack != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onTrack,
                    icon: const Icon(Icons.map_outlined, size: 16),
                    label: Text('Track', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: buttonStyle,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _vehicleLine(TransporterProfile p) => [p.plate, p.vehicle]
      .where((v) => v.trim().isNotEmpty && v != 'Not provided')
      .join(' · ');

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
          width: 56,
          height: 56,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() => Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.directions_car, color: AppColors.textSecondary),
      );
}
