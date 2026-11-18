import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Every module is open to every Staff member outside the care-tasks
/// screen; where they lack the permission it is view only (firestore.rules
/// `readKeys()` for reads, the permission itself for writes).
///
/// True when the signed-in account may change things covered by any of
/// [perms]. Platform staff with no organization of their own keep the
/// operational modules they always had. True while loading, so buttons
/// don't flicker away for people who do have access; the backend still
/// refuses a write without the permission.
final canEditProvider = Provider.autoDispose.family<bool, OrgPermission>((ref, perm) {
  final caps = ref.watch(currentOrganizationCapabilitiesProvider);
  final platform = ref.watch(isPlatformStaffProvider).asData?.value ?? false;
  final c = caps.asData?.value;
  if (c == null) return true;
  if (!c.isActive) return platform && perm.group != OrgPermissionGroup.money;
  return c.has(perm);
});

/// [canEditProvider] for a module covered by several permissions (Records:
/// animals or care).
bool canEditAny(WidgetRef ref, Iterable<OrgPermission> perms) => perms.any((p) => ref.watch(canEditProvider(p)));

/// What the signed-in account can do, for code that isn't a widget.
OrganizationCapabilities myCapabilities(WidgetRef ref) =>
    ref.watch(currentOrganizationCapabilitiesProvider).asData?.value ?? OrganizationCapabilities.none;

/// A slim strip at the top of a module or detail page the account can see
/// but not change. Shows nothing when they have any of [perms].
class ViewOnlyBanner extends ConsumerWidget {
  const ViewOnlyBanner({super.key, required this.perms});

  final List<OrgPermission> perms;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (canEditAny(ref, perms)) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: AppColors.yellowrspwn.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.visibility_outlined, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'View only. Ask an Admin for "${perms.first.label}" access to make changes.',
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows [child] only when the account may change things under [perms].
class IfCanEdit extends ConsumerWidget {
  const IfCanEdit({super.key, required this.perms, required this.child});

  final List<OrgPermission> perms;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      canEditAny(ref, perms) ? child : const SizedBox.shrink();
}
