import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/community_adoption_listing.dart';

const String _geocodingApiKey = 'AIzaSyChQ9xBxn59vAehhzsPuMgCqJoW_qbVOs0';

const double kCommunityAdoptionProximityMeters = 100;

class CommunityAdoptionTrackPage extends StatefulWidget {
  final String caseId;
  const CommunityAdoptionTrackPage({super.key, required this.caseId});

  @override
  State<CommunityAdoptionTrackPage> createState() =>
      _CommunityAdoptionTrackPageState();
}

class _CommunityAdoptionTrackPageState
    extends State<CommunityAdoptionTrackPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.yellowrspwn,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Community Adoption',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('cases').doc(widget.caseId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.data();
          if (data == null) {
            return Center(
              child: Text('This report is no longer available.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            );
          }

          return _CommunityAdoptionBody(caseId: widget.caseId, data: data);
        },
      ),
    );
  }
}

class _CommunityAdoptionBody extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _CommunityAdoptionBody({required this.caseId, required this.data});

  @override
  State<_CommunityAdoptionBody> createState() => _CommunityAdoptionBodyState();
}

class _CommunityAdoptionBodyState extends State<_CommunityAdoptionBody> {
  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final photoUrls = List<String>.from(data['photoUrls'] ?? const []);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhotoGallery(photoUrls: photoUrls),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.greenrspwn.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.favorite, size: 16, color: AppColors.greenrspwn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    ((data['animals'] as List?)?.length ?? 1) > 1
                        ? 'These animals are open for adoption.'
                        : 'This animal is open for adoption.',
                    style: GoogleFonts.zain(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Text('#${widget.caseId.substring(0, 7).toUpperCase()}',
              style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 12),

          // Reported information only -- no pickup/transporter/clinic
          // fields belong here, since this animal was never dispatched
          // for rescue.
          _DetailRow('Reporter Name', data['reporterName']),
          _DetailRow('Description', data['condition']),
          _AnimalGroupSection(data: data),

          const SizedBox(height: 8),
          const Divider(color: AppColors.slaterspwn),
          const SizedBox(height: 8),

          _LatestLocationSection(caseId: widget.caseId, data: data),

          const SizedBox(height: 8),
          const Divider(color: AppColors.slaterspwn),
          const SizedBox(height: 8),

          _CommunityReportSection(caseId: widget.caseId),

          const SizedBox(height: 16),
          _AdoptionButtonSection(caseId: widget.caseId, data: data),

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _PhotoGallery extends StatelessWidget {
  final List<String> photoUrls;
  const _PhotoGallery({required this.photoUrls});

  @override
  Widget build(BuildContext context) {
    if (photoUrls.isEmpty) {
      return Container(
        height: 200,
        decoration: BoxDecoration(
          color: AppColors.tearspwn,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(Icons.image_not_supported_outlined, size: 48, color: AppColors.textSecondary),
        ),
      );
    }
    return SizedBox(
      height: 200,
      child: PageView.builder(
        itemCount: photoUrls.length,
        itemBuilder: (context, i) => ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.network(
            photoUrls[i],
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.tearspwn,
              child: const Icon(Icons.image_not_supported_outlined, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(value!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Same animal breakdown shape as track_case_page.dart's own
/// _AnimalGroupSection/_AnimalDetailBlock -- duplicated here rather than
/// imported, since that file's classes are private to it. Kept in sync
/// manually with the same `animals[]` field set (see
/// core/utils/animal_health_assessment.dart).
class _AnimalGroupSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnimalGroupSection({required this.data});

  Map<String, dynamic> _animalMap(Map raw) => {
    'animalType': raw['species'],
    'breed': raw['breed'],
    'sex': raw['sex'],
    'size': raw['size'],
    'colorMarkings': raw['colorMarkings'],
    'biteRisk': raw['biteRisk'],
    'escapeRisk': raw['escapeRisk'],
    'handlingNotes': raw['handlingNotes'],
    'bodyCondition': raw['bodyCondition'],
    'mobility': raw['mobility'],
    'alertness': raw['alertness'],
    'behavior': raw['behavior'],
    'eyesNoseMouth': raw['eyesNoseMouth'],
    'skinAndCoat': raw['skinAndCoat'],
    'appetiteHydration': raw['appetiteHydration'],
    'environmentSafety': raw['environmentSafety'],
  };

  @override
  Widget build(BuildContext context) {
    final animals = (data['animals'] as List?)?.whereType<Map>().toList() ?? const [];
    if (animals.isEmpty) {
      return _AnimalDetailBlock(data: data, index: 1, total: 1);
    }
    final total = animals.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (total > 1) _DetailRow('No. of Animals', '$total'),
        for (var i = 0; i < animals.length; i++)
          _AnimalDetailBlock(data: _animalMap(animals[i]), index: i + 1, total: total),
      ],
    );
  }
}

class _AnimalDetailBlock extends StatefulWidget {
  final Map<String, dynamic> data;
  final int index;
  final int total;
  const _AnimalDetailBlock({required this.data, required this.index, required this.total});

  @override
  State<_AnimalDetailBlock> createState() => _AnimalDetailBlockState();
}

class _AnimalDetailBlockState extends State<_AnimalDetailBlock> {
  bool _expanded = true;

  static String? _str(Map data, String key) => data[key] as String?;
  static List<String> _list(Map data, String key) =>
      (data[key] as List?)?.whereType<String>().toList() ?? const [];

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final species = _str(data, 'animalType');
    final breed = _str(data, 'breed');
    final sex = _str(data, 'sex');
    final size = _str(data, 'size');
    final colorMarkings = _str(data, 'colorMarkings');
    final biteRisk = _str(data, 'biteRisk');
    final escapeRisk = _str(data, 'escapeRisk');
    final handlingNotes = _str(data, 'handlingNotes');
    final bodyCondition = _str(data, 'bodyCondition');
    final mobility = _str(data, 'mobility');
    final alertness = _str(data, 'alertness');
    final behavior = _list(data, 'behavior');
    final eyesNoseMouth = _str(data, 'eyesNoseMouth');
    final skinAndCoat = _str(data, 'skinAndCoat');
    final appetiteHydration = _str(data, 'appetiteHydration');
    final environmentSafety = _list(data, 'environmentSafety');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.total > 1 ? 'Animal ${widget.index} of ${widget.total}' : 'Animal Details',
                  style: GoogleFonts.zain(
                      fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18, color: AppColors.textPrimary),
              ],
            ),
          ),
          if (_expanded) const SizedBox(height: 6),
          if (_expanded) ...[
            if ((species ?? '').isNotEmpty) _MiniDetailRow('Species', species!),
            if ((breed ?? '').isNotEmpty) _MiniDetailRow('Breed', breed!),
            if ((sex ?? '').isNotEmpty) _MiniDetailRow('Sex', sex!),
            if ((size ?? '').isNotEmpty) _MiniDetailRow('Size', size!),
            if ((colorMarkings ?? '').isNotEmpty) _MiniDetailRow('Color/Markings', colorMarkings!),
            if ((biteRisk ?? '').isNotEmpty) _MiniDetailRow('Bite Risk', biteRisk!),
            if ((escapeRisk ?? '').isNotEmpty) _MiniDetailRow('Escape Risk', escapeRisk!),
            if ((handlingNotes ?? '').isNotEmpty) _MiniDetailRow('Handling Notes', handlingNotes!),
            if ((bodyCondition ?? '').isNotEmpty) _MiniDetailRow('Body Condition', bodyCondition!),
            if ((mobility ?? '').isNotEmpty) _MiniDetailRow('Mobility', mobility!),
            if ((alertness ?? '').isNotEmpty) _MiniDetailRow('Alertness', alertness!),
            if (behavior.isNotEmpty) _MiniDetailRow('Behavior', behavior.join(', ')),
            if ((eyesNoseMouth ?? '').isNotEmpty) _MiniDetailRow('Eyes, Nose, Mouth', eyesNoseMouth!),
            if ((skinAndCoat ?? '').isNotEmpty) _MiniDetailRow('Skin and Coat', skinAndCoat!),
            if ((appetiteHydration ?? '').isNotEmpty)
              _MiniDetailRow('Appetite and Hydration', appetiteHydration!),
            if (environmentSafety.isNotEmpty)
              _MiniDetailRow('Environment and Safety', environmentSafety.join(', ')),
          ],
        ],
      ),
    );
  }
}

class _MiniDetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _MiniDetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child:
            Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(value, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// Shows the animal's latest known location -- the case's own original
/// lat/lng/address, unless a "moved" Community Report has since come in
/// with newer coordinates (see track_case_page.dart's
/// _CommunityReportSectionState, which now persists newLat/newLng
/// alongside newAddress). Whichever is more recent wins.
class _LatestLocationSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _LatestLocationSection({required this.caseId, required this.data});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('communityReports')
          .where('type', isEqualTo: 'moved')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final movedDocs = snap.data?.docs ?? const [];
        String address;
        if (movedDocs.isNotEmpty) {
          final moved = movedDocs.first.data();
          address = (moved['newAddress'] as String?)?.trim().isNotEmpty == true
              ? moved['newAddress'] as String
              : (data['address'] as String? ?? '-');
        } else {
          address = (data['address'] as String?)?.trim().isNotEmpty == true
              ? data['address'] as String
              : '-';
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Latest Location',
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(address,
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                ),
              ],
            ),
            if (movedDocs.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text('Updated via a community sighting report.',
                  style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ],
        );
      },
    );
  }
}

/// Resolves the coordinates a location-gate check should measure against --
/// the same "latest moved report, else original case location" logic as
/// _LatestLocationSection, but returning raw lat/lng instead of the
/// display text.
class _LatestCoordinates {
  final double? lat;
  final double? lng;
  const _LatestCoordinates(this.lat, this.lng);
}

Future<_LatestCoordinates> _resolveLatestCoordinates(
    String caseId,
    Map<String, dynamic> data,
    ) async {
  try {
    final movedSnap = await FirebaseFirestore.instance
        .collection('cases')
        .doc(caseId)
        .collection('communityReports')
        .where('type', isEqualTo: 'moved')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();
    if (movedSnap.docs.isNotEmpty) {
      final moved = movedSnap.docs.first.data();
      final lat = (moved['newLat'] as num?)?.toDouble();
      final lng = (moved['newLng'] as num?)?.toDouble();
      if (lat != null && lng != null) return _LatestCoordinates(lat, lng);
    }
  } catch (_) {
    // Fall through to the case's own coordinates below.
  }
  return _LatestCoordinates(
    (data['lat'] as num?)?.toDouble(),
    (data['lng'] as num?)?.toDouble(),
  );
}

/// The location-gated entry point into adopting this animal. Only ever
/// shows the "Community Adoption" button once the viewer's current GPS
/// position is within kCommunityAdoptionProximityMeters of the animal's
/// latest known location -- someone who isn't actually there has no way to
/// go collect the animal they'd be adopting, so the button simply isn't
/// offered rather than letting them tap through from anywhere.
class _AdoptionButtonSection extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _AdoptionButtonSection({required this.caseId, required this.data});

  @override
  State<_AdoptionButtonSection> createState() => _AdoptionButtonSectionState();
}

enum _LocationCheckState { checking, atLocation, tooFar, unavailable }

class _AdoptionButtonSectionState extends State<_AdoptionButtonSection> {
  _LocationCheckState _state = _LocationCheckState.checking;
  double? _distanceMeters;

  @override
  void initState() {
    super.initState();
    _checkLocation();
  }

  Future<void> _checkLocation() async {
    setState(() => _state = _LocationCheckState.checking);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) setState(() => _state = _LocationCheckState.unavailable);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _state = _LocationCheckState.unavailable);
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(
        const Duration(seconds: 12),
        onTimeout: () => Geolocator.getLastKnownPosition().then(
              (p) => p ?? (throw Exception('no position available')),
        ),
      );

      final target = await _resolveLatestCoordinates(widget.caseId, widget.data);
      if (target.lat == null || target.lng == null) {
        if (mounted) setState(() => _state = _LocationCheckState.unavailable);
        return;
      }

      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        target.lat!,
        target.lng!,
      );

      if (!mounted) return;
      setState(() {
        _distanceMeters = distance;
        _state = distance <= kCommunityAdoptionProximityMeters
            ? _LocationCheckState.atLocation
            : _LocationCheckState.tooFar;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _LocationCheckState.unavailable);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LocationCheckState.checking:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 10),
            Text('Checking your location…',
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          ],
        );

      case _LocationCheckState.atLocation:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityAdoptionListingPage(caseId: widget.caseId),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: Text('Community Adoption',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),
        );

      case _LocationCheckState.tooFar:
        final km = _distanceMeters != null ? (_distanceMeters! / 1000).toStringAsFixed(1) : null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.slaterspwn,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                "You're ${km != null ? '$km km' : 'too far'} away from this animal's "
                    'last known location.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Head to the location shown above to adopt this animal through Community Adoption.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _checkLocation,
                child: Text('Check again',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
        );

      case _LocationCheckState.unavailable:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(
            color: AppColors.slaterspwn,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Text(
                "We couldn't confirm your location.",
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                "Enable location access and make sure you're at the location shown above, then try again.",
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _checkLocation,
                child: Text('Try again',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
        );
    }
  }
}

/// Same Community Report widget/behavior as track_case_page.dart's own
/// _CommunityReportSection (still-here/moved/rescued/no-animal sighting
/// updates, with newLat/newLng persisted for "moved") -- duplicated here
/// since that class is private to its own file. Any behavior change made
/// to one should be mirrored in the other.
class _CommunityReportSection extends StatefulWidget {
  final String caseId;
  const _CommunityReportSection({required this.caseId});

  @override
  State<_CommunityReportSection> createState() => _CommunityReportSectionState();
}

class _CommunityReportSectionState extends State<_CommunityReportSection> {
  bool _expanded = false;
  String? _selectedType;
  XFile? _pickedImage;
  bool _submitting = false;
  bool _detectingLocation = false;
  double? _detectedLat;
  double? _detectedLng;
  final _commentController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();

  @override
  void dispose() {
    _commentController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> get _reportsRef => FirebaseFirestore.instance
      .collection('cases')
      .doc(widget.caseId)
      .collection('communityReports');

  String _typeLabel(String? t) => switch (t) {
    'still_here' => 'Animal still here',
    'moved' => 'Animal moved',
    'rescued' => 'Animal rescued',
    'no_animal' => 'No animal present',
    _ => 'Update',
  };

  String _typeDescription(String? t) => switch (t) {
    'still_here' => 'Upload a recent photo to confirm the animal is still at the reported location.',
    'moved' =>
    'The animal is no longer at the original location. Upload a recent photo and share the new location.',
    'rescued' =>
    'This animal has already been rescued, adopted, or taken in by someone. Add a photo or proof if you can.',
    'no_animal' =>
    'No animal was found at the reported location. Add a recent photo of the area to confirm.',
    _ => '',
  };

  Future<void> _pickImage() async {
    final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file != null && mounted) setState(() => _pickedImage = file);
  }

  Future<void> _autoDetectLocation() async {
    if (_detectingLocation) return;
    setState(() {
      _detectingLocation = true;
      _locationController.text = 'Detecting your location…';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          setState(() {
            _locationController.clear();
            _detectedLat = null;
            _detectedLng = null;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() {
            _locationController.clear();
            _detectedLat = null;
            _detectedLng = null;
          });
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high).timeout(
        const Duration(seconds: 12),
        onTimeout: () => Geolocator.getLastKnownPosition().then(
              (p) =>
          p ??
              Position(
                latitude: 14.5416,
                longitude: 121.0644,
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

      String resolvedAddress = '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final url = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json'
              '?latlng=${pos.latitude},${pos.longitude}'
              '&key=$_geocodingApiKey',
        );
        final res = await http.get(url).timeout(const Duration(seconds: 10));
        final body = jsonDecode(res.body);
        if (res.statusCode == 200 && body['status'] == 'OK' && (body['results'] as List).isNotEmpty) {
          resolvedAddress = body['results'][0]['formatted_address'];
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _locationController.text = resolvedAddress;
          _detectedLat = pos.latitude;
          _detectedLng = pos.longitude;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationController.clear();
          _detectedLat = null;
          _detectedLng = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not detect your location — please type it in.')),
        );
      }
    } finally {
      if (mounted) setState(() => _detectingLocation = false);
    }
  }

  Future<void> _submit() async {
    if (_selectedType == null || _submitting) return;
    if (_selectedType == 'moved' && _locationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the new location.'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name = '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'.trim();

      final reportRef = _reportsRef.doc();

      String? photoUrl;
      if (_pickedImage != null) {
        final ref = FirebaseStorage.instance
            .ref()
            .child('cases/${widget.caseId}/communityReports/${reportRef.id}.jpg');
        await ref.putFile(File(_pickedImage!.path), SettableMetadata(contentType: 'image/jpeg'));
        photoUrl = await ref.getDownloadURL();
      }

      await reportRef.set({
        'reporterId': uid,
        'reporterName': name.isEmpty ? 'A community member' : name,
        'type': _selectedType,
        'comment': _commentController.text.trim(),
        'newAddress': _selectedType == 'moved' ? _locationController.text.trim() : null,
        'newLat': _selectedType == 'moved' ? _detectedLat : null,
        'newLng': _selectedType == 'moved' ? _detectedLng : null,
        'photoUrl': photoUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          _selectedType = null;
          _pickedImage = null;
          _expanded = false;
        });
        _commentController.clear();
        _locationController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! Your report has been submitted.'), backgroundColor: AppColors.greenrspwn),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not submit report: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _optionButton(String type, String label) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedType = type);
          if (type == 'moved') _autoDetectLocation();
        },
        child: Column(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppColors.textPrimary, shape: BoxShape.circle),
              child: const Icon(Icons.pets, size: 18, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 10.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Stack(
      children: [
        Column(
          children: [
            const SizedBox(height: 8),
            Text(_typeLabel(_selectedType),
                style: GoogleFonts.tiltWarp(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text(_typeDescription(_selectedType),
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.slaterspwn),
                  borderRadius: BorderRadius.circular(10),
                  color: AppColors.background,
                ),
                child: _pickedImage != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(File(_pickedImage!.path), fit: BoxFit.cover),
                )
                    : const Icon(Icons.add_a_photo_outlined, color: AppColors.textSecondary, size: 26),
              ),
            ),
            const SizedBox(height: 14),
            if (_selectedType == 'moved') ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Location Found *',
                    style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _locationController,
                enabled: !_detectingLocation,
                onChanged: (_) {
                  if (_detectedLat != null || _detectedLng != null) {
                    setState(() {
                      _detectedLat = null;
                      _detectedLng = null;
                    });
                  }
                },
                style: GoogleFonts.zain(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Enter the new location',
                  hintStyle: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                  suffixIcon: _detectingLocation
                      ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                      : IconButton(
                    icon: const Icon(Icons.my_location, size: 18, color: AppColors.textSecondary),
                    tooltip: 'Use current location',
                    onPressed: _autoDetectLocation,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.slaterspwn),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            TextField(
              controller: _commentController,
              maxLines: 2,
              style: GoogleFonts.zain(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Comment',
                hintStyle: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                child: _submitting
                    ? const SizedBox(
                    height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                    : Text('Report',
                    style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              ),
            ),
          ],
        ),
        Positioned(
          top: 0,
          right: 0,
          child: GestureDetector(
            onTap: () => setState(() => _selectedType = null),
            child: const Icon(Icons.close, size: 20, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _reportTile(Map<String, dynamic> r) {
    final ts = r['timestamp'] as Timestamp?;
    final date = ts?.toDate();
    final newAddress = r['newAddress'] as String?;
    final comment = r['comment'] as String?;
    final photoUrl = r['photoUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.textPrimary,
            child: const Icon(Icons.pets, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['reporterName'] ?? 'Someone'} · ${_typeLabel(r['type'] as String?)}',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (date != null)
                  Text('${date.month}/${date.day}/${date.year}',
                      style: GoogleFonts.zain(fontSize: 10, color: AppColors.textSecondary)),
                if (newAddress != null && newAddress.isNotEmpty)
                  Text(newAddress, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
                if (comment != null && comment.isNotEmpty)
                  Text(comment, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          if (photoUrl != null && photoUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(photoUrl, width: 36, height: 36, fit: BoxFit.cover),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Community Report',
                    style: GoogleFonts.tiltWarp(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Icon(_expanded ? Icons.expand_less : Icons.add_circle_outline, color: AppColors.textPrimary),
              ),
            ],
          ),
          if (_expanded) ...[
            const SizedBox(height: 10),
            if (_selectedType == null) ...[
              Text(
                "Help keep this listing accurate by sharing timely updates on the animal's location, condition, and safety.",
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _optionButton('still_here', 'Animal still here'),
                  _optionButton('moved', 'Animal moved'),
                  _optionButton('rescued', 'Animal rescued'),
                  _optionButton('no_animal', 'No Animal Present'),
                ],
              ),
            ] else
              _buildForm(),
          ],
          const SizedBox(height: 12),
          const Divider(color: AppColors.slaterspwn),
          const SizedBox(height: 4),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _reportsRef.orderBy('timestamp', descending: true).limit(20).snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text('No community reports yet.',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                );
              }
              return Column(children: docs.map((d) => _reportTile(d.data())).toList());
            },
          ),
        ],
      ),
    );
  }
}