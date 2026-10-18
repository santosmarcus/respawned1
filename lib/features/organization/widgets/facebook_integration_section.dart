import 'package:flutter/material.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/facebook_integration.dart';
import 'package:respawnd1/core/repos/facebook_integration_repository.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Organization Profile's "Facebook Page Integration" section (Facebook
/// Page Sharing spec §4). Embedded as a standalone [ConsumerStatefulWidget]
/// inside organization_profile_edit_page.dart's existing plain-Column
/// build() rather than converting that whole page to a ConsumerStatefulWidget
/// itself — same "small composable section" pattern already used elsewhere
/// in this codebase (community_report_section.dart) to avoid widening an
/// unrelated file's diff.
///
/// [canManage] gates connect/reconnect/disconnect/test-connection —
/// Owner/Admin only per the Facebook Page Publishing Compatibility spec.
/// Viewing basic connection status stays visible to any active member; a
/// failed load here never blocks the rest of Organization Profile (this
/// widget owns its own loading/error/empty/data states independently).
class FacebookIntegrationSection extends ConsumerStatefulWidget {
  final String organizationId;
  final bool canManage;
  const FacebookIntegrationSection({super.key, required this.organizationId, required this.canManage});

  @override
  ConsumerState<FacebookIntegrationSection> createState() => _FacebookIntegrationSectionState();
}

class _FacebookIntegrationSectionState extends ConsumerState<FacebookIntegrationSection> {
  bool _busy = false;

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: isError ? Colors.redAccent : AppColors.greenrspwn),
    );
  }

  String? _friendlyLoginError(LoginStatus status) => switch (status) {
        LoginStatus.cancelled => null, // user backed out — not an error to report
        LoginStatus.failed => 'Facebook login failed. Please try again.',
        LoginStatus.operationInProgress => 'A Facebook login is already in progress.',
        LoginStatus.success => null,
      };

  Future<void> _connect() async {
    setState(() => _busy = true);
    try {
      final result = await FacebookAuth.instance.login(
        permissions: const ['pages_show_list', 'pages_read_engagement', 'pages_manage_posts'],
      );
      if (result.status != LoginStatus.success) {
        final message = _friendlyLoginError(result.status);
        if (message != null) _showMessage(message, isError: true);
        return;
      }
      final accessToken = result.accessToken;
      final tokenString = accessToken?.tokenString;
      if (tokenString == null || tokenString.isEmpty) {
        _showMessage('Could not read the Facebook login result. Please try again.', isError: true);
        return;
      }

      final connectResult = await ref.read(facebookIntegrationRepositoryProvider).connect(
            organizationId: widget.organizationId,
            userAccessToken: tokenString,
          );
      if (!mounted) return;
      if (connectResult.selectionRequired) {
        await _pickPage(connectResult.requestId!, connectResult.pages);
      } else {
        _showMessage('Facebook Page connected.');
      }
    } on FacebookOperationException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not connect to Facebook. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickPage(String requestId, List<FacebookPageOption> pages) async {
    final selected = await showModalBottomSheet<FacebookPageOption>(
      context: context,
      backgroundColor: AppColors.background,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Select a Page', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            ),
            for (final p in pages)
              ListTile(
                leading: p.pagePictureUrl != null
                    ? CircleAvatar(backgroundImage: NetworkImage(p.pagePictureUrl!))
                    : const CircleAvatar(child: Icon(Icons.facebook)),
                title: Text(p.pageName),
                subtitle: p.pageUsername != null ? Text('@${p.pageUsername}') : null,
                onTap: () => Navigator.pop(ctx, p),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(facebookIntegrationRepositoryProvider).confirmPageSelection(
            organizationId: widget.organizationId,
            requestId: requestId,
            pageId: selected.pageId,
          );
      _showMessage('Facebook Page connected.');
    } on FacebookOperationException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not finish connecting this Page. Please try again.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _busy = true);
    try {
      await ref.read(facebookIntegrationRepositoryProvider).testConnection(widget.organizationId);
      _showMessage('Facebook Page connection is working.');
    } on FacebookOperationException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not test the Facebook connection.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: const Text('Disconnect Facebook Page?'),
        content: const Text(
          'ResPAWnd will no longer be able to publish Animal Records to this Page. This does not remove ResPAWnd from the Page on Facebook\'s side — do that from Facebook Business Settings if needed.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Disconnect'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await ref.read(facebookIntegrationRepositoryProvider).disconnect(widget.organizationId);
      _showMessage('Facebook Page disconnected.');
    } on FacebookOperationException catch (e) {
      _showMessage(e.message, isError: true);
    } catch (_) {
      _showMessage('Could not disconnect the Facebook Page.', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _viewPage(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final integrationAsync = ref.watch(organizationFacebookIntegrationProvider(widget.organizationId));

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Facebook Page Integration', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          integrationAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            error: (e, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not load Facebook connection status.',
                    style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: () => ref.invalidate(organizationFacebookIntegrationProvider(widget.organizationId)),
                  child: const Text('Retry'),
                ),
              ],
            ),
            data: (integration) => _buildForStatus(integration),
          ),
        ],
      ),
    );
  }

  Widget _buildForStatus(FacebookIntegration? integration) {
    if (integration == null || integration.connectionStatus == 'disconnected') {
      return _row(
        title: 'Facebook Page',
        subtitle: 'Not connected',
        actions: widget.canManage
            ? [_actionButton('Connect Facebook Page', _connect, primary: true)]
            : const [],
      );
    }
    if (integration.connectionStatus == 'error') {
      return _row(
        title: 'Facebook Page connection needs attention.',
        subtitle: integration.pageName,
        actions: widget.canManage
            ? [_actionButton('Reconnect', _connect, primary: true), _actionButton('View Details', _testConnection)]
            : const [],
      );
    }
    // connected
    return _row(
      title: integration.pageName,
      subtitle: 'Connected',
      actions: [
        _actionButton('View Page', () => _viewPage(integration.pageUrl)),
        if (widget.canManage) ...[
          _actionButton('Test Connection', _testConnection),
          _actionButton('Reconnect', _connect),
          _actionButton('Disconnect', _disconnect, isDestructive: true),
        ],
      ],
    );
  }

  Widget _row({required String title, required String subtitle, required List<Widget> actions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        Text(subtitle, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
        if (!widget.canManage)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Only an Organization Owner or Admin can manage the connected Facebook Page.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _actionButton(String label, VoidCallback onTap, {bool primary = false, bool isDestructive = false}) {
    final child = _busy
        ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2))
        : Text(label, style: const TextStyle(fontSize: 12));
    if (primary) {
      return ElevatedButton(
        onPressed: _busy ? null : onTap,
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.yellowrspwn, foregroundColor: AppColors.textPrimary),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: _busy ? null : onTap,
      style: isDestructive
          ? OutlinedButton.styleFrom(foregroundColor: Colors.redAccent, side: const BorderSide(color: Colors.redAccent))
          : null,
      child: child,
    );
  }
}
