import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/constants/feature_flags.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/org_role.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// A member's access as the editor holds it.
class MemberAccess {
  const MemberAccess(this.role, this.permissions);

  final OrgRole role;
  final Set<OrgPermission> permissions;

  OrgPreset get preset => role == OrgRole.admin ? OrgPreset.custom : OrgPreset.matching(permissions);
}

/// Admin or Staff, and for Staff the permission boxes, starting from the one
/// default Staff set ([OrgPreset.staff]). Money permissions and Facebook
/// posting are never in the default; an Admin ticks them here. Ticking
/// Manage money also ticks (and locks) View donations & funds. Used when
/// inviting and when an Admin edits a member (staff_members_page.dart).
class MemberAccessEditor extends StatefulWidget {
  const MemberAccessEditor({
    super.key,
    required this.initial,
    required this.onChanged,
    this.roleLocked = false,
    this.available,
  });

  final MemberAccess initial;
  final ValueChanged<MemberAccess> onChanged;

  /// The owner is always an Admin.
  final bool roleLocked;

  /// What the organization has at all (orgEnabledPermissions); null for a
  /// shelter, which has everything. Only these boxes are shown.
  final Set<OrgPermission>? available;

  @override
  State<MemberAccessEditor> createState() => _MemberAccessEditorState();
}

class _MemberAccessEditorState extends State<MemberAccessEditor> {
  late final Set<OrgPermission> _available = widget.available ?? OrgPermission.values.toSet();
  late final Set<OrgPermission> _default = OrgPreset.staff.permissions.intersection(_available);
  late OrgRole _role = widget.initial.role;
  late Set<OrgPermission> _perms = widget.initial.role == OrgRole.admin
      ? {..._default}
      : normalizePermissions(widget.initial.permissions).intersection(_available);

  void _emit() => widget.onChanged(MemberAccess(_role, {..._perms}));

  void _setRole(OrgRole r) {
    setState(() => _role = r);
    _emit();
  }

  /// Back to the default Staff set (no money permissions).
  void _resetToDefault() {
    setState(() => _perms = {..._default});
    _emit();
  }

  void _toggle(OrgPermission p, bool on) {
    setState(() {
      if (on) {
        _perms.add(p);
      } else {
        _perms.remove(p);
        if (p == OrgPermission.financeView) _perms.remove(OrgPermission.financeManage);
      }
      _perms = normalizePermissions(_perms);
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final label = GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary);
    final isDefault = _perms.length == _default.length && _perms.containsAll(_default);
    final limited = widget.available != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Role', style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Admin'),
              selected: _role == OrgRole.admin,
              selectedColor: AppColors.yellowrspwn,
              onSelected: widget.roleLocked ? null : (_) => _setRole(OrgRole.admin),
            ),
            ChoiceChip(
              label: const Text('Staff'),
              selected: _role == OrgRole.staff,
              selectedColor: AppColors.yellowrspwn,
              onSelected: widget.roleLocked ? null : (_) => _setRole(OrgRole.staff),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _role == OrgRole.admin
              ? 'Admins can do everything, including managing members, the organization profile and settings.'
              : 'Staff can do only what is ticked below.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
        ),
        if (_role == OrgRole.staff) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(isDefault ? 'Default staff permissions' : 'Custom permissions',
                    key: const ValueKey('access-summary'), style: label),
              ),
              if (!isDefault)
                TextButton(
                  key: const ValueKey('reset-default'),
                  onPressed: _resetToDefault,
                  child: Text('Reset to default',
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                ),
            ],
          ),
          Text(
            limited
                ? 'Your team has only the modules turned on for rescue volunteers. A system admin can turn on more.'
                : 'Every Staff member starts with rescue, animal records, daily care (the care-tasks screen), adoptions, '
                    'events and volunteers, and analytics. Tick Money permissions or Facebook posting by hand for the '
                    'people who handle them.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          for (final group in OrgPermissionGroup.values.where((g) => _available.any((p) => p.group == g))) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(group.label, style: label),
            ),
            // Daily care's box is hidden while care tasks are
            // (FeatureFlags.careTasksEnabled); the permission itself stays in
            // the default set and on members who have it.
            for (final p in OrgPermission.values.where((p) =>
                p.group == group &&
                _available.contains(p) &&
                (FeatureFlags.careTasksEnabled || p != OrgPermission.care)))
              CheckboxListTile(
                key: ValueKey('perm-${p.key}'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.textPrimary,
                value: _perms.contains(p),
                // Manage money always includes viewing it.
                onChanged: p == OrgPermission.financeView && _perms.contains(OrgPermission.financeManage)
                    ? null
                    : (v) => _toggle(p, v ?? false),
                title: Text(p.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                subtitle: Text(p.description, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ),
          ],
          if (_perms.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('With nothing ticked, this member can sign in but sees no organization tools.',
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.error)),
            ),
        ],
      ],
    );
  }
}

/// A bottom sheet with [MemberAccessEditor] (and an email field when
/// [askEmail]); returns the email (when asked) and the chosen access, or
/// null when cancelled.
Future<({String email, String phone, MemberAccess access})?> showMemberAccessSheet(
  BuildContext context, {
  required String title,
  required MemberAccess initial,
  required String confirmLabel,
  bool askEmail = false,
  /// With [askEmail]: also offer inviting by mobile number.
  bool allowPhone = false,
  bool roleLocked = false,
  String? Function(String email)? validateEmail,
  Set<OrgPermission>? available,
}) {
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  var byPhone = false;
  var access = initial.role == OrgRole.admin ? initial : MemberAccess(OrgRole.staff, normalizePermissions(initial.permissions));
  return showModalBottomSheet<({String email, String phone, MemberAccess access})>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 12 + MediaQuery.of(sheetContext).viewInsets.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  if (askEmail)
                    StatefulBuilder(
                      builder: (context, setSheet) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (allowPhone) ...[
                            SegmentedButton<bool>(
                              segments: const [
                                ButtonSegment(value: false, label: Text('Email'), icon: Icon(Icons.mail_outline)),
                                ButtonSegment(value: true, label: Text('Mobile number'), icon: Icon(Icons.phone_iphone)),
                              ],
                              selected: {byPhone},
                              onSelectionChanged: (v) => setSheet(() => byPhone = v.first),
                              showSelectedIcon: false,
                            ),
                            const SizedBox(height: 12),
                          ],
                          Text(byPhone ? 'Mobile number' : 'Email',
                              style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          const SizedBox(height: 6),
                          if (byPhone) ...[
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              inputFormatters: AppInputFormatters.phoneFlexible,
                              decoration: const InputDecoration(hintText: '09171234567'),
                            ),
                            const SizedBox(height: 4),
                            Text('They join by signing in with this number (SMS code).',
                                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                          ] else
                            TextField(
                              controller: emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(hintText: 'name@example.com'),
                            ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  MemberAccessEditor(
                    initial: initial,
                    roleLocked: roleLocked,
                    available: available,
                    onChanged: (a) => access = a,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: () => Navigator.pop(sheetContext), child: const Text('Cancel')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: AppButtons.primary,
                    onPressed: () {
                      if (askEmail && byPhone) {
                        final phone = phoneController.text.trim();
                        final error = AppValidators.phFlexiblePhone(phone);
                        if (error != null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(appSnackBar(error, kind: AppMessageKind.error));
                          return;
                        }
                        Navigator.pop(sheetContext, (email: '', phone: phone, access: access));
                        return;
                      }
                      final email = emailController.text.trim();
                      if (askEmail && validateEmail != null) {
                        final error = validateEmail(email);
                        if (error != null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(appSnackBar(error, kind: AppMessageKind.error));
                          return;
                        }
                      }
                      Navigator.pop(sheetContext, (email: email, phone: '', access: access));
                    },
                    child: Text(confirmLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
