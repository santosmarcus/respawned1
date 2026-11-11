import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/rescue_readiness.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';

/// What the admin confirmed in the Accept Case sheet.
class AcceptCaseResult {
  const AcceptCaseResult({
    required this.openForTransfer,
    required this.readinessSnapshot,
  });

  /// Optional flag: this case may be handed to another organization.
  final bool openForTransfer;

  /// Stored on the case as `readinessSnapshot`: the factors the admin saw
  /// when accepting, plus their note. Acceptance is not blocked by any
  /// constraint; the decision stays with the admin.
  final Map<String, dynamic> readinessSnapshot;
}

/// Accept Case modal. Accepting always means "handled by our organization".
/// Shows the same readiness factors as the dashboard card (capacity, transport,
/// vet access, funds, continuing care), so the decision is made against them.
/// Returns null if dismissed without confirming.
Future<AcceptCaseResult?> showAcceptCaseSheet(BuildContext context) {
  return showModalBottomSheet<AcceptCaseResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _AcceptCaseSheetBody(),
  );
}

class _AcceptCaseSheetBody extends ConsumerStatefulWidget {
  const _AcceptCaseSheetBody();

  @override
  ConsumerState<_AcceptCaseSheetBody> createState() => _AcceptCaseSheetBodyState();
}

class _AcceptCaseSheetBodyState extends ConsumerState<_AcceptCaseSheetBody> {
  bool _openForTransfer = false;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _confirm(List<ReadinessFactor> factors, {required bool unavailable}) {
    final note = _noteController.text.trim();
    Navigator.pop(
      context,
      AcceptCaseResult(
        openForTransfer: _openForTransfer,
        readinessSnapshot: {
          'factors': [
            for (final f in factors)
              {'name': f.name, 'detail': f.detail, 'state': f.state.name},
          ],
          'note': note,
          // Readiness couldn't load; the admin accepted without it.
          if (unavailable) 'unavailable': true,
          'capturedAt': Timestamp.now(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final occAsync = ref.watch(shelterOccupancyProvider);
    final occ = occAsync.asData?.value;
    // A readiness error must never block accepting a case.
    final failed = occ == null && occAsync.hasError;
    final loading = occ == null && !failed;
    final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    final supply = ref.watch(transportSupplyProvider).asData?.value;
    final records = ref.watch(allAnimalRecordsProvider).asData?.value;
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final campaigns = ref.watch(adminCampaignsProvider).asData?.value;

    final factors = occ == null
        ? const <ReadinessFactor>[]
        : RescueReadinessCard.buildFactors(
            occ: occ,
            settings: settings,
            snap: snap,
            supply: supply,
            records: records,
            canManage: canManage,
            campaigns: campaigns,
          );

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Accept Case',
                style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Check capacity before accepting. The decision is yours.',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            _ReadinessList(occ: occ, factors: factors, failed: failed),
            const SizedBox(height: 14),
            TextField(
              controller: _noteController,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: 'Admin note (optional)',
                hintText: 'Why accepting now, or what to watch',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.slaterspwn),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Open for transfer to another organization',
                            style: GoogleFonts.zain(
                                fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          'Optional. Flags this case as available for another org to take on. '
                          'No transfer listing or matching yet — this only saves the flag for now.',
                          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _openForTransfer,
                    activeThumbColor: AppColors.textPrimary,
                    onChanged: (v) => setState(() => _openForTransfer = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: loading ? null : () => _confirm(factors, unavailable: failed),
                style: AppButtons.primary,
                child: Text(loading ? 'Loading readiness…' : 'Accept Case',
                    style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessList extends StatelessWidget {
  const _ReadinessList({required this.occ, required this.factors, required this.failed});

  final ShelterOccupancy? occ;
  final List<ReadinessFactor> factors;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    if (failed) {
      return Text('Readiness couldn’t load. You can still accept; the case will note it.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.error));
    }
    if (occ == null) {
      return Text('Loading readiness…',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        children: [
          for (final f in factors)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(f.icon, size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(f.name,
                            style: GoogleFonts.zain(
                                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        Text(f.detail,
                            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Text(f.state.label,
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
