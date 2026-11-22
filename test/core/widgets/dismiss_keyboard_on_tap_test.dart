import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/widgets/dismiss_keyboard_on_tap.dart';

void main() {
  Future<FocusNode> pumpForm(WidgetTester tester, {required bool withFix}) async {
    final focus = FocusNode();
    String? picked;
    Widget form = Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => Column(
          children: [
            TextField(key: const Key('name'), focusNode: focus),
            DropdownButtonFormField<String>(
              key: const Key('choice'),
              initialValue: picked,
              items: const [
                DropdownMenuItem(value: 'Dog', child: Text('Dog')),
                DropdownMenuItem(value: 'Cat', child: Text('Cat')),
              ],
              onChanged: (v) => setState(() => picked = v),
            ),
          ],
        ),
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: form,
      builder: withFix ? (context, child) => DismissKeyboardOnTap(child: child!) : null,
    ));
    await tester.tap(find.byKey(const Key('name')));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('choice')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cat').last);
    await tester.pumpAndSettle();
    return focus;
  }

  testWidgets('picking from a dropdown leaves the text field (and keyboard) closed', (tester) async {
    final focus = await pumpForm(tester, withFix: true);
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('typing in the field itself keeps it focused', (tester) async {
    final focus = FocusNode();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => DismissKeyboardOnTap(child: child!),
      home: Scaffold(body: TextField(key: const Key('name'), focusNode: focus)),
    ));
    await tester.tap(find.byKey(const Key('name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('name')));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);
  });
}
