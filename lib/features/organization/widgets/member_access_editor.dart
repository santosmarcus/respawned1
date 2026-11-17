import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

/// Admin or Staff, and for Staff a preset to start from plus the permission
/// boxes. Changing any box shows "Custom". Ticking Manage money also ticks
/// (and locks) View donations & funds. Used when inviting and when an Admin
/// edits a member (staff_members_page.dart).
class MemberAccessEditor extends StatefulWidget {
  const MemberAccessEditor({super.key, required this.initial, required this.onChanged, this.roleLocked = false});

  final MemberAccess initial;
  final ValueChanged<MemberAccess> onChanged;

  /// The owner is always an Admin.
  final bool roleLocked;

  @override
  State<MemberAccessEditor> createState() => _MemberAccessEditorState();
}

class _MemberAccessEditorState extends State<MemberAccessEditor> {
  late OrgRole _role = widget.initial.role;
  late Set<OrgPermission> _perms = widget.initial.role == OrgRole.admin
      ? {...OrgPreset.fullStaff.permissions}
      : normalizePermissions(widget.initial.permissions);

  void _emit() => widget.onChanged(MemberAccess(_role, {..._perms}));

  void _setRole(OrgRole r) {
    setState(() => _role = r);
    _emit();
  }

  void _setPreset(OrgPreset? p) {
    if (p == null || p == OrgPreset.custom) return;
    setState(() => _perms = {...p.permissions});
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
    final preset = OrgPreset.matching(_perms);
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
          Text('Preset', style: label),
          const SizedBox(height: 6),
          DropdownButtonFormField<OrgPreset>(
            key: ValueKey(preset),
            initialValue: preset,
            isExpanded: true,
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
            items: [
              for (final p in OrgPreset.values)
                DropdownMenuItem(
                  value: p,
                  enabled: p != OrgPreset.custom,
                  child: Text(p == OrgPreset.custom ? 'Custom (changed below)' : p.label),
                ),
            ],
            onChanged: _setPreset,
          ),
          const SizedBox(height: 8),
          for (final group in OrgPermissionGroup.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 2),
              child: Text(group.label, style: label),
            ),
            for (final p in OrgPermission.values.where((p) => p.group == group))
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
Future<({String email, MemberAccess access})?> showMemberAccessSheet(
  BuildContext context, {
  required String title,
  required MemberAccess initial,
  required String confirmLabel,
  bool askEmail = false,
  bool roleLocked = false,
  String? Function(String email)? validateEmail,
}) {
  final emailController = TextEditingController();
  var access = initial.role == OrgRole.admin ? initial : MemberAccess(OrgRole.staff, normalizePermissions(initial.permissions));
  return showModalBottomSheet<({String email, MemberAccess access})>(
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
                  if (askEmail) ...[
                    Text('Email',
                        style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(hintText: 'name@example.com'),
                    ),
                    const SizedBox(height: 16),
                  ],
                  MemberAccessEditor(initial: initial, roleLocked: roleLocked, onChanged: (a) => access = a),
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
                      final email = emailController.text.trim();
                      if (askEmail && validateEmail != null) {
                        final error = validateEmail(email);
                        if (error != null) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(appSnackBar(error, kind: AppMessageKind.error));
                          return;
                        }
                      }
                      Navigator.pop(sheetContext, (email: email, access: access));
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
