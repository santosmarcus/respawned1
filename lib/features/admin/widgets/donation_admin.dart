import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';
import 'package:respawnd1/core/models/donation/donation_model.dart';

class DonationAdminHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMenu;
  final String helpText;

  const DonationAdminHeader({super.key, required this.title, this.onMenu, required this.helpText});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.textPrimary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: onMenu != null ? 'Menu' : 'Back',
                    icon: Icon(onMenu != null ? Icons.menu : Icons.arrow_back_ios_new,
                        color: AppColors.background, size: onMenu != null ? 26 : 20),
                    onPressed: onMenu ?? () => Navigator.maybePop(context),
                  ),
                  IconButton(
                    tooltip: 'Help',
                    icon: const Icon(Icons.lightbulb_outline, color: AppColors.background),
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: AppColors.background,
                        title: Text(title, style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
                        content: Text(helpText, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text('Got it', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(title, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Austin's LabelWidget — bold Tilt Warp field label.
class FieldLabel extends StatelessWidget {
  final String text;
  final bool required;
  const FieldLabel(this.text, {super.key, this.required = false});

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(children: [
      TextSpan(text: text),
      if (required) const TextSpan(text: ' *', style: TextStyle(color: Colors.redAccent)),
    ]),
    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary),
  );
}

/// Figma's filled-square checkbox.
class SquareCheck extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const SquareCheck({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: value,
      child: InkWell(
        onTap: () => onChanged(!value),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: value ? AppColors.textPrimary : Colors.transparent,
            border: Border.all(color: AppColors.textPrimary, width: 1.6),
            borderRadius: BorderRadius.circular(2),
          ),
          child: value ? const Icon(Icons.check, size: 16, color: AppColors.background) : null,
        ),
      ),
    );
  }
}

/// Label on the left, square checkbox on the right (Figma tag / in-kind rows).
class CheckRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool bold;
  const CheckRow({super.key, required this.label, required this.value, required this.onChanged, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: bold
                ? FieldLabel(label)
                : Text(label, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
          ),
          SquareCheck(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Figma "+" image box (dashed olive border). Shows the picked file or an
/// already uploaded URL.
class ImagePickBox extends StatelessWidget {
  final XFile? file;
  final String? url;
  final VoidCallback onTap;
  final double size;
  const ImagePickBox({super.key, this.file, this.url, required this.onTap, this.size = 96});

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (file != null) {
      child = Image.file(File(file!.path), fit: BoxFit.cover);
    } else if (url != null && url!.isNotEmpty) {
      child = Image.network(url!, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined, color: AppColors.greenrspwn));
    } else {
      child = const Icon(Icons.add, color: AppColors.greenrspwn, size: 40);
    }
    return Semantics(
      button: true,
      label: 'Choose image',
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(),
          child: SizedBox(
            width: size,
            height: size,
            child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Center(child: child)),
          ),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.greenrspwn
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(10)));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Figma yellow pill (Create Campaign / Create Donation).
class YellowPillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  const YellowPillButton({super.key, required this.label, required this.onPressed, this.busy = false});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.yellowrspwn,
        disabledBackgroundColor: AppColors.yellowrspwn.withValues(alpha: 0.5),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 12),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.textPrimary))
          : Text(label, style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
    );
  }
}

class StatusChip extends StatelessWidget {
  final String status;
  const StatusChip(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'active' => AppColors.greenrspwn,
      'goal_met' => const Color(0xFF2E7D32),
      'goal_not_met' => Colors.deepOrange,
      'draft' => AppColors.textSecondary,
      'paused' => const Color(0xFF9C6B10),
      'archived' => AppColors.textSecondary,
      _ => Colors.redAccent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(campaignStatusLabel(status).toUpperCase(),
          style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

/// Figma campaign card (Search Donation/Sponsorship and the general feed):
/// tinted card, title + chevron, "Funds collected" and time left.
class CampaignCard extends StatelessWidget {
  final DonationListing listing;
  final VoidCallback onTap;
  const CampaignCard({super.key, required this.listing, required this.onTap});

  String get _timeLeft {
    if (listing.type == 'sponsorship' && listing.endDate == null) return 'Ongoing';
    if (listing.isDraft) return 'Not published';
    // Finished listings: what's left to allocate matters more than time.
    if (listing.isArchived) return 'Archived';
    if (listing.status == 'goal_met' || listing.status == 'closed') {
      final left = listing.availableBalance;
      return left < 0.005 ? 'Fully allocated' : '${formatPesoExact(left)} to allocate';
    }
    if (listing.isEnded) return 'Ended';
    if (listing.endDate == null) return 'No deadline';
    final days = listing.daysRemaining;
    if (days <= 1) return 'Ends today';
    if (days >= 30) return '${(days / 30).floor()} month${days >= 60 ? 's' : ''} left';
    return '$days days left';
  }

  /// Donations: verified funds vs. target. Sponsorships have no funding
  /// goal, so their bar shows how much of the listing period has passed
  /// (start → end date); open-ended sponsorships have nothing to measure.
  (double, String)? get _progress {
    if (listing.type == 'donation') {
      if (listing.target <= 0) return null;
      final v = (listing.collected / listing.target).clamp(0, 1).toDouble();
      return (v, '${listing.percentage}% of ${formatPesoExact(listing.target)}');
    }
    final start = listing.startDate ?? listing.createdAt;
    final end = listing.endDate;
    if (start == null || end == null || !end.isAfter(start)) return null;
    final total = end.difference(start).inMinutes;
    final done = DateTime.now().difference(start).inMinutes.clamp(0, total);
    final v = done / total;
    return (v, '${(v * 100).round()}% of period');
  }

  @override
  Widget build(BuildContext context) {
    final muted = listing.isEnded || listing.isDraft;
    final bg = muted ? const Color(0xFFC9C6B5) : listing.backgroundColor;
    final small = GoogleFonts.zain(fontSize: 12, height: 1.0, color: AppColors.textPrimary);
    final progress = _progress;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 9, 6, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(listing.title,
                          style: GoogleFonts.tiltWarp(fontSize: 14, height: 1.15, color: AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (listing.status != 'active') ...[const SizedBox(width: 6), StatusChip(listing.status)],
                    const Icon(Icons.chevron_right, size: 20, color: AppColors.textPrimary),
                  ],
                ),
                const SizedBox(height: 4),
                Text(listing.type == 'sponsorship' ? 'Sponsorships received' : 'Funds collected', style: small),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(formatPesoExact(listing.collected),
                            style: GoogleFonts.tiltWarp(fontSize: 16, height: 1.2, color: AppColors.textPrimary)),
                      ),
                      Text(_timeLeft, style: small),
                    ],
                  ),
                ),
                if (progress != null) ...[
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress.$1,
                              minHeight: 5,
                              backgroundColor: AppColors.background.withValues(alpha: 0.6),
                              valueColor: const AlwaysStoppedAnimation(AppColors.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(progress.$2, style: GoogleFonts.zain(fontSize: 11, height: 1.0, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma bottom-sheet frame: centred title, "Done" on the right, Cancel left.
class AdminSheetFrame extends StatelessWidget {
  final String title;
  final String doneLabel;
  final VoidCallback? onDone;
  final bool busy;
  final List<Widget> children;

  const AdminSheetFrame({
    super.key,
    required this.title,
    required this.onDone,
    required this.children,
    this.doneLabel = 'Done',
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => Navigator.pop(context),
                      child: Text('Cancel', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary)),
                    ),
                    Expanded(
                      child: Text(title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                    ),
                    busy
                        ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                        : TextButton(
                      onPressed: onDone,
                      child: Text(doneLabel,
                          style: GoogleFonts.zain(
                              fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Underlined row field used inside the sheets (Figma "Enter Title" style).
class SheetTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final String? prefix;
  final int maxLines;
  const SheetTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.keyboardType,
    this.prefix,
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        hintStyle: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary),
        enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.slaterspwn)),
        focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
      ),
    );
  }
}

/// Figma "Select Category ............ Medication and Treatment" row with the
/// inline option card underneath.
class InlineSelectRow extends StatefulWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  const InlineSelectRow({super.key, required this.label, required this.value, required this.options, required this.onChanged});

  @override
  State<InlineSelectRow> createState() => _InlineSelectRowState();
}

class _InlineSelectRowState extends State<InlineSelectRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
            child: Row(
              children: [
                Expanded(child: Text(widget.label, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary))),
                Text(widget.value ?? 'Select',
                    style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
        if (_open)
          Container(
            margin: const EdgeInsets.only(top: 4, bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Column(
              children: [
                for (final o in widget.options)
                  InkWell(
                    onTap: () {
                      widget.onChanged(o);
                      setState(() => _open = false);
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.slaterspwn))),
                      child: Text(o,
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                              fontWeight: o == widget.value ? FontWeight.w800 : FontWeight.w400)),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmAction(
    BuildContext context, {
      required String title,
      required String message,
      required String confirmLabel,
      bool destructive = false,
    }) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      title: Text(title, style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      content: Text(message, style: GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel', style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel,
              style: GoogleFonts.zain(
                  fontSize: 16, fontWeight: FontWeight.w800, color: destructive ? Colors.redAccent : AppColors.textPrimary)),
        ),
      ],
    ),
  );
  return ok == true;
}

void showAdminSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(message),
    backgroundColor: error ? Colors.redAccent : AppColors.textPrimary,
  ));
}

/// Parses "1,250.50" style input; null when not a positive amount with ≤2 decimals.
double? parsePesoInput(String raw) {
  final cleaned = raw.replaceAll(',', '').trim();
  if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(cleaned)) return null;
  final v = double.tryParse(cleaned);
  return (v == null || v <= 0) ? null : v;
}
