import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show Factory;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:respawnd1/features/rescue/lost_found_track_case.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart'
as community_adoption_util;
import 'package:respawnd1/core/utils/public_case_visibility.dart';
import 'package:respawnd1/core/utils/species_summary.dart' as species_summary_util;
import 'package:respawnd1/features/adoption/community_adoption_track_page.dart';

import '../../app_theme.dart';

/// Ring color for a marker/thumbnail — encodes the report's urgency level,
/// matching the palette used when the report was submitted (rescue_page.dart).
Color urgencyRingColor(String? urgency) {
  switch (urgency) {
    case 'Critical':
      return Colors.redAccent;
    case 'Medium':
      return AppColors.yellowrspwn;
    case 'Low':
      return AppColors.greenrspwn;
    default:
      return AppColors.slaterspwn;
  }
}

double _hueForUrgency(String? urgency) {
  switch (urgency) {
    case 'Critical':
      return BitmapDescriptor.hueRed;
    case 'Medium':
      return BitmapDescriptor.hueYellow;
    case 'Low':
      return BitmapDescriptor.hueGreen;
    default:
      return BitmapDescriptor.hueAzure;
  }
}

/// Converts any rescue-type category color into the nearest Google Maps
/// default-marker hue — used as the instant fallback pin before the
/// custom-colored ring icon (which can render any exact color) finishes
/// loading, so even that brief placeholder follows the rescue-type color
/// instead of urgency.
double _hueForColor(Color color) => HSVColor.fromColor(color).hue;

/// Report categories shown on the map. Each one gets its own pin color +
/// icon so a report's type is readable at a glance, e.g. red = Illness,
/// blue = Lost Pet.
class ReportCategory {
  final String label;
  final Color color;
  final IconData icon;

  const ReportCategory(this.label, this.color, this.icon);
}

const List<ReportCategory> kReportCategories = [
  ReportCategory('Illness', Color(0xFFE53935), Icons.sick_outlined),
  ReportCategory('Injury', Color(0xFFFB8C00), Icons.healing),
  ReportCategory('Abandonment', Color(0xFF8D6E63), Icons.no_accounts),
  ReportCategory('Neglect or Abuse', Color(0xFFAD1457), Icons.report),
  ReportCategory('Pet Surrender', Color(0xFF00897B), Icons.pets),
  ReportCategory('Lost Pet', Color(0xFF1E88E5), Icons.search),
  ReportCategory('Aggressive Animal', Color(0xFF37474F), Icons.pets),
];

const ReportCategory kFallbackReportCategory =
ReportCategory('Other', AppColors.textSecondary, Icons.location_on);

ReportCategory categoryForRescueType(String? rescueType) {
  for (final c in kReportCategories) {
    if (c.label.toLowerCase() == (rescueType ?? '').toLowerCase()) return c;
  }
  return kFallbackReportCategory;
}

/// Lightweight row pulled from a `cases` doc — just what the map + preview
/// card needs.
class ReportMapEntry {
  final String caseId;
  final double lat;
  final double lng;
  final double? riderLat;
  final double? riderLng;
  final String rescueType;
  final String address;
  final String urgency;
  final String animalType;
  final String statusLabel;
  final String reporterTag;
  final DateTime? createdAt;
  final List<String> photoUrls;
  final String? rawStatus;
  final String? rejectionReason;
  final String? collarTagId;
  // True for entries sourced from the `petAlerts` collection (the owner
  // "report my pet lost" flow) rather than `cases` — the map previously
  // only ever queried `cases`, so a lost-pet alert (and its collar tag)
  // had no path onto the Explore Map at all, regardless of filter. This
  // flag lets the preview sheet route "View Details" to the correct
  // tracking page for whichever collection the entry actually came from.
  final bool isPetAlert;

  const ReportMapEntry({
    required this.caseId,
    required this.lat,
    required this.lng,
    this.riderLat,
    this.riderLng,
    required this.rescueType,
    required this.address,
    required this.urgency,
    required this.animalType,
    required this.statusLabel,
    required this.reporterTag,
    required this.createdAt,
    required this.photoUrls,
    this.rawStatus,
    this.rejectionReason,
    this.collarTagId,
    this.isPetAlert = false,
  });

  /// True only for a Lost Pet report that's linked to a registered collar
  /// tag (`scannedTagId` on the case doc) — used to surface the collar tag
  /// badge/link on the map and report preview, and only for that report
  /// type per spec.
  bool get hasLostPetCollarTag =>
      rescueType.toLowerCase() == 'lost pet' &&
          (collarTagId != null && collarTagId!.trim().isNotEmpty);

  /// True while a transporter is actively en route — the pin should follow
  /// their live position instead of sitting at the original report location.
  bool get hasLiveRider => riderLat != null && riderLng != null;

  /// True for a healthy/low-urgency report that was rejected (and isn't a
  /// Lost Pet report) — see community_adoption_eligibility.dart. The map
  /// keeps this pin visible and offers the Community Adoption listing
  /// action instead of hiding it like any other rejected case.
  bool get isCommunityAdoptionEligible => community_adoption_util.isCommunityAdoptionEligible(
    status: rawStatus,
    rejectionReason: rejectionReason,
    rescueType: rescueType,
  );

  static ReportMapEntry? fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final history = (data['statusHistory'] as List?)?.cast<Map>() ?? [];
    final latestStatus =
    history.isNotEmpty ? (history.last['status'] as String? ?? 'Pending') : 'Pending';

    final ts = data['createdAt'] as Timestamp?;
    final reporterName = (data['reporterName'] as String? ?? '').trim();
    final reporterTag = reporterName.isNotEmpty
        ? 'Reported by $reporterName'
        : 'Reported by a community member';

    // Species summary derived the same way PublicRescueItem does (spec:
    // the map must never disagree with the feed about a multi-animal
    // case's species) — prefers `animals[]`, falls back to the legacy
    // top-level `animalType` for a pre-`animals[]` report.
    final animalSummary = species_summary_util.summarizeSpecies(
      animals: data['animals'] as List?,
      legacyAnimalType: data['animalType'] as String?,
    );

    return ReportMapEntry(
      caseId: doc.id,
      lat: lat,
      lng: lng,
      riderLat: (data['riderLastLat'] as num?)?.toDouble(),
      riderLng: (data['riderLastLng'] as num?)?.toDouble(),
      rescueType: data['rescueType'] as String? ?? '',
      address: (data['address'] as String? ?? '').trim().isEmpty
          ? '-'
          : data['address'] as String,
      urgency: data['urgency'] as String? ?? '',
      animalType: animalSummary,
      statusLabel: latestStatus,
      reporterTag: reporterTag,
      createdAt: ts?.toDate(),
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      rawStatus: data['status'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      collarTagId: data['scannedTagId'] as String?,
    );
  }

  /// Builds a map entry from a `petAlerts` doc — only ever called for
  /// `type: 'lost'` alerts (the owner-reported "my pet is missing" flow).
  /// Tagged with `rescueType: 'Lost Pet'` so it automatically picks up the
  /// same color/icon/filter-chip behavior as any other Lost Pet entry.
  static ReportMapEntry? fromPetAlertDoc(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;

    final ts = data['createdAt'] as Timestamp?;
    final reporterName = (data['reporterName'] as String? ?? '').trim();
    final reporterTag = reporterName.isNotEmpty
        ? 'Reported by $reporterName'
        : 'Reported by a community member';

    final status = (data['status'] as String? ?? 'open').toLowerCase();
    final statusLabel = switch (status) {
      'verified' => 'Match verified — coordinating handover',
      'resolved' => 'Resolved',
      _ => 'Searching for possible matches',
    };

    return ReportMapEntry(
      caseId: doc.id,
      lat: lat,
      lng: lng,
      rescueType: 'Lost Pet',
      address: (data['address'] as String? ?? '').trim().isEmpty
          ? '-'
          : data['address'] as String,
      urgency: '',
      animalType: data['species'] as String? ?? '',
      statusLabel: statusLabel,
      reporterTag: reporterTag,
      createdAt: ts?.toDate(),
      photoUrls: List<String>.from(data['photoUrls'] ?? []),
      collarTagId: data['scannedTagId'] as String?,
      isPetAlert: true,
    );
  }
}

List<ReportMapEntry> extractPublicReports(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final out = <ReportMapEntry>[];
  for (final doc in docs) {
    final data = doc.data();
    final isPublic = isCasePublic(
      reporterId: data['reporterId'] as String?,
      viewerId: currentUserId,
      status: data['status'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      rescueType: data['rescueType'] as String?,
      hiddenFromExplore: data['hiddenFromExplore'] == true,
      groupId: data['groupId'] as String?,
      docId: doc.id,
    );
    if (!isPublic) continue;

    final report = ReportMapEntry.fromDoc(doc);
    if (report != null) out.add(report);
  }
  return out;
}

/// The current user's OWN reports, for the "My Reports" map filter — the
/// same [isCasePublic] rules apply (hidden/final-status/groupId/Community
/// Adoption carve-out), just with the self-report exclusion deliberately
/// bypassed (`viewerId: null`), since these reports are being shown
/// *because* they're the viewer's own, not despite it. Reuses the one
/// shared visibility predicate rather than a second implementation.
List<ReportMapEntry> extractMyReports(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
    ) {
  final out = <ReportMapEntry>[];
  for (final doc in docs) {
    final data = doc.data();
    if (data['reporterId'] != uid) continue;
    final isPublic = isCasePublic(
      reporterId: data['reporterId'] as String?,
      viewerId: null,
      status: data['status'] as String?,
      rejectionReason: data['rejectionReason'] as String?,
      rescueType: data['rescueType'] as String?,
      hiddenFromExplore: data['hiddenFromExplore'] == true,
      groupId: data['groupId'] as String?,
      docId: doc.id,
    );
    if (!isPublic) continue;

    final report = ReportMapEntry.fromDoc(doc);
    if (report != null) out.add(report);
  }
  return out;
}

// Statuses that mean an alert is no longer active — same set
// activity_feed.dart already uses for petAlerts, kept consistent here.
const Set<String> _kAlertDismissedStatuses = {
  'dismissed',
  'cancelled',
  'withdrawn',
  'rejected',
};

/// Public lost-pet alerts for the Explore Map — the `petAlerts` counterpart
/// of [extractPublicReports]. Only `type: 'lost'` alerts are included
/// (found-pet alerts aren't "reports" in the rescue-map sense); the
/// viewer's own alerts are excluded here for the same reason their own
/// `cases` docs are excluded from the public pool — they see those via
/// "My Reports" instead.
List<ReportMapEntry> extractPublicLostPetAlerts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    ) {
  final currentUserId = FirebaseAuth.instance.currentUser?.uid;
  final out = <ReportMapEntry>[];
  for (final doc in docs) {
    final data = doc.data();
    if ((data['type'] as String? ?? '') != 'lost') continue;
    if (data['reporterId'] == currentUserId) continue;
    final status = (data['status'] as String? ?? 'open').toLowerCase();
    if (_kAlertDismissedStatuses.contains(status)) continue;
    final groupId = data['groupId'] as String?;
    if (groupId != null && groupId.isNotEmpty && groupId != doc.id) continue;

    final entry = ReportMapEntry.fromPetAlertDoc(doc);
    if (entry != null) out.add(entry);
  }
  return out;
}

/// The viewer's own lost-pet alerts, for the "My Reports" map filter —
/// the `petAlerts` counterpart of [extractMyReports].
List<ReportMapEntry> extractMyLostPetAlerts(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String uid,
    ) {
  final out = <ReportMapEntry>[];
  for (final doc in docs) {
    final data = doc.data();
    if ((data['type'] as String? ?? '') != 'lost') continue;
    if (data['reporterId'] != uid) continue;
    final status = (data['status'] as String? ?? 'open').toLowerCase();
    if (_kAlertDismissedStatuses.contains(status)) continue;
    final groupId = data['groupId'] as String?;
    if (groupId != null && groupId.isNotEmpty && groupId != doc.id) continue;

    final entry = ReportMapEntry.fromPetAlertDoc(doc);
    if (entry != null) out.add(entry);
  }
  return out;
}

/// Scope-modifier filter chip labels — combined with rescue-type filters
/// using AND, never OR (see _ExploreReportsMapState._visibleMarkers).
const String kCommunityAdoptionFilterLabel = 'Community Adoption';
const String kMyReportsFilterLabel = 'My Reports';

class ExploreReportsMap extends StatefulWidget {
  final VoidCallback? onSeeAll;
  const ExploreReportsMap({super.key, this.onSeeAll});

  @override
  State<ExploreReportsMap> createState() => _ExploreReportsMapState();
}

class _ExploreReportsMapState extends State<ExploreReportsMap> {
  GoogleMapController? _mapController;
  final Map<String, BitmapDescriptor> _iconCache = {};
  final Set<String> _iconRequestsInFlight = {};
  // Empty set == "All" — never a normal selected chip alongside others (see
  // _toggleFilter/_selectAll). Rescue-type labels inside this set are OR'd
  // together; the two scope modifiers (Community Adoption/My Reports) are
  // AND'd against that OR group and against each other — see
  // _visibleMarkers.
  final Set<String> _selectedFilters = {};
  LatLng _initialCamera = const LatLng(14.5416, 121.0644); // Pateros, Metro Manila fallback

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  // Separate subscription for "My Reports" — deliberately NOT sourced from
  // the global top-150-by-recency `_sub` query above. That query is scoped
  // to the most recently created cases app-wide, so a viewer's own report
  // silently drops out of it (and therefore out of "My Reports", even with
  // the chip selected) once enough other people's newer reports push it
  // past position 150. Querying `reporterId == uid` directly guarantees
  // every one of the viewer's own reports is always considered, regardless
  // of how much other public traffic exists. No `orderBy` here since it's
  // paired with a `where` and ordering doesn't matter for map pins.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myReportsSub;
  // Lost-pet alerts live in a wholly separate `petAlerts` collection (the
  // owner "report my pet lost" flow writes there, not to `cases`) — two
  // more subscriptions merge that source in so those reports (and their
  // collar tags) actually have a path onto the map at all.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertsSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _myAlertsSub;

  List<ReportMapEntry> _caseReports = [];
  List<ReportMapEntry> _alertReports = [];
  List<ReportMapEntry> _caseMyReports = [];
  List<ReportMapEntry> _alertMyReports = [];

  List<ReportMapEntry> get _allReports => [..._caseReports, ..._alertReports];
  // The viewer's own reports — only computed/used when the My Reports
  // filter is active; kept as a separate list rather than folded into
  // _allReports since the two use different visibility rules (see
  // extractMyReports's doc comment).
  List<ReportMapEntry> get _myReports => [..._caseMyReports, ..._alertMyReports];
  bool _loadingReports = true;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _centerOnUser();
    _listenToReports();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _myReportsSub?.cancel();
    _alertsSub?.cancel();
    _myAlertsSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _listenToReports() {
    _sub = FirebaseFirestore.instance
        .collection('cases')
        .orderBy('serverCreatedAt', descending: true)
        .limit(150)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _caseReports = extractPublicReports(snap.docs);
        _loadingReports = false;
        _loadError = null;
      });
    }, onError: (e) {
      if (!mounted) return;
      setState(() {
        _loadingReports = false;
        _loadError = e;
      });
    });

    // Public lost-pet alerts (petAlerts, type: 'lost') — single equality
    // `where`, no `orderBy`, so no composite index is needed.
    _alertsSub = FirebaseFirestore.instance
        .collection('petAlerts')
        .where('type', isEqualTo: 'lost')
        .limit(150)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _alertReports = extractPublicLostPetAlerts(snap.docs);
      });
    }, onError: (_) {
      // Non-fatal — the map still works off cases-derived reports.
    });

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _myReportsSub = FirebaseFirestore.instance
          .collection('cases')
          .where('reporterId', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() {
          _caseMyReports = extractMyReports(snap.docs, uid);
        });
      }, onError: (_) {
        // Non-fatal — "My Reports" simply stays empty; the rest of the map
        // keeps working off _allReports.
      });

      _myAlertsSub = FirebaseFirestore.instance
          .collection('petAlerts')
          .where('reporterId', isEqualTo: uid)
          .snapshots()
          .listen((snap) {
        if (!mounted) return;
        setState(() {
          _alertMyReports = extractMyLostPetAlerts(snap.docs, uid);
        });
      }, onError: (_) {
        // Non-fatal — same fallback as above.
      });
    }
  }

  Future<void> _centerOnUser() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 8),
        onTimeout: () => Geolocator.getLastKnownPosition().then(
              (p) => p ?? Position(
            latitude: _initialCamera.latitude,
            longitude: _initialCamera.longitude,
            timestamp: DateTime.now(),
            accuracy: 0,
            altitude: 0,
            altitudeAccuracy: 0,
            heading: 0,
            headingAccuracy: 0,
            speed: 0,
            speedAccuracy: 0,
          ),
        ),
      );
      if (!mounted) return;
      setState(() => _initialCamera = LatLng(pos.latitude, pos.longitude));
      _mapController?.animateCamera(CameraUpdate.newLatLng(_initialCamera));
      _saveLastLocation(pos.latitude, pos.longitude);
    } catch (_) {

    }
  }
  void _saveLastLocation(double lat, double lng) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'lastLat': lat,
        'lastLng': lng,
        'lastLocationAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ).catchError((_) {});
  }

  Future<void> _ensureIconFor(ReportMapEntry r) async {
    if (_iconCache.containsKey(r.caseId) ||
        _iconRequestsInFlight.contains(r.caseId)) {
      return;
    }
    _iconRequestsInFlight.add(r.caseId);
    // Ring color AND icon glyph follow the same rescue-type styling used
    // on the filter chips (kReportCategories is the single source of
    // truth) — Community-Adoption-eligible cases get a distinct lavender
    // + heart look instead, since the animal was assessed healthy and its
    // original rescue-type styling would be misleading at this point.
    final ringColor = r.isCommunityAdoptionEligible
        ? AppColors.lavenderrspwn
        : categoryForRescueType(r.rescueType).color;
    final glyph = r.isCommunityAdoptionEligible
        ? Icons.favorite
        : categoryForRescueType(r.rescueType).icon;

    try {
      final quick = await _buildRingIcon(ringColor, icon: glyph, photoBytes: null);
      if (mounted) setState(() => _iconCache[r.caseId] = quick);
    } catch (_) {
      // Leave it to fall back to a default hued marker in _markerFor.
    }

    if (r.photoUrls.isNotEmpty) {
      try {
        final resp = await http
            .get(Uri.parse(r.photoUrls.first))
            .timeout(const Duration(seconds: 8));
        if (resp.statusCode == 200) {
          final upgraded =
          await _buildRingIcon(ringColor, icon: glyph, photoBytes: resp.bodyBytes);
          if (mounted) setState(() => _iconCache[r.caseId] = upgraded);
        }
      } catch (_) {
        // Keep the ring-only icon — the photo just didn't come through.
      }
    }

    _iconRequestsInFlight.remove(r.caseId);
  }

  Future<BitmapDescriptor> _buildRingIcon(
      Color ringColor, {
        required IconData icon,
        Uint8List? photoBytes,
      }) async {
    const double size = 112;
    const double ringWidth = 8;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const radius = size / 2;
    const center = Offset(radius, radius);

    // Outer ring = urgency color.
    canvas.drawCircle(center, radius, Paint()..color = ringColor);
    // White gap between the ring and the photo/fill.
    canvas.drawCircle(center, radius - ringWidth, Paint()..color = Colors.white);

    const innerRadius = radius - ringWidth - 3;

    if (photoBytes != null) {
      try {
        final codec = await ui.instantiateImageCodec(photoBytes, targetWidth: size.toInt());
        final frame = await codec.getNextFrame();
        final image = frame.image;

        canvas.save();
        canvas.clipPath(Path()..addOval(Rect.fromLTWH(0, 0, size, size).deflate(ringWidth + 3)));

        final w = image.width.toDouble();
        final h = image.height.toDouble();
        Rect fitSrc = Rect.fromLTWH(0, 0, w, h);
        if (w > h) {
          fitSrc = Rect.fromLTWH((w - h) / 2, 0, h, h);
        } else if (h > w) {
          fitSrc = Rect.fromLTWH(0, (h - w) / 2, w, w);
        }
        canvas.drawImageRect(
          image,
          fitSrc,
          const Rect.fromLTWH(ringWidth + 3, ringWidth + 3, size - (ringWidth + 3) * 2, size - (ringWidth + 3) * 2),
          Paint(),
        );
        canvas.restore();
      } catch (_) {
        // Photo failed to decode — same solid-color + icon look as the
        // no-photo case below, so it still reads as "this rescue type".
        canvas.drawCircle(center, innerRadius, Paint()..color = ringColor);
        _paintIcon(canvas, icon, center, innerRadius);
      }
    } else {
      // No photo yet — solid rescue-type color with the exact same icon
      // glyph shown on the matching filter chip, so the pin reads the
      // same way the chip does at a glance instead of just a bare ring.
      canvas.drawCircle(center, innerRadius, Paint()..color = ringColor);
      _paintIcon(canvas, icon, center, innerRadius);
    }

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  // Renders a Material icon glyph directly onto the marker canvas, white on
  // the rescue-type color fill — mirrors how _FilterChip shows the same
  // icon in white against its selected/colored background.
  void _paintIcon(Canvas canvas, IconData icon, Offset center, double innerRadius) {
    final iconSize = innerRadius * 1.15;
    final textPainter = TextPainter(textDirection: TextDirection.ltr)
      ..text = TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: iconSize,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: Colors.white,
        ),
      )
      ..layout();
    textPainter.paint(
      canvas,
      Offset(center.dx - textPainter.width / 2, center.dy - textPainter.height / 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mapHeight = (MediaQuery.sizeOf(context).height * 0.55).clamp(360.0, 560.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: mapHeight,
              width: double.infinity,
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(target: _initialCamera, zoom: 13.5),
                    onMapCreated: (c) => _mapController = c,
                    markers: _loadingReports ? const {} : _visibleMarkers(),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                    gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                      Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                      ),
                    },
                  ),

                  // Recenter button — mirrors the floating action buttons in
                  // the map-app reference.
                  Positioned(
                    right: 12,
                    top: 12,
                    child: _RoundIconButton(
                      icon: Icons.my_location,
                      onTap: () => _mapController?.animateCamera(
                        CameraUpdate.newLatLng(_initialCamera),
                      ),
                    ),
                  ),

                  if (widget.onSeeAll != null)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: GestureDetector(
                        onTap: widget.onSeeAll,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'See All Reports',
                                style: GoogleFonts.zain(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_forward, size: 14, color: AppColors.textPrimary),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (_loadingReports)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: Center(
                          child: CircularProgressIndicator(color: AppColors.greenrspwn),
                        ),
                      ),
                    ),

                  if (!_loadingReports && _loadError != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _MapBanner(
                        text: 'Could not load reports right now.',
                      ),
                    ),

                  if (!_loadingReports && _loadError == null && _allReports.isEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: _MapBanner(text: 'No public reports yet.'),
                    ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Filter row — multi-select toggle chips (spec): tapping an
        // unselected chip adds it, tapping a selected one removes it; "All"
        // clears everything and is never itself a member of the set. No
        // separate Apply button — every tap updates markers immediately via
        // setState.
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              _FilterChip(
                label: 'All',
                color: AppColors.textPrimary,
                icon: Icons.public,
                selected: _selectedFilters.isEmpty,
                onTap: () => setState(() => _selectedFilters.clear()),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: kCommunityAdoptionFilterLabel,
                color: AppColors.greenrspwn,
                icon: Icons.favorite,
                selected: _selectedFilters.contains(kCommunityAdoptionFilterLabel),
                onTap: () => _toggleFilter(kCommunityAdoptionFilterLabel),
              ),
              const SizedBox(width: 8),
              _FilterChip(
                label: kMyReportsFilterLabel,
                color: AppColors.lavenderrspwn,
                icon: Icons.person_outline,
                selected: _selectedFilters.contains(kMyReportsFilterLabel),
                onTap: () => _toggleFilter(kMyReportsFilterLabel),
              ),
              const SizedBox(width: 8),
              for (final c in kReportCategories) ...[
                _FilterChip(
                  label: c.label,
                  color: c.color,
                  icon: c.icon,
                  selected: _selectedFilters.contains(c.label),
                  onTap: () => _toggleFilter(c.label),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _toggleFilter(String label) {
    setState(() {
      if (_selectedFilters.contains(label)) {
        _selectedFilters.remove(label);
      } else {
        _selectedFilters.add(label);
      }
    });
  }

  /// Filter-combination rules (spec): rescue-type labels are OR'd together
  /// (any case matching ANY selected type qualifies); the two scope
  /// modifiers (Community Adoption / My Reports) are each AND'd on top of
  /// that OR group, and AND'd against each other when both are selected.
  /// "My Reports" swaps the base pool to the viewer's own reports (which
  /// the ordinary public pool excludes by design) rather than filtering the
  /// public pool by reporterId.
  Set<Marker> _visibleMarkers() {
    final myReportsSelected = _selectedFilters.contains(kMyReportsFilterLabel);
    final communityAdoptionSelected = _selectedFilters.contains(kCommunityAdoptionFilterLabel);
    final typeFilters = _selectedFilters
        .where((f) => f != kMyReportsFilterLabel && f != kCommunityAdoptionFilterLabel)
        .toSet();

    final basePool = myReportsSelected ? _myReports : _allReports;

    final filtered = basePool.where((r) {
      if (communityAdoptionSelected && !r.isCommunityAdoptionEligible) return false;
      if (typeFilters.isNotEmpty && !typeFilters.contains(categoryForRescueType(r.rescueType).label)) {
        return false;
      }
      return true;
    });

    return filtered.map(_markerFor).toSet();
  }



  Marker _markerFor(ReportMapEntry r) {
    _ensureIconFor(r); // fire-and-forget; upgrades the icon once ready
    final category = categoryForRescueType(r.rescueType);
    final position = r.hasLiveRider
        ? LatLng(r.riderLat!, r.riderLng!)
        : LatLng(r.lat, r.lng);
    return Marker(
      markerId: MarkerId(r.caseId),
      position: position,
      icon: _iconCache[r.caseId] ??
          BitmapDescriptor.defaultMarkerWithHue(
            r.isCommunityAdoptionEligible
                ? BitmapDescriptor.hueViolet
                : _hueForColor(category.color),
          ),
      onTap: () => _showReportPreview(r, category),
    );
  }

  Future<void> _openCollarTag(String tagId) async {
    final uri = Uri.parse(AppLinks.tagUrl(tagId));
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Non-fatal — worst case the tap silently does nothing.
    }
  }

  void _showReportPreview(ReportMapEntry r, ReportCategory category) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: r.photoUrls.isNotEmpty
                      ? Image.network(
                    r.photoUrls.first,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _thumbFallback(category),
                  )
                      : _thumbFallback(category),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: category.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            category.label,
                            style: GoogleFonts.zain(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '#${r.caseId.substring(0, 7).toUpperCase()} • ${r.animalType}',
                        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (r.hasLiveRider) ...[
              Row(children: [
                const Icon(Icons.local_shipping, size: 14, color: AppColors.greenrspwn),
                const SizedBox(width: 6),
                Text(
                  'Transporter en route — pin shows their live location',
                  style: GoogleFonts.zain(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.greenrspwn,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            Row(children: [
              const Icon(Icons.location_on_outlined, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.info_outline, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  r.statusLabel,
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ]),
            if (r.urgency.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.priority_high, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Urgency: ${r.urgency}',
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                ),
              ]),
            ],
            if (r.hasLostPetCollarTag) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _openCollarTag(r.collarTagId!),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.lavenderrspwn.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code, size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Text(
                        'Registered collar tag — tap to view',
                        style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (r.isCommunityAdoptionEligible) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.greenrspwn.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.favorite, size: 14, color: AppColors.greenrspwn),
                    const SizedBox(width: 6),
                    Text(
                      'This animal is open for adoption.',
                      style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.greenrspwn),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => r.isPetAlert
                          ? LostFoundTrackCasePage(alertId: r.caseId)
                          : (r.isCommunityAdoptionEligible
                          ? CommunityAdoptionTrackPage(caseId: r.caseId)
                          : TrackCasePage(caseId: r.caseId, initialTabIndex: 0)),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  elevation: 0,
                ),
                child: Text('View Details', style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thumbFallback(ReportCategory category) {
    return Container(
      width: 60,
      height: 60,
      color: category.color.withOpacity(0.15),
      child: Icon(category.icon, color: category.color),
    );
  }
}

class _MapBanner extends StatelessWidget {
  final String text;
  const _MapBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.slaterspwn,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.color,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color : color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(selected ? 0 : 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : color),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}