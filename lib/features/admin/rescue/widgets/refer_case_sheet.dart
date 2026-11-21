import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/share_referral_sheet.dart';

/// Refer Case selection modal — the entry point for the Refer action.
///
/// Refer: a shared link anyone outside the app can open and take
/// (showShareReferralSheet). Rescue Volunteer is listed but not available
/// yet. Returns true if a referral was actually created.
Future<bool> showReferCaseSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required RescueCaseRepository caseRepository,
  required OrganizationDirectoryRepository organizationDirectory,
  required String actorUid,
  required String actorName,
}) async {
  final type = await showModalBottomSheet<ReferralType>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Refer Case',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          _TypeOption(
            icon: Icons.ios_share,
            label: 'Refer',
            subtitle: 'Share a link; whoever takes it fills in their contact',
            onTap: () => Navigator.pop(context, ReferralType.localGovernmentUnit),
          ),
          _TypeOption(
            icon: Icons.volunteer_activism_outlined,
            label: ReferralType.rescueVolunteer.label,
            subtitle: 'Not available yet',
            enabled: false,
          ),
        ],
      ),
    ),
  );

  if (type == null || !context.mounted) return false;
  return showShareReferralSheet(
    context,
    rescueCase: rescueCase,
    caseRepository: caseRepository,
    actorUid: actorUid,
    actorName: actorName,
  );
}

class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool enabled;
  final VoidCallback? onTap;
  const _TypeOption({required this.icon, required this.label, this.subtitle, this.enabled = true, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: enabled,
      leading: Icon(icon, color: color),
      title: Text(label, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary.withValues(alpha: enabled ? 1 : 0.6))),
      trailing: enabled ? const Icon(Icons.chevron_right, color: AppColors.textSecondary) : null,
      onTap: enabled ? onTap : null,
    );
  }
}
