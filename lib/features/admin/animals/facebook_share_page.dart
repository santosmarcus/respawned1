import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/core/models/organization/facebook_integration.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/repos/facebook_integration_repository.dart';
import 'package:respawnd1/core/utils/facebook_post_composer.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/photo_caption_sheet.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Most photos one post carries (functions/facebook_share_rules.js MAX_PHOTOS).
const int kMaxSharePhotos = 20;

/// Most records one post covers (functions/facebook_share_rules.js MAX_RECORDS).
const int kMaxShareRecords = 10;

/// Opens the composer for [animals]. Returns true when something was posted
/// or shared.
Future<bool> openFacebookShare(BuildContext context, List<AnimalRecord> animals) async {
  if (animals.isEmpty) return false;
  if (animals.length > kMaxShareRecords) {
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar('Share up to $kMaxShareRecords records in one post.', kind: AppMessageKind.error),
    );
    return false;
  }
  final shared = await Navigator.push<bool>(
    context,
    MaterialPageRoute(builder: (_) => FacebookSharePage(animals: animals)),
  );
  return shared == true;
}

/// Compose a Facebook post for one or more animal records: pick which
/// details go in the text, which photos to attach (each with its own
/// description), and whether to add the link to each animal's public web
/// page (functions/public_animal_page.js), which has every public detail and
/// an "Open in the app" button. Then post it to the organization's connected
/// Page, or share it through any app (Facebook, Messenger, ...).
class FacebookSharePage extends ConsumerStatefulWidget {
  const FacebookSharePage({super.key, required this.animals});

  final List<AnimalRecord> animals;

  @override
  ConsumerState<FacebookSharePage> createState() => _FacebookSharePageState();
}

class _FacebookSharePageState extends ConsumerState<FacebookSharePage> {
  final Set<ShareField> _fields = {...ShareField.defaults};
  bool _withLinks = true;
  late final _introController = TextEditingController(text: defaultIntro(widget.animals));
  final _closingController = TextEditingController(text: kDefaultClosing);

  /// Attached photos per animal id, in the order they'll appear.
  late final Map<String, List<String>> _selectedPhotos = _initialPhotos();

  /// Description per photo URL for this post, starting from the record's.
  late final Map<String, String> _captions = {
    for (final a in widget.animals) ...a.photoCaptions,
  };
  bool _busy = false;

  Map<String, List<String>> _initialPhotos() {
    // Up to 4 photos each to start, within the post's limit.
    final perAnimal = (kMaxSharePhotos ~/ widget.animals.length).clamp(1, 4);
    return {for (final a in widget.animals) a.id: a.photoUrls.take(perAnimal).toList()};
  }

  int get _photoCount => _selectedPhotos.values.fold(0, (n, l) => n + l.length);

  List<AnimalRecord> get _withoutProfile => widget.animals.where((a) => !hasPublicProfile(a)).toList();

  String get _postText => composeFacebookPost(
        animals: widget.animals,
        fields: _fields,
        withLinks: _withLinks,
        intro: _introController.text,
        closing: _closingController.text,
      );

  /// The link a post without photos carries, so Facebook shows a preview.
  String? get _previewLink {
    if (!_withLinks) return null;
    final first = widget.animals.where(hasPublicProfile).firstOrNull;
    return first == null ? null : AppLinks.animalUrl(first.id);
  }

  @override
  void dispose() {
    _introController.dispose();
    _closingController.dispose();
    super.dispose();
  }

  void _togglePhoto(AnimalRecord a, String url) {
    final list = _selectedPhotos[a.id]!;
    setState(() {
      if (list.contains(url)) {
        list.remove(url);
      } else if (_photoCount >= kMaxSharePhotos) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('A post can carry up to $kMaxSharePhotos photos.', kind: AppMessageKind.error),
        );
      } else {
        // Keep the record's own order.
        list
          ..add(url)
          ..sort((x, y) => a.photoUrls.indexOf(x).compareTo(a.photoUrls.indexOf(y)));
      }
    });
  }

  Future<void> _editCaption(String url) async {
    final text = await showPhotoCaptionSheet(
      context,
      image: Image.network(url, fit: BoxFit.cover),
      initialValue: _captions[url] ?? '',
      title: 'Description for this post',
    );
    if (text == null || !mounted) return;
    setState(() => text.isEmpty ? _captions.remove(url) : _captions[url] = text);
  }

  List<FacebookShareItem> get _items => [
        for (final a in widget.animals)
          FacebookShareItem(
            animalId: a.id,
            photos: [for (final url in _selectedPhotos[a.id]!) (url: url, caption: _captions[url] ?? '')],
          ),
      ];

  Future<void> _postToPage(String organizationId, FacebookIntegration page) async {
    final link = _photoCount == 0 ? _previewLink : null;
    if (_photoCount == 0 && link == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Pick at least one photo, or add the profile link.', kind: AppMessageKind.error),
      );
      return;
    }
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Post to ${page.pageName}?',
      message: 'This posts publicly on the Facebook Page as ${page.pageName}'
          '${_photoCount > 0 ? ' with $_photoCount photo${_photoCount == 1 ? '' : 's'}' : ''}.',
      confirmLabel: 'Post',
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(facebookIntegrationRepositoryProvider).publishAnimalRecords(
            organizationId: organizationId,
            items: _items,
            message: _postText,
            link: link,
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
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not post to Facebook. Please try again.', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Hands the text (with its links) to the phone's share sheet. Facebook
  /// drops text that other apps pre-fill, so it's also copied for pasting;
  /// the link's preview (photo, name, status) comes from the web page.
  Future<void> _shareElsewhere() async {
    final text = _postText;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar('Post text copied. Paste it in if Facebook leaves the post empty.'),
    );
    final result = await SharePlus.instance.share(
      ShareParams(text: text, subject: defaultIntro(widget.animals)),
    );
    if (mounted && result.status == ShareResultStatus.success) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final orgId = ref.watch(currentOrganizationIdProvider).asData?.value;
    final canPublish = ref.watch(currentOrganizationCapabilitiesProvider).asData?.value.canPublishToFacebook ?? false;
    final page = orgId == null ? null : ref.watch(organizationFacebookIntegrationProvider(orgId)).asData?.value;
    final pageConnected = page?.isConnected ?? false;

    final String? postBlockedReason = switch ((pageConnected, canPublish)) {
      (false, _) => 'No Facebook Page is connected. An Organization Admin can connect one in Organization Profile.',
      (true, false) => 'Ask an Organization Admin to allow you to post to the Facebook Page.',
      _ => null,
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        title: Text(
          widget.animals.length == 1 ? 'Share ${displayNameOf(widget.animals.single)}' : 'Share ${widget.animals.length} animals',
          style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _sectionTitle('Details to include'),
            Text('The name is always included.', style: _hint),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final f in ShareField.values)
                  FilterChip(
                    label: Text(f.label),
                    selected: _fields.contains(f),
                    selectedColor: AppColors.yellowrspwn,
                    checkmarkColor: AppColors.textPrimary,
                    onSelected: (on) => setState(() => on ? _fields.add(f) : _fields.remove(f)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionTitle('Link'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _withLinks,
              activeThumbColor: AppColors.greenrspwn,
              onChanged: (v) => setState(() => _withLinks = v),
              title: Text('Add a link to the full profile', style: _body),
              subtitle: Text(
                'Opens a web page with every public detail and photo, and an "Open in the app" button '
                'for people who have ResPAWnd.',
                style: _hint,
              ),
            ),
            if (_withLinks && _withoutProfile.isNotEmpty)
              _notice(
                '${_withoutProfile.map(displayNameOf).join(', ')} '
                '${_withoutProfile.length == 1 ? 'has' : 'have'} no public profile (archived, hidden or deceased), '
                'so no link is added for ${_withoutProfile.length == 1 ? 'it' : 'them'}.',
              ),
            const SizedBox(height: 16),
            _sectionTitle('Photos'),
            Text(
              'Tap a photo to include or leave it out, and "Describe" to write what it shows. '
              '$_photoCount of $kMaxSharePhotos photos selected.',
              style: _hint,
            ),
            const SizedBox(height: 8),
            for (final a in widget.animals) _photoPicker(a),
            const SizedBox(height: 8),
            _sectionTitle('Text'),
            _textField(_introController, 'Opening line'),
            const SizedBox(height: 8),
            _textField(_closingController, 'Closing line'),
            const SizedBox(height: 16),
            _sectionTitle('Preview'),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.slaterspwn),
              ),
              child: SelectableText(_postText, style: GoogleFonts.zain(fontSize: 15, height: 1.3, color: AppColors.textPrimary)),
            ),
            if (_photoCount > 0) ...[
              const SizedBox(height: 6),
              Text('+ $_photoCount photo${_photoCount == 1 ? '' : 's'}, each with its description.', style: _hint),
            ],
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
                      label: Text(pageConnected ? 'Post to ${page!.pageName}' : 'Post to Page',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
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

  Widget _photoPicker(AnimalRecord a) {
    final selected = _selectedPhotos[a.id]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${displayNameOf(a)} · ${selected.length} of ${a.photoUrls.length}',
            style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          if (a.photoUrls.isEmpty)
            Text('No photos on this record.', style: _hint)
          else
            SizedBox(
              height: 150,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: a.photoUrls.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (_, i) {
                  final url = a.photoUrls[i];
                  final on = selected.contains(url);
                  final caption = _captions[url];
                  return SizedBox(
                    width: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () => _togglePhoto(a, url),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Opacity(
                                  opacity: on ? 1 : 0.45,
                                  child: Image.network(url, width: 104, height: 104, fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                            width: 104,
                                            height: 104,
                                            color: AppColors.tearspwn,
                                            child: const Icon(Icons.pets, color: AppColors.textSecondary),
                                          )),
                                ),
                              ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Icon(
                                  on ? Icons.check_circle : Icons.radio_button_unchecked,
                                  color: on ? AppColors.yellowrspwn : Colors.white,
                                  shadows: const [Shadow(blurRadius: 4, color: Colors.black54)],
                                ),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () => _editCaption(url),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              caption ?? 'Describe',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.zain(
                                fontSize: 12,
                                height: 1.15,
                                color: caption == null ? AppColors.greenrspwn : AppColors.textPrimary,
                                fontWeight: caption == null ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController controller, String label) => TextField(
        controller: controller,
        minLines: 1,
        maxLines: 3,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  Widget _notice(String text) => Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
      );

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(text, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
      );

  TextStyle get _hint => GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary);
  TextStyle get _body => GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary);
}
