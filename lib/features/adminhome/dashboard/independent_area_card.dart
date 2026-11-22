import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/organization/org_permission.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/repos/organization_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_query_repository.dart';
import 'package:respawnd1/core/repos/rescue_case/rescue_case_store.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
import 'package:respawnd1/features/generalhome/explore_reports_map.dart' show urgencyRingColor;

/// "Your area" on an independent rescuer's dashboard: a working map rather
/// than the public reports map. It shows the rescuer's coverage circle, the
/// unowned cases that have opened to them inside it (after the shelters'
/// head start), their own active cases, shelters nearby for handing an
/// animal over, and their home pin, which only their team sees. Cases other
/// organizations own and reporters' details are left out.
///
/// Also: Available / Paused, the radius (1–5 km), and how much room they
/// have (cases and animals in care against their limits). Shelters see
/// nothing here.
class IndependentAreaCard extends StatefulWidget {
  const IndependentAreaCard({super.key});

  @override
  State<IndependentAreaCard> createState() => _IndependentAreaCardState();
}

class _IndependentAreaCardState extends State<IndependentAreaCard> {
  final _repo = OrganizationRepository();
  String? _orgId;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orgSub;
  StreamSubscription<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _caseSub;
  Map<String, dynamic>? _org;
  ({String name, double lat, double lng})? _home;
  List<({String id, String name, double lat, double lng})> _shelters = const [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _cases = const [];
  double? _draftRadius;
  bool _savingToggle = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final db = FirebaseFirestore.instance;
    final orgId = (await db.collection('users').doc(uid).get()).data()?['organizationId'] as String? ?? '';
    if (orgId.isEmpty || !mounted) return;
    final first = await db.collection('organizations').doc(orgId).get();
    if (OrgKind.fromName(first.data()?['kind'] as String?) != OrgKind.independent || !mounted) return;
    setState(() {
      _orgId = orgId;
      _org = first.data();
    });
    _orgSub = db.collection('organizations').doc(orgId).snapshots().listen((s) {
      if (mounted) setState(() => _org = s.data());
    });
    _caseSub = RescueCaseQueryRepository(RescueCaseStore(db))
        .watchScopedCaseDocs((q) => q, includeReferred: true)
        .listen((docs) {
      if (mounted) setState(() => _cases = docs);
    }, onError: (Object e) => debugPrint('[IndependentAreaCard] cases: $e'));
    try {
      final home = await _repo.homeLocation(orgId);
      if (mounted) setState(() => _home = home);
    } catch (_) {}
    unawaited(_loadShelters());
  }

  /// Approved shelters with a saved shelter pin within 15 km of the
  /// rescuer's area, for handing an animal over.
  Future<void> _loadShelters() async {
    final center = _area?.lat == null ? null : (lat: _area!.lat!, lng: _area!.lng!);
    if (center == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('organizations')
          .where('verificationStatus', isEqualTo: 'approved')
          .get();
      final out = <({String id, String name, double lat, double lng})>[];
      for (final d in snap.docs) {
        final o = d.data();
        if (o['kind'] == 'independent') continue;
        final lat = (o['shelterLat'] as num?)?.toDouble();
        final lng = (o['shelterLng'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        if (Geolocator.distanceBetween(center.lat, center.lng, lat, lng) > 15000) continue;
        out.add((id: d.id, name: (o['name'] as String?) ?? 'Shelter', lat: lat, lng: lng));
      }
      if (mounted) setState(() => _shelters = out);
    } catch (e) {
      debugPrint('[IndependentAreaCard] shelters: $e');
    }
  }

  @override
  void dispose() {
    _orgSub?.cancel();
    _caseSub?.cancel();
    super.dispose();
  }

  ServiceArea? get _area {
    final raw = (_org?['serviceAreas'] as List?)?.whereType<Map>().toList() ?? const [];
    if (raw.isEmpty) return null;
    final a = ServiceArea.fromMap(Map<String, dynamic>.from(raw.first));
    return a.hasGeofence ? a : null;
  }

  int _n(String k, int fallback) => (_org?[k] as num?)?.toInt() ?? fallback;

  Future<void> _setAccepting(bool on) async {
    final orgId = _orgId;
    if (orgId == null) return;
    setState(() => _savingToggle = true);
    try {
      await _repo.setAcceptingCases(organizationId: orgId, accepting: on);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not change this: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _savingToggle = false);
    }
  }

  Future<void> _saveRadius(double km) async {
    final orgId = _orgId;
    if (orgId == null) return;
    try {
      await _repo.setIndependentRadius(organizationId: orgId, radiusKm: km);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not save your area: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _draftRadius = null);
    }
  }

  void _openCase(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RescueDetailPage(caseId: d.id, data: d.data())),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_orgId == null) return const SizedBox.shrink();
    final area = _area;
    final radius = _draftRadius ??
        (area?.radiusKm ?? IndependentRescuer.defaultRadiusKm)
            .clamp(IndependentRescuer.minRadiusKm, IndependentRescuer.maxRadiusKm)
            .toDouble();
    final accepting = _org?['acceptingCases'] != false;
    final cases = _n('activeCaseCount', 0);
    final maxCases = _n('maxActiveCases', IndependentRescuer.maxActiveCases);
    final animals = _n('animalsInCareCount', 0);
    final maxAnimals = _n('maxAnimalsInCare', IndependentRescuer.maxAnimalsInCare);
    final open = _cases.where((d) => (d.data()['organizationId'] as String? ?? '').isEmpty).toList();
    final mine = _cases
        .where((d) => d.data()['organizationId'] == _orgId)
        .where((d) => !RescueStatus.fromFirestoreValue(d.data()['status'] as String?).isTerminal)
        .toList();

    final markers = <Marker>{
      for (final d in [...open, ...mine])
        if (d.data()['lat'] is num && d.data()['lng'] is num)
          Marker(
            markerId: MarkerId('case-${d.id}'),
            position: LatLng((d.data()['lat'] as num).toDouble(), (d.data()['lng'] as num).toDouble()),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              HSVColor.fromColor(urgencyRingColor(d.data()['urgency'] as String?)).hue,
            ),
            alpha: (d.data()['organizationId'] as String? ?? '').isEmpty ? 1 : 0.75,
            infoWindow: InfoWindow(
              title: (d.data()['organizationId'] as String? ?? '').isEmpty
                  ? 'Open case · ${d.data()['urgency'] ?? 'Rescue'}'
                  : 'Your case · ${RescueStatus.fromFirestoreValue(d.data()['status'] as String?).label}',
              snippet: (d.data()['rescueType'] as String?) ?? 'Tap to open',
              onTap: () => _openCase(d),
            ),
          ),
      for (final s in _shelters)
        Marker(
          markerId: MarkerId('shelter-${s.id}'),
          position: LatLng(s.lat, s.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
          infoWindow: InfoWindow(title: s.name, snippet: 'Shelter · for handing an animal over'),
        ),
      if (_home != null)
        Marker(
          markerId: const MarkerId('home'),
          position: LatLng(_home!.lat, _home!.lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: const InfoWindow(title: 'Home', snippet: 'Only your team sees this'),
        ),
    };
    final center = area == null ? null : LatLng(area.lat!, area.lng!);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Your area', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary))),
              Text(accepting ? 'Available' : 'Paused',
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: accepting ? AppColors.success : AppColors.textSecondary)),
              Switch(
                value: accepting,
                activeThumbColor: AppColors.greenrspwn,
                onChanged: _savingToggle ? null : _setAccepting,
              ),
            ],
          ),
          Text(
            accepting
                ? '${open.length} open case(s) near you · $cases of $maxCases active cases · $animals of $maxAnimals animals in care'
                : 'Paused: no new cases or referrals reach you until you turn Available back on.',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 240,
              child: center == null
                  ? Container(
                      color: AppColors.tearspwn,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(16),
                      child: Text('Set your home location in your profile to see your area.',
                          textAlign: TextAlign.center, style: GoogleFonts.zain(color: AppColors.textSecondary)),
                    )
                  : GoogleMap(
                      initialCameraPosition: CameraPosition(target: center, zoom: 12.5),
                      markers: markers,
                      circles: {
                        Circle(
                          circleId: const CircleId('area'),
                          center: center,
                          radius: radius * 1000,
                          strokeWidth: 2,
                          strokeColor: AppColors.greenrspwn,
                          fillColor: AppColors.greenrspwn.withValues(alpha: 0.12),
                        ),
                      },
                      myLocationButtonEnabled: false,
                      mapToolbarEnabled: false,
                      zoomControlsEnabled: true,
                      // Pan and zoom the map instead of scrolling the page.
                      gestureRecognizers: {Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new)},
                    ),
            ),
          ),
          if (center != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Text('Radius', style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700)),
                Expanded(
                  child: Slider(
                    value: radius,
                    min: IndependentRescuer.minRadiusKm,
                    max: IndependentRescuer.maxRadiusKm,
                    divisions: 8,
                    label: '${radius.toStringAsFixed(1)} km',
                    activeColor: AppColors.textPrimary,
                    onChanged: (v) => setState(() => _draftRadius = v),
                    onChangeEnd: _saveRadius,
                  ),
                ),
                Text('${radius.toStringAsFixed(1)} km', style: GoogleFonts.zain(fontSize: 13)),
              ],
            ),
            Text(
              'Red, yellow and green pins are cases by urgency (faded: yours). Violet: shelters. Blue: your home. '
              'New reports open to you after shelters have had first look; Critical ones right away.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}
