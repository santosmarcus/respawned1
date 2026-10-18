import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/organization_directory_repository.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/features/admin/rescue/widgets/refer_to_lgu_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/refer_to_organization_sheet.dart';
import 'package:respawnd1/features/admin/rescue/widgets/refer_to_volunteer_sheet.dart';

/// Refer Case selection modal — the entry point for the Refer action. Picks
/// a referral type, then opens the matching type-specific modal. Returns
/// true if a referral was actually sent (false for volunteer, which is a
/// UI-only stub for now).
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
            icon: Icons.apartment_outlined,
            label: ReferralType.anotherOrganization.label,
            onTap: () => Navigator.pop(context, ReferralType.anotherOrganization),
          ),
          _TypeOption(
            icon: Icons.volunteer_activism_outlined,
            label: ReferralType.rescueVolunteer.label,
            onTap: () => Navigator.pop(context, ReferralType.rescueVolunteer),
          ),
          _TypeOption(
            icon: Icons.account_balance_outlined,
            label: ReferralType.localGovernmentUnit.label,
            onTap: () => Navigator.pop(context, ReferralType.localGovernmentUnit),
          ),
        ],
      ),
    ),
  );

  if (type == null || !context.mounted) return false;

  switch (type) {
    case ReferralType.anotherOrganization:
      return showReferToOrganizationSheet(
        context,
        rescueCase: rescueCase,
        directory: organizationDirectory,
        caseRepository: caseRepository,
        actorUid: actorUid,
        actorName: actorName,
      );
    case ReferralType.rescueVolunteer:
      await showReferToVolunteerSheet(context);
      return false;
    case ReferralType.localGovernmentUnit:
      return showReferToLguSheet(
        context,
        rescueCase: rescueCase,
        caseRepository: caseRepository,
        actorUid: actorUid,
        actorName: actorName,
      );
  }
}

class _TypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TypeOption({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.textPrimary),
      title: Text(label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
      trailing: const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }
}
