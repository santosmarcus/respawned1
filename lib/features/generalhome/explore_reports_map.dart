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
import 'package:respawnd1/features/rescue/track_case_page.dart';
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
  ReportCategory('Trapped/Disaster', Color(0xFFFFB300), Icons.warning_amber),
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
  });

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
  String? _selectedCategory; // null == "All"
  LatLng _initialCamera = const LatLng(14.5416, 121.0644); // Pateros, Metro Manila fallback

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  List<ReportMapEntry> _allReports = [];
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
        _allReports = extractPublicReports(snap.docs);
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
    // Community-Adoption-eligible cases get a distinct ring color instead
    // of the usual urgency color — the animal was assessed healthy, so an
    // urgency-red/yellow ring would be misleading at this point; lavender
    // marks it as "up for community adoption" instead, distinct from every
    // urgency color so the two are never confused on the map.
    final ringColor = r.isCommunityAdoptionEligible ? AppColors.lavenderrspwn : urgencyRingColor(r.urgency);

    try {
      final quick = await _buildRingIcon(ringColor, photoBytes: null);
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
          await _buildRingIcon(ringColor, photoBytes: resp.bodyBytes);
          if (mounted) setState(() => _iconCache[r.caseId] = upgraded);
        }
      } catch (_) {
        // Keep the ring-only icon — the photo just didn't come through.
      }
    }

    _iconRequestsInFlight.remove(r.caseId);
  }

  Future<BitmapDescriptor> _buildRingIcon(Color ringColor, {Uint8List? photoBytes}) async {
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
        canvas.drawCircle(center, innerRadius, Paint()..color = ringColor.withOpacity(0.25));
      }
    } else {
      canvas.drawCircle(center, innerRadius, Paint()..color = ringColor.withOpacity(0.25));
    }

    final image = await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
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

        // Filter row — same pill treatment as the reference, colored per
        // report type so it doubles as a legend.
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
                selected: _selectedCategory == null,
                onTap: () => setState(() => _selectedCategory = null),
              ),
              const SizedBox(width: 8),
              for (final c in kReportCategories) ...[
                _FilterChip(
                  label: c.label,
                  color: c.color,
                  icon: c.icon,
                  selected: _selectedCategory == c.label,
                  onTap: () => setState(() => _selectedCategory = c.label),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Set<Marker> _visibleMarkers() {
    final filtered = _selectedCategory == null
        ? _allReports
        : _allReports.where((r) => categoryForRescueType(r.rescueType).label == _selectedCategory);
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
            r.isCommunityAdoptionEligible ? BitmapDescriptor.hueViolet : _hueForUrgency(r.urgency),
          ),
      onTap: () => _showReportPreview(r, category),
    );
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
                      builder: (_) => r.isCommunityAdoptionEligible
                          ? CommunityAdoptionTrackPage(caseId: r.caseId)
                          : TrackCasePage(caseId: r.caseId, initialTabIndex: 0),
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