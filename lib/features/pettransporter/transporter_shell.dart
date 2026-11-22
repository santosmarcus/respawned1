import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/service_screen.dart';
import 'package:respawnd1/features/pettransporter/transporter_notif.dart';
import 'package:respawnd1/features/pettransporter/transporter_profile.dart';

/// The pet transporter's app shell: Home, Notifications and My Profile under
/// one bottom bar that stays put (the same idea as HomeScreen for regular
/// users). The bar used to be a separate copy on every page, so it slid in
/// with each new route and disappeared during a transit.
///
/// Each tab has its own navigator, so pages opened from a tab (a job offer,
/// a transit in progress, the account page) stay under the bar, and
/// switching tabs keeps each tab where it was. Tapping the open tab again
/// goes back to its first page. Back pops inside the tab first, then
/// returns to Home, then leaves the app.
class TransporterShell extends StatefulWidget {
  const TransporterShell({super.key, this.initialTab = 0});

  final int initialTab;

  /// The shell around [context], or null when a page was opened outside it
  /// (for example from a push notification).
  static TransporterShellState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<TransporterShellState>();

  @override
  State<TransporterShell> createState() => TransporterShellState();
}

class TransporterShellState extends State<TransporterShell> {
  late int _index = widget.initialTab;
  late final Set<int> _opened = {widget.initialTab};
  final _navigators = List.generate(3, (_) => GlobalKey<NavigatorState>());

  static const _tabs = <Widget>[ServiceScreen(), TransporterNotifications(), TransporterProfile()];

  /// Shows tab [i]. Selecting the tab that is already open returns it to
  /// its first page.
  void select(int i) {
    if (i == _index) {
      _navigators[i].currentState?.popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _index = i;
      _opened.add(i);
    });
  }

  Future<void> _handleBack() async {
    final nav = _navigators[_index].currentState;
    if (nav != null && nav.canPop()) {
      await nav.maybePop(); // respects a page's own PopScope
      return;
    }
    if (_index != 0) {
      select(0);
      return;
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Theme(
        data: AppTheme.rescuerTheme,
        child: Scaffold(
          body: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                _opened.contains(i)
                    ? Navigator(
                        key: _navigators[i],
                        onGenerateRoute: (settings) =>
                            MaterialPageRoute(settings: settings, builder: (_) => _tabs[i]),
                      )
                    : const SizedBox.shrink(),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _index,
            onTap: select,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined),
                activeIcon: Icon(Icons.home),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.notifications_outlined),
                activeIcon: Icon(Icons.notifications),
                label: 'Notifications',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_outline),
                activeIcon: Icon(Icons.person),
                label: 'My Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
