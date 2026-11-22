import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';

/// A system admin turns an independent rescuer's modules on or off and sets
/// its team size and capacity (setIndependentLimits,
/// functions/independent_rescuers.js). Rescue cases can't be turned off.
Future<void> showIndependentLimitsSheet(
  BuildContext context, {
  required String organizationId,
  required String name,
  OrganizationRepository? repository,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _IndependentLimitsSheet(
      organizationId: organizationId,
      name: name,
      repository: repository ?? OrganizationRepository(),
    ),
  );
}

class _IndependentLimitsSheet extends StatefulWidget {
  const _IndependentLimitsSheet({required this.organizationId, required this.name, required this.repository});

  final String organizationId;
  final String name;
  final OrganizationRepository repository;

  @override
  State<_IndependentLimitsSheet> createState() => _IndependentLimitsSheetState();
}

class _IndependentLimitsSheetState extends State<_IndependentLimitsSheet> {
  bool _loading = true;
  bool _saving = false;
  Set<OrgPermission> _enabled = {...IndependentRescuer.defaults};
  int _memberCap = IndependentRescuer.memberCap;
  int _maxCases = IndependentRescuer.maxActiveCases;
  int _maxAnimals = IndependentRescuer.maxAnimalsInCare;
  int _members = 1;
  int _cases = 0;
  int _animals = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = (await FirebaseFirestore.instance.collection('organizations').doc(widget.organizationId).get()).data();
    int n(String k, int fallback) => (d?[k] as num?)?.toInt() ?? fallback;
    if (!mounted) return;
    setState(() {
      _enabled = orgEnabledPermissions({...?d, 'kind': 'independent'});
      _memberCap = n('memberCap', IndependentRescuer.memberCap);
      _maxCases = n('maxActiveCases', IndependentRescuer.maxActiveCases);
      _maxAnimals = n('maxAnimalsInCare', IndependentRescuer.maxAnimalsInCare);
      _members = n('memberCount', 1);
      _cases = n('activeCaseCount', 0);
      _animals = n('animalsInCareCount', 0);
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.setIndependentLimits(
        organizationId: widget.organizationId,
        enabledPermissions: _enabled,
        memberCap: _memberCap,
        maxActiveCases: _maxCases,
        maxAnimalsInCare: _maxAnimals,
      );
      navigator.pop();
      messenger.showSnackBar(appSnackBar('Limits saved.', kind: AppMessageKind.success));
    } on FirebaseFunctionsException catch (e) {
      messenger.showSnackBar(appSnackBar(e.message ?? 'Could not save the limits.', kind: AppMessageKind.error));
      if (mounted) setState(() => _saving = false);
    } catch (e) {
      messenger.showSnackBar(appSnackBar('Could not save the limits: $e', kind: AppMessageKind.error));
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _stepper(String label, String hint, int value, int min, int max, ValueChanged<int> set) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(hint, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Less',
          onPressed: value > min ? () => setState(() => set(value - 1)) : null,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text('$value', textAlign: TextAlign.center, style: GoogleFonts.tiltWarp(fontSize: 16)),
        ),
        IconButton(
          tooltip: 'More',
          onPressed: value < max ? () => setState(() => set(value + 1)) : null,
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: _loading
          ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Modules & limits', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
                  Text(widget.name, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  Text('Modules', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  for (final p in OrgPermission.values.where(IndependentRescuer.allowed.contains))
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: AppColors.textPrimary,
                      value: _enabled.contains(p),
                      onChanged: p == OrgPermission.rescue
                          ? null
                          : (v) => setState(() => v == true ? _enabled.add(p) : _enabled.remove(p)),
                      title: Text(p.label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                      subtitle: Text(p.description, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  Text(
                    'Fundraising, donations, events and Facebook posting are never available to rescue volunteers.',
                    style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  const Divider(height: 24),
                  _stepper('Team size', 'Now $_members', _memberCap, 1, 10, (v) => _memberCap = v),
                  _stepper('Active cases at once', 'Now $_cases', _maxCases, 1, 20, (v) => _maxCases = v),
                  _stepper('Animals in care', 'Now $_animals', _maxAnimals, 0, 50, (v) => _maxAnimals = v),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: AppButtons.primary,
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text('Save', style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
    );
  }
}
