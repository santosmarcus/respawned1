import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/features/admin/organizations/organization_review_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/widgets/admin_app_bar.dart';

/// Rescue volunteer applications: people who signed up as a rescue volunteer
/// (an organizations doc with kind 'independent') and submitted their
/// documents. Organization staff with the Volunteers permission, platform
/// staff and system admins approve, reject or ask for changes
/// (the reviewOrganization callable).
///
/// [canSetLimits]: whether approved rescue volunteers show "Modules &
/// limits" (setIndependentLimits); null = only for platform staff.
class VolunteerApplicationsPage extends ConsumerWidget {
  const VolunteerApplicationsPage({
    super.key,
    this.showBackButton = true,
    this.canSetLimits,
    this.menuActions = const [],
  });

  final bool showBackButton;
  final bool? canSetLimits;
  final List<AdminMenuAction> menuActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final limits = canSetLimits ?? (ref.watch(isPlatformStaffProvider).asData?.value ?? false);
    return OrganizationReviewPage(
      kind: OrgKind.independent,
      title: 'Rescue Volunteer Applications',
      showBackButton: showBackButton,
      canSetLimits: limits,
      menuActions: menuActions,
    );
  }
}
