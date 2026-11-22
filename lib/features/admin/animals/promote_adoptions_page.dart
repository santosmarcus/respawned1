import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/adoption_promotion_schedule.dart';
import 'package:respawnd1/core/repos/facebook_integration_repository.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/organization/widgets/adoption_promotion_schedule_sheet.dart';

/// Facebook only shows so many photos in one post well.
const int kMaxAnimalsPerFacebookPost = 10;

/// The suggested animal ids a reminder carries (comma-separated in push
/// data and in-app notification docs).
List<String> promotionIdsFrom(Object? raw) {
  if (raw is List) return raw.whereType<String>().where((s) => s.isNotEmpty).toList();
  if (raw is String) return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  return const [];
}

/// A ready-to-edit caption for a post of [names]. Same wording as
/// defaultCaption in functions/adoption_promotion_rules.js.
String adoptionPostCaption(List<String> names) {
  final clean = names.map((n) => n.trim()).where((n) => n.isNotEmpty).toList();
  if (clean.isEmpty) return 'These animals are looking for a home. Message us to adopt!';
  final list = clean.length == 1
      ? clean.first
      : '${clean.sublist(0, clean.length - 1).join(', ')} and ${clean.last}';
  final one = clean.length == 1;
  return 'Meet $list! ${one ? 'This animal is' : 'They are'} ready for a loving home. '
      'Message us or apply through the ResPAWnd app to adopt.';
}

/// Promote Adoptions: the Admin's post schedule (every member sees it and
/// gets its reminders) and, for members allowed to share to Facebook, pick
/// animals open for adoption, edit the caption and post them to the
/// organization's Facebook Page in one post. Opened from the admin drawer, the Facebook section of Organization Profile, and the
/// adoption_promotion_due reminder (functions/adoption_promotion.js), whose
/// suggested animals arrive as [preselectedIds].
class PromoteAdoptionsPage extends ConsumerStatefulWidget {
  final String? organizationId;
  final List<String>? preselectedIds;
  const PromoteAdoptionsPage({super.key, this.organizationId, this.preselectedIds});

  @override
  ConsumerState<PromoteAdoptionsPage> createState() => _PromoteAdoptionsPageState();
}

class _PromoteAdoptionsPageState extends ConsumerState<PromoteAdoptionsPage> {
  final _caption = TextEditingController();
  Future<PromotionSuggestions>? _suggestions;
  String? _orgId;
  final Set<String> _selected = {};
  Map<String, String> _names = const {};
  bool _captionEdited = false;
  bool _posting = false;
  bool _usePreselected = true;

  @override
  void initState() {
    super.initState();
    _orgId = widget.organizationId;
    if (_orgId != null) _load();
  }

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  /// Starts (or restarts) loading the ranked animals. Safe from initState.
  void _load() {
    final orgId = _orgId;
    if (orgId == null) return;
    final future = _fetch(orgId);
    // Members without facebookPublish never show the picker, so nothing
    // listens to this future's (permission) error; don't report it.
    future.ignore();
    if (_suggestions == null) {
      _suggestions = future;
    } else {
      setState(() => _suggestions = future);
    }
  }

  Future<PromotionSuggestions> _fetch(String orgId) {
    return ref.read(facebookIntegrationRepositoryProvider).fetchPromotionSuggestions(orgId).then((s) {
      if (!mounted) return s;
      final available = {for (final a in s.animals) a.id};
      // The reminder's picks only on the first load; after a post, the
      // fresh ranking decides.
      final wanted = _usePreselected
          ? (widget.preselectedIds ?? const <String>[]).where(available.contains).toList()
          : const <String>[];
      _usePreselected = false;
      setState(() {
        _names = {for (final a in s.animals) a.id: a.name};
        _selected
          ..clear()
          ..addAll(wanted.isNotEmpty ? wanted : s.suggestedIds);
        _captionEdited = false;
        _refreshCaption();
      });
      return s;
    });
  }

  void _refreshCaption() {
    if (_captionEdited) return;
    _caption.text = adoptionPostCaption([for (final id in _selected) _names[id] ?? '']);
  }

  void _toggle(String id, bool on) {
    setState(() {
      if (on) {
        if (_selected.length >= kMaxAnimalsPerFacebookPost) {
          ScaffoldMessenger.of(context).showSnackBar(
            appSnackBar('A post can have up to $kMaxAnimalsPerFacebookPost animals.'),
          );
          return;
        }
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
      _refreshCaption();
    });
  }

  Future<void> _post() async {
    final orgId = _orgId;
    if (orgId == null || _selected.isEmpty) return;
    final caption = _caption.text.trim();
    if (caption.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Write a caption first.', kind: AppMessageKind.error));
      return;
    }
    final ok = await showConfirmActionDialog(
      context,
      title: 'Post to Facebook?',
      message: 'This posts ${_selected.length == 1 ? '1 animal' : '${_selected.length} animals'} '
          'to the organization\'s Facebook Page right away.',
      confirmLabel: 'Post',
    );
    if (!ok || !mounted) return;
    setState(() => _posting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      // One photo per animal (its first), the same as a post from the
      // animal's record; the caption carries the text.
      final items = <FacebookShareItem>[];
      for (final id in _selected) {
        final record = await ref.read(animalRecordProvider(id).future);
        final photo = (record?.photoUrls.isNotEmpty ?? false) ? record!.photoUrls.first : null;
        if (photo == null) continue;
        items.add(FacebookShareItem(animalId: id, photos: [(url: photo, caption: '')]));
      }
      if (items.isEmpty) {
        messenger.showSnackBar(
          appSnackBar('The selected animals have no photos to post.', kind: AppMessageKind.error),
        );
        return;
      }
      final result = await ref.read(facebookIntegrationRepositoryProvider).publishAnimalRecords(
            organizationId: orgId,
            items: items,
            message: caption,
          );
      if (!mounted) return;
      messenger.showSnackBar(appSnackBar('Posted to Facebook Page.', kind: AppMessageKind.success));
      final open = await showConfirmActionDialog(
        context,
        title: 'Posted',
        message: 'The adoption post is on your Facebook Page.',
        confirmLabel: 'View post',
        cancelLabel: 'Done',
      );
      if (open && result.postUrl.isNotEmpty) {
        final uri = Uri.tryParse(result.postUrl);
        if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (mounted) _load();
    } on FacebookOperationException catch (e) {
      messenger.showSnackBar(appSnackBar(e.message, kind: AppMessageKind.error));
    } catch (_) {
      messenger.showSnackBar(appSnackBar('Could not post to Facebook.', kind: AppMessageKind.error));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_orgId == null) {
      final orgAsync = ref.watch(currentOrganizationIdProvider);
      return orgAsync.when(
        loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (e, _) => _scaffold(const Center(child: Text('Could not load your organization.'))),
        data: (orgId) {
          if (orgId == null) {
            return _scaffold(const Center(child: Text('You are not part of an organization.')));
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _orgId == null) {
              setState(() {
                _orgId = orgId;
                _load();
              });
            }
          });
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        },
      );
    }

    final orgId = _orgId!;
    final caps = ref.watch(currentOrganizationCapabilitiesProvider).asData?.value;
    final integration = ref.watch(organizationFacebookIntegrationProvider(orgId)).asData?.value;
    final connected = integration?.isConnected ?? false;

    return _scaffold(
      ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _ScheduleCard(organizationId: orgId, canEdit: caps?.canManageFacebookConnection ?? false),
          const SizedBox(height: 16),
          if (integration != null && !connected)
            _notice('The Facebook Page is not connected. An Admin can connect it from Organization Profile.')
          else if (caps != null && !caps.canPublishToFacebook)
            _notice('You get these reminders as a member of the organization. Posting needs the '
                'Share to Facebook permission: tell an Admin or a member who has it, or ask an Admin to give it to you.')
          else
            _picker(),
        ],
      ),
      bottom: connected && (caps?.canPublishToFacebook ?? false) ? _postBar() : null,
    );
  }

  Widget _scaffold(Widget body, {Widget? bottom}) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Promote Adoptions'),
        actions: [
          if (_orgId != null)
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _posting ? null : _load),
        ],
      ),
      body: body,
      bottomNavigationBar: bottom,
    );
  }

  Widget _notice(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(text, textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );

  Widget _picker() {
    return FutureBuilder<PromotionSuggestions>(
      future: _suggestions,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          final e = snap.error;
          return Column(
            children: [
              _notice(e is FacebookOperationException ? e.message : 'Could not load the animals open for adoption.'),
              OutlinedButton(onPressed: _load, child: const Text('Retry')),
            ],
          );
        }
        final s = snap.data!;
        if (s.animals.isEmpty) {
          return _notice('No animals are open for adoption with a photo right now. '
              'Animals need the Adoptable status, a photo, and to be shown on the public profile.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Caption', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: _caption,
              maxLines: 5,
              minLines: 3,
              enabled: !_posting,
              onChanged: (_) => _captionEdited = true,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
            ),
            if (_captionEdited)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _posting
                      ? null
                      : () => setState(() {
                            _captionEdited = false;
                            _refreshCaption();
                          }),
                  child: const Text('Reset caption'),
                ),
              ),
            const SizedBox(height: 16),
            Text('Animals (${_selected.length} selected)',
                style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            Text('Most in need of a post first. Suggested animals are already ticked.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            for (final a in s.animals)
              _CandidateTile(
                candidate: a,
                selected: _selected.contains(a.id),
                suggested: s.suggestedIds.contains(a.id),
                enabled: !_posting,
                onChanged: (v) => _toggle(a.id, v),
              ),
          ],
        );
      },
    );
  }

  Widget _postBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: ElevatedButton.icon(
          style: AppButtons.primary,
          onPressed: _posting || _selected.isEmpty ? null : _post,
          icon: _posting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.facebook),
          label: Text(_selected.isEmpty
              ? 'Select animals to post'
              : 'Post ${_selected.length == 1 ? '1 animal' : '${_selected.length} animals'} to Facebook'),
        ),
      ),
    );
  }
}

class _ScheduleCard extends ConsumerWidget {
  final String organizationId;
  final bool canEdit;
  const _ScheduleCard({required this.organizationId, required this.canEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(organizationAdoptionPromotionProvider(organizationId)).asData?.value ??
        AdoptionPromotionSchedule.initial;
    final small = GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Post schedule',
                    style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              if (canEdit)
                TextButton(
                  onPressed: () => showAdoptionPromotionScheduleSheet(
                    context,
                    organizationId: organizationId,
                    current: schedule,
                  ),
                  child: Text(schedule.isOff ? 'Set up' : 'Edit'),
                ),
            ],
          ),
          Text(schedule.summary, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary)),
          if (schedule.enabled && schedule.nextDueAt != null)
            Text('Next reminder: ${formatDateTime(schedule.nextDueAt!)}', style: small),
          Text('Last post: ${formatDateOr(schedule.lastPostedAt, 'none yet')}', style: small),
          if (schedule.isOff && !canEdit)
            Text('An Admin can set a regular reminder to post animals open for adoption.', style: small),
        ],
      ),
    );
  }
}

class _CandidateTile extends ConsumerWidget {
  final PromotionCandidate candidate;
  final bool selected;
  final bool suggested;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.suggested,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(animalRecordProvider(candidate.id)).asData?.value;
    final photo = (record?.photoUrls.isNotEmpty ?? false) ? record!.photoUrls.first : null;
    final last = candidate.lastSharedAt;
    final detail = [
      candidate.reason,
      if (last != null) 'last shared ${formatDate(last)}',
      if (suggested) 'suggested',
    ].join(' · ');
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      value: selected,
      onChanged: enabled ? (v) => onChanged(v ?? false) : null,
      secondary: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: photo == null
              ? const ColoredBox(color: AppColors.slaterspwn, child: Icon(Icons.pets, color: AppColors.textSecondary))
              : Image.network(photo, fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) =>
                      const ColoredBox(color: AppColors.slaterspwn, child: Icon(Icons.pets, color: AppColors.textSecondary))),
        ),
      ),
      title: Text(candidate.name.isEmpty ? 'Unnamed animal' : candidate.name,
          style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: Text(detail, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}
