import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/features/donation/models.dart';

/// The four transparent readiness states. There is no overall score: the
/// card names which factors cause a constraint, and the decision to accept
/// a rescue always stays with the admin.
enum ReadinessState {
  confirmed,
  constrained,
  incomplete,
  adminAssess;

  String get label => switch (this) {
    ReadinessState.confirmed => 'Confirmed',
    ReadinessState.constrained => 'Constrained',
    ReadinessState.incomplete => 'Info incomplete',
    ReadinessState.adminAssess => 'Admin to assess',
  };

  ChipTone get tone => switch (this) {
    ReadinessState.confirmed => ChipTone.green,
    ReadinessState.constrained => ChipTone.amber,
    ReadinessState.incomplete => ChipTone.notRecorded,
    ReadinessState.adminAssess => ChipTone.info,
  };

  IconData get icon => switch (this) {
    ReadinessState.confirmed => Icons.check,
    ReadinessState.constrained => Icons.warning_rounded,
    ReadinessState.incomplete => Icons.question_mark,
    ReadinessState.adminAssess => Icons.psychology_outlined,
  };
}

class ReadinessFactor {
  final IconData icon;
  final String name;
  final String detail;
  final ReadinessState state;
  const ReadinessFactor(this.icon, this.name, this.detail, this.state);
}

const _inShelterColor = Color(0xFF2E2C25);
const _atVetColor = AppColors.lavenderrspwn;
const _isolationColor = Color(0xFFE9B8F7);
const _freeColor = Color(0xFFE2DFD6);

class RescueReadinessCard extends ConsumerWidget {
  const RescueReadinessCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occAsync = ref.watch(shelterOccupancyProvider);
    final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    final supply = ref.watch(transportSupplyProvider).asData?.value;
    final records = ref.watch(allAnimalRecordsProvider).asData?.value;
    final canManage = ref.watch(canManageFinancesProvider).asData?.value ?? false;
    final campaigns = ref.watch(adminCampaignsProvider).asData?.value;

    return SectionCard(
      icon: Icons.dashboard,
      title: 'Rescue readiness',
      trailing: const StatusChip('Admin to assess', tone: ChipTone.info, icon: Icons.psychology_outlined),
      child: DashAsync<ShelterOccupancy>(
        value: occAsync,
        what: 'shelter space',
        builder: (occ) {
          final factors = _factors(
            occ: occ,
            settings: settings,
            snap: snap,
            supply: supply,
            records: records,
            canManage: canManage,
            campaigns: campaigns,
          );
          final limiting = factors
              .where((f) => f.state == ReadinessState.constrained)
              .map((f) => f.name.toLowerCase())
              .toList();
          final message = limiting.isNotEmpty
              ? '${plural(limiting.length, 'factor')} ${limiting.length == 1 ? 'limits' : 'limit'} the next rescue: ${limiting.join(', ')}'
              : factors.any((f) => f.state == ReadinessState.incomplete)
              ? 'No constraint found, but some information is missing'
              : 'No recorded factor limits the next rescue';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!settings.isConfigured)
                _SetupPrompt(onTap: () => showShelterSetupSheet(context))
              else
                _Gauge(occ: occ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
                decoration: BoxDecoration(color: AppColors.textPrimary, borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      limiting.isEmpty ? Icons.info_outline : Icons.warning_rounded,
                      size: 17,
                      color: AppColors.yellowrspwn,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        message,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.zain(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.background,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              for (int i = 0; i < factors.length; i++) _FactorRow(factor: factors[i], first: i == 0),
              const SizedBox(height: 10),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  minimumSize: const Size.fromHeight(46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => openRescueTab(context, ref, RescuePipelineTab.review),
                icon: const Icon(Icons.fact_check, size: 18, color: AppColors.background),
                label: Text(
                  'Assess an incoming report',
                  style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.background),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text('Supports your decision. It never rejects a rescue on its own.', style: dashMuted()),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<ReadinessFactor> _factors({
    required ShelterOccupancy occ,
    required ShelterSettings settings,
    required RescueSnapshot? snap,
    required TransportSupply? supply,
    required List<AnimalRecord>? records,
    required bool canManage,
    required List<DonationListing>? campaigns,
  }) {
    // Space — physical capacity only; the other factors cover care.
    final free = occ.free;
    final ReadinessFactor space;
    if (free == null) {
      space = const ReadinessFactor(Icons.house, 'Space', 'Shelter capacity not set', ReadinessState.incomplete);
    } else {
      final iso = occ.isolationCapacity == null
          ? 'isolation not set'
          : (occ.isolationFull ? 'isolation full' : 'isolation ${occ.isolation}/${occ.isolationCapacity}');
      space = ReadinessFactor(
        Icons.house,
        'Space',
        '${free < 0 ? 'Over capacity by ${-free}' : '$free general ${free == 1 ? 'space' : 'spaces'}'} · $iso',
        free <= 0 || occ.isolationFull ? ReadinessState.constrained : ReadinessState.confirmed,
      );
    }

    // Transport — free riders vs. cases already waiting.
    final waiting = snap?.count(RescueStage.transporter);
    final ReadinessFactor transport;
    if (supply == null || waiting == null) {
      transport = const ReadinessFactor(
        Icons.local_shipping,
        'Transport',
        'Loading riders…',
        ReadinessState.incomplete,
      );
    } else {
      final target = settings.ridersNeeded;
      transport = ReadinessFactor(
        Icons.local_shipping,
        'Transport',
        '${supply.free} of ${supply.registered} riders free · ${plural(waiting, 'case')} waiting'
            '${target == null ? '' : ' · target $target'}',
        (supply.free == 0 || waiting >= supply.free || (target != null && supply.free < target))
            ? ReadinessState.constrained
            : ReadinessState.confirmed,
      );
    }

    // Care coverage — carer schedules aren't recorded anywhere yet.
    const care = ReadinessFactor(
      Icons.groups,
      'Care coverage',
      'Carer schedules aren’t recorded yet',
      ReadinessState.incomplete,
    );

    // Vet access — a clinic has been used on an active case.
    final clinics = snap == null
        ? <String>{}
        : snap.all.where((c) => c.hasSavedClinic).map((c) => c.vetClinicName!).toSet();
    final vet = clinics.isEmpty
        ? const ReadinessFactor(
      Icons.local_hospital,
      'Vet access',
      'No clinic on any active case',
      ReadinessState.incomplete,
    )
        : ReadinessFactor(Icons.local_hospital, 'Vet access', clinics.take(2).join(' & '), ReadinessState.confirmed);

    // Food & medicine — only in-kind pledges are recorded, not stock.
    double foodKg = 0;
    for (final c in campaigns ?? const <DonationListing>[]) {
      for (final i in c.inKindItems) {
        if (i.category.toLowerCase().contains('food') && (i.unit ?? '').toLowerCase() == 'kg') {
          foodKg += i.quantityReceived;
        }
      }
    }
    final perDay = settings.foodPerDayKg;
    final food = ReadinessFactor(
      Icons.restaurant,
      'Food & medicine',
      foodKg > 0 && perDay != null
          ? '${foodKg.round()} kg donated ≈ ${(foodKg / perDay).floor()} days · stock not tracked'
          : 'Stock levels aren’t tracked yet',
      ReadinessState.incomplete,
    );

    // Funds — admins only; general (unrestricted) campaign balances.
    final ReadinessFactor funds;
    if (!canManage) {
      funds = const ReadinessFactor(Icons.lock, 'Funds', 'Visible to organization admins', ReadinessState.adminAssess);
    } else if (campaigns == null) {
      funds = const ReadinessFactor(Icons.account_balance_wallet, 'Funds', 'Loading…', ReadinessState.incomplete);
    } else {
      final general = campaigns
          .where((c) => !c.restricted && !c.isDraft && !c.isArchived)
          .fold<double>(0, (s, c) => s + (c.availableBalance > 0 ? c.availableBalance : 0));
      funds = ReadinessFactor(
        Icons.account_balance_wallet,
        'Funds',
        '${formatPeso(general)} general available${settings.monthlyBudget == null ? '' : ' · budget ${formatPeso(settings.monthlyBudget!)}/mo'}',
        general > 0 ? ReadinessState.confirmed : ReadinessState.constrained,
      );
    }

    // Continuing care — long-term needs already in care.
    final ongoing = (records ?? const <AnimalRecord>[])
        .where((a) => isInCare(a) && ((a.health.currentMedications ?? '').trim().isNotEmpty || a.specialNeeds))
        .length;
    final continuing = ReadinessFactor(
      Icons.medical_services,
      'Continuing care',
      ongoing == 0
          ? 'No ongoing medication or special needs recorded'
          : '${plural(ongoing, 'animal')} on medication or with special needs',
      ongoing == 0 ? ReadinessState.confirmed : ReadinessState.adminAssess,
    );

    return [space, transport, care, vet, food, funds, continuing];
  }
}

class _FactorRow extends StatelessWidget {
  final ReadinessFactor factor;
  final bool first;
  const _FactorRow({required this.factor, required this.first});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(9)),
            child: Icon(factor.icon, size: 18, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(factor.name, style: dashBody(size: 14.5, weight: FontWeight.w700)),
                Text(factor.detail, style: dashMuted(12.5)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          StatusChip(factor.state.label, tone: factor.state.tone, icon: factor.state.icon),
        ],
      ),
    );
  }
}

class _SetupPrompt extends StatelessWidget {
  final VoidCallback onTap;
  const _SetupPrompt({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textPrimary, width: 1.3),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.tune, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Shelter capacity isn’t set', style: dashBody(size: 15, weight: FontWeight.w700)),
                Text('Add spaces, isolation, budget and food use so readiness can judge space.', style: dashMuted()),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.textPrimary, minimumSize: const Size(0, 40)),
            onPressed: onTap,
            child: Text(
              'Set up',
              style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.background),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reference-style thick, segmented half-circle: in shelter / at vet /
/// isolation / free, with the used count in the middle.
class _Gauge extends StatelessWidget {
  final ShelterOccupancy occ;
  const _Gauge({required this.occ});

  @override
  Widget build(BuildContext context) {
    final cap = occ.capacity!;
    final free = (occ.free ?? 0).clamp(0, cap);
    return Column(
      children: [
        Semantics(
          label: '${occ.used} of $cap spaces in use, ${occ.arriving} arriving',
          child: SizedBox(
            height: 160,
            width: 300,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                CustomPaint(
                  size: const Size(300, 156),
                  painter: _GaugePainter([
                    (occ.inShelter, _inShelterColor),
                    (occ.atVet, _atVetColor),
                    (occ.isolation, _isolationColor),
                    (occ.arriving, const Color(0xFFC2B500)),
                    (free, _freeColor),
                  ], cap),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${occ.used}',
                            style: GoogleFonts.tiltWarp(fontSize: 34, color: AppColors.textPrimary),
                          ),
                          TextSpan(
                            text: '/$cap',
                            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    Text('spaces in use', style: dashMuted(14)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            _Legend(_inShelterColor, 'In shelter ${occ.inShelter}'),
            _Legend(_atVetColor, 'At vet ${occ.atVet}'),
            _Legend(
              _isolationColor,
              occ.isolationCapacity == null
                  ? 'Isolation ${occ.isolation}'
                  : 'Isolation ${occ.isolation}/${occ.isolationCapacity}',
            ),
            if (occ.arriving > 0) _Legend(const Color(0xFFC2B500), 'Arriving ${occ.arriving}'),
            _Legend(_freeColor, 'Free $free'),
          ],
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  final Color color;
  final String text;
  const _Legend(this.color, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 5),
        Text(text, style: dashBody(size: 13, weight: FontWeight.w700)),
      ],
    );
  }
}

class _GaugePainter extends CustomPainter {
  final List<(int, Color)> parts;
  final int capacity;
  _GaugePainter(this.parts, this.capacity);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height - 4);
    const outer = 132.0;
    const inner = 80.0;
    final total = math.max(capacity, parts.fold<int>(0, (s, p) => s + p.$1));
    if (total <= 0) return;
    const gap = 0.025;
    double start = math.pi;
    for (final (n, color) in parts) {
      if (n <= 0) continue;
      final sweep = math.pi * n / total;
      final a0 = start + gap / 2;
      final a1 = start + sweep - gap / 2;
      if (a1 > a0) {
        final path = Path()
          ..arcTo(Rect.fromCircle(center: center, radius: outer), a0, a1 - a0, true)
          ..arcTo(Rect.fromCircle(center: center, radius: inner), a1, -(a1 - a0), false)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter old) => old.parts != parts || old.capacity != capacity;
}
