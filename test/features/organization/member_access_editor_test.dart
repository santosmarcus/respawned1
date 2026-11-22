import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/features/organization/widgets/member_access_editor.dart';

void main() {
  Finder box(OrgPermission p) => find.byKey(ValueKey('perm-${p.key}'));

  testWidgets('ticking a money box makes access Custom; Reset goes back to the default', (tester) async {
    MemberAccess? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MemberAccessEditor(
            initial: MemberAccess(OrgRole.staff, {...OrgPreset.staff.permissions}),
            onChanged: (a) => last = a,
          ),
        ),
      ),
    ));
    expect(find.text('Default staff permissions'), findsOneWidget);
    expect(find.byKey(const ValueKey('reset-default')), findsNothing);
    await tester.ensureVisible(box(OrgPermission.campaigns));
    await tester.tap(box(OrgPermission.campaigns));
    await tester.pumpAndSettle();
    expect(last!.permissions, containsAll([...OrgPreset.staff.permissions, OrgPermission.campaigns]));
    expect(last!.preset, OrgPreset.custom);
    expect(find.text('Custom permissions'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('reset-default')));
    await tester.tap(find.byKey(const ValueKey('reset-default')));
    await tester.pumpAndSettle();
    expect(last!.permissions, OrgPreset.staff.permissions);
    expect(last!.preset, OrgPreset.staff);
  });

  testWidgets('Manage money ticks and locks View donations', (tester) async {
    MemberAccess? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MemberAccessEditor(
            initial: const MemberAccess(OrgRole.staff, {OrgPermission.care}),
            onChanged: (a) => last = a,
          ),
        ),
      ),
    ));
    await tester.ensureVisible(box(OrgPermission.financeManage));
    await tester.tap(box(OrgPermission.financeManage));
    await tester.pumpAndSettle();
    expect(last!.permissions, containsAll([OrgPermission.financeManage, OrgPermission.financeView]));
    final view = tester.widget<CheckboxListTile>(box(OrgPermission.financeView));
    expect(view.value, isTrue);
    expect(view.onChanged, isNull);
  });

  testWidgets('Admins have no boxes; switching to Staff starts from the default set', (tester) async {
    MemberAccess? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MemberAccessEditor(
            initial: const MemberAccess(OrgRole.admin, {}),
            onChanged: (a) => last = a,
          ),
        ),
      ),
    ));
    expect(box(OrgPermission.rescue), findsNothing);
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    expect(last!.role, OrgRole.staff);
    expect(last!.preset, OrgPreset.staff);
    expect(last!.permissions, isNot(contains(OrgPermission.financeView)));
    expect(box(OrgPermission.rescue), findsOneWidget);
  });

  testWidgets('the owner cannot be made Staff', (tester) async {
    MemberAccess? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MemberAccessEditor(
          initial: const MemberAccess(OrgRole.admin, {}),
          roleLocked: true,
          onChanged: (a) => last = a,
        ),
      ),
    ));
    await tester.tap(find.text('Staff'));
    await tester.pumpAndSettle();
    expect(last, isNull);
  });
}
