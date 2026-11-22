import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/core/constants/feature_flags.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_ui.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/features/organization/widgets/shelter_pin_prompt.dart';
import 'package:respawnd1/features/donation/models.dart';
import 'package:respawnd1/features/admin/stock/stock_service.dart';
import 'package:respawnd1/features/care/care_rounds.dart';
import 'package:respawnd1/features/care/care_rounds_widgets.dart';
import 'package:respawnd1/features/adminhome/dashboard/care_need_row.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart';

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

  /// Today's rescue availability: shelter space, transporters available
  /// today, carers on shift and present, animals already needing
  /// continuing care, and supplies. Each section names its own state; the
  /// banner lists the ones that limit the next rescue.
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occAsync = ref.watch(shelterOccupancyProvider);
    final settings = ref.watch(shelterSettingsProvider).asData?.value ?? ShelterSettings.empty;
    final snap = ref.watch(dashboardRescueSnapshotProvider).asData?.value;
    final transportersAsync = ref.watch(petTransportersProvider);
    final busyByRider = ref.watch(activeAssignmentsByRiderProvider).asData?.value;
    final records = ref.watch(allAnimalRecordsProvider).asData?.value;
    final isAdmin = ref.watch(isOrgAdminProvider).asData?.value ?? false;
    final orgId = ref.watch(dashboardOrgIdProvider).asData?.value;
    final stockAsync = ref.watch(stockItemsProvider);
    final careSetup = orgId == null ? null : ref.watch(careSetupProvider(orgId)).asData?.value;
    final now = DateTime.now();
    final round = orgId == null ? null : ref.watch(careRoundProvider(careRoundKey(orgId, now))).asData?.value;
    final plans = ref.watch(activeMedicationPlansByAnimalProvider).asData?.value;
    final missed = ref.watch(missedDosesByAnimalProvider).asData?.value;
    final vax = ref.watch(vaccinationsByAnimalProvider).asData?.value;

    return SectionCard(
      icon: Icons.dashboard,
      title: 'Rescue readiness',
      trailing: Padding(
        padding: const EdgeInsets.only(right: 6),
        child: StatusChip('Today · ${shortDate(now)}', tone: ChipTone.ink, icon: Icons.today),
      ),
      child: DashAsync<ShelterOccupancy>(
        value: occAsync,
        what: 'shelter space',
        builder: (occ) {
          final space = _spaceSection(occ);
          final transport = _transportSection(transportersAsync, busyByRider, snap, settings, now);
          final carers = _carersSection(careSetup, round, now, orgId == null);
          final needing = records == null
              ? null
              : animalsNeedingCare(records, plans: plans, missedDoses: missed, vaccinations: vax);
          final care = _continuingCareSection(needing);
          final supplies = _suppliesSection(stockAsync, settings);
          final sections = [space, transport, carers, care, supplies];

          final limiting = sections.where((s) => s.state == ReadinessState.constrained).map((s) => s.title).toList();
          final message = limiting.isNotEmpty
              ? '${limiting.join(', ')} ${limiting.length == 1 ? 'limits' : 'limit'} today’s next rescue'
              : sections.any((s) => s.state == ReadinessState.incomplete)
              ? 'Nothing limits a rescue today, but some information is missing'
              : 'Nothing recorded limits a rescue today';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (orgId != null) ShelterPinPrompt(organizationId: orgId, canSet: isAdmin),
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
              const SizedBox(height: 4),
              _SectionBlock(
                section: space,
                first: true,
                body: settings.isConfigured ? _Gauge(occ: occ) : _SetupPrompt(onTap: () => showShelterSetupSheet(context)),
              ),
              _SectionBlock(section: transport),
              // Care tasks are hidden for now (FeatureFlags.careTasksEnabled).
              if (FeatureFlags.careTasksEnabled)
              _SectionBlock(
                section: carers,
                actions: [
                  if (orgId != null)
                    DashLinkButton(
                      label: 'Care rounds',
                      icon: Icons.checklist,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CareRoundsPage(organizationId: orgId, canEditSetup: isAdmin),
                        ),
                      ),
                    ),
                  if (orgId != null && isAdmin)
                    DashLinkButton(
                      label: 'Roster',
                      icon: Icons.edit_calendar,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CareRosterPage(organizationId: orgId)),
                      ),
                    ),
                ],
              ),
              _SectionBlock(
                section: care,
                after: needing == null || needing.isEmpty
                    ? null
                    : ExpandableList(
                  initialCount: 3,
                  moreLabel: 'All animals needing care',
                  children: [for (final (a, needs) in needing) CareNeedRow(animal: a, needs: needs)],
                ),
              ),
              _SectionBlock(
                section: supplies,
                actions: [DashLinkButton(label: 'Stock', icon: Icons.inventory_2, onPressed: () => openStock(context))],
              ),
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

  static _Section _spaceSection(ShelterOccupancy occ) {
    final free = occ.free;
    if (free == null) {
      return const _Section(Icons.house, 'Shelter space', ReadinessState.incomplete, ['Shelter capacity not set']);
    }
    final iso = occ.isolationCapacity == null
        ? 'Isolation capacity not set'
        : (occ.isolationFull
        ? 'Isolation full (${occ.isolation}/${occ.isolationCapacity})'
        : 'Isolation ${occ.isolation}/${occ.isolationCapacity} in use');
    return _Section(
      Icons.house,
      'Shelter space',
      free <= 0 || occ.isolationFull ? ReadinessState.constrained : ReadinessState.confirmed,
      [
        free < 0 ? 'Over capacity by ${-free}' : '${plural(free, 'general space')} free',
        if (occ.arriving > 0) '${plural(occ.arriving, 'animal')} arriving (already counted)',
        iso,
      ],
    );
  }

  static _Section _transportSection(
      AsyncValue<List<PetTransporter>> transportersAsync,
      Map<String, TransportAssignmentStatus>? busyByRider,
      RescueSnapshot? snap,
      ShelterSettings settings,
      DateTime now,
      ) {
    const title = 'Transporters today';
    if (transportersAsync.hasError) {
      return const _Section(Icons.local_shipping, title, ReadinessState.incomplete, ['Couldn’t load transporters']);
    }
    final list = transportersAsync.asData?.value;
    if (list == null || busyByRider == null) {
      return const _Section(Icons.local_shipping, title, ReadinessState.incomplete, ['Loading transporters…']);
    }
    bool busy(String uid) {
      final s = busyByRider[uid];
      return s == TransportAssignmentStatus.pending || s == TransportAssignmentStatus.accepted;
    }

    bool seenToday(PetTransporter t) {
      final at = t.lastSeenAt;
      return at != null && at.year == now.year && at.month == now.month && at.day == now.day;
    }

    final available = list.where((t) => t.isOnline && !busy(t.uid)).toList();
    final onRide = list.where((t) => busy(t.uid)).toList();
    final activeToday = list.where((t) => seenToday(t) || t.isOnline).length;
    final waiting = snap?.count(RescueStage.transporter) ?? 0;
    final target = settings.ridersNeeded;
    String names(List<PetTransporter> l) =>
        '${l.take(3).map((t) => t.name).join(', ')}${l.length > 3 ? ' +${l.length - 3}' : ''}';

    return _Section(
      Icons.local_shipping,
      title,
      available.isEmpty || waiting >= available.length || (target != null && available.length < target)
          ? ReadinessState.constrained
          : ReadinessState.confirmed,
      [
        available.isEmpty
            ? 'No one online and free right now'
            : '${available.length} available now: ${names(available)}',
        if (onRide.isNotEmpty) '${onRide.length} on a ride: ${names(onRide)}',
        '$activeToday of ${list.length} registered active today'
            '${waiting > 0 ? ' · ${plural(waiting, 'case')} waiting for one' : ''}'
            '${target == null ? '' : ' · target $target'}',
      ],
    );
  }

  static _Section _carersSection(CareSetup? setup, CareRound? round, DateTime now, bool noOrg) {
    const title = 'Carers present';
    if (noOrg) {
      return const _Section(Icons.groups, title, ReadinessState.incomplete, [
        'This account isn’t linked to an organization',
      ]);
    }
    if (setup == null) {
      return const _Section(Icons.groups, title, ReadinessState.incomplete, ['Loading roster…']);
    }
    // Present = logged at least one care round today.
    final present = <String, String>{
      for (final t in (round ?? CareRound.empty).done.values)
        if (t.byUid != null) t.byUid!: t.byName,
    };
    if (!setup.hasRoster) {
      return _Section(Icons.groups, title, ReadinessState.incomplete, [
        'Carer roster not set',
        if (present.isNotEmpty) 'Logged care rounds today: ${present.values.take(3).join(', ')}',
      ]);
    }
    final lines = <String>[];
    var uncovered = 0;
    for (final shift in setup.shifts) {
      final on = setup.onShift(now.weekday, shift.id);
      if (on.isEmpty) uncovered++;
      final times = shift.start.isEmpty ? '' : ' (${shift.start}–${shift.end})';
      lines.add(on.isEmpty
          ? '${shift.label}$times: no carer on the roster'
          : '${shift.label}$times: ${on.map((e) => present.containsKey(e.uid) ? '${e.name} ✓' : e.name).join(', ')}');
    }
    final rostered = {for (final s in setup.shifts) ...setup.onShift(now.weekday, s.id).map((e) => e.uid)};
    final presentRostered = rostered.where(present.containsKey).length;
    lines.add(present.isEmpty
        ? 'No care rounds logged yet today'
        : '$presentRostered of ${rostered.length} rostered carers have logged rounds (✓)'
        '${present.length > presentRostered ? ' · ${present.length - presentRostered} others helped' : ''}');
    return _Section(
      Icons.groups,
      title,
      uncovered > 0 ? ReadinessState.constrained : ReadinessState.confirmed,
      lines,
    );
  }

  static _Section _continuingCareSection(List<(AnimalRecord, List<CareNeed>)>? needing) {
    const title = 'Continuing care';
    if (needing == null) {
      return const _Section(Icons.medical_services, title, ReadinessState.incomplete, ['Loading animals…']);
    }
    if (needing.isEmpty) {
      return const _Section(Icons.medical_services, title, ReadinessState.confirmed, [
        'No animal needs medication, isolation or treatment',
      ]);
    }
    int count(bool Function(CareNeed) test) => needing.where((e) => e.$2.any(test)).length;
    final breakdown = [
      if (count((n) => n.label.startsWith('Medication')) case final n when n > 0) '$n on medication',
      if (count((n) => n.label == 'Isolation') case final n when n > 0) '$n in isolation',
      if (count((n) => n.label == 'In treatment') case final n when n > 0) '$n in treatment',
    ];
    return _Section(
      Icons.medical_services,
      title,
      ReadinessState.adminAssess,
      [
        '${plural(needing.length, 'animal')} need continuing care${breakdown.isEmpty ? '' : ': ${breakdown.join(', ')}'}. '
            'Tap one to open its record.',
      ],
    );
  }

  static _Section _suppliesSection(AsyncValue<List<StockItem>> stockAsync, ShelterSettings settings) {
    const title = 'Supplies';
    if (stockAsync.hasError) {
      return const _Section(Icons.inventory_2, title, ReadinessState.incomplete, ['Couldn’t load stock']);
    }
    final stock = stockAsync.asData?.value;
    if (stock == null) {
      return const _Section(Icons.inventory_2, title, ReadinessState.incomplete, ['Loading stock…']);
    }
    if (stock.isEmpty) {
      return const _Section(Icons.inventory_2, title, ReadinessState.incomplete, ['No stock recorded yet']);
    }
    final perDay = settings.foodPerDayKg;
    final low = stock.where((i) => i.isLow).toList();
    final out = stock.where((i) => i.quantity <= 0).toList();
    final foodKg = stock.where((i) => i.isFood).fold<double>(0, (s, i) => s + (i.kilograms ?? 0));
    final days = foodKg > 0 && perDay != null && perDay > 0 ? (foodKg / perDay).floor() : null;
    bool isMedicine(StockItem i) => i.category.toLowerCase().contains('medicine');
    final constrained = low.any((i) => i.isFood || isMedicine(i)) || (days != null && days < 3);
    String names(List<StockItem> l) =>
        '${l.take(3).map((i) => i.name).join(', ')}${l.length > 3 ? ' +${l.length - 3}' : ''}';
    return _Section(
      Icons.inventory_2,
      title,
      constrained ? ReadinessState.constrained : ReadinessState.confirmed,
      [
        if (days != null)
          '${foodKg.round()} kg food ≈ ${plural(days, 'day')}'
        else if (foodKg > 0)
          '${foodKg.round()} kg food (set food use per day to see days left)',
        if (out.isNotEmpty) 'Out of stock: ${names(out)}',
        if (low.where((i) => i.quantity > 0).isNotEmpty) 'Running low: ${names(low.where((i) => i.quantity > 0).toList())}',
        '${stock.length - low.length} of ${plural(stock.length, 'item')} above their low-stock level',
      ],
    );
  }

  /// Pure: the same factors the dashboard card shows. The accept sheet calls
  /// this too, so the snapshot saved on a case matches what the admin saw.
  static List<ReadinessFactor> buildFactors({
    required ShelterOccupancy occ,
    required ShelterSettings settings,
    required RescueSnapshot? snap,
    required TransportSupply? supply,
    required List<AnimalRecord>? records,
    required bool canManage,
    required List<DonationListing>? campaigns,
    List<StockItem>? stock,
    CareSetup? careSetup,
    DateTime? now,
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

    // Care coverage — Dashboard gap 3: the weekly carer roster. Any shift
    // in the next 7 days with no one on it is a constraint.
    final ReadinessFactor care;
    if (careSetup == null || !careSetup.hasRoster) {
      care = const ReadinessFactor(
        Icons.groups,
        'Care coverage',
        'Carer roster not set',
        ReadinessState.incomplete,
      );
    } else {
      final today = now ?? DateTime.now();
      final gaps = rosterGaps(careSetup, today);
      final todayNames = {
        for (final s in careSetup.shifts) ...careSetup.onShift(today.weekday, s.id).map((e) => e.name),
      };
      care = gaps.isEmpty
          ? ReadinessFactor(
        Icons.groups,
        'Care coverage',
        'Every shift covered this week · today: ${todayNames.take(3).join(', ')}'
            '${todayNames.length > 3 ? ' +${todayNames.length - 3}' : ''}',
        ReadinessState.confirmed,
      )
          : ReadinessFactor(
        Icons.groups,
        'Care coverage',
        '${plural(gaps.length, 'shift')} with no carer in 7 days · first: '
            '${kWeekdayShort[gaps.first.day.weekday - 1]} ${gaps.first.shift.label.toLowerCase()}',
        ReadinessState.constrained,
      );
    }

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

    // Food & medicine — Donation gap 5: the organization's stock list
    // (received in-kind goods are added to it automatically).
    final perDay = settings.foodPerDayKg;
    final ReadinessFactor food;
    if (stock == null || stock.isEmpty) {
      food = const ReadinessFactor(
        Icons.restaurant,
        'Food & medicine',
        'No stock recorded yet',
        ReadinessState.incomplete,
      );
    } else {
      final low = stock.where((i) => i.isLow).toList();
      final foodKg = stock.where((i) => i.isFood).fold<double>(0, (s, i) => s + (i.kilograms ?? 0));
      final days = foodKg > 0 && perDay != null && perDay > 0 ? (foodKg / perDay).floor() : null;
      final parts = [
        if (days != null) '${foodKg.round()} kg food ≈ $days days' else if (foodKg > 0) '${foodKg.round()} kg food',
        if (low.isNotEmpty) 'low: ${low.take(2).map((i) => i.name).join(', ')}${low.length > 2 ? ' +${low.length - 2}' : ''}',
        if (days == null && foodKg == 0 && low.isEmpty) '${stock.length} stock items, none low',
      ];
      // Only food and medicine running low limits the next rescue.
      final constrained = low.any((i) => i.isFood || i.category.toLowerCase().contains('medicine')) ||
          (days != null && days < 3);
      food = ReadinessFactor(
        Icons.restaurant,
        'Food & medicine',
        parts.join(' · '),
        constrained ? ReadinessState.constrained : ReadinessState.confirmed,
      );
    }

    // Funds — admins only; general (unrestricted) campaign balances.
    final ReadinessFactor funds;
    if (!canManage) {
      funds = const ReadinessFactor(Icons.lock, 'Funds', 'Visible to people who handle money', ReadinessState.adminAssess);
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
        .where((a) => isInCare(a) && ((a.health.currentMedications ?? '').trim().isNotEmpty || a.hasSpecialNeeds))
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

/// One part of today's readiness: a title, its state and what the records
/// show.
class _Section {
  final IconData icon;
  final String title;
  final ReadinessState state;
  final List<String> lines;
  const _Section(this.icon, this.title, this.state, this.lines);
}

class _SectionBlock extends StatelessWidget {
  final _Section section;
  final bool first;
  final Widget? body;

  /// Shown below the section's lines, e.g. the animals it is about.
  final Widget? after;
  final List<Widget> actions;
  const _SectionBlock({required this.section, this.first = false, this.body, this.after, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: first ? null : Border(top: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.14))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(9)),
                child: Icon(section.icon, size: 18, color: AppColors.textPrimary),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(section.title, style: dashBody(size: 15, weight: FontWeight.w700))),
              StatusChip(section.state.label, tone: section.state.tone, icon: section.state.icon),
            ],
          ),
          const SizedBox(height: 6),
          if (body != null) ...[body!, const SizedBox(height: 6)],
          for (final line in section.lines)
            Padding(
              padding: const EdgeInsets.only(left: 42, bottom: 2),
              child: Text(line, style: dashMuted(13)),
            ),
          if (after != null) Padding(padding: const EdgeInsets.only(left: 42, top: 4), child: after),
          if (actions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 42, top: 6),
              child: Wrap(spacing: 6, runSpacing: 6, children: actions),
            ),
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
