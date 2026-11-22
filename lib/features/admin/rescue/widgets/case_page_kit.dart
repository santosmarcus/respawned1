import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/admin/rescue/widgets/status_chip.dart';
import 'package:respawnd1/features/admin/widgets/view_only.dart';

/// Shared building blocks for the admin case pages (Rescue Details, Track
/// Case, Treatment, Intake): a compact header, one outcome/next-step
/// banner, a two-column fact grid instead of tall label/value rows,
/// collapsible secondary sections, and a sticky action bar with one
/// primary and one secondary action (the rest in the app bar's menu).

const double kCaseGap = 12;

/// Case header: a strip of photo/video thumbnails, species, status and
/// urgency chips, the case id and who reported it when.
class CaseHeaderCard extends StatelessWidget {
  final String title;
  final String caseId;
  final RescueStatus? status;
  final Widget? statusChip;
  final String? urgency;
  final String? reporterName;
  final DateTime? reportedAt;
  final List<String> photoUrls;
  final List<String> videoUrls;

  /// Called with the index into `[...photoUrls, ...videoUrls]`.
  final ValueChanged<int>? onMediaTap;

  /// Extra pills under the title (open for transfer, verified, ...).
  final List<Widget> badges;

  const CaseHeaderCard({
    super.key,
    required this.title,
    required this.caseId,
    this.status,
    this.statusChip,
    this.urgency,
    this.reporterName,
    this.reportedAt,
    this.photoUrls = const [],
    this.videoUrls = const [],
    this.onMediaTap,
    this.badges = const [],
  });

  @override
  Widget build(BuildContext context) {
    final media = [...photoUrls, ...videoUrls];
    final meta = [
      if (reporterName != null && reporterName!.trim().isNotEmpty) 'Reported by ${reporterName!.trim()}',
      if (reportedAt != null) formatDateTime(reportedAt!),
    ].join(' · ');
    return _KitCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (media.isNotEmpty) ...[
            SizedBox(
              height: 76,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: media.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final isVideo = i >= photoUrls.length;
                  return GestureDetector(
                    onTap: onMediaTap == null ? null : () => onMediaTap!(i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: media.length == 1 ? 120 : 76,
                        height: 76,
                        child: isVideo
                            ? Container(
                                color: Colors.black87,
                                child: const Icon(Icons.play_circle_fill, color: Colors.white70, size: 30),
                              )
                            : Image.network(
                                media[i],
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: AppColors.tearspwn,
                                  child: const Icon(Icons.broken_image, color: AppColors.textSecondary),
                                ),
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  if (urgency != null) UrgencyChip(urgency: urgency),
                  if (statusChip != null) statusChip! else if (status != null) RescueStatusChip(status: status!),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Case #$caseId${meta.isEmpty ? '' : ' · $meta'}',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
          ),
          if (badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: badges),
          ],
        ],
      ),
    );
  }
}

/// Small rounded pill for [CaseHeaderCard.badges].
class CaseBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  const CaseBadge({super.key, required this.label, this.icon, this.color = AppColors.lavenderrspwn});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: AppColors.textPrimary),
            const SizedBox(width: 4),
          ],
          Text(label, style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

enum CaseBannerTone { info, success, warning, danger, neutral }

/// The one place that says where a case stands and what happens next:
/// why it was rejected, who it is referred to and for how long, what came
/// back from a referral, the intake result, or a safety warning.
class CaseOutcomeBanner extends StatelessWidget {
  final CaseBannerTone tone;
  final IconData? icon;
  final String title;
  final String? message;

  /// Short label/value lines (reason, date, by ...).
  final List<(String, String)> facts;

  /// Inline links/buttons (e.g. open the animal record).
  final List<Widget> actions;

  const CaseOutcomeBanner({
    super.key,
    required this.tone,
    required this.title,
    this.icon,
    this.message,
    this.facts = const [],
    this.actions = const [],
  });

  Color get _accent => switch (tone) {
        CaseBannerTone.info => const Color(0xFF4E6BD8),
        CaseBannerTone.success => AppColors.success,
        CaseBannerTone.warning => const Color(0xFFB7791F),
        CaseBannerTone.danger => AppColors.error,
        CaseBannerTone.neutral => AppColors.textSecondary,
      };

  IconData get _defaultIcon => switch (tone) {
        CaseBannerTone.info => Icons.info_outline,
        CaseBannerTone.success => Icons.check_circle_outline,
        CaseBannerTone.warning => Icons.schedule,
        CaseBannerTone.danger => Icons.warning_amber_rounded,
        CaseBannerTone.neutral => Icons.inventory_2_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final accent = _accent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _defaultIcon, size: 20, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
                if (message != null && message!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(message!, style: GoogleFonts.zain(fontSize: 13, height: 1.25, color: AppColors.textPrimary)),
                ],
                if (facts.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  for (final (label, value) in facts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: RichText(
                        text: TextSpan(
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                          children: [
                            TextSpan(text: '$label  ', style: const TextStyle(color: AppColors.textSecondary)),
                            TextSpan(text: value, style: const TextStyle(fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                ],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 8, runSpacing: 4, children: actions),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One fact in a [CaseInfoGrid]. [wide] spans both columns (long text).
class CaseInfoItem {
  final String label;
  final String? value;
  final bool wide;
  final Color? valueColor;
  const CaseInfoItem(this.label, this.value, {this.wide = false, this.valueColor});

  bool get hasValue => value != null && value!.trim().isNotEmpty;
}

/// Two-column label/value grid. Empty values are skipped, long ones can
/// take a full row ([CaseInfoItem.wide]); on very narrow widths it falls
/// back to one column.
class CaseInfoGrid extends StatelessWidget {
  final String? title;
  final List<CaseInfoItem> items;
  final Widget? trailing;
  final bool card;

  const CaseInfoGrid({super.key, this.title, required this.items, this.trailing, this.card = true});

  @override
  Widget build(BuildContext context) {
    final visible = items.where((i) => i.hasValue).toList();
    if (visible.isEmpty && trailing == null) return const SizedBox.shrink();
    final grid = LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 280;
        final rows = <Widget>[];
        CaseInfoItem? pending;
        void flush() {
          if (pending == null) return;
          rows.add(Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Expanded(child: _cell(pending!)), const SizedBox(width: 12), const Expanded(child: SizedBox())],
          ));
          pending = null;
        }

        for (final item in visible) {
          if (!twoCol || item.wide) {
            flush();
            rows.add(_cell(item));
          } else if (pending == null) {
            pending = item;
          } else {
            rows.add(Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Expanded(child: _cell(pending!)), const SizedBox(width: 12), Expanded(child: _cell(item))],
            ));
            pending = null;
          }
        }
        flush();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              rows[i],
            ],
          ],
        );
      },
    );
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Text(title!, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
        ],
        if (visible.isNotEmpty) grid,
        if (trailing != null) ...[
          if (visible.isNotEmpty) const SizedBox(height: 6),
          trailing!,
        ],
      ],
    );
    return card ? _KitCard(child: body) : body;
  }

  Widget _cell(CaseInfoItem item) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.label.toUpperCase(),
            style: GoogleFonts.zain(
                fontSize: 10.5, letterSpacing: 0.4, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
          ),
          Text(
            item.value!.trim(),
            style: GoogleFonts.zain(
                fontSize: 13.5, height: 1.2, fontWeight: FontWeight.w600, color: item.valueColor ?? AppColors.textPrimary),
          ),
        ],
      );
}

/// A secondary section that starts collapsed: a slim header (title, short
/// summary, optional count/attention dot) that expands to show [child].
/// The child isn't built while collapsed, so its listeners don't run.
class CollapsibleSection extends StatefulWidget {
  final String title;
  final String? summary;
  final IconData? icon;
  final bool initiallyExpanded;

  /// Highlights the header (e.g. a pending location report to approve).
  final bool attention;
  final Widget child;

  const CollapsibleSection({
    super.key,
    required this.title,
    required this.child,
    this.summary,
    this.icon,
    this.initiallyExpanded = false,
    this.attention = false,
  });

  @override
  State<CollapsibleSection> createState() => _CollapsibleSectionState();
}

class _CollapsibleSectionState extends State<CollapsibleSection> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: 18, color: AppColors.textPrimary),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            style: GoogleFonts.zain(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        if (widget.summary != null && widget.summary!.isNotEmpty)
                          Text(widget.summary!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  if (widget.attention)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
                    ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.expand_more, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          widget.child,
        ],
      ],
    );
  }
}

/// One button in a [CaseActionBar].
class CaseAction {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool destructive;

  const CaseAction(this.label, this.onPressed, {this.icon, this.destructive = false});
}

/// Sticky bottom bar: one primary (filled) and one secondary (outlined)
/// action. Everything else goes in the app bar's [CaseOverflowMenu] (top
/// right). Hidden for Staff who can only view rescue cases. Use
/// [CaseActionBar.maybe] for a Scaffold's bottomNavigationBar.
class CaseActionBar extends ConsumerWidget {
  final CaseAction? primary;
  final CaseAction? secondary;
  final bool busy;

  const CaseActionBar({super.key, this.primary, this.secondary, this.busy = false});

  /// Null when there is nothing to show.
  static Widget? maybe({CaseAction? primary, CaseAction? secondary, bool busy = false}) {
    if (primary == null && secondary == null) return null;
    return CaseActionBar(primary: primary, secondary: secondary, busy: busy);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(canEditProvider(OrgPermission.rescue))) return const SizedBox.shrink();
    final secondary = this.secondary;
    if (primary == null && secondary == null) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              if (secondary != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: busy ? null : secondary.onPressed,
                    style: (secondary.destructive ? AppButtons.dangerOutline : AppButtons.outline)
                        .copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
                    child: _label(secondary, secondary.destructive ? AppColors.error : AppColors.textPrimary),
                  ),
                ),
              if (secondary != null && primary != null) const SizedBox(width: 10),
              if (primary != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: busy ? null : primary!.onPressed,
                    style: (primary!.destructive ? AppButtons.danger : AppButtons.primary)
                        .copyWith(padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
                    child: busy
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                        : _label(primary!, primary!.destructive ? Colors.white : AppColors.textPrimary),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(CaseAction a, Color color) => Text(
        a.label,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.tiltWarp(fontSize: 14, color: color),
      );
}

/// The case page's other actions, as a "more" button for the app bar's
/// `actions` (top right). Shows nothing when [actions] is empty or the
/// account can only view rescue cases.
class CaseOverflowMenu extends ConsumerWidget {
  final List<CaseAction> actions;
  final bool busy;

  const CaseOverflowMenu({super.key, required this.actions, this.busy = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (actions.isEmpty || !ref.watch(canEditProvider(OrgPermission.rescue))) return const SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: 'More actions',
      enabled: !busy,
      icon: const Icon(Icons.more_vert, color: AppColors.background),
      onSelected: (i) => actions[i].onPressed?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: actions[i].onPressed != null,
            child: Row(
              children: [
                if (actions[i].icon != null) ...[
                  Icon(actions[i].icon, size: 18, color: actions[i].destructive ? AppColors.error : AppColors.textPrimary),
                  const SizedBox(width: 10),
                ],
                Flexible(
                  child: Text(
                    actions[i].label,
                    style: GoogleFonts.zain(
                      fontSize: 14,
                      color: actions[i].destructive ? AppColors.error : AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The white rounded card the kit's pieces sit on (same look as
/// SectionCard, slightly tighter).
class _KitCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const _KitCard({required this.child, this.padding = const EdgeInsets.all(12)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: child,
    );
  }
}

/// A plain card for the kit pages' own content (description, clinic).
class CaseCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  const CaseCard({super.key, this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return _KitCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null || trailing != null) ...[
            Row(
              children: [
                if (title != null)
                  Expanded(child: Text(title!, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary))),
                ?trailing,
              ],
            ),
            const SizedBox(height: 6),
          ],
          child,
        ],
      ),
    );
  }
}

/// "12m", "5h", "3d" since [since].
String caseAgeLabel(DateTime since, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(since);
  if (d.inMinutes < 60) return '${d.inMinutes < 1 ? 1 : d.inMinutes}m';
  if (d.inHours < 48) return '${d.inHours}h';
  return '${d.inDays}d';
}
