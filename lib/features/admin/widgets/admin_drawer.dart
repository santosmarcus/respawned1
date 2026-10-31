import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/admin/adoption/adoption_application_review_page.dart';
import 'package:respawnd1/features/admin/animals/animal_record_page.dart';
import 'package:respawnd1/features/admin/audit/audit_page.dart';
import 'package:respawnd1/features/admin/collarTags/admin_collar_screen.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_home.dart';
import 'package:respawnd1/features/admin/events/admin_events_page.dart';
import 'package:respawnd1/features/admin/rescue/rescue_reports_page.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/volunteers/volunteers_page.dart';
import 'package:respawnd1/features/organization/organization_profile_edit_page.dart';

/// The full set of admin root modules the drawer can open, in the required
/// order — the single source of truth for labels/ordering/highlighting so
/// no page can drift into its own separately-ordered/labeled copy again.
/// `shelterResources` removed — it was a permanent no-op placeholder with
/// no destination page at all; shelter-capacity now lives in Organization
/// Profile. `audit` added for the new Audit module.
enum AdminModule { dashboard, rescue, adoptions, donations, records, events, volunteers, transporters, collarTags, audit }

/// Pops back to AdminHomeScreen (the app's first/root route) before pushing
/// the requested module — every drawer module item uses this so switching
/// modules replaces the current root instead of stacking a new one on top
/// of whatever module was already open (Rescue -> Adoptions -> Rescue used
/// to leave two Rescue root pages on the stack).
void _openModule(BuildContext context, WidgetBuilder builder) {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  Navigator.pop(context); // close the drawer
  rootNavigator.popUntil((route) => route.isFirst);
  rootNavigator.push(MaterialPageRoute(builder: builder));
}

// _openOrganizationProfile used to be a bare top-level async function with
// no re-entrancy guard, no loading feedback, and a silent `if
// (context.mounted)` no-op if the widget unmounted mid-flight (see
// _AdminDrawerState._handleOpenOrganizationProfile below for the fixed,
// guarded version — this is the root cause the "sometimes does not open
// even after repeated taps" bug report pointed at).

/// The one shared admin navigation drawer — every admin root page
/// (`AdminHomeScreen`, `RescueReportsPage`, `AdminAdoptionPage`,
/// `AnimalRecordsPage`, `AdminCollarTagScreen`) sets `drawer: const
/// AdminDrawer()` on its own `Scaffold` and opens it via a
/// `Builder`-wrapped menu `IconButton` calling `Scaffold.of(context).
/// openDrawer()` — this used to be duplicated byte-for-byte between
/// `adminhome_screen.dart` and `admin_collar_screen.dart`, with three other
/// admin pages having a menu button that did nothing at all (no `onPressed`
/// action, and no `drawer:` on their own `Scaffold` for it to open even if
/// it had one). One shared widget now, not a third copy.
class AdminDrawer extends ConsumerStatefulWidget {
  // Which module the page hosting this drawer represents — null on pages
  // that don't correspond to a drawer entry. Highlights that one item so
  // an admin can tell which module they're currently in.
  final AdminModule? active;
  const AdminDrawer({super.key, this.active});

  @override
  ConsumerState<AdminDrawer> createState() => _AdminDrawerState();
}

class _AdminDrawerState extends ConsumerState<AdminDrawer> {
  bool _signingOut = false;

  // Root cause of "Organization Profile sometimes does not open even after
  // repeated taps" (first pass): the old top-level `_openOrganizationProfile`
  // did two chained Firestore reads with no re-entrancy guard, no loading
  // feedback, and a bare `if (context.mounted)` before pushing. Fixed by a
  // guard flag that disables the row and shows a spinner while resolving,
  // resetting the guard in `finally`, and an explicit error snackbar
  // instead of a silent no-op.
  //
  // Root cause of the SECOND bug ("Bad state: The provider
  // StreamProvider<OrgMembership?> was disposed during loading state, yet
  // no value could be emitted."): that fix read
  // `currentOrgMembershipProvider.future` — a `StreamProvider.autoDispose`
  // — via `ref.read` from inside this tap callback. `ref.read` does not
  // register a listener, so with nothing else on screen watching that
  // provider (e.g. no rescue_detail_page.dart open), autoDispose tears it
  // down again almost immediately — often before its underlying Firestore
  // stream has emitted a first value, which is exactly the disposed-while-
  // loading crash. The membership value was only ever used for its
  // `organizationId` field anyway, and per OrgMembershipService's own
  // doc comment, [getMembership]/the membership stream return null for
  // every real account today (no `organizations/{orgId}/members/{uid}`
  // subdocs exist yet) — so this always fell through to
  // [resolveOrganizationId] regardless. Fixed by dropping the disposable
  // stream read entirely for this one-time "which org do I open" lookup
  // and going straight to the plain repository Future
  // (OrgMembershipService.resolveOrganizationId), which has no Riverpod
  // provider lifecycle to be disposed out from under. Role-gated actions
  // elsewhere (e.g. rescue_detail_page.dart's `canManageOrgActions`) are
  // unaffected — they still `ref.watch` the membership stream directly on
  // a page that stays mounted, which is the safe pattern this callback
  // was not following.
  bool _openingOrgProfile = false;

  Future<void> _handleOpenOrganizationProfile() async {
    if (_openingOrgProfile) return; // re-entrancy guard — no duplicate route pushes
    setState(() => _openingOrgProfile = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final organizationId = uid == null
          ? null
          : await ref.read(orgMembershipServiceProvider).resolveOrganizationId(uid);

      if (!mounted) return;
      Navigator.pop(context); // close the drawer only once the destination is ready
      if (!context.mounted) return;
      // organizationId == null legitimately reaches this page too — it
      // runs its own pending-invitation/bootstrap flow for an admin not
      // yet linked to an organization (see OrganizationProfileEditPage's
      // own doc comment), which is a real, meaningful screen, not a blank
      // error state.
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrganizationProfileEditPage(organizationId: organizationId)),
      );
    } catch (e, st) {
      debugPrint('[AdminDrawer] Could not resolve organization membership: $e\n$st');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: const Text('Could not load the organization profile.'),
            action: SnackBarAction(label: 'Retry', onPressed: _handleOpenOrganizationProfile),
          ),
        );
      }
    } finally {
      // Reset the guard even if this screen is no longer mounted (e.g. the
      // admin navigated away while this was resolving) — never leaves the
      // row permanently disabled for the next time this Drawer is opened.
      if (mounted) setState(() => _openingOrgProfile = false);
    }
  }

  Future<void> _logOut() async {
    if (_signingOut) return; // disable repeated taps while processing
    setState(() => _signingOut = true);

    // Captured before any `await` — these stay usable even if the Drawer's
    // own BuildContext is deactivated once the drawer closes mid-flow.
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context); // close the drawer, same pattern every other item uses

    try {
      await authService.value.signOut();

      // The admin-scoped case/adoption list providers are already
      // autoDispose (see rescue_reports_providers.dart / adoption_providers.dart)
      // so their Firestore listeners tear themselves down as soon as the
      // pages watching them are removed below. currentOrgMembershipProvider
      // and currentOrganizationCapabilitiesProvider are global (not tied to
      // a specific page) so they're cleared explicitly.
      ref.invalidate(currentOrgMembershipProvider);
      ref.invalidate(currentOrganizationCapabilitiesProvider);

      // Remove every pushed admin route so the stale authenticated screen
      // can't linger on top of AuthWrapper's now-signed-out content —
      // AuthWrapper (the app's root, first route) reactively swaps to
      // LoginScreen on its own once authStateChanges() emits null.
      rootNavigator.popUntil((route) => route.isFirst);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Log out failed: $e')));
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.textPrimary,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.yellowrspwn,
                    child: Text('G', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Loved by the Gapz', style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.background)),
                      Text('Admin Staff', style: GoogleFonts.zain(fontSize: 12, color: AppColors.background.withValues(alpha: 0.7))),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(color: Colors.white24),

            // Menu items — order matches the project's required admin menu
            // order: Dashboard, Rescue, Adoptions, Donations, Records,
            // Events, Volunteers, Transporters, Collar Tags, Audit.
            // Volunteers now opens VolunteersPage (role ==
            // 'rescue_volunteer' directory), Events opens AdminEventsPage.
            // Transporters still has no admin screen built yet, so it stays
            // a no-op placeholder. Shelter Resources was removed entirely — it
            // was a permanent no-op with no destination page; shelter
            // capacity is edited from Organization Profile.
            _DrawerItem(
              label: 'Dashboard',
              selected: widget.active == AdminModule.dashboard,
              onTap: () {
                final rootNavigator = Navigator.of(context, rootNavigator: true);
                Navigator.pop(context); // close the drawer
                // Pops every pushed admin route back to AdminHomeScreen
                // (the app's first/root route) — previously this only
                // closed the drawer and did nothing else, so "Dashboard"
                // appeared broken from any page other than the dashboard
                // itself.
                rootNavigator.popUntil((route) => route.isFirst);
              },
            ),
            _DrawerItem(
              label: 'Rescue',
              selected: widget.active == AdminModule.rescue,
              onTap: () => _openModule(context, (_) => const RescueReportsPage()),
            ),
            _DrawerItem(
              label: 'Adoptions',
              selected: widget.active == AdminModule.adoptions,
              // Straight to the tabbed Adoption Applications page — the
              // separate admin adoption dashboard is no longer the
              // landing page for Adoptions.
              onTap: () => _openModule(context, (_) => const AdoptionApplicationReviewPage()),
            ),
            _DrawerItem(
              label: 'Donations',
              selected: widget.active == AdminModule.donations,
              onTap: () => _openModule(context, (_) => const DonationAdminHomeScreen()),
            ),
            _DrawerItem(
              label: 'Records',
              selected: widget.active == AdminModule.records,
              onTap: () => _openModule(context, (_) => const AnimalRecordsPage()),
            ),
            _DrawerItem(
              label: 'Events',
              selected: widget.active == AdminModule.events,
              onTap: () => _openModule(context, (_) => const AdminEventsPage()),
            ),
            _DrawerItem(
              label: 'Volunteers',
              selected: widget.active == AdminModule.volunteers,
              onTap: () => _openModule(context, (_) => const VolunteersPage()),
            ),
            _DrawerItem(label: 'Transporters', selected: widget.active == AdminModule.transporters, onTap: () {}),
            _DrawerItem(
              label: 'Collar Tags',
              selected: widget.active == AdminModule.collarTags,
              onTap: () => _openModule(context, (_) => const AdminCollarTagScreen()),
            ),
            _DrawerItem(
              label: 'Audit',
              selected: widget.active == AdminModule.audit,
              onTap: () => _openModule(context, (_) => const AuditPage()),
            ),
            const Divider(color: Colors.white24),
            _DrawerItem(
              label: 'Organization Profile',
              loading: _openingOrgProfile,
              onTap: _openingOrgProfile ? null : _handleOpenOrganizationProfile,
            ),

            const Spacer(),

            // Log out
            Padding(
              padding: const EdgeInsets.all(20),
              child: GestureDetector(
                onTap: _signingOut ? null : _logOut,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Log out',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            color: _signingOut ? Colors.redAccent.withValues(alpha: 0.5) : Colors.redAccent,
                            fontWeight: FontWeight.w600)),
                    if (_signingOut) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool selected;
  // Shows a spinner instead of the chevron and disables taps — used by
  // Organization Profile while its async membership lookup resolves, so a
  // slow lookup reads as "in progress" instead of "nothing happened",
  // and can't be re-triggered by an impatient repeated tap.
  final bool loading;

  const _DrawerItem({required this.label, required this.onTap, this.selected = false, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: selected ? AppColors.background.withValues(alpha: 0.12) : null,
      child: ListTile(
        onTap: onTap,
        leading: selected ? const Icon(Icons.circle, size: 8, color: AppColors.yellowrspwn) : const SizedBox(width: 8),
        title: Text(label,
            style: GoogleFonts.zain(
                fontSize: 15,
                color: AppColors.background,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
        trailing: loading
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
            : const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
        dense: true,
      ),
    );
  }
}
