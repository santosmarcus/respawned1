import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_search_bar.dart';
import 'package:respawnd1/features/admin/widgets/admin_tab_bar.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('date format', () {
    test('one format for date, time and both', () {
      final d = DateTime(2026, 11, 2, 15, 5);
      expect(formatDate(d), 'Nov 2, 2026');
      expect(formatTime(d), '3:05 PM');
      expect(formatTime(DateTime(2026, 1, 1, 0, 7)), '12:07 AM');
      expect(formatDateTime(d), 'Nov 2, 2026 · 3:05 PM');
      expect(formatDateOr(null, 'Not set'), 'Not set');
    });
  });

  group('AdminAppBar + AdminTabBar', () {
    Widget screen({
      required int selected,
      required ValueChanged<int> onSelected,
      List<AdminMenuAction> menuActions = const [],
    }) {
      return MaterialApp(
        home: Scaffold(
          drawer: const Drawer(child: Text('drawer content')),
          appBar: AdminAppBar(
            title: 'Rescue Reports',
            menuActions: menuActions,
            bottom: AdminTabBar(
              tabs: const [
                AdminTab('Review', count: 3),
                AdminTab('Assign', count: 0),
                AdminTab('Ongoing'),
                AdminTab('Treatment', count: 120),
                AdminTab('Intake'),
              ],
              selectedIndex: selected,
              onSelected: onSelected,
            ),
          ),
          body: AdminTabSwipe(
            index: selected,
            count: 5,
            onSelected: onSelected,
            child: const SizedBox.expand(child: Text('list')),
          ),
        ),
      );
    }

    testWidgets('shows labels with counts and reports taps', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(screen(selected: 0, onSelected: taps.add));

      expect(find.text('Rescue Reports'), findsOneWidget);
      expect(find.text('Review'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('99+'), findsOneWidget);
      // Zero and missing counts show no pill.
      expect(find.text('0'), findsNothing);

      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();
      // Re-tapping the selected tab is reported too (Rescue uses it to clear
      // a status override).
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(taps, [1, 0]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('swiping the list moves one tab and stops at the ends', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(screen(selected: 0, onSelected: taps.add));

      await tester.fling(find.text('list'), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(taps, [1]);

      // Already on the first tab: swiping right does nothing.
      await tester.fling(find.text('list'), const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(taps, [1]);
    });

    testWidgets('menu button opens the drawer; actions sit in the overflow menu', (tester) async {
      var helped = false;
      await tester.pumpWidget(screen(
        selected: 0,
        onSelected: (_) {},
        menuActions: [AdminMenuAction(label: 'Help', icon: Icons.lightbulb_outline, onTap: () => helped = true)],
      ));

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      expect(helped, isTrue);

      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      expect(find.text('drawer content'), findsOneWidget);
    });

    testWidgets('no overflow menu when a screen has no actions', (tester) async {
      await tester.pumpWidget(screen(selected: 2, onSelected: (_) {}));
      expect(find.byTooltip('More'), findsNothing);
    });
  });

  group('AdminSearchBar', () {
    testWidgets('clear button empties the field; filter button is optional', (tester) async {
      final controller = TextEditingController();
      final changes = <String>[];
      var filterTaps = 0;
      Widget bar({VoidCallback? onFilter, int count = 0}) => MaterialApp(
            home: Scaffold(
              body: AdminSearchBar(
                controller: controller,
                hintText: 'Search events…',
                onChanged: changes.add,
                onFilter: onFilter,
                activeFilterCount: count,
              ),
            ),
          );

      await tester.pumpWidget(bar());
      expect(find.byTooltip('Filter'), findsNothing);
      expect(find.byTooltip('Clear search'), findsNothing);

      await tester.enterText(find.byType(TextField), 'drive');
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes, ['drive', '']);

      await tester.pumpWidget(bar(onFilter: () => filterTaps++, count: 2));
      expect(find.text('2'), findsOneWidget);
      await tester.tap(find.byTooltip('Filter'));
      expect(filterTaps, 1);
      expect(tester.takeException(), isNull);
      controller.dispose();
    });
  });
}
