import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/organization/organization_capabilities.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/core/services/known_accounts.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/core/widgets/delete_account.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Signs out and returns to the app's root, which shows the login screen.
/// Uses the ProviderContainer (it outlives the screen that called this) to
/// clear the organization providers.
Future<void> signOutToLogin(BuildContext context) async {
  final rootNavigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final container = ProviderScope.containerOf(context, listen: false);
  try {
    await authService.value.signOut();
    container.invalidate(currentOrgMembershipProvider);
    container.invalidate(currentOrganizationCapabilitiesProvider);
    rootNavigator.popUntil((route) => route.isFirst);
  } catch (e) {
    messenger?.showSnackBar(appSnackBar('Log out failed: $e', kind: AppMessageKind.error));
  }
}

/// Signs out and asks the login screen to sign [account] in (it fills in the
/// email, opens Google's chooser, or opens phone sign-in).
Future<void> switchToAccount(BuildContext context, KnownAccount? account) async {
  KnownAccounts.pendingSwitch.value = account;
  await signOutToLogin(context);
}

/// Account details, the other accounts signed in on this device (Switch
/// account), log out and delete account. The same page for every account
/// type: opened from the admin drawer, the care-tasks screen, the general
/// and transporter/volunteer profiles, the system admin menu and the
/// organization sign-up screens.
///
/// [returnToDashboard]: back closes every screen above the app's first one
/// (the admin drawer opens modules on top of each other). Off, back just
/// closes this page, returning to the profile that opened it.
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key, this.returnToDashboard = true});

  final bool returnToDashboard;

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  late Future<List<KnownAccount>> _known = KnownAccounts.load();
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forget(KnownAccount a) async {
    await KnownAccounts.forget(a.uid);
    setState(() => _known = KnownAccounts.load());
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final caps = ref.watch(currentOrganizationCapabilitiesProvider).asData?.value ?? OrganizationCapabilities.none;
    final orgName = ref.watch(currentOrganizationHeaderProvider).asData?.value?.name;
    // Back (the arrow or the system gesture) returns to the dashboard, the
    // app's first screen, unless this page was opened from a profile.
    void backToDashboard() => Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
    return PopScope(
      canPop: !widget.returnToDashboard,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) backToDashboard();
      },
      child: Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        foregroundColor: AppColors.background,
        leading: IconButton(
          tooltip: widget.returnToDashboard ? 'Back to dashboard' : 'Back',
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: widget.returnToDashboard ? backToDashboard : () => Navigator.of(context).maybePop(),
        ),
        title: Text('Account', style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.background)),
      ),
      body: user == null
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
              builder: (context, snap) {
                final data = snap.data?.data() ?? const <String, dynamic>{};
                final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
                final photo = (data['photoUrl'] as String?) ?? user.photoURL;
                final phone = ((data['phone'] as String?) ?? '').isNotEmpty ? data['phone'] as String : (user.phoneNumber ?? '');
                final created = data['createdAt'];
                final joined = created is Timestamp ? created.toDate() : user.metadata.creationTime;
                final role = !caps.isActive
                    ? null
                    : caps.isAdmin
                        ? 'Admin'
                        : 'Staff · ${(caps.preset ?? OrgPreset.custom).label}';
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: AppColors.yellowrspwn,
                          backgroundImage: photo != null && photo.startsWith('http') ? NetworkImage(photo) : null,
                          child: photo != null && photo.startsWith('http')
                              ? null
                              : Text(
                                  (name.isNotEmpty ? name : (user.email ?? '?')).characters.first.toUpperCase(),
                                  style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary),
                                ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name.isNotEmpty ? name : 'Your account',
                                  style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
                              if (role != null)
                                Text(role, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _Card(
                      title: 'Details',
                      children: [
                        if ((user.email ?? '').isNotEmpty) _Line(Icons.mail_outline, 'Email', user.email!),
                        if (phone.isNotEmpty) _Line(Icons.phone_outlined, 'Phone', phone),
                        if (orgName != null) _Line(Icons.apartment_outlined, 'Organization', orgName),
                        if (role != null) _Line(Icons.badge_outlined, 'Role', role),
                        _Line(Icons.login, 'Signs in with', _methodLabel(user)),
                        if (joined != null) _Line(Icons.event_outlined, 'Joined', formatDate(joined)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _Card(
                      title: 'Switch account',
                      children: [
                        FutureBuilder<List<KnownAccount>>(
                          future: _known,
                          builder: (context, s) {
                            final others = (s.data ?? const <KnownAccount>[]).where((a) => a.uid != user.uid).toList();
                            return Column(
                              children: [
                                if (others.isEmpty && s.hasData)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('No other accounts have signed in on this device.',
                                        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                                  ),
                                for (final a in others)
                                  ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    enabled: !_busy,
                                    leading: CircleAvatar(
                                      backgroundColor: AppColors.tearspwn,
                                      backgroundImage: a.photoUrl != null ? NetworkImage(a.photoUrl!) : null,
                                      child: a.photoUrl != null
                                          ? null
                                          : Text(a.name.isNotEmpty ? a.name.characters.first.toUpperCase() : '?'),
                                    ),
                                    title: Text(a.name, style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
                                    subtitle: Text(a.contact, style: GoogleFonts.zain(fontSize: 13)),
                                    onTap: () => _run(() => switchToAccount(context, a)),
                                    trailing: IconButton(
                                      tooltip: 'Remove from this device',
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: _busy ? null : () => _forget(a),
                                    ),
                                  ),
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  enabled: !_busy,
                                  leading: const CircleAvatar(
                                    backgroundColor: AppColors.slaterspwn,
                                    child: Icon(Icons.person_add_alt, color: AppColors.textPrimary),
                                  ),
                                  title: Text('Add another account',
                                      style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700)),
                                  onTap: () => _run(() => switchToAccount(context, null)),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _run(() => signOutToLogin(context)),
                      icon: const Icon(Icons.logout, color: AppColors.error),
                      label: Text('Log out', style: GoogleFonts.zain(fontSize: 15, color: AppColors.error, fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : () => showDeleteAccountFlow(context),
                      child: Text('Delete account',
                          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
                    ),
                  ],
                );
              },
            ),
    ),
    );
  }

  static String _methodLabel(User user) {
    final providers = user.providerData.map((p) => p.providerId).toSet();
    if (providers.contains('password')) return 'Email and password';
    if (providers.contains('google.com')) return 'Google';
    if (providers.contains('phone')) return 'Mobile number (SMS code)';
    return 'Other';
  }
}

/// Opens [AccountPage] (details, Switch account, Log out) from a screen's
/// app bar. [color] matches the app bar's foreground.
class AccountButton extends StatelessWidget {
  const AccountButton({super.key, this.color = AppColors.textPrimary, this.returnToDashboard = false});

  final Color color;
  final bool returnToDashboard;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Account',
        icon: Icon(Icons.account_circle_outlined, color: color),
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => AccountPage(returnToDashboard: returnToDashboard)),
        ),
      );
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(label, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value,
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
