import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/dashboard/dashboard_model.dart';
import 'package:respawnd1/features/admin/adoption/state/adoption_providers.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';
import 'package:respawnd1/features/admin/animals/widgets/medication_section.dart' show missedDosesByAnimalProvider;
import 'package:respawnd1/features/admin/donation/donation_admin_providers.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';
import 'package:respawnd1/features/admin/stock/stock_service.dart';
import 'package:respawnd1/features/adminhome/admin_dashboard_home_widgets.dart' show staleTransportOffersProvider;
import 'package:respawnd1/features/adminhome/dashboard/alert_claims.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/shelter_settings.dart';
import 'package:respawnd1/features/care/care_rounds.dart';

// ─── Keeping the Today data loaded ───────────────────────────────────────

/// Every data source the Today cards read. Riverpod pauses the dashboard's
/// own listeners while another screen covers it, so a source it shares with
/// that screen (cases, animal records, donations…) was disposed when the
/// screen closed, and the whole dashboard loaded again on the way back.
/// [DashboardKeepAlive] listens to this through the container, which is
/// never paused, so the sources stay loaded while the dashboard exists.
///
/// Only leaf sources are watched: the derived dashboard providers stay with
/// their (paused) cards and recompute from these on return.
final dashboardKeepAliveProvider = Provider.autoDispose<void>((ref) {
  for (final tab in const [
    RescuePipelineTab.review,
    RescuePipelineTab.assign,
    RescuePipelineTab.ongoing,
    RescuePipelineTab.treatment,
    RescuePipelineTab.intake,
  ]) {
    ref.watch(casesForTabProvider(tab));
  }
  ref.watch(casesByStatusesProvider(kFieldIssueStatuses));
  ref.watch(staleTransportOffersProvider);
  for (final s in const [
    AdoptionStatus.pending,
    AdoptionStatus.interview,
    AdoptionStatus.approved,
    AdoptionStatus.adopted,
  ]) {
    ref.watch(adoptionsByStatusesProvider(statusFilter(s)));
  }
  ref.watch(orgOpenFollowUpsProvider);
  ref.watch(pendingVolunteerApplicationsProvider);
  ref.watch(pendingTransporterApplicationsProvider);
  ref.watch(allAnimalRecordsProvider);
  ref.watch(vaccinationsByAnimalProvider);
  ref.watch(careRecordsByAnimalProvider);
  ref.watch(missedDosesByAnimalProvider);
  ref.watch(activeMedicationPlansByAnimalProvider);
  ref.watch(shelterSettingsProvider);
  ref.watch(petTransportersProvider);
  ref.watch(activeAssignmentsByRiderProvider);
  ref.watch(stockItemsProvider);
  ref.watch(isOrgAdminProvider);
  ref.watch(upcomingEventsProvider);
  ref.watch(alertClaimsProvider);

  final orgId = ref.watch(dashboardOrgIdProvider).asData?.value;
  if (orgId != null) {
    ref.watch(careSetupProvider(orgId));
    ref.watch(careRoundProvider(careRoundKey(orgId, DateTime.now())));
  }

  // Money sources only for the people allowed to read them, as the cards do.
  if (ref.watch(canManageFinancesProvider).asData?.value ?? false) {
    ref.watch(campaignsNeedingDecisionProvider);
    ref.watch(paymentAttemptsProvider);
    ref.watch(adminCampaignsProvider);
    ref.watch(orgAllocationsProvider);
    ref.watch(allCaseExpensesProvider);
    ref.watch(myGeneralExpensesProvider);
    ref.watch(allDonationsProvider);
  }
});

/// Keeps [dashboardKeepAliveProvider] listened to while mounted.
class DashboardKeepAlive extends StatefulWidget {
  final Widget child;
  const DashboardKeepAlive({super.key, required this.child});

  @override
  State<DashboardKeepAlive> createState() => _DashboardKeepAliveState();
}

class _DashboardKeepAliveState extends State<DashboardKeepAlive> {
  ProviderSubscription<void>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A container subscription, not a WidgetRef one: those are paused while
    // the route is covered, which is exactly what this works around.
    _sub ??= ProviderScope.containerOf(context, listen: false).listen<void>(dashboardKeepAliveProvider, (_, _) {});
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// ─── Remembered card heights ─────────────────────────────────────────────

/// Last laid-out height of each dashboard card (per card and width), kept in
/// memory and on the device so a loading card keeps its size: the page
/// doesn't collapse and grow back, only the content fills in.
class DashCardHeights {
  DashCardHeights._();

  static const _prefsKey = 'dashboardCardHeights.v1';
  static final Map<String, double> _heights = {};
  static Future<void>? _load;
  static Timer? _saveTimer;

  /// Changes once the saved heights are read from the device.
  static final ValueNotifier<bool> loaded = ValueNotifier(false);

  static Future<void> load() => _load ??= () async {
        try {
          final raw = (await SharedPreferences.getInstance()).getString(_prefsKey);
          final decoded = raw == null ? null : jsonDecode(raw);
          if (decoded is Map) {
            for (final e in decoded.entries) {
              // Heights measured this session are newer than the saved ones.
              if (e.key is String && e.value is num) _heights.putIfAbsent(e.key, () => (e.value as num).toDouble());
            }
          }
        } catch (e) {
          debugPrint('[Dashboard] could not read card heights: $e');
        }
        loaded.value = true;
      }();

  static double? of(String key) => _heights[key];

  static void record(String key, double height) {
    final old = _heights[key];
    if (old != null && (old - height).abs() < 1) return;
    _heights[key] = height;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), _save);
  }

  static Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setString(_prefsKey, jsonEncode(_heights));
    } catch (e) {
      debugPrint('[Dashboard] could not save card heights: $e');
    }
  }
}

/// How many loading indicators are showing inside one card.
class _LoadingCount extends ChangeNotifier {
  int _n = 0;
  bool get loading => _n > 0;

  void add() {
    if (++_n == 1) notifyListeners();
  }

  void remove() {
    if (_n > 0 && --_n == 0) notifyListeners();
  }
}

class _DashCardScope extends InheritedWidget {
  final _LoadingCount loading;
  const _DashCardScope({required this.loading, required super.child});

  @override
  bool updateShouldNotify(_DashCardScope old) => false;
}

/// Wraps one dashboard card. While any DashLoading inside it is showing,
/// the card keeps the height it had last time it finished loading.
class DashCardSlot extends StatefulWidget {
  final String id;
  final Widget child;
  const DashCardSlot({super.key, required this.id, required this.child});

  /// Called by DashLoading: [add] while shown, [remove] once gone.
  static void Function()? register(BuildContext context) {
    final count = context.getInheritedWidgetOfExactType<_DashCardScope>()?.loading;
    if (count == null) return null;
    count.add();
    return count.remove;
  }

  @override
  State<DashCardSlot> createState() => _DashCardSlotState();
}

class _DashCardSlotState extends State<DashCardSlot> {
  final _loading = _LoadingCount();

  @override
  void initState() {
    super.initState();
    DashCardHeights.load();
  }

  @override
  void dispose() {
    _loading.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _DashCardScope(
        loading: _loading,
        child: _RememberedHeight(id: widget.id, loading: _loading, child: widget.child),
      );
}

class _RememberedHeight extends SingleChildRenderObjectWidget {
  final String id;
  final _LoadingCount loading;
  const _RememberedHeight({required this.id, required this.loading, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderRememberedHeight(id, loading);

  @override
  void updateRenderObject(BuildContext context, _RenderRememberedHeight renderObject) {
    renderObject
      ..id = id
      ..loading = loading;
  }
}

class _RenderRememberedHeight extends RenderProxyBox {
  _RenderRememberedHeight(this._id, this._loading);

  String _id;
  set id(String v) {
    if (v == _id) return;
    _id = v;
    markNeedsLayout();
  }

  _LoadingCount _loading;
  set loading(_LoadingCount v) {
    if (v == _loading) return;
    if (attached) {
      _loading.removeListener(_changed);
      v.addListener(_changed);
    }
    _loading = v;
    markNeedsLayout();
  }

  void _changed() {
    if (attached) markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _loading.addListener(_changed);
    DashCardHeights.loaded.addListener(_changed);
  }

  @override
  void detach() {
    _loading.removeListener(_changed);
    DashCardHeights.loaded.removeListener(_changed);
    super.detach();
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    // Phone and tablet widths lay a card out differently.
    final key = '$_id@${constraints.maxWidth.isFinite ? constraints.maxWidth.round() : 0}';
    var inner = constraints;
    final saved = DashCardHeights.of(key);
    if (_loading.loading && saved != null) {
      inner = constraints.copyWith(minHeight: saved.clamp(constraints.minHeight, constraints.maxHeight));
    }
    child.layout(inner, parentUsesSize: true);
    size = constraints.constrain(child.size);
    if (!_loading.loading) DashCardHeights.record(key, size.height);
  }
}
