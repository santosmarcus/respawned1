import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';

/// Shared building blocks for the operational dashboard. Styled from the
/// existing ResPawnd tokens (AppColors, TiltWarp headings, Zain body) and
/// the same white-card/soft-shadow treatment admin_dashboard_home_widgets.dart
/// already uses, so the dashboard reads as part of the same app.

const double kDashMinTouch = 44;

TextStyle dashTitle([double size = 16]) => GoogleFonts.tiltWarp(fontSize: size, color: AppColors.textPrimary);

TextStyle dashBody({double size = 13, FontWeight weight = FontWeight.w500, Color color = AppColors.textPrimary}) =>
    GoogleFonts.zain(fontSize: size, fontWeight: weight, color: color, height: 1.25);

TextStyle dashMuted([double size = 12]) =>
    GoogleFonts.zain(fontSize: size, color: AppColors.textSecondary, height: 1.25);

BoxDecoration dashCardDecoration({Color? borderColor}) => BoxDecoration(
  color: AppColors.surface,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: borderColor ?? AppColors.textPrimary.withValues(alpha: 0.06)),
  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
);

/// One dashboard section: icon + heading + one-line "why this matters",
/// optional trailing summary pill, then content.
class DashSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String purpose;
  final Widget? trailing;
  final Widget child;

  const DashSection({
    super.key,
    required this.icon,
    required this.title,
    required this.purpose,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: dashCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, size: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(header: true, child: Text(title, style: dashTitle())),
                    const SizedBox(height: 2),
                    Text(purpose, style: dashMuted()),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A smaller titled group inside a section.
class DashSubheading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const DashSubheading(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: GoogleFonts.zain(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Icon + text status pill. Never color alone.
class SeverityPill extends StatelessWidget {
  final DashSeverity severity;
  final String? text;
  const SeverityPill(this.severity, {super.key, this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: severity.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(severity.icon, size: 12, color: severity.color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text ?? severity.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w800, color: severity.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutral tag (e.g. "Dog ×2", "Bite risk").
class DashTag extends StatelessWidget {
  final String text;
  final IconData? icon;
  final Color? color;
  const DashTag(this.text, {super.key, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color == null ? AppColors.background : c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 11, color: c), const SizedBox(width: 3)],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w700, color: c),
            ),
          ),
        ],
      ),
    );
  }
}

/// A KPI tile that distinguishes "unavailable" (null → "—" with reason)
/// from a true zero.
class MetricTile extends StatelessWidget {
  final String label;
  final int? value;
  final String? valueText;
  final String? caption;
  final DashSeverity? severity;
  final VoidCallback? onTap;

  const MetricTile({
    super.key,
    required this.label,
    this.value,
    this.valueText,
    this.caption,
    this.severity,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final shown = valueText ?? (value == null ? '—' : '$value');
    final accent = severity?.color ?? AppColors.textPrimary;
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border(
              left: BorderSide(color: accent.withValues(alpha: severity == null ? 0.15 : 0.9), width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      shown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.tiltWarp(fontSize: 20, color: accent),
                    ),
                  ),
                  if (severity != null) Icon(severity!.icon, size: 14, color: accent),
                  if (onTap != null) const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: dashBody(size: 12, weight: FontWeight.w700),
              ),
              if (caption != null) ...[
                const SizedBox(height: 1),
                Text(caption!, maxLines: 2, overflow: TextOverflow.ellipsis, style: dashMuted(11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive tile grid: 2 columns on phones, 3 on large phones/small
/// tablets, 4 on wide layouts. Uses Wrap so tall labels never overflow.
class MetricGrid extends StatelessWidget {
  final List<Widget> tiles;
  const MetricGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final columns = w >= 640 ? 4 : (w >= 440 ? 3 : 2);
        final tileWidth = (w - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final t in tiles) SizedBox(width: tileWidth, child: t)],
        );
      },
    );
  }
}

/// Clearly-labelled "this isn't recorded in ResPawnd yet" state. Used
/// instead of placeholder numbers whenever the data model has no source
/// for a metric — never mistaken for a real reading.
class NotTrackedNotice extends StatelessWidget {
  final String title;
  final String message;
  final List<String> items;
  const NotTrackedNotice({super.key, required this.title, required this.message, this.items = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.slaterspwn.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.do_not_disturb_on_outlined, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title, style: dashBody(size: 13, weight: FontWeight.w800)),
              ),
              const DashTag('Not tracked yet', icon: Icons.info_outline),
            ],
          ),
          const SizedBox(height: 6),
          Text(message, style: dashMuted()),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final i in items) DashTag(i)]),
          ],
        ],
      ),
    );
  }
}

/// Shown in place of restricted content for viewers without permission.
class RestrictedNotice extends StatelessWidget {
  final String message;
  const RestrictedNotice(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lavenderrspwn.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: dashBody(size: 12))),
        ],
      ),
    );
  }
}

class DashLoading extends StatelessWidget {
  final String? label;
  const DashLoading({super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.greenrspwn),
          ),
          if (label != null) ...[const SizedBox(width: 10), Text(label!, style: dashMuted())],
        ],
      ),
    );
  }
}

class DashError extends StatelessWidget {
  final String what;
  final Object error;
  const DashError({super.key, required this.what, required this.error});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, size: 16, color: DashSeverity.critical.color),
          const SizedBox(width: 8),
          Expanded(child: Text('Could not load $what. $error', style: dashMuted())),
        ],
      ),
    );
  }
}

class DashEmpty extends StatelessWidget {
  final String message;
  final DashSeverity severity;
  const DashEmpty(this.message, {super.key, this.severity = DashSeverity.ok});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(severity.icon, size: 16, color: severity.color),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: dashMuted())),
        ],
      ),
    );
  }
}

/// Renders an AsyncValue with the dashboard's own loading/error states so
/// one failed stream only affects its own block, never the whole page.
class DashAsync<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final String what;
  final Widget Function(T data) builder;
  const DashAsync({super.key, required this.value, required this.what, required this.builder});

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => DashLoading(label: 'Loading $what…'),
      error: (e, _) => DashError(what: what, error: e),
    );
  }
}

/// List row with leading thumbnail/icon, title, subtitle lines, a status
/// pill, and a chevron. Whole row is the touch target (>= 44px).
class DashListRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget? status;
  final List<Widget> details;
  final String? nextAction;
  final VoidCallback? onTap;

  const DashListRow({
    super.key,
    required this.leading,
    required this.title,
    this.status,
    this.details = const [],
    this.nextAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kDashMinTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: dashBody(size: 14, weight: FontWeight.w800),
                          ),
                        ),
                        if (status != null) ...[const SizedBox(width: 6), status!],
                      ],
                    ),
                    for (final d in details) Padding(padding: const EdgeInsets.only(top: 3), child: d),
                    if (nextAction != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.arrow_forward, size: 13, color: AppColors.textPrimary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text('Next: $nextAction', style: dashBody(size: 12, weight: FontWeight.w700)),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 4, top: 2),
                  child: Icon(Icons.chevron_right, color: AppColors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Icon + muted text detail line.
class DetailLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  /// Null = wrap fully (explanatory notes); data lines default to 3.
  final int? maxLines;
  const DetailLine(this.icon, this.text, {super.key, this.color, this.maxLines = 3});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: color ?? AppColors.textSecondary),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: color == null ? dashMuted() : dashBody(size: 12, color: color!),
          ),
        ),
      ],
    );
  }
}

/// Square photo thumbnail with an icon fallback.
class DashThumb extends StatelessWidget {
  final String? url;
  final IconData fallbackIcon;
  final double size;
  const DashThumb({super.key, this.url, this.fallbackIcon = Icons.pets, this.size = 46});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      color: AppColors.tearspwn,
      child: Icon(fallbackIcon, size: size * 0.45, color: AppColors.textPrimary),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: (url == null || url!.isEmpty)
          ? fallback
          : CachedNetworkImage(
        imageUrl: url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}

/// Round severity icon used as a list leading when there's no photo.
class SeverityDot extends StatelessWidget {
  final DashSeverity severity;
  final IconData? icon;
  const SeverityDot(this.severity, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: severity.color.withValues(alpha: 0.13), shape: BoxShape.circle),
      child: Icon(icon ?? severity.icon, size: 18, color: severity.color),
    );
  }
}

/// Shows the first [initialCount] children, with a "Show all (N)" toggle.
class ExpandableList extends StatefulWidget {
  final List<Widget> children;
  final int initialCount;
  final String moreLabel;
  const ExpandableList({super.key, required this.children, this.initialCount = 3, this.moreLabel = 'Show all'});

  @override
  State<ExpandableList> createState() => _ExpandableListState();
}

class _ExpandableListState extends State<ExpandableList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.children;
    final shown = _expanded ? all : all.take(widget.initialCount).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < shown.length; i++) ...[
          if (i > 0) Divider(height: 1, color: AppColors.textPrimary.withValues(alpha: 0.07)),
          shown[i],
        ],
        if (all.length > widget.initialCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                minimumSize: const Size(0, kDashMinTouch),
              ),
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18),
              label: Text(
                _expanded ? 'Show less' : '${widget.moreLabel} (${all.length})',
                style: dashBody(size: 13, weight: FontWeight.w800),
              ),
            ),
          ),
      ],
    );
  }
}

/// Outlined link-style action that opens an existing screen.
class DashLinkButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const DashLinkButton({super.key, required this.label, required this.onPressed, this.icon = Icons.open_in_new});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(0, kDashMinTouch),
        side: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: dashBody(size: 13, weight: FontWeight.w800)),
    );
  }
}

/// Horizontal progress bar with an accessible text label.
class DashProgress extends StatelessWidget {
  final double fraction;
  final Color color;
  final String semanticsLabel;
  const DashProgress({
    super.key,
    required this.fraction,
    required this.semanticsLabel,
    this.color = AppColors.greenrspwn,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: LinearProgressIndicator(
          value: fraction.clamp(0.0, 1.0),
          minHeight: 7,
          color: color,
          backgroundColor: AppColors.slaterspwn.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}

/// Single-select filter chips that wrap (no horizontal scroll).
class DashFilterChips<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelected;
  const DashFilterChips({
    super.key,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final o in options)
          ChoiceChip(
            label: Text(labelOf(o)),
            selected: o == selected,
            onSelected: (_) => onSelected(o),
            showCheckmark: false,
            labelStyle: GoogleFonts.zain(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: o == selected ? AppColors.background : AppColors.textPrimary,
            ),
            selectedColor: AppColors.textPrimary,
            backgroundColor: AppColors.background,
            side: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.2)),
            materialTapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

// ─── Reference-style containers (approved mobile design) ────────────────

/// Outlined card with a centered title over a divider — the "Today at a
/// glance" / "Are we saving more lives?" style from the reference.
class OutlinedCard extends StatelessWidget {
  final String title;
  final Widget child;
  const OutlinedCard({super.key, required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textPrimary, width: 1.3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 9, 12, 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.textPrimary, width: 1.3)),
            ),
            child: Semantics(
              header: true,
              child: Text(title, textAlign: TextAlign.center, style: dashTitle(14.5)),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// White card with icon + title header, optional trailing widget and a
/// chevron when tappable — the Rescue card style from the reference.
class SectionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onOpen;
  final Widget child;
  final EdgeInsets padding;
  final Color? background;

  const SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.trailing,
    this.onOpen,
    this.padding = const EdgeInsets.all(12),
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final line = AppColors.textPrimary.withValues(alpha: 0.14);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background ?? AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: line),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 7, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onOpen,
            child: Container(
              constraints: const BoxConstraints(minHeight: kDashMinTouch),
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 9),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: line)),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: AppColors.textPrimary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(header: true, child: Text(title, style: dashTitle(15.5))),
                  ),
                  ?trailing,
                  if (onOpen != null) const Icon(Icons.chevron_right, color: AppColors.textPrimary),
                ],
              ),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

enum ChipTone { red, amber, green, info, notRecorded, ink }

/// Small status chip: icon + words, never colour alone. [ChipTone.notRecorded]
/// is dashed and grey so "not recorded" never looks like a pass or a fail.
class StatusChip extends StatelessWidget {
  final String text;
  final ChipTone tone;
  final IconData? icon;
  const StatusChip(this.text, {super.key, this.tone = ChipTone.info, this.icon});

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border) = switch (tone) {
      ChipTone.red => (
      DashSeverity.critical.color,
      DashSeverity.critical.color.withValues(alpha: .10),
      DashSeverity.critical.color.withValues(alpha: .25),
      ),
      ChipTone.amber => (
      DashSeverity.warning.color,
      DashSeverity.warning.color.withValues(alpha: .10),
      DashSeverity.warning.color.withValues(alpha: .28),
      ),
      ChipTone.green => (
      DashSeverity.ok.color,
      DashSeverity.ok.color.withValues(alpha: .10),
      DashSeverity.ok.color.withValues(alpha: .25),
      ),
      ChipTone.info => (
      DashSeverity.info.color,
      DashSeverity.info.color.withValues(alpha: .08),
      DashSeverity.info.color.withValues(alpha: .22),
      ),
      ChipTone.notRecorded => (AppColors.textSecondary, Colors.transparent, const Color(0xFFA9A79F)),
      ChipTone.ink => (AppColors.background, AppColors.textPrimary, AppColors.textPrimary),
    };
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 2, 7, 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: tone == ChipTone.notRecorded ? null : Border.all(color: border),
      ),
      foregroundDecoration: tone == ChipTone.notRecorded ? _DashedBorder(border) : null,
      child: content,
    );
  }
}

class _DashedBorder extends Decoration {
  final Color color;
  const _DashedBorder(this.color);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _DashedPainter(color);
}

class _DashedPainter extends BoxPainter {
  final Color color;
  _DashedPainter(this.color);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final rrect = RRect.fromRectAndRadius(offset & size, const Radius.circular(6));
    final path = Path()..addRRect(rrect.deflate(0.5));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 3), paint);
        d += 6;
      }
    }
  }
}

/// Uppercase micro-label used inside cards ("TODAY'S CARE").
class CardLabel extends StatelessWidget {
  final String text;
  const CardLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 7),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.zain(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

/// Big number + label column, as in the reference Rescue card.
class BigStat extends StatelessWidget {
  final String value;
  final String label;
  final Color? color;
  final VoidCallback? onTap;
  const BigStat({super.key, required this.value, required this.label, this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          children: [
            Text(
              value,
              maxLines: 1,
              style: GoogleFonts.tiltWarp(fontSize: 28, color: color ?? AppColors.textPrimary, height: 1),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: dashBody(size: 13.5, weight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

/// Colour square + label for chart legends (drawn, not a text glyph).
class LegendText extends StatelessWidget {
  final Color color;
  final String text;
  final TextStyle? style;
  const LegendText(this.color, this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(text, style: style ?? dashBody(size: 12.5, weight: FontWeight.w700)),
        ),
      ],
    );
  }
}
