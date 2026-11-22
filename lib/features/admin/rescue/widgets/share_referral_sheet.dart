import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/repos/rescue_case_repository.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/facebook/facebook_record_post_page.dart';
import 'package:respawnd1/features/admin/rescue/widgets/referral_share_flow.dart';

/// Refer → shared link. The referral (CaseReferralRepository.referByLink)
/// and its web link (functions/referral_shares.js) are made the first time
/// staff share; whoever opens the link fills in their own name and contact
/// to take the case. The sheet stays open so the same link can go out more
/// than one way: the phone's share sheet, and a post on the organization's
/// Facebook Page. Returns true once a referral was created.
Future<bool> showShareReferralSheet(
  BuildContext context, {
  required RescueCase rescueCase,
  required RescueCaseRepository caseRepository,
  required String actorUid,
  required String actorName,
  ReferralShareService? service,
}) async {
  var created = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ShareReferralSheet(
      rescueCase: rescueCase,
      caseRepository: caseRepository,
      actorUid: actorUid,
      actorName: actorName,
      service: service ?? ReferralShareService(),
      onCreated: () => created = true,
    ),
  );
  return created;
}

class _ShareReferralSheet extends StatefulWidget {
  final RescueCase rescueCase;
  final RescueCaseRepository caseRepository;
  final String actorUid;
  final String actorName;
  final ReferralShareService service;
  final VoidCallback onCreated;

  const _ShareReferralSheet({
    required this.rescueCase,
    required this.caseRepository,
    required this.actorUid,
    required this.actorName,
    required this.service,
    required this.onCreated,
  });

  @override
  State<_ShareReferralSheet> createState() => _ShareReferralSheetState();
}

class _ShareReferralSheetState extends State<_ShareReferralSheet> {
  final _note = TextEditingController();
  bool _includeReporter = false;
  bool _busy = false;
  String? _referralId;
  String? _url;
  bool? _urlIncludesReporter;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The referral and a link matching the reporter choice, made on first use.
  Future<String> _ensureLink() async {
    var id = _referralId;
    if (id == null) {
      id = await widget.caseRepository.referByLink(
        caseId: widget.rescueCase.id,
        note: _note.text,
        actorUid: widget.actorUid,
        actorName: widget.actorName,
      );
      _referralId = id;
      widget.onCreated();
    }
    if (_url == null || _urlIncludesReporter != _includeReporter) {
      _url = await widget.service.createLink(
        caseId: widget.rescueCase.id,
        referralId: id,
        includeReporter: _includeReporter,
      );
      _urlIncludesReporter = _includeReporter;
    }
    return _url!;
  }

  Future<void> _run(Future<void> Function(String url) share) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await share(await _ensureLink());
    } on StateError catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(
          _referralId == null
              ? 'Could not refer the case: $e'
              : '${ReferralShareService.errorMessage(e)} The referral is saved; share it again from Referral History.',
          kind: AppMessageKind.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _referralId != null;
    final body = GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text('Refer this case', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                'Anyone with the link sees the report, photos and location without the app, and fills in their '
                "name and contact to take it. The case stays pending in Review until someone says they'll handle "
                'it. The link lasts 30 days.',
                style: body,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                enabled: !created,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                style: body,
                decoration: InputDecoration(
                  labelText: 'Note to whoever takes it (optional)',
                  helperText: created ? 'Saved with the referral.' : null,
                  border: const OutlineInputBorder(),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeReporter,
                activeColor: AppColors.textPrimary,
                onChanged: _busy ? null : (v) => setState(() => _includeReporter = v ?? false),
                title: Text("Include the reporter's name and phone", style: body),
                subtitle: Text('Left out anyway if they reported anonymously.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                style: AppButtons.primary,
                onPressed: _busy
                    ? null
                    : () => _run((url) => shareReferralUrl(caseId: widget.rescueCase.id, url: url)),
                icon: _busy
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.ios_share, size: 18),
                label: Text('Share link…', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: AppButtons.outline,
                onPressed: _busy || _includeReporter
                    ? null
                    : () => _run((url) => openReferralFacebookShare(context, widget.rescueCase, url)),
                icon: const Icon(Icons.facebook, size: 18),
                label: Text('Post to Facebook Page', style: GoogleFonts.zain(fontWeight: FontWeight.w700)),
              ),
              if (_includeReporter)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text("Reporter details can't go on a public post. Untick the box to post.",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(created ? 'Done' : 'Cancel',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
