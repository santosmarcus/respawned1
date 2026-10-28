import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';

/// Admin-entered shelter numbers the dashboard needs: safe capacity,
/// isolation spots, monthly care budget, daily food use and how many riders
/// the organization wants free at once.
///
/// Stored in the shared `settings/shelter` document — the SAME document
/// the dev branch's Organization Profile "Shelter Capacity" field and its
/// dashboard Capacity card already use (`maxCapacity`). This sheet only
/// adds sibling fields to that document with a merge write; it never
/// overwrites anything else there. Every value is nullable — a missing
/// value means "not set", never zero, and the dashboard shows a setup
/// prompt instead of guessing.
class ShelterSettings {
  final int? capacity;
  final int? isolationCapacity;
  final double? monthlyBudget;
  final double? foodPerDayKg;
  final int? ridersNeeded;
  final DateTime? updatedAt;
  final String? updatedByName;

  const ShelterSettings({
    this.capacity,
    this.isolationCapacity,
    this.monthlyBudget,
    this.foodPerDayKg,
    this.ridersNeeded,
    this.updatedAt,
    this.updatedByName,
  });

  static const empty = ShelterSettings();

  bool get isConfigured => capacity != null;

  factory ShelterSettings.fromMap(Map<String, dynamic>? m) {
    if (m == null) return empty;
    final ts = m['updatedAt'];
    return ShelterSettings(
      capacity: (m['maxCapacity'] as num?)?.toInt(),
      isolationCapacity: (m['isolationCapacity'] as num?)?.toInt(),
      monthlyBudget: (m['monthlyBudget'] as num?)?.toDouble(),
      foodPerDayKg: (m['foodPerDayKg'] as num?)?.toDouble(),
      ridersNeeded: (m['ridersNeeded'] as num?)?.toInt(),
      updatedAt: ts is Timestamp ? ts.toDate() : null,
      updatedByName: m['updatedByName'] as String?,
    );
  }
}

/// The signed-in admin's organization id from `users/{uid}.organizationId`
/// — the same field AdminHomeScreen and OrgMembershipService already read.
final dashboardOrgIdProvider = StreamProvider.autoDispose<String?>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance.collection('users').doc(uid).snapshots().map((d) {
    final id = d.data()?['organizationId'] as String?;
    return (id == null || id.isEmpty) ? null : id;
  });
});

final shelterSettingsProvider = StreamProvider.autoDispose<ShelterSettings>((ref) {
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('shelter')
      .snapshots()
      .map((d) => ShelterSettings.fromMap(d.data()));
});

Future<void> saveShelterSettings({
  required int capacity,
  required int isolationCapacity,
  double? monthlyBudget,
  double? foodPerDayKg,
  int? ridersNeeded,
}) {
  final user = FirebaseAuth.instance.currentUser;
  return FirebaseFirestore.instance.collection('settings').doc('shelter').set({
    'maxCapacity': capacity,
    'isolationCapacity': isolationCapacity,
    'monthlyBudget': monthlyBudget,
    'foodPerDayKg': foodPerDayKg,
    'ridersNeeded': ridersNeeded,
    'updatedAt': FieldValue.serverTimestamp(),
    'updatedBy': user?.uid,
    'updatedByName': user?.displayName,
  }, SetOptions(merge: true));
}

/// Opens the setup sheet. Only admins who can manage the organization
/// (same UI gate as the Donations module) may save; others see why not.
Future<void> showShelterSetupSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => const _ShelterSetupSheet(),
  );
}

class _ShelterSetupSheet extends ConsumerStatefulWidget {
  const _ShelterSetupSheet();

  @override
  ConsumerState<_ShelterSetupSheet> createState() => _ShelterSetupSheetState();
}

class _ShelterSetupSheetState extends ConsumerState<_ShelterSetupSheet> {
  int _capacity = 20;
  int _isolation = 2;
  int _riders = 2;
  double _foodKg = 3;
  final _budget = TextEditingController();
  bool _seeded = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _budget.dispose();
    super.dispose();
  }

  void _seed(ShelterSettings s) {
    if (_seeded) return;
    _seeded = true;
    _capacity = s.capacity ?? _capacity;
    _isolation = s.isolationCapacity ?? _isolation;
    _riders = s.ridersNeeded ?? _riders;
    _foodKg = s.foodPerDayKg ?? _foodKg;
    if (s.monthlyBudget != null) _budget.text = s.monthlyBudget!.round().toString();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await saveShelterSettings(
        capacity: _capacity,
        isolationCapacity: _isolation,
        monthlyBudget: double.tryParse(_budget.text.replaceAll(',', '')),
        foodPerDayKg: _foodKg,
        ridersNeeded: _riders,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final current = ref.watch(shelterSettingsProvider).asData?.value;
    if (current != null) _seed(current);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: const Color(0xFFCFCBBE), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.house, size: 36, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 10),
              Text('Set up your shelter', textAlign: TextAlign.center, style: dashTitle(21)),
              const SizedBox(height: 4),
              Text(
                'These answer “can we take more?”, “will money last?” and “how long will food last?”.',
                textAlign: TextAlign.center,
                style: dashMuted(14),
              ),
              const SizedBox(height: 14),
              _StepField(
                icon: Icons.pets,
                title: 'Spaces',
                hint: 'Animals you can safely house',
                value: '$_capacity',
                onMinus: () => setState(() => _capacity = (_capacity - 1).clamp(1, 999)),
                onPlus: () => setState(() => _capacity = (_capacity + 1).clamp(1, 999)),
              ),
              _StepField(
                icon: Icons.medical_services,
                title: 'Isolation',
                hint: 'Quarantine spots',
                value: '$_isolation',
                onMinus: () => setState(() => _isolation = (_isolation - 1).clamp(0, 99)),
                onPlus: () => setState(() => _isolation = (_isolation + 1).clamp(0, 99)),
              ),
              _FieldShell(
                icon: Icons.account_balance_wallet,
                title: 'Monthly budget',
                hint: 'Care, food & vet',
                trailing: SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _budget,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    textAlign: TextAlign.right,
                    style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary),
                    decoration: const InputDecoration(prefixText: '₱ ', hintText: 'Not set', isDense: true),
                  ),
                ),
              ),
              _StepField(
                icon: Icons.rice_bowl,
                title: 'Food per day',
                hint: 'All animals together',
                value: '${_foodKg % 1 == 0 ? _foodKg.toInt() : _foodKg} kg',
                onMinus: () => setState(() => _foodKg = (_foodKg - 0.5).clamp(0.5, 999)),
                onPlus: () => setState(() => _foodKg = (_foodKg + 0.5).clamp(0.5, 999)),
              ),
              _StepField(
                icon: Icons.two_wheeler,
                title: 'Riders needed',
                hint: 'Free at once, ideally',
                value: '$_riders',
                onMinus: () => setState(() => _riders = (_riders - 1).clamp(0, 99)),
                onPlus: () => setState(() => _riders = (_riders + 1).clamp(0, 99)),
              ),
              if (current?.updatedAt != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Last updated ${current!.updatedAt!.day}/${current.updatedAt!.month}/${current.updatedAt!.year}'
                        '${current.updatedByName == null ? '' : ' by ${current.updatedByName}'}'
                        '${current.monthlyBudget == null ? '' : ' · budget ${formatPeso(current.monthlyBudget!)}'}',
                    textAlign: TextAlign.center,
                    style: dashMuted(),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_error!, style: dashBody(color: Colors.red)),
                ),
              if (!canManage)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: RestrictedNotice('Only organization admins can change shelter settings.'),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      child: Text('Later', style: dashBody(size: 15, weight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 48),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: (!canManage || _saving) ? null : _save,
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : Text(
                        'Save',
                        style: dashBody(size: 15, weight: FontWeight.w700, color: AppColors.background),
                      ),
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
}

class _FieldShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final Widget trailing;
  const _FieldShell({required this.icon, required this.title, required this.hint, required this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: dashBody(size: 15, weight: FontWeight.w700)),
                Text(hint, style: dashMuted()),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}

class _StepField extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  const _StepField({
    required this.icon,
    required this.title,
    required this.hint,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, VoidCallback onTap, String label) => Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.2), width: 1.5),
          ),
          child: Icon(i, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
    return _FieldShell(
      icon: icon,
      title: title,
      hint: hint,
      trailing: Row(
        children: [
          btn(Icons.remove, onMinus, 'Decrease $title'),
          SizedBox(
            width: 52,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary),
            ),
          ),
          btn(Icons.add, onPlus, 'Increase $title'),
        ],
      ),
    );
  }
}
