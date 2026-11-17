import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/features/admin/rescue/widgets/referral_share_flow.dart';
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
        ReferralStatus.expired => 'No answer (returned)',
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

  Widget _referralRow(BuildContext context, Referral r) {
    final small = GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary);
    final share = r.share;
    final linkOpen = share != null && share.isOpen(DateTime.now());
    // Volunteer referrals are a stub with no one to send a link to.
    final shareable = r.type != ReferralType.rescueVolunteer;
    final answer = r.lastResponse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
              children: [
                TextSpan(
                  text: 'Referred to ${_targetLabel(r)}',
                  style: const TextStyle(decoration: TextDecoration.underline, fontWeight: FontWeight.w600),
                ),
                TextSpan(text: '  ${_dateLabel(r.createdAt)} · ${_statusLabel(r.status)}', style: small),
                if (r.declineReason != null && r.declineReason!.isNotEmpty)
                  TextSpan(text: '\nReason: ${r.declineReason}', style: small),
              ],
            ),
          ),
          if (answer != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                [
                  'Answer from ${answer.name}: ${answer.label}',
                  if (answer.note != null && answer.note!.isNotEmpty) answer.note!,
                  if (answer.contact != null && answer.contact!.isNotEmpty) 'Contact: ${answer.contact}',
                ].join('\n'),
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              ),
            ),
          if (shareable)
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                if (linkOpen && share.expiresAt != null)
                  Text('Link open until ${_dateLabel(share.expiresAt)}', style: small),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  icon: const Icon(Icons.share_outlined, size: 16),
                  label: Text(linkOpen ? 'Share again' : 'Share link', style: GoogleFonts.zain(fontSize: 13)),
                  onPressed: () => shareReferralLink(
                    context,
                    caseId: caseId,
                    referralId: r.id,
                    recipientLabel: _targetLabel(r),
                    currentIncludeReporter: share?.includeReporter ?? false,
                  ),
                ),
                if (linkOpen)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: AppColors.error,
                    ),
                    onPressed: () => stopSharingReferral(context, caseId: caseId, referralId: r.id),
                    child: Text('Stop sharing', style: GoogleFonts.zain(fontSize: 13)),
                  ),
              ],
            ),
        ],
      ),
    );
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
            children: [for (final r in referrals) _referralRow(context, r)],
          );
        },
      ),
    );
  }
}
