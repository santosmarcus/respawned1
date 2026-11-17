import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// Web links for referrals (functions/referral_shares.js): a page at
/// `/referral/<token>` that people outside the app (a barangay or LGU office,
/// another rescuer) open without signing in, showing a copy of the report and
/// letting them answer. The link expires after 30 days, and staff can stop
/// sharing it.
class ReferralShareService {
  ReferralShareService({FirebaseFunctions? functions}) : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// The open link for the referral, or a new one. Changing
  /// [includeReporter] replaces the old link.
  Future<String> createLink({
    required String caseId,
    required String referralId,
    required bool includeReporter,
  }) async {
    final result = await _functions.httpsCallable('createReferralShare').call<Object?>({
      'caseId': caseId,
      'referralId': referralId,
      'includeReporter': includeReporter,
    });
    final data = result.data;
    final url = data is Map ? data['url'] as String? : null;
    if (url == null || url.isEmpty) throw StateError('No link was returned.');
    return url;
  }

  Future<void> revoke({required String caseId, required String referralId}) async {
    await _functions.httpsCallable('revokeReferralShare').call<Object?>({
      'caseId': caseId,
      'referralId': referralId,
    });
  }

  static String errorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      return switch (e.code) {
        'permission-denied' || 'not-found' || 'failed-precondition' || 'invalid-argument' =>
          e.message ?? 'This could not be done.',
        'unavailable' || 'deadline-exceeded' => 'No connection. Try again.',
        _ => 'Could not create the link. Try again.',
      };
    }
    return 'Could not create the link. Try again.';
  }
}

/// Asks whether to include the reporter's contact, creates (or reuses) the
/// link and opens the share sheet. [currentIncludeReporter] preselects the
/// choice of an existing link.
Future<void> shareReferralLink(
  BuildContext context, {
  required String caseId,
  required String referralId,
  String? recipientLabel,
  bool currentIncludeReporter = false,
  ReferralShareService? service,
}) async {
  var includeReporter = currentIncludeReporter;
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text('Share referral link', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Anyone with the link can see the report, its photos and location, and send an answer back. '
              'It works without the app and stays open for 30 days unless you stop sharing it.',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: includeReporter,
              activeColor: AppColors.textPrimary,
              onChanged: (v) => setState(() => includeReporter = v ?? false),
              title: Text("Include the reporter's name and phone",
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
              subtitle: Text('Left out anyway if they reported anonymously.',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: AppButtons.primary,
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Share link'),
          ),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final url = await (service ?? ReferralShareService()).createLink(
      caseId: caseId,
      referralId: referralId,
      includeReporter: includeReporter,
    );
    final to = recipientLabel == null || recipientLabel.isEmpty ? '' : ' for $recipientLabel';
    await SharePlus.instance.share(ShareParams(
      subject: 'Rescue referral ${shortCaseId(caseId)}',
      text: 'Rescue referral$to (case ${shortCaseId(caseId)}). See the report and reply here: $url',
    ));
  } catch (e) {
    messenger.showSnackBar(appSnackBar(ReferralShareService.errorMessage(e), kind: AppMessageKind.error));
  }
}

/// Confirms, then closes the referral's link.
Future<void> stopSharingReferral(
  BuildContext context, {
  required String caseId,
  required String referralId,
  ReferralShareService? service,
}) async {
  final ok = await showConfirmActionDialog(
    context,
    title: 'Stop sharing this referral?',
    message: 'The link stops working for everyone who has it. You can share a new link later.',
    confirmLabel: 'Stop sharing',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  try {
    await (service ?? ReferralShareService()).revoke(caseId: caseId, referralId: referralId);
    messenger.showSnackBar(appSnackBar('Link closed.', kind: AppMessageKind.success));
  } catch (e) {
    messenger.showSnackBar(appSnackBar(ReferralShareService.errorMessage(e), kind: AppMessageKind.error));
  }
}
