import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';

/// One tab: its label and, optionally, how many items wait in it.
class AdminTab {
  final String label;
  final int? count;
  const AdminTab(this.label, {this.count});
}

/// The underline tab bar every admin screen uses to switch views. Goes in
/// [AdminAppBar.bottom].
///
/// Give it [selectedIndex] and [onSelected] to drive it from the screen's own
/// state. Leave both out to use the nearest [DefaultTabController] (for a
/// screen that pairs it with a [TabBarView]).
///
/// More than three tabs scroll sideways; up to three share the width.
class AdminTabBar extends StatefulWidget implements PreferredSizeWidget {
  const AdminTabBar({super.key, required this.tabs, this.selectedIndex, this.onSelected});

  final List<AdminTab> tabs;
  final int? selectedIndex;

  /// Also called when the already-selected tab is tapped.
  final ValueChanged<int>? onSelected;

  static const double height = 46;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<AdminTabBar> createState() => _AdminTabBarState();
}

class _AdminTabBarState extends State<AdminTabBar> with TickerProviderStateMixin {
  TabController? _controller;

  bool get _controlled => widget.selectedIndex != null;

  int get _index => widget.selectedIndex!.clamp(0, widget.tabs.length - 1);

  @override
  void initState() {
    super.initState();
    if (_controlled) _controller = TabController(length: widget.tabs.length, vsync: this, initialIndex: _index);
  }

  @override
  void didUpdateWidget(AdminTabBar old) {
    super.didUpdateWidget(old);
    if (!_controlled) {
      _controller?.dispose();
      _controller = null;
      return;
    }
    final controller = _controller;
    if (controller == null || controller.length != widget.tabs.length) {
      controller?.dispose();
      _controller = TabController(length: widget.tabs.length, vsync: this, initialIndex: _index);
    } else if (controller.index != _index) {
      controller.animateTo(_index);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrollable = widget.tabs.length > 3;
    return SizedBox(
      height: AdminTabBar.height,
      child: TabBar(
        controller: _controller,
        isScrollable: scrollable,
        tabAlignment: scrollable ? TabAlignment.start : TabAlignment.fill,
        labelColor: AppColors.background,
        unselectedLabelColor: AppColors.background.withValues(alpha: 0.6),
        indicatorColor: AppColors.yellowrspwn,
        indicatorWeight: 3,
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600),
        labelPadding: scrollable ? const EdgeInsets.symmetric(horizontal: 14) : null,
        onTap: widget.onSelected,
        tabs: [for (final t in widget.tabs) _TabLabel(tab: t)],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.tab});

  final AdminTab tab;

  @override
  Widget build(BuildContext context) {
    final count = tab.count ?? 0;
    return Tab(
      height: AdminTabBar.height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(tab.label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            // A filled pill, so waiting work stays visible on unselected tabs.
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: AppColors.yellowrspwn, borderRadius: BorderRadius.circular(10)),
              child: Text(
                count > 99 ? '99+' : '$count',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.3),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lets a sideways swipe on [child] move to the next or previous tab, for
/// screens that drive [AdminTabBar] from their own state.
class AdminTabSwipe extends StatelessWidget {
  const AdminTabSwipe({
    super.key,
    required this.index,
    required this.count,
    required this.onSelected,
    required this.child,
  });

  final int index;
  final int count;
  final ValueChanged<int> onSelected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v.abs() < 300) return;
        final next = v < 0 ? index + 1 : index - 1;
        if (next >= 0 && next < count) onSelected(next);
      },
      child: child,
    );
  }
}
