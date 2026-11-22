import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/referral_type.dart';

/// Required "why are you referring this case" choice on the organization
/// and rescue volunteer referral sheets (analytics: referrals by reason).
class ReferralReasonField extends StatelessWidget {
  const ReferralReasonField({super.key, required this.value, required this.onChanged});

  final OrgReferralReason? value;
  final ValueChanged<OrgReferralReason?> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary);
    return DropdownButtonFormField<OrgReferralReason>(
      initialValue: value,
      isDense: true,
      decoration: InputDecoration(
        hintText: 'Reason for referring (required)',
        hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 13),
        isDense: true,
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5)),
      ),
      items: [
        for (final r in OrgReferralReason.values) DropdownMenuItem(value: r, child: Text(r.label, style: style)),
      ],
      onChanged: onChanged,
    );
  }
}
