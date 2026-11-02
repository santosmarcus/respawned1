import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// Accept Case modal. Accepting always means "handled by our organization"
/// by default — that's not a choice the admin has to make. "Open for
/// transfer to another organization" is an optional flag they can switch on
/// before confirming. Returns the resulting `openForTransfer` value, or
/// null if dismissed without confirming.
///
/// This only captures the flag today — there is no open-transfer listing,
/// cross-org browsing, or transfer-request workflow yet. See
/// RescueCase.openForTransfer / RescueCaseRepository.acceptCase.
Future<bool?> showAcceptCaseSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AcceptCaseSheetBody(),
  );
}

class _AcceptCaseSheetBody extends StatefulWidget {
  const _AcceptCaseSheetBody();

  @override
  State<_AcceptCaseSheetBody> createState() => _AcceptCaseSheetBodyState();
}

class _AcceptCaseSheetBodyState extends State<_AcceptCaseSheetBody> {
  bool _openForTransfer = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
          Text('Accept Case',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('This case will be handled by our organization.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.slaterspwn),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Open for transfer to another organization',
                          style: GoogleFonts.zain(
                              fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text(
                        'Optional. Flags this case as available for another org to take on. '
                        'No transfer listing or matching yet — this only saves the flag for now.',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Switch(
                  value: _openForTransfer,
                  activeThumbColor: AppColors.textPrimary,
                  onChanged: (v) => setState(() => _openForTransfer = v),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, _openForTransfer),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text('Accept Case',
                  style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}
