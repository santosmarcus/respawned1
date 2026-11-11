import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// The search row every admin list screen shows under its tabs: a search
/// field, then a filter (or sort) button when the screen has one, then any
/// extra square buttons in [trailing].
class AdminSearchBar extends StatelessWidget {
  const AdminSearchBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.onClear,
    this.onFilter,
    this.filterIcon = Icons.tune,
    this.filterTooltip = 'Filter',
    this.filterActive = false,
    this.activeFilterCount = 0,
    this.trailing = const [],
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 0),
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;

  /// Called after the clear button empties the field. Defaults to
  /// `onChanged('')`.
  final VoidCallback? onClear;

  /// Null hides the filter button (the screen has nothing to filter by).
  final VoidCallback? onFilter;
  final IconData filterIcon;
  final String filterTooltip;

  /// Highlights the filter button when filters are applied.
  final bool filterActive;

  /// Shown as a badge on the filter button when above zero.
  final int activeFilterCount;
  final List<Widget> trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.slaterspwn),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: hintText,
                        hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                    ),
                  ),
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => value.text.isEmpty
                        ? const SizedBox.shrink()
                        : GestureDetector(
                            onTap: () {
                              controller.clear();
                              if (onClear != null) {
                                onClear!();
                              } else {
                                onChanged('');
                              }
                            },
                            child: const Tooltip(
                              message: 'Clear search',
                              child: Icon(Icons.clear, size: 18, color: AppColors.textSecondary),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          if (onFilter != null) ...[
            const SizedBox(width: 10),
            AdminSquareButton(
              icon: filterIcon,
              tooltip: filterTooltip,
              active: filterActive || activeFilterCount > 0,
              badgeCount: activeFilterCount,
              onTap: onFilter!,
            ),
          ],
          for (final w in trailing) ...[const SizedBox(width: 10), w],
        ],
      ),
    );
  }
}

/// The 40×40 rounded button beside the search field (filter, sort, view
/// toggle).
class AdminSquareButton extends StatelessWidget {
  const AdminSquareButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: active ? AppColors.yellowrspwn : AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.slaterspwn),
              ),
              child: Icon(icon, size: 20, color: AppColors.textPrimary, semanticLabel: tooltip),
            ),
            if (badgeCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    '$badgeCount',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Centered grey message for an empty or failed admin list.
class AdminListMessage extends StatelessWidget {
  const AdminListMessage(this.text, {super.key, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, style: AppButtons.outline, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}
