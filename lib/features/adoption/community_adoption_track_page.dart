import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/adoption/community_adoption_listing.dart';

/// How close (meters) a viewer's live GPS position must be to the animal's
/// last known location before the "Community Adoption" button is offered at
/// all — someone who isn't actually there has no way to go collect the
/// animal they'd be adopting.
const double kCommunityAdoptionProximityMeters = 100;

/// Read-only preview of a Community-Adoption-eligible rescue report, gating
/// the actual adoption transaction (community_adoption_listing.dart) behind
/// a live-location check. Reached from PublicRescueCard / ExploreReportsMap
/// whenever `isCommunityAdoptionEligible` is true for the case.
class CommunityAdoptionTrackPage extends StatefulWidget {
  final String caseId;
  const CommunityAdoptionTrackPage({super.key, required this.caseId});

  @override
  State<CommunityAdoptionTrackPage> createState() => _CommunityAdoptionTrackPageState();
}

class _CommunityAdoptionTrackPageState extends State<CommunityAdoptionTrackPage> {
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
        title: Text('Community Adoption', style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
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

class _CommunityAdoptionBody extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _CommunityAdoptionBody({required this.caseId, required this.data});

  @override
  Widget build(BuildContext context) {
    final photoUrls = List<String>.from(data['photoUrls'] ?? const []);
    final animalCount = (data['animals'] as List?)?.length ?? 1;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhotoGallery(photoUrls: photoUrls),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(color: AppColors.greenrspwn.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                const Icon(Icons.favorite, size: 16, color: AppColors.greenrspwn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    animalCount > 1 ? 'These animals are open for adoption.' : 'This animal is open for adoption.',
                    style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Text('#${caseId.substring(0, 7).toUpperCase()}', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          const SizedBox(height: 12),

          _DetailRow('Reporter Name', data['reporterName']),
          _DetailRow('Description', data['condition']),
          _AnimalGroupSection(data: data),

          const SizedBox(height: 8),
          const Divider(color: AppColors.slaterspwn),
          const SizedBox(height: 8),

          _DetailRow('Location', data['address']),

          const SizedBox(height: 16),
          _AdoptionButtonSection(caseId: caseId, data: data),

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
        decoration: BoxDecoration(color: AppColors.tearspwn, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Icon(Icons.image_not_supported_outlined, size: 48, color: AppColors.textSecondary)),
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
          Text(label, style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          Text(value!, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// Per-animal breakdown — species/breed/sex/size/color plus bite/escape
/// risk and (when present) the Community Adoption name/description added
/// to the Rescue Report form. Falls back to the case's own flat fields for
/// a legacy single-animal report with no `animals[]` array.
class _AnimalGroupSection extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AnimalGroupSection({required this.data});

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
          _AnimalDetailBlock(
            data: Map<String, dynamic>.from(animals[i]).map((k, v) => MapEntry(k == 'species' ? 'animalType' : k, v)),
            index: i + 1,
            total: total,
          ),
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

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final name = _str(data, 'name');
    final species = _str(data, 'animalType');
    final breed = _str(data, 'breed');
    final sex = _str(data, 'sex');
    final size = _str(data, 'size');
    final colorMarkings = _str(data, 'colorMarkings');
    final biteRisk = _str(data, 'biteRisk');
    final escapeRisk = _str(data, 'escapeRisk');
    final description = _str(data, 'description');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.slaterspwn)),
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
                  (name != null && name.trim().isNotEmpty)
                      ? name
                      : (widget.total > 1 ? 'Animal ${widget.index} of ${widget.total}' : 'Animal Details'),
                  style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                ),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textPrimary),
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
            if ((description ?? '').trim().isNotEmpty) _MiniDetailRow('About', description!),
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
          SizedBox(width: 100, child: Text(label, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))),
          Expanded(child: Text(value, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary))),
        ],
      ),
    );
  }
}

/// The location-gated entry point into adopting this animal. Only ever
/// shows the "Community Adoption" button once the viewer's current GPS
/// position is within [kCommunityAdoptionProximityMeters] of the animal's
/// reported location — someone who isn't actually there has no way to go
/// collect the animal they'd be adopting, so the button simply isn't
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

      final pos = await Geolocator.getCurrentPosition().timeout(
        const Duration(seconds: 12),
        onTimeout: () => Geolocator.getLastKnownPosition().then((p) => p ?? (throw Exception('no position available'))),
      );

      final lat = (widget.data['lat'] as num?)?.toDouble();
      final lng = (widget.data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        if (mounted) setState(() => _state = _LocationCheckState.unavailable);
        return;
      }

      final distance = Geolocator.distanceBetween(pos.latitude, pos.longitude, lat, lng);

      if (!mounted) return;
      setState(() {
        _distanceMeters = distance;
        _state = distance <= kCommunityAdoptionProximityMeters ? _LocationCheckState.atLocation : _LocationCheckState.tooFar;
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
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary)),
            const SizedBox(width: 10),
            Text('Checking your location…', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          ],
        );

      case _LocationCheckState.atLocation:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => CommunityAdoptionListingPage(caseId: widget.caseId)));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
            child: Text('Community Adoption', style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
          ),
        );

      case _LocationCheckState.tooFar:
        final km = _distanceMeters != null ? (_distanceMeters! / 1000).toStringAsFixed(1) : null;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              Text(
                "You're ${km != null ? '$km km' : 'too far'} away from this animal's last known location.",
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
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
                child: Text('Check again', style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
        );

      case _LocationCheckState.unavailable:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          decoration: BoxDecoration(color: AppColors.slaterspwn, borderRadius: BorderRadius.circular(10)),
          child: Column(
            children: [
              Text(
                "We couldn't confirm your location.",
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
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
                child: Text('Try again', style: GoogleFonts.zain(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
            ],
          ),
        );
    }
  }
}
