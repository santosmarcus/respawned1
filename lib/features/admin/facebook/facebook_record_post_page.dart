import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/facebook_integration.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/facebook_integration_repository.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/facebook/record_post_text.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/donation/models.dart';

/// Most characters a post may have (functions/facebook_share_rules.js
/// MAX_MESSAGE_LENGTH).
const int kMaxFacebookPostLength = 5000;

/// Opens the Facebook composer for a donation or sponsorship campaign.
Future<bool> openCampaignFacebookShare(BuildContext context, DonationListing campaign) async {
  final shared = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => FacebookRecordPostPage(
        kind: FacebookRecordKind.campaign,
        recordId: campaign.id,
        recordOrganizationId: campaign.organizationId,
        heading: campaign.title,
        imageUrl: campaign.imageUrl,
        suggestedText: composeCampaignPost(campaign),
      ),
    ),
  );
  return shared == true;
}

/// Opens the Facebook composer for a volunteer event.
Future<bool> openEventFacebookShare(BuildContext context, VolunteerEvent event) async {
  final shared = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (_) => FacebookRecordPostPage(
        kind: FacebookRecordKind.event,
        recordId: event.id,
        recordOrganizationId: event.organizationId,
        heading: event.title,
        imageUrl: event.imageUrl,
        suggestedText: composeEventPost(event),
      ),
    ),
  );
  return shared == true;
}

/// Compose a Facebook post for one campaign or volunteer event: edit the
/// suggested text, choose whether to attach the cover photo, then post it to
/// the organization's connected Page (functions/facebook.js
/// facebookPublishRecordPost) or hand it to any app through the share sheet.
class FacebookRecordPostPage extends ConsumerStatefulWidget {
  const FacebookRecordPostPage({
    super.key,
    required this.kind,
    required this.recordId,
    required this.recordOrganizationId,
    required this.heading,
    required this.imageUrl,
    required this.suggestedText,
  });

  final FacebookRecordKind kind;
  final String recordId;

  /// The organization that owns the record; null for records saved before
  /// campaigns were tied to an organization (the backend refuses those).
  final String? recordOrganizationId;
  final String heading;
  final String? imageUrl;
  final String suggestedText;

  @override
  ConsumerState<FacebookRecordPostPage> createState() => _FacebookRecordPostPageState();
}

class _FacebookRecordPostPageState extends ConsumerState<FacebookRecordPostPage> {
  late final _textController = TextEditingController(text: widget.suggestedText);
  late bool _withPhoto = _hasPhoto;
  bool _busy = false;

  bool get _hasPhoto => (widget.imageUrl ?? '').startsWith('https://');
  String get _kindLabel => widget.kind == FacebookRecordKind.campaign ? 'campaign' : 'event';

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  String? _textProblem() {
    final text = _textController.text.trim();
    if (text.isEmpty) return 'Write the post text first.';
    if (text.length > kMaxFacebookPostLength) return 'The post text must be under $kMaxFacebookPostLength characters.';
    return null;
  }

  Future<void> _postToPage(String organizationId, FacebookIntegration page) async {
    final problem = _textProblem();
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(problem, kind: AppMessageKind.error));
      return;
    }
    final attach = _withPhoto && _hasPhoto;
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Post to ${page.pageName}?',
      message:
          'This posts the $_kindLabel publicly on the Facebook Page as ${page.pageName}'
          '${attach ? ' with its cover photo' : ''}.',
      confirmLabel: 'Post',
    );
    if (!confirmed || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(facebookIntegrationRepositoryProvider)
          .publishRecordPost(
            organizationId: organizationId,
            kind: widget.kind,
            recordId: widget.recordId,
            message: _textController.text.trim(),
            includePhoto: attach,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        appSnackBar(
          'Posted to ${page.pageName}.',
          kind: AppMessageKind.success,
          action: SnackBarAction(
            label: 'View',
            textColor: Colors.white,
            onPressed: () {
              final uri = Uri.tryParse(result.postUrl);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ),
      );
    } on FacebookOperationException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(appSnackBar('Could not post to Facebook. Please try again.', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hands the text to the phone's share sheet (Facebook, Messenger, ...).
  /// Facebook drops text other apps pre-fill, so it's also copied for
  /// pasting.
  Future<void> _shareElsewhere() async {
    final problem = _textProblem();
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(problem, kind: AppMessageKind.error));
      return;
    }
    final text = _textController.text.trim();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(appSnackBar('Post text copied. Paste it in if Facebook leaves the post empty.'));
    final result = await SharePlus.instance.share(ShareParams(text: text, subject: widget.heading));
    if (mounted && result.status == ShareResultStatus.success) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final currentOrgId = ref.watch(currentOrganizationIdProvider).asData?.value;
    final orgId = widget.recordOrganizationId?.isNotEmpty == true ? widget.recordOrganizationId : null;
    final canPublish = ref.watch(currentOrganizationCapabilitiesProvider).asData?.value.canPublishToFacebook ?? false;
    final page = orgId == null ? null : ref.watch(organizationFacebookIntegrationProvider(orgId)).asData?.value;
    final pageConnected = page?.isConnected ?? false;

    final String? postBlockedReason = orgId == null
        ? 'This $_kindLabel is not linked to an organization, so it can only be shared through the share sheet.'
        : currentOrgId != null && currentOrgId != orgId
        ? 'This $_kindLabel belongs to another organization.'
        : !pageConnected
        ? 'No Facebook Page is connected. An Organization Admin can connect one in Organization Profile.'
        : !canPublish
        ? 'Ask an Organization Admin to allow you to post to the Facebook Page.'
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
          widget.kind == FacebookRecordKind.campaign ? 'Share campaign' : 'Share event',
          style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Text(widget.heading, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            _sectionTitle('Photo'),
            if (_hasPhoto) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Opacity(
                  opacity: _withPhoto ? 1 : 0.4,
                  child: Image.network(
                    widget.imageUrl!,
                    height: 170,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 170,
                      color: AppColors.tearspwn,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary),
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _withPhoto,
                activeThumbColor: AppColors.greenrspwn,
                onChanged: (v) => setState(() => _withPhoto = v),
                title: Text('Attach the cover photo', style: _body),
                subtitle: Text('Posts go out as a photo post with the text below as its caption.', style: _hint),
              ),
            ] else
              Text('This $_kindLabel has no cover photo, so it posts as text only.', style: _hint),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _sectionTitle('Post text')),
                TextButton.icon(
                  onPressed: () => setState(() => _textController.text = widget.suggestedText),
                  icon: const Icon(Icons.restart_alt, size: 18, color: AppColors.textPrimary),
                  label: Text('Reset', style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                ),
              ],
            ),
            TextField(
              controller: _textController,
              minLines: 8,
              maxLines: 18,
              maxLength: kMaxFacebookPostLength,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: GoogleFonts.zain(fontSize: 15, height: 1.3, color: AppColors.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Text('People can find the $_kindLabel in the ResPAWnd app. Edit anything before posting.', style: _hint),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (postBlockedReason != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(postBlockedReason, style: _hint, textAlign: TextAlign.center),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _shareElsewhere,
                      icon: const Icon(Icons.ios_share, size: 18),
                      label: const Text('Share…'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _busy || postBlockedReason != null || orgId == null || page == null
                          ? null
                          : () => _postToPage(orgId, page),
                      icon: _busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.facebook, size: 20),
                      label: Text(
                        pageConnected ? 'Post to ${page!.pageName}' : 'Post to Page',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: AppButtons.primary.copyWith(minimumSize: const WidgetStatePropertyAll(Size(0, 48))),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text(text, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
  );

  TextStyle get _hint => GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary);
  TextStyle get _body => GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary);
}
