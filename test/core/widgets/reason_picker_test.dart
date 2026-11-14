import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/reason_picker.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  // Google Fonts finish loading asynchronously; let them land before typing,
  // or the relayout trips a text-painter assertion that only exists in tests.
  Future<void> settle(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await tester.runAsync(() => GoogleFonts.pendingFonts());
    await tester.pumpAndSettle();
  }

  ElevatedButton confirmButton(WidgetTester tester, String label) =>
      tester.widget<ElevatedButton>(find.ancestor(of: find.text(label), matching: find.byType(ElevatedButton)));

  testWidgets('"Other" needs an explanation before it can be confirmed', (tester) async {
    ReasonPickerResult<String>? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showReasonPicker<String>(
              context,
              title: 'Decline Reason',
              options: const [ReasonOption('far', 'Too far'), ReasonOption('other', 'Other', isOther: true)],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);

    expect(confirmButton(tester, 'Confirm').onPressed, isNull, reason: 'nothing chosen yet');
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    expect(confirmButton(tester, 'Confirm').onPressed, isNull, reason: 'Other without text');

    await tester.enterText(find.byType(TextField), 'Flooded road');
    await tester.pumpAndSettle();
    expect(confirmButton(tester, 'Confirm').onPressed, isNotNull);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(picked?.value, 'other');
    expect(picked?.otherText, 'Flooded road');
  });

  testWidgets('several reasons can be picked when allowed, in list order', (tester) async {
    ReasonPickerResult<String>? picked;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => picked = await showReasonPicker<String>(
              context,
              title: 'Rejection Reason',
              multiple: true,
              noteLabel: 'Additional notes',
              options: const [ReasonOption('a', 'Housing'), ReasonOption('b', 'Incomplete')],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('Incomplete'));
    await tester.tap(find.text('Housing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(picked?.values, ['a', 'b']);
    expect(picked?.note, isNull);
  });

  testWidgets('a required text prompt cannot be confirmed empty', (tester) async {
    String? typed = 'unset';
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                typed = await showTextInputDialog(context, title: 'Decline Return', label: 'Reason', required: true),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(confirmButton(tester, 'Save').onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  Moving abroad  ');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(typed, 'Moving abroad');
  });

  testWidgets('cancelling a confirm dialog returns false', (tester) async {
    bool? ok;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                ok = await showConfirmActionDialog(context, title: 'End this order?', message: 'Stops today.'),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(ok, isFalse);
  });
}
