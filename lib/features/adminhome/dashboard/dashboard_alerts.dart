import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/adoption/return_request.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/adminhome/admin_dashboard_home_widgets.dart'
    show overdueFollowUpsProvider, staleTransportOffersProvider;
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_nav.dart';

/// Which module an alert belongs to — drives the Priority actions filter.
enum AlertArea {
  rescue,
  care,
  adoption,
  funds;

  String get label => switch (this) {
    AlertArea.rescue => 'Rescue',
    AlertArea.care => 'Care',
    AlertArea.adoption => 'Adoption',
    AlertArea.funds => 'Funds',
  };
}

/// One prioritized, unresolved operational issue.
class DashAlert {
  final DashSeverity severity;
  final IconData icon;
  final String title;
  final String status;
  final String? subject;
  final String? timing;
  final String action;
  final AlertArea area;

  /// Short verb for the row's button (Verify, Assign, Review, Open).
  final String button;
  final void Function(BuildContext context, WidgetRef ref) open;

  const DashAlert({
    required this.severity,
    required this.icon,
    required this.title,
    required this.status,
    required this.action,
    required this.open,
    required this.area,
    this.button = 'Open',
    this.subject,
    this.timing,
  });
}

class DashAlertsState {
  final List<DashAlert> alerts;
  final bool loading;
  final List<String> failedSources;
  const DashAlertsState({required this.alerts, required this.loading, required this.failedSources});

  int count(DashSeverity s) => alerts.where((a) => a.severity == s).length;
}

/// When one category has more than this many items, they are grouped into
/// a single alert that opens the full queue instead of flooding the list.
const int _kGroupAbove = 2;

/// Aggregates every alert from the SAME providers the module screens
/// already stream (Riverpod shares one listener per provider instance, so
/// this adds no duplicate Firestore queries for data those screens use).
/// Shared by the header summary, the Priority Alerts list, and the app-bar
/// bell badge.
final dashboardAlertsProvider = Provider.autoDispose<DashAlertsState>((ref) {
  final review = ref.watch(casesForTabProvider(RescuePipelineTab.review));
  final assign = ref.watch(casesForTabProvider(RescuePipelineTab.assign));
  final treatment = ref.watch(casesForTabProvider(RescuePipelineTab.treatment));
  final intake = ref.watch(casesForTabProvider(RescuePipelineTab.intake));
  final fieldIssues = ref.watch(casesByStatusesProvider(kFieldIssueStatuses));
  final staleOffers = ref.watch(staleTransportOffersProvider);
  final pendingApps = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.pending)));
  final approvedApps = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.approved)));
  final adoptedBucket = ref.watch(adoptionsByStatusesProvider(statusFilter(AdoptionStatus.adopted)));
  final overdueFollowUps = ref.watch(overdueFollowUpsProvider);
  final canManageFinances = ref.watch(canManageFinancesProvider).asData?.value ?? false;
  final needsDecision = canManageFinances ? ref.watch(campaignsNeedingDecisionProvider) : null;
  final payments = canManageFinances ? ref.watch(paymentAttemptsProvider) : null;
  final records = ref.watch(allAnimalRecordsProvider);
  final vaccinations = ref.watch(vaccinationsByAnimalProvider);

  final alerts = <DashAlert>[];
  final failed = <String>[];

  void track(AsyncValue<dynamic> v, String name) {
    if (v.hasError) failed.add(name);
  }

  track(review, 'rescue review queue');
  track(assign, 'transport queue');
  track(treatment, 'treatment cases');
  track(intake, 'intake cases');
  track(fieldIssues, 'field-issue cases');
  track(staleOffers, 'transporter offers');
  track(pendingApps, 'adoption applications');
  track(approvedApps, 'approved adoptions');
  track(adoptedBucket, 'adoption returns');
  track(overdueFollowUps, 'post-adoption follow-ups');
  if (needsDecision != null) track(needsDecision, 'campaign decisions');

  String caseSubject(RescueCase c) => [
    '${c.speciesSummary.isEmpty ? 'Animal' : c.speciesSummary} · #${c.shortCaseId}',
    if (c.address != null) c.address!,
  ].join(' · ');

  void addCases({
    required List<RescueCase> cases,
    required DashSeverity severity,
    required IconData icon,
    required String singleTitle,
    required String groupTitle,
    required String status,
    required String action,
    required RescuePipelineTab? tab,
    required String button,
  }) {
    if (cases.isEmpty) return;
    final sorted = [...cases]..sort(compareTriage);
    if (sorted.length <= _kGroupAbove) {
      for (final c in sorted) {
        alerts.add(
          DashAlert(
            severity: severity,
            icon: icon,
            title: singleTitle,
            status: status,
            subject: caseSubject(c),
            timing: 'Reported ${elapsedSince(c.createdAt)}',
            action: action,
            area: AlertArea.rescue,
            button: button,
            open: (context, _) => openRescueCase(context, c),
          ),
        );
      }
    } else {
      final oldest = sorted
          .map((c) => c.createdAt)
          .whereType<DateTime>()
          .fold<DateTime?>(null, (m, t) => m == null || t.isBefore(m) ? t : m);
      alerts.add(
        DashAlert(
          severity: severity,
          icon: icon,
          title: '${sorted.length} $groupTitle',
          status: status,
          subject: 'Most urgent: ${caseSubject(sorted.first)}',
          timing: oldest == null ? null : 'Oldest reported ${elapsedSince(oldest)}',
          action: action,
          area: AlertArea.rescue,
          button: button,
          open: (context, ref) =>
          tab == null ? openRescueCase(context, sorted.first) : openRescueTab(context, ref, tab),
        ),
      );
    }
  }

  // ── Rescue: genuine emergencies first ─────────────────────────────────
  final reviewCases = review.asData?.value ?? const <RescueCase>[];
  final assignCases = assign.asData?.value ?? const <RescueCase>[];
  bool isCritical(RescueCase c) => UrgencyLevel.fromFirestoreValue(c.urgency) == UrgencyLevel.critical;

  addCases(
    cases: reviewCases.where((c) => c.status == RescueStatus.pendingReview && isCritical(c)).toList(),
    severity: DashSeverity.critical,
    icon: Icons.priority_high,
    singleTitle: 'Critical report awaiting assessment',
    groupTitle: 'critical reports awaiting assessment',
    status: 'Critical · not yet reviewed',
    action: 'Assess condition and location, then accept or refer',
    tab: RescuePipelineTab.review,
    button: 'Verify',
  );

  final specialist = (fieldIssues.asData?.value ?? const <RescueCase>[])
      .where((c) => c.status == RescueStatus.needsSpecializedAssistance)
      .toList();
  addCases(
    cases: specialist,
    severity: DashSeverity.critical,
    icon: Icons.support_agent_outlined,
    singleTitle: 'Rescue needs specialized assistance',
    groupTitle: 'rescues needing specialized assistance',
    status: 'Blocked in the field',
    action: 'Arrange a specialized handler or refer the case',
    tab: null,
    button: 'Open',
  );

  addCases(
    cases: [...reviewCases.where((c) => c.status == RescueStatus.accepted), ...assignCases].where(isCritical).toList(),
    severity: DashSeverity.critical,
    icon: Icons.local_shipping_outlined,
    singleTitle: 'Critical case not yet moving',
    groupTitle: 'critical cases waiting for clinic or transport',
    status: 'Critical · accepted, not dispatched',
    action: 'Select a clinic and assign a transporter',
    tab: RescuePipelineTab.assign,
    button: 'Assign',
  );

  final stale = staleOffers.asData?.value ?? const [];
  if (stale.isNotEmpty) {
    alerts.add(
      DashAlert(
        severity: DashSeverity.critical,
        icon: Icons.hourglass_disabled_outlined,
        title: '${plural(stale.length, 'transporter offer')} expired unanswered',
        status: 'No transporter response',
        subject: stale.length == 1 ? 'Offered to ${stale.first.riderName}' : null,
        timing: stale.first.expiresAt == null ? null : 'Expired ${elapsedSince(stale.first.expiresAt)}',
        action: 'Re-offer to another available transporter',
        area: AlertArea.rescue,
        button: 'Assign',
        open: (context, ref) => openRescueTab(context, ref, RescuePipelineTab.assign),
      ),
    );
  }

  // ── Rescue: bottlenecks ───────────────────────────────────────────────
  addCases(
    cases: assignCases.where((c) => !isCritical(c)).toList(),
    severity: DashSeverity.warning,
    icon: Icons.local_shipping_outlined,
    singleTitle: 'Case waiting for a transporter',
    groupTitle: 'cases waiting for a transporter',
    status: 'Clinic selected · no transporter',
    action: 'Assign a transporter',
    tab: RescuePipelineTab.assign,
    button: 'Assign',
  );

  addCases(
    cases: reviewCases.where((c) => c.status == RescueStatus.accepted && !isCritical(c)).toList(),
    severity: DashSeverity.warning,
    icon: Icons.local_hospital_outlined,
    singleTitle: 'Accepted case without a vet clinic',
    groupTitle: 'accepted cases without a vet clinic',
    status: 'Accepted · no clinic',
    action: 'Select a veterinary clinic',
    tab: RescuePipelineTab.review,
    button: 'Select',
  );

  addCases(
    cases: reviewCases.where((c) => c.status == RescueStatus.pendingReview && !isCritical(c)).toList(),
    severity: DashSeverity.warning,
    icon: Icons.fact_check_outlined,
    singleTitle: 'Report awaiting review',
    groupTitle: 'reports awaiting review',
    status: 'Not yet assessed or verified',
    action: 'Review the report and confirm location',
    tab: RescuePipelineTab.review,
    button: 'Verify',
  );

  addCases(
    cases: (fieldIssues.asData?.value ?? const <RescueCase>[])
        .where((c) => c.status != RescueStatus.needsSpecializedAssistance)
        .toList(),
    severity: DashSeverity.warning,
    icon: Icons.location_off_outlined,
    singleTitle: 'Animal not located / pickup failed',
    groupTitle: 'rescues stalled in the field',
    status: 'Location unconfirmed or pickup failed',
    action: 'Follow up with the reporter and decide on a re-attempt',
    tab: null,
    button: 'Open',
  );

  // ── Treatment & intake ────────────────────────────────────────────────
  final ready = (treatment.asData?.value ?? const <RescueCase>[]).where((c) => c.readyForDischarge).toList();
  if (ready.isNotEmpty) {
    alerts.add(
      DashAlert(
        severity: DashSeverity.warning,
        icon: Icons.assignment_turned_in_outlined,
        title: ready.length == 1 ? 'Animal ready for discharge' : '${ready.length} cases ready for discharge',
        status: 'Marked ready by treatment update',
        subject: ready.length == 1 ? caseSubject(ready.first) : null,
        action: 'Decide post-treatment action and plan shelter space',
        area: AlertArea.care,
        button: 'Decide',
        open: (context, ref) => ready.length == 1
            ? openTreatment(context, ready.first)
            : openRescueTab(context, ref, RescuePipelineTab.treatment),
      ),
    );
  }

  final intakeCases = intake.asData?.value ?? const <RescueCase>[];
  if (intakeCases.isNotEmpty) {
    alerts.add(
      DashAlert(
        severity: DashSeverity.warning,
        icon: Icons.house_outlined,
        title: intakeCases.length == 1
            ? 'Animal awaiting shelter intake'
            : '${intakeCases.length} cases awaiting shelter intake',
        status: 'Discharged · intake not completed',
        subject: intakeCases.length == 1 ? caseSubject(intakeCases.first) : null,
        action: 'Confirm intake and create the animal record',
        area: AlertArea.care,
        button: 'Confirm',
        open: (context, ref) => intakeCases.length == 1
            ? openIntakeCase(context, intakeCases.first)
            : openRescueTab(context, ref, RescuePipelineTab.intake),
      ),
    );
  }

  // ── Adoption ──────────────────────────────────────────────────────────
  final returns = activeReturnsIn(adoptedBucket.asData?.value ?? const <AdoptionApplication>[]);
  for (final app in returns) {
    final r = app.returnRequest!;
    final pendingReview = r.status == ReturnRequestStatus.pendingReview;
    alerts.add(
      DashAlert(
        severity: pendingReview ? DashSeverity.warning : DashSeverity.info,
        icon: Icons.assignment_return_outlined,
        title: pendingReview ? 'Adoption return request to review' : 'Adoption return in progress',
        status: r.status.label,
        subject: app.animalName.isEmpty ? 'Adopter: ${app.adopterName}' : '${app.animalName} · ${app.adopterName}',
        timing: 'Requested ${elapsedSince(r.requestedAt)}',
        action: nextReturnStep(r),
        area: AlertArea.adoption,
        button: 'Review',
        open: (context, _) => openReturn(context, app),
      ),
    );
  }

  final overdue = overdueFollowUps.asData?.value ?? const [];
  if (overdue.isNotEmpty) {
    alerts.add(
      DashAlert(
        severity: DashSeverity.warning,
        icon: Icons.event_busy_outlined,
        title: '${plural(overdue.length, 'post-adoption follow-up')} overdue',
        status: 'Past scheduled check-in date',
        action: 'Contact adopters and record the follow-up',
        area: AlertArea.adoption,
        open: (context, _) => openAdoptionQueue(context, AdoptionStatus.adopted),
      ),
    );
  }

  final pending = pendingApps.asData?.value ?? const <AdoptionApplication>[];
  if (pending.isNotEmpty) {
    final oldest = pending
        .map((a) => a.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (m, t) => m == null || t.isBefore(m) ? t : m);
    alerts.add(
      DashAlert(
        severity: DashSeverity.info,
        icon: Icons.assignment_ind_outlined,
        title: '${plural(pending.length, 'adoption application')} awaiting screening',
        status: 'Pending',
        timing: oldest == null ? null : 'Oldest submitted ${elapsedSince(oldest)}',
        action: 'Screen applicants and schedule interviews',
        area: AlertArea.adoption,
        button: 'Review',
        open: (context, _) => openAdoptionQueue(context, AdoptionStatus.pending),
      ),
    );
  }

  final approved = approvedApps.asData?.value ?? const <AdoptionApplication>[];
  if (approved.isNotEmpty) {
    alerts.add(
      DashAlert(
        severity: DashSeverity.info,
        icon: Icons.home_outlined,
        title: '${plural(approved.length, 'approved adoption')} awaiting release',
        status: 'Approved · handover not completed',
        action: 'Coordinate release with the adopter',
        area: AlertArea.adoption,
        open: (context, _) => openAdoptionQueue(context, AdoptionStatus.approved),
      ),
    );
  }

  // ── Funding (authorized viewers only) ─────────────────────────────────
  final decisions = needsDecision?.asData?.value ?? const [];
  if (decisions.isNotEmpty) {
    alerts.add(
      DashAlert(
        severity: DashSeverity.warning,
        icon: Icons.savings_outlined,
        title: '${plural(decisions.length, 'campaign')} ended below goal',
        status: 'Extension decision needed',
        subject: decisions.length == 1 ? decisions.first.title : null,
        action: 'Decide whether to extend, or cover the remaining need from applicable funds',
        area: AlertArea.funds,
        button: 'Decide',
        open: (context, _) =>
        decisions.length == 1 ? openCampaign(context, decisions.first.id) : openDonationsAdmin(context),
      ),
    );
  }

  // ── Care: overdue vaccinations (only from recorded due dates) ─────────
  final vax = vaccinations.asData?.value;
  final inCare = (records.asData?.value ?? const <AnimalRecord>[]).where(isInCare).toList();
  if (vax != null) {
    final overdueVax = inCare.where((a) => healthStatusOf(vax[a.id]) == HealthRecordStatus.overdue).toList();
    if (overdueVax.isNotEmpty) {
      final a = overdueVax.first;
      final due = nextVaccineDue(vax[a.id]);
      alerts.add(
        DashAlert(
          severity: DashSeverity.critical,
          icon: Icons.vaccines_outlined,
          title: overdueVax.length == 1
              ? 'Vaccination overdue'
              : '${overdueVax.length} animals with overdue vaccinations',
          status: 'Past the recorded next-due date',
          subject: overdueVax.length == 1 ? (a.name.isEmpty ? a.species : a.name) : null,
          timing: due == null ? null : 'Overdue since ${shortDate(due)}',
          action: 'Schedule the vaccine and record it',
          area: AlertArea.care,
          open: (context, _) => overdueVax.length == 1 ? openAnimalRecord(context, a) : openAnimalRecords(context),
        ),
      );
    }
  }

  // ── Funds: payments needing manual verification ───────────────────────
  final review2 = (payments?.asData?.value ?? const []).where((p) => p.status == 'needs_review').toList();
  if (review2.isNotEmpty) {
    final total = review2.fold<double>(0, (s, p) => s + p.amount);
    final oldest = review2
        .map((p) => p.createdAt)
        .whereType<DateTime>()
        .fold<DateTime?>(null, (m, t) => m == null || t.isBefore(m) ? t : m);
    alerts.add(
      DashAlert(
        severity: DashSeverity.warning,
        icon: Icons.payments_outlined,
        title: '${plural(review2.length, 'donation')} to verify',
        status: '${formatPeso(total)} · payment needs review',
        timing: oldest == null ? null : 'Oldest ${elapsedSince(oldest)}',
        action: 'Confirm the payment before counting it as received',
        area: AlertArea.funds,
        button: 'Verify',
        open: (context, _) => openDonationsAdmin(context),
      ),
    );
  }

  // Stable by severity — List.sort isn't guaranteed stable, and the
  // insertion order above is itself the within-severity priority.
  final ordered = [for (final s in DashSeverity.values) ...alerts.where((a) => a.severity == s)];

  final loading = [review, assign, treatment, intake, fieldIssues, pendingApps, adoptedBucket].any((v) => v.isLoading);
  return DashAlertsState(alerts: ordered, loading: loading, failedSources: failed);
});
