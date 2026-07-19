import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/referral.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

/// Referral History section on the rescue detail page — every referral
/// document ever created for this case, newest first.
class ReferralHistorySection extends ConsumerWidget {
  final String caseId;
  const ReferralHistorySection({super.key, required this.caseId});

  String _statusLabel(ReferralStatus status) => switch (status) {
        ReferralStatus.referredPending => 'Pending',
        ReferralStatus.accepted => 'Accepted',
        ReferralStatus.declined => 'Declined',
        ReferralStatus.notified => 'Notified',
      };

  String _targetLabel(Referral r) => switch (r.type) {
        ReferralType.anotherOrganization => r.targetOrgName ?? 'Another organization',
        ReferralType.rescueVolunteer => r.targetVolunteerName ?? 'Rescue volunteer',
        ReferralType.localGovernmentUnit => r.barangay ?? 'LGU/Barangay',
      };

  String _dateLabel(DateTime? d) {
    if (d == null) return '';
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final referralsAsync = ref.watch(caseReferralsProvider(caseId));

    return SectionCard(
      title: 'Referral History',
      child: referralsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (e, _) => Text('Could not load referrals.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        data: (referrals) {
          if (referrals.isEmpty) {
            return Text('No referrals yet.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: referrals
                .map((r) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                          children: [
                            TextSpan(
                              text: 'Referred to ${_targetLabel(r)}',
                              style: const TextStyle(
                                  decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
                            ),
                            TextSpan(
                                text:
                                    '  ${_dateLabel(r.createdAt)} · ${_statusLabel(r.status)}',
                                style: GoogleFonts.zain(
                                    fontSize: 11, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    ))
                .toList(),
          );
        },
      ),
    );
  }
}
