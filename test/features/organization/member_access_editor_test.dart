import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/features/organization/widgets/member_access_editor.dart';

void main() {
  Finder box(OrgPermission p) => find.byKey(ValueKey('perm-${p.key}'));

  testWidgets('changing a box from a preset makes it Custom', (tester) async {
    MemberAccess? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MemberAccessEditor(
            initial: MemberAccess(OrgRole.staff, {...OrgPreset.rescueCoordinator.permissions}),
            onChanged: (a) => last = a,
          ),
        ),
      ),
    ));
    expect(find.text('Rescue coordinator'), findsOneWidget);
    await tester.ensureVisible(box(OrgPermission.adoptions));
    await tester.tap(box(OrgPermission.adoptions));
    await tester.pumpAndSettle();
    expect(last!.permissions, contains(OrgPermission.adoptions));
    expect(last!.preset, OrgPreset.custom);
    expect(find.text('Custom (changed below)'), findsOneWidget);
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

  testWidgets('Admins have no boxes; switching to Staff starts from Full staff', (tester) async {
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
    expect(last!.preset, OrgPreset.fullStaff);
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
