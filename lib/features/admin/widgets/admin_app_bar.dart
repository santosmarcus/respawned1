import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// One entry in an admin screen's overflow (three-dot) menu.
class AdminMenuAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const AdminMenuAction({required this.label, required this.icon, required this.onTap});
}

/// The top bar every admin module screen uses: drawer (or back) button, title,
/// and screen-specific actions in a three-dot menu. The alerts bell lives on
/// the Dashboard only.
///
/// [bottom] is where a screen's [AdminTabBar] goes. [actions] is for the rare
/// inline control that can't be a menu entry (Animal Records' selection-mode
/// "Cancel").
class AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  const AdminAppBar({
    super.key,
    this.title,
    this.titleSize = 18,
    this.showDrawerButton = true,
    this.showLeading = true,
    this.menuActions = const [],
    this.actions = const [],
    this.bottom,
  });

  final String? title;
  final double titleSize;

  /// True on a module's root screen (opens the drawer); false on a screen
  /// pushed on top of one (back arrow).
  final bool showDrawerButton;
  final bool showLeading;
  final List<AdminMenuAction> menuActions;
  final List<Widget> actions;
  final PreferredSizeWidget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.textPrimary,
      centerTitle: true,
      automaticallyImplyLeading: false,
      leading: !showLeading
          ? null
          : showDrawerButton
              ? IconButton(
                  icon: const Icon(Icons.menu, color: AppColors.background),
                  tooltip: 'Menu',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.background),
                  tooltip: 'Back',
                  onPressed: () => Navigator.maybePop(context),
                ),
      title: title == null
          ? null
          : Text(title!, style: GoogleFonts.tiltWarp(fontSize: titleSize, color: AppColors.background)),
      actions: [
        ...actions,
        if (menuActions.isNotEmpty)
          PopupMenuButton<int>(
            tooltip: 'More',
            icon: const Icon(Icons.more_vert, color: AppColors.background),
            color: AppColors.background,
            onSelected: (i) => menuActions[i].onTap(),
            itemBuilder: (_) => [
              for (var i = 0; i < menuActions.length; i++)
                PopupMenuItem<int>(
                  value: i,
                  child: Row(
                    children: [
                      Icon(menuActions[i].icon, size: 18, color: AppColors.textPrimary),
                      const SizedBox(width: 10),
                      Text(menuActions[i].label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
            ],
          ),
      ],
      bottom: bottom,
    );
  }
}
