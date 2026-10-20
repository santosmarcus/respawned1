import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/core/utils/animal_health_assessment.dart';
import 'package:respawnd1/core/utils/rescue_risk.dart';
import 'package:respawnd1/core/utils/validators.dart';
import 'package:respawnd1/features/collartag/scan_tag_flow.dart';
import 'package:respawnd1/features/collartag/pet_found_chat.dart';
import 'package:video_player/video_player.dart';

const String _geocodingApiKey = 'AIzaSyChQ9xBxn59vAehhzsPuMgCqJoW_qbVOs0';

const String _dogSpecies = 'Dog';
const String _catSpecies = 'Cat';
const String _othersBreedLabel = 'Others / Not sure';

const List<String> _dogBreeds = [
  _othersBreedLabel,
  'Aspin (Mixed/Native)',
  'Beagle',
  'Chihuahua',
  'Corgi',
  'Dachshund',
  'French Bulldog',
  'German Shepherd',
  'Golden Retriever',
  'Japanese Spitz',
  'Labrador Retriever',
  'Pomeranian',
  'Poodle',
  'Shiba Inu',
  'Shih Tzu',
  'Siberian Husky',
  'Rottweiler',
];

const List<String> _catBreeds = [
  _othersBreedLabel,
  'American Shorthair',
  'Bengal',
  'British Shorthair',
  'Himalayan',
  'Maine Coon',
  'Persian',
  'Puspin (Mixed/Native)',
  'Ragdoll',
  'Scottish Fold',
  'Siamese',
];

List<String> _breedOptionsFor(String? species) {
  if (species == _dogSpecies) return _dogBreeds;
  if (species == _catSpecies) return _catBreeds;
  return const [_othersBreedLabel];
}

//Media
class _MediaItem {
  final XFile file;
  final bool isVideo;

  _MediaItem({
    required this.file, required this.isVideo
  });
}

class _FoundAnimalEntry {
  String? species; // 'Dog' | 'Cat'
  String? breed; // one of _breedOptionsFor(species), or _othersBreedLabel
  final TextEditingController breedOtherController = TextEditingController();
  final TextEditingController colorController = TextEditingController();
  String? sex;
  String? size;

  // Health & Behavior Assessment — per animal, never applied across other
  // animals in the same multi-animal report; each entry owns its own
  // values. See core/utils/animal_health_assessment.dart for each field's
  // option list. Single-select:
  String? bodyCondition;
  String? mobility;
  String? alertness;
  String? eyesNoseMouth;
  String? skinAndCoat;
  String? appetiteHydration;
  // Multi-select:
  final Set<String> behavior = {};
  // Multi-select + reporter-added custom entries beyond the predefined
  // list (see _EnvironmentSafetySection).
  final Set<String> environmentSafety = {};
  final TextEditingController environmentSafetyOtherController = TextEditingController();

  // Per-animal safety risk — never applied across other animals in the
  // same multi-animal report; each entry owns its own values.
  String? biteRisk;
  String? escapeRisk;

  void dispose() {
    breedOtherController.dispose();
    colorController.dispose();
    environmentSafetyOtherController.dispose();
  }

  String get speciesText => species ?? '';
  String get breedText {
    if (breed == null) return '';
    return breed == _othersBreedLabel ? breedOtherController.text.trim() : breed!;
  }
}

class RescuePage extends StatefulWidget {
  const RescuePage({super.key});

  @override
  State<RescuePage> createState() => _RescuePageState();
}

class _RescuePageState extends State<RescuePage> {
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _conditionController = TextEditingController();
  final TextEditingController _witnessNameController = TextEditingController();
  final TextEditingController _witnessNumberController = TextEditingController();
  final TextEditingController _accessInstructionsController = TextEditingController();
  final TextEditingController _bestTimeContactController = TextEditingController();

  String? _selectedUrgency;
  String? _selectedRescueType;
  String? _coordinateChoice;
  String? _adoptionChoice;
  // Only asked/answered when _adoptionChoice == 'yes' — resets to false if
  // the reporter changes their mind and un-checks Yes, so a stale consent
  // never survives under a "No" answer.
  bool _adoptionCommitmentAccepted = false;
  String? _selectedAnimalType;
  bool _isLoading = false;

  // Additional stray-rescue triage questions
  String? _onSiteChoice; // 'yes' | 'no'
  bool _reportAnonymously = false;

  bool? _isOwner;
  String? _scannedTagId;

  // Owner-side controllers
  final TextEditingController _petNameController = TextEditingController();
  String? _lostBreed;
  final TextEditingController _lostBreedOtherController = TextEditingController();
  final TextEditingController _lostColorController = TextEditingController();
  DateTime? _lastSeenDate;
  TimeOfDay? _lastSeenTime;
  final TextEditingController _rewardAmountController = TextEditingController();
  final TextEditingController _ownerContactController = TextEditingController();
  String? _lostSex;
  String? _temperament;
  bool _offerReward = false;

  String get _lostBreedText {
    if (_lostBreed == null) return '';
    return _lostBreed == _othersBreedLabel
        ? _lostBreedOtherController.text.trim()
        : _lostBreed!;
  }

  // Pet Surrender — its own distinct question set (see _buildSurrenderFields).
  final TextEditingController _surrenderDurationController = TextEditingController();
  final TextEditingController _surrenderAgeController = TextEditingController();
  String? _surrenderReason;
  final TextEditingController _surrenderReasonOtherController = TextEditingController();
  final TextEditingController _surrenderExplanationController = TextEditingController();
  String? _petAcquisitionSource;

  static const List<String> _surrenderReasonOptions = [
    'Financial difficulties',
    'Moving/Relocation',
    'Housing restrictions',
    'Medical issues (owner)',
    'Medical issues (pet)',
    'Behavioral issues',
    'Compatibility with other pets',
    'Compatibility with children/family',
    'Lack of time',
    'Lifestyle changes',
    'Owner passed away',
    'Emergency circumstances',
    'Other (please specify)',
  ];

  static const List<String> _acquisitionSourceOptions = [
    'Breeder',
    'Stray',
    'Pet Store',
    'Rescue Org',
    'Friend/Family',
    'Born at home',
  ];

  // Only these reasons need the reporter to explain what's actually wrong
  // and what they've already tried — a plain checkbox reason isn't enough
  // for staff to assess these two specifically.
  bool get _surrenderNeedsExplanation =>
      _surrenderReason == 'Medical issues (pet)' ||
          _surrenderReason == 'Behavioral issues';

  // Once the pet came from another rescue org, this flow is meant to stop
  // here and redirect the owner back to that org rather than collect a
  // full surrender case for this one.
  bool get _isRescueOrgAcquisition => _petAcquisitionSource == 'Rescue Org';

  // Finder-side: one card per animal found (supports a multi-animal group case)
  final List<_FoundAnimalEntry> _foundAnimals = [_FoundAnimalEntry()];
  final TextEditingController _finderContactController = TextEditingController();
  String? _animalStatus; // 'with_finder' | 'still_roaming' | 'brought_to_vet'
  bool _finderNeedsRescue = false;

  bool get _isLostPetType => _selectedRescueType == 'Lost Pet';
  bool get _isPetSurrenderType => _selectedRescueType == 'Pet Surrender';

  // Rescue Type options — each type carries its own inherent urgency level,
  // so reporters are no longer asked to separately self-assess urgency.
  static const List<Map<String, String>> _rescueTypeOptions = [
    {
      'label': 'Pet Surrender',
      'description': 'Voluntary ownership surrender',
      'urgency': 'Low',
    },
    {
      'label': 'Lost Pet',
      'description': 'Owner reporting a missing pet for reunification',
      'urgency': 'Low',
    },
    {
      'label': 'Abandonment',
      'description': 'Animal left without care',
      'urgency': 'Medium',
    },
    {
      'label': 'Illness',
      'description':
      'Appears weak, vomiting, coughing, skin disease; suspected illness',
      'urgency': 'Critical',
    },
    {
      'label': 'Injury',
      'description': 'Visible wounds, fractures, bleeding',
      'urgency': 'Critical',
    },

    {
      'label': 'Neglect or Abuse',
      'description':
      'Suspected animal cruelty, starvation, chaining, hoarding',
      'urgency': 'Critical',
    },
    {
      'label': 'Aggressive Animal',
      'description':
      'Displaying aggressive behavior and posing a safety concern',
      'urgency': 'Critical',
    },
  ];

  // Looks up the inherent urgency level for a given rescue type label.
  static String? _urgencyForRescueType(String? label) {
    if (label == null) return null;
    for (final option in _rescueTypeOptions) {
      if (option['label'] == label) return option['urgency'];
    }
    return null;
  }

  // Small color cue per urgency level, reusing existing app palette.
  static Color _urgencyColor(String? urgency) {
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

  final List<_MediaItem?> _mediaFiles = [null, null, null, null];
  final ImagePicker _picker = ImagePicker();
  final List<double?> _uploadProgress = [null, null, null, null];

  // Google Maps
  GoogleMapController? _mapController;
  // This is only ever a camera-framing default, used for the very first
  // frame before any real position resolves — it must never be shown to
  // the person as an actual pinned marker (see _hasResolvedLocation below),
  // since it happens to be a real, recognizable Manila address rather than
  // a neutral placeholder.
  LatLng _pinnedLocation = const LatLng(14.5995, 120.9842);
  // True once _pinnedLocation reflects an actual resolved position (fresh
  // GPS, or the device's own last-known real fix) rather than the
  // hardcoded camera-framing default above. The map marker only renders
  // once this is true, so the person is never shown a pin sitting at that
  // default coordinate as if it were their actual rescue location.
  bool _hasResolvedLocation = false;
  String _pinnedAddress = 'Fetching location…';
  bool _loadingLocation = true;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  @override
  void dispose() {
    _mapController?.dispose();
    _addressController.dispose();
    _conditionController.dispose();
    _witnessNameController.dispose();
    _witnessNumberController.dispose();
    _accessInstructionsController.dispose();
    _bestTimeContactController.dispose();
    _petNameController.dispose();
    _lostBreedOtherController.dispose();
    _lostColorController.dispose();
    _rewardAmountController.dispose();
    _ownerContactController.dispose();
    _finderContactController.dispose();
    _surrenderDurationController.dispose();
    _surrenderAgeController.dispose();
    _surrenderReasonOtherController.dispose();
    _surrenderExplanationController.dispose();
    for (final a in _foundAnimals) {
      a.dispose();
    }
    super.dispose();
  }

  Future<void> _fallbackToLastKnownOrDefault(String reasonMessage) async {
    if (_hasResolvedLocation) {
      if (mounted) setState(() => _loadingLocation = false);
      return;
    }

    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {
      lastKnown = null;
    }

    if (lastKnown != null) {
      await _updatePin(LatLng(lastKnown.latitude, lastKnown.longitude));
      return;
    }

    if (mounted) {
      setState(() {
        _loadingLocation = false;
        _pinnedAddress = reasonMessage;
      });
    }
  }

  Future<void> _fetchCurrentLocation() async {
    setState(() => _loadingLocation = true);

    if (!_hasResolvedLocation) {
      try {
        final cached = await Geolocator.getLastKnownPosition();
        if (cached != null && mounted) {
          await _updatePin(LatLng(cached.latitude, cached.longitude));
        }
      } catch (_) {
      }
    }

    try {
      // Check if location service is on
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Please enable location services for accurate pinning.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        await _fallbackToLastKnownOrDefault(
            'Location services disabled — tap map to pin manually.');
        return;
      }

      // Check/request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted && permission == LocationPermission.deniedForever) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Location permission permanently denied.'),
              action: SnackBarAction(
                label: 'App Settings',
                onPressed: () => Geolocator.openAppSettings(),
              ),
            ),
          );
        }
        await _fallbackToLastKnownOrDefault(
            'Location permission denied — tap map to pin manually.');
        return;
      }

      // Get a fresh, accurate fix. On timeout, fall back to whatever cached
      // position is available rather than ever substituting the hardcoded
      // default coordinate as if it were a real resolved location.
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).then<Position?>((p) => p).timeout(
        const Duration(seconds: 15),
        onTimeout: () => Geolocator.getLastKnownPosition(),
      );

      if (pos != null) {
        await _updatePin(LatLng(pos.latitude, pos.longitude));
      } else {
        await _fallbackToLastKnownOrDefault(
            'Could not get your location — tap map to pin manually.');
      }
    } catch (e) {
      await _fallbackToLastKnownOrDefault(
          'Could not get location — tap map to pin manually.');
    }
  }

  Future<String?> _nearbyLandmark(LatLng pos) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/nearbysearch/json'
            '?location=${pos.latitude},${pos.longitude}'
            '&rankby=distance'                  // closest first
            '&type=point_of_interest'           // landmarks, establishments, etc.
            '&key=$_geocodingApiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);

      print("===== NEARBY LANDMARK =====");
      print("STATUS: ${data['status']}");
      print("ERROR: ${data['error_message']}");

      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        return data['results'][0]['name'] as String?;
      }
      return null;
    } catch (e) {
      print("Nearby landmark lookup failed: $e");
      return null;
    }
  }

  Future<void> _updatePin(LatLng pos) async {
    setState(() {
      _pinnedLocation = pos;
      _hasResolvedLocation = true;
      _pinnedAddress = 'Resolving address…';
      _loadingLocation = true;
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 17)),
    );

    String resolvedAddress;

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${pos.latitude},${pos.longitude}'
            '&key=$_geocodingApiKey',
      );

      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);

      print("===== REVERSE GEOCODE =====");
      print("STATUS: ${data['status']}");
      print("ERROR: ${data['error_message']}");
      print("BODY: ${res.body}");

      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        resolvedAddress = data['results'][0]['formatted_address'];
      } else {
        // Fallback to coordinates
        resolvedAddress =
        '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      }
    } catch (_) {
      resolvedAddress =
      '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
    }

    // Try to attach a nearby landmark name, without blocking on failure
    final landmark = await _nearbyLandmark(pos);

    setState(() {
      _pinnedAddress = (landmark != null && landmark.trim().isNotEmpty)
          ? 'Near $landmark • $resolvedAddress'
          : resolvedAddress;
      _loadingLocation = false;
    });
  }

  Future<void> _geocodeAddress(String address) async {
    if (address
        .trim()
        .isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _loadingLocation = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(address)}'
            '&key=$_geocodingApiKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);

      print("===== ADDRESS SEARCH =====");
      print("STATUS: ${data['status']}");
      print("ERROR: ${data['error_message']}");
      print("BODY: ${res.body}");

      if (res.statusCode == 200 &&
          data['status'] == 'OK' &&
          (data['results'] as List).isNotEmpty) {
        final loc = data['results'][0]['geometry']['location'];
        final latLng = LatLng(
          (loc['lat'] as num).toDouble(),
          (loc['lng'] as num).toDouble(),
        );
        _addressController.text = data['results'][0]['formatted_address'];
        await _updatePin(latLng);
      } else {
        setState(() => _loadingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Address not found. Try a different search.')),
          );
        }
      }
    } catch (_) {
      setState(() => _loadingLocation = false);
    }
  }

  //Rescue Type picker
  Future<void> _pickRescueType() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.slaterspwn,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Rescue Type',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: scrollController,
                  itemCount: _rescueTypeOptions.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.slaterspwn.withOpacity(0.4)),
                  itemBuilder: (context, index) {
                    final option = _rescueTypeOptions[index];
                    final isSelected = option['label'] == _selectedRescueType;
                    final urgency = option['urgency'];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              option['label']!,
                              style: GoogleFonts.zain(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (urgency != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _urgencyColor(urgency).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: _urgencyColor(urgency), width: 1),
                              ),
                              child: Text(
                                urgency,
                                style: GoogleFonts.zain(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        option['description']!,
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle,
                          color: AppColors.textPrimary, size: 20)
                          : null,
                      onTap: () => Navigator.pop(context, option['label']),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        _selectedRescueType = selected;
        _selectedUrgency = _urgencyForRescueType(selected);
      });
    }
  }

  //Media picker
  Future<void> _previewVideo(XFile file) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _VideoPreviewPage(file: File(file.path)),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _pickMedia(int index) async{
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.slaterspwn,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 14),
            Text('Add Photo or Video',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined,
                  color: AppColors.textPrimary),
              title: Text('Take a photo',
                  style: GoogleFonts.zain(
                      fontSize: 15, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, 'photo_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.textPrimary),
              title: Text('Choose photos from gallery',
                  style: GoogleFonts.zain(
                      fontSize: 15, color: AppColors.textPrimary)),
              subtitle: Text('Select up to ${_mediaFiles.length} at once',
                  style: GoogleFonts.zain(
                      fontSize: 12, color: AppColors.textSecondary)),
              onTap: () => Navigator.pop(context, 'photo_gallery_multi'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined,
                  color: AppColors.textPrimary),
              title: Text('Record a video',
                  style: GoogleFonts.zain(
                      fontSize: 15, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, 'video_camera'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined,
                  color: AppColors.textPrimary),
              title: Text('Choose video from gallery',
                  style: GoogleFonts.zain(
                      fontSize: 15, color: AppColors.textPrimary)),
              onTap: () => Navigator.pop(context, 'video_gallery'),
            ),
            if (_mediaFiles[index] != null && _mediaFiles[index]!.isVideo)
              ListTile(
                leading: const Icon(Icons.play_circle_outline, color: AppColors.textPrimary),
                title: Text('Preview video',
                    style: GoogleFonts.zain(
                        fontSize: 15, color: AppColors.textPrimary)),
                onTap: () {
                  Navigator.pop(context, 'preview');
                  _previewVideo(_mediaFiles[index]!.file);
                },
              ),
            if (_mediaFiles[index] != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text('Remove',
                    style: GoogleFonts.zain(
                        fontSize: 15, color: Colors.redAccent)),
                onTap: () {
                  setState(() => _mediaFiles[index] = null);
                  Navigator.pop(context, 'remove');
                },
              ),
          ],
        ),
      ),
    );

    if (action == null || action == 'remove') return;

    if (action == 'photo_gallery_multi') {
      await _pickMultipleImages(startIndex: index);
      return;
    }

    XFile? file;
    bool isVideo = false;

    switch (action) {
      case 'photo_camera':
        file = await _picker.pickImage(
            source: ImageSource.camera, imageQuality: 80, maxWidth: 1280);
        break;
      case 'video_camera':
        file = await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 60));
        isVideo = true;
        break;
      case 'video_gallery':
        file = await _picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(seconds: 60));
        isVideo = true;
        break;
    }

    if (file != null && mounted) {
      setState(() => _mediaFiles[index] = _MediaItem(file: file!, isVideo: isVideo));
    }
  }

  Future<void> _pickMultipleImages({required int startIndex}) async {
    final picked = await _picker.pickMultiImage(imageQuality: 80, maxWidth: 1280);
    if (picked.isEmpty || !mounted) return;

    final emptySlots = [
      if (_mediaFiles[startIndex] == null) startIndex,
      for (int i = 0; i < _mediaFiles.length; i++)
        if (i != startIndex && _mediaFiles[i] == null) i,
    ];

    final placeCount =
    picked.length < emptySlots.length ? picked.length : emptySlots.length;

    setState(() {
      for (int i = 0; i < placeCount; i++) {
        _mediaFiles[emptySlots[i]] = _MediaItem(file: picked[i], isVideo: false);
      }
    });

    if (placeCount < picked.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            placeCount == 0
                ? 'You already have ${_mediaFiles.length} photos/videos added — remove one first.'
                : 'Only $placeCount of ${picked.length} photos were added (max ${_mediaFiles.length} total).',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  // Firebase Storage upload, uploads media slots to firebase storage
  Future<({List<String> photoUrls, List<String> videoUrls})> _uploadAllMedia(
      String caseId) async {
    final photoUrls = <String>[];
    final videoUrls = <String>[];

    for (int i = 0; i < _mediaFiles.length; i++) {
      final item = _mediaFiles[i];
      if (item == null) continue;

      final ext = item.isVideo ? 'mp4' : 'jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('cases/$caseId/media_$i.$ext');

      final task = ref.putFile(
        File(item.file.path),
        SettableMetadata(
          contentType: item.isVideo ? 'video/mp4' : 'image/jpeg',
        ),
      );

      // Track upload progress for slot
      task.snapshotEvents.listen((snap) {
        if (!mounted) return;
        setState(() {
          _uploadProgress[i] =
              snap.bytesTransferred / (snap.totalBytes == 0 ? 1 : snap.totalBytes);
        });
      });

      await task;
      final url = await ref.getDownloadURL();
      if (item.isVideo) {
        videoUrls.add(url);
      } else {
        photoUrls.add(url);
      }

      if (mounted) setState(() => _uploadProgress[i] = null);
    }

    return (photoUrls: photoUrls, videoUrls: videoUrls);
  }

  //NFC and QR
  void _showScanOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Scan Animal Tag',
              style: GoogleFonts.zain(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _scanQR();
                    },
                    icon: const Icon(Icons.qr_code),
                    label: Text('Scan QR', style: GoogleFonts.zain(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _scanNFC();
                    },
                    icon: const Icon(Icons.nfc),
                    label: Text('Scan NFC', style: GoogleFonts.zain(fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _scanQR() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QRScannerPage(),
      ),
    );

    if (result != null && mounted) {
      _handleScanResult(result);
    }
  }

  Future<void> _scanNFC() async {
    try {
      final availability = await FlutterNfcKit.nfcAvailability;
      if (availability != NFCAvailability.available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('NFC is not available on this device.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hold your device near the NFC tag…'),
            duration: Duration(seconds: 4),
          ),
        );
      }

      final tag = await FlutterNfcKit.poll(timeout: const Duration(seconds: 10));
      await FlutterNfcKit.finish();

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _handleScanResult(tag.id);
      }
    } catch (e) {
      await FlutterNfcKit.finish();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('NFC scan failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _awaitResolvedLocation({
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (!_hasResolvedLocation && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
      if (!mounted) return;
    }
  }

  Future<void> _handleScanResult(String result) async {
    setState(() => _scannedTagId = result);

    final tagId = AppLinks.tagIdFromScan(result);
    if (tagId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tag scanned: $result'),
          backgroundColor: Colors.green,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Tag scanned — checking for a registered pet…'),
        backgroundColor: Colors.green,
      ),
    );

    await _awaitResolvedLocation();
    if (!mounted) return;

    try {
      final outcome = await resolveScannedTagId(
        tagId,
        location: _hasResolvedLocation
            ? ScanLocation(
          lat: _pinnedLocation.latitude,
          lng: _pinnedLocation.longitude,
          address: _pinnedAddress,
        )
            : null,
      );

      if (!mounted) return;

      if (!outcome.tagExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isLostPetType
                  ? 'Tag scanned, but no registered profile was found for it.'
                  : 'Tag scanned: $result',
            ),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PetFoundChatScreen(
            tagId: outcome.tagId!,
            sessionId: outcome.sessionId!,
            petName: outcome.petName!,
            isOwner: false,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not check this tag: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

//build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Report a Stray',
          style: Theme.of(context).textTheme.displayLarge,
        ),
        automaticallyImplyLeading: true,
        centerTitle: true,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined),
            activeIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person_outline),
            activeIcon: Icon(Icons.person),
            label: 'My Profile',
          ),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
          else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          else if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UserProfile()),
            );
          }
        },
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),

            //Map
            Stack(
              children: [
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  height: 300,
                  decoration: BoxDecoration(
                    color: AppColors.slaterspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: GoogleMap(
                    gestureRecognizers: {
                      Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                      ),
                    },
                    onMapCreated: (ctrl) => _mapController = ctrl,
                    initialCameraPosition: CameraPosition(
                      target: _pinnedLocation,
                      zoom: 15,
                    ),
                    onTap: _updatePin,
                    markers: _hasResolvedLocation
                        ? {
                      Marker(
                        markerId: const MarkerId('rescue_pin'),
                        position: _pinnedLocation,
                        infoWindow:
                        const InfoWindow(title: 'Rescue Location'),
                      ),
                    }
                        : {},
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                  ),
                ),

                // Locate-me button
                Positioned(
                  bottom: 10,
                  right: 26,
                  child: GestureDetector(
                    onTap: _fetchCurrentLocation,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppColors.yellowrspwn,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: _loadingLocation
                          ? const Padding(
                        padding: EdgeInsets.all(9),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.textPrimary,
                        ),
                      )
                          : const Icon(Icons.my_location,
                          size: 20, color: AppColors.textPrimary),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // Address Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.yellowrspwn,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        size: 20, color: AppColors.textPrimary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _addressController,
                        decoration: InputDecoration(
                          hintText: 'Search address…',
                          hintStyle: GoogleFonts.zain(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: GoogleFonts.zain(
                          color: AppColors.textPrimary,
                          fontSize: 16,
                        ),
                        textInputAction: TextInputAction.search,
                        onSubmitted: _geocodeAddress,
                      ),
                    ),
                    GestureDetector(
                      onTap: () =>
                          _geocodeAddress(_addressController.text),
                      child: const Icon(Icons.arrow_forward_ios,
                          size: 16, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Pinned location display
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Pinned location', required: true),
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                            color: AppColors.textPrimary, width: 1),
                      ),
                    ),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: _loadingLocation
                              ? const LinearProgressIndicator(
                            minHeight: 2,
                            color: AppColors.greenrspwn,
                            backgroundColor: AppColors.slaterspwn,
                          )
                              : Text(
                            _pinnedAddress,
                            style: GoogleFonts.zain(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap the map to manually adjust the pin.',
                    style: GoogleFonts.zain(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Include images and videos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLabel('Include images and videos', required: true),
                  const SizedBox(height: 4),
                  Text(
                    'Provide actual images or videos of the animal. '
                        'At least 2 are required.',
                    style: GoogleFonts.zain(
                        fontSize: 11, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(4, (i) => _buildMediaBox(i)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Scan NFC / QR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _showScanOptions,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ), backgroundColor: AppColors.yellowrspwn,
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.qr_code_scanner, size: 18),
                              const SizedBox(width: 8,),
                              Text(
                                'Scan for NFC or QR',
                                style: GoogleFonts.tiltWarp(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          GestureDetector(
                            onTap: () => _showScanInfo(context),
                            child: const Icon(Icons.info_outline,
                                size: 18, color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Divider
            const Divider(
              height: 1,
              thickness: 1,
              indent: 16,
              endIndent: 16,
              color: AppColors.slaterspwn,
            ),

            const SizedBox(height: 20),

            // Details Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Details:',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      color: AppColors.textPrimary,
                    ),
                  ),

                  const SizedBox(height: 18),

                  // Rescue Type
                  _buildLabel('Rescue Type', required: true),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickRescueType,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.slaterspwn),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _selectedRescueType ?? 'Select',
                            style: GoogleFonts.zain(
                              fontSize: 14,
                              color: _selectedRescueType == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down,
                              color: AppColors.textPrimary, size: 20),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_isPetSurrenderType) ...[
                    ..._buildSurrenderFields(),
                  ] else if (!_isLostPetType) ...[
                    if (_selectedRescueType != null) ...[
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: _urgencyColor(_selectedUrgency),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Urgency level: ${_selectedUrgency ?? 'N/A'}',
                            style: GoogleFonts.zain(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Set automatically based on the rescue type you chose.',
                        style: GoogleFonts.zain(
                            fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 20),
                    ],
                    // Describe Condition
                    _buildLabel('Describe Condition', required: true),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _conditionController,
                      decoration: InputDecoration(
                        hintText: 'Enter condition',
                        hintStyle: GoogleFonts.zain(
                          color: AppColors.textSecondary,
                          fontSize: 14,
                        ),
                        enabledBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.only(bottom: 8),
                      ),
                      style: GoogleFonts.zain(
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),

                    const SizedBox(height: 20),

                    _buildLabel('Type of Animal', required: true),
                    const SizedBox(height: 4),
                    Text(
                      'Found more than one? Add each animal below — they will '
                          'be tracked together as one case.',
                      style: GoogleFonts.zain(
                          fontSize: 11, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 10),
                    ..._buildAnimalEntryFields(),

                    const SizedBox(height: 20),

                    // On-site presence
                    _buildLabel('Are you currently on-site with the animal?',
                        required: true),
                    const SizedBox(height: 8),
                    _buildCheckboxOption2('Yes, I am on-site', _onSiteChoice,
                            (val) => setState(() => _onSiteChoice = val)),
                    _buildCheckboxOption2(
                        'No, I am reporting remotely', _onSiteChoice,
                            (val) => setState(() => _onSiteChoice = val)),

                    const SizedBox(height: 20),

                    // Access instructions
                    _buildLabel('Access instructions', required: false),
                    const SizedBox(height: 6),
                    _lostPetTextField(_accessInstructionsController,
                        'e.g. Gated compound, ask guard for entry'),

                    const SizedBox(height: 20),

                    // Coordinate with shelter
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Would you be willing to coordinate with the shelter to assist in the rescue?',
                            style: GoogleFonts.zain(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _coordinateChoice == 'yes',
                            onChanged: (val) => setState(()
                            => _coordinateChoice = 'yes'),
                            activeColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Yes, I would.',
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _coordinateChoice == 'no',
                            onChanged: (val) =>
                                setState(() => _coordinateChoice = 'no'),
                            activeColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No, but I can refer you to witnesses who can assist.',
                            style: GoogleFonts.zain(
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_coordinateChoice == 'no') ...[
                      const SizedBox(height: 6),
                      _buildLabel('Witness name', required: true),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _witnessNameController,
                        inputFormatters: [AppInputFormatters.nameOnly],
                        decoration: InputDecoration(
                          hintText: 'Enter name of witness',
                          hintStyle: GoogleFonts.zain(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.only(bottom: 8),
                        ),
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                      ),
                      const SizedBox(height: 12),
                      _buildLabel('Witness mobile number', required: true),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _witnessNumberController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: AppInputFormatters.phoneFlexible,
                        decoration: InputDecoration(
                          hintText: 'Enter mobile number of witness',
                          hintStyle: GoogleFonts.zain(
                            color: AppColors.textSecondary,
                            fontSize: 14,
                          ),
                          enabledBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.only(bottom: 8),
                        ),
                        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
                      ),
                    ],
                    const SizedBox(height: 20,),

                    if(_coordinateChoice == 'yes') ...[
                      // Best time to contact
                      _buildLabel('Best time to reach you', required: false),
                      const SizedBox(height: 6),
                      _lostPetTextField(_bestTimeContactController,
                          'e.g. Anytime after 3PM'),

                      const SizedBox(height: 20),
                    ],

                    // Willing to adopt
                    const SizedBox(height: 20,),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            'Would you like to adopt the animal once rescued?',
                            style: GoogleFonts.zain(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '*',
                          style: TextStyle(
                            color: Colors.red,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8,),
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _adoptionChoice == 'yes',
                            onChanged: (val) => setState(()
                            => _adoptionChoice = 'yes'),
                            activeColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Yes, I would.',
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: Checkbox(
                            value: _adoptionChoice == 'no',
                            onChanged: (val) => setState(() {
                              _adoptionChoice = 'no';
                              _adoptionCommitmentAccepted = false;
                            }),
                            activeColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(2),
                            ),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'No.',
                          style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),

                    // Only shown once the reporter has expressed interest in
                    // adopting — a plain "yes I'd like to adopt" isn't
                    // enough on its own; this makes the actual obligations
                    // explicit (cost, interview, agreement, follow-ups)
                    // before staff treat them as a real candidate at
                    // discharge. Separate from (and not automatic approval
                    // for) the removed Community Adoption Details path.
                    if (_adoptionChoice == 'yes') ...[
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              'By agreeing to this, you confirm that you are '
                                  'willing to cover any necessary veterinary '
                                  'expenses, participate in the adoption interview '
                                  'process, comply with the adoption agreement, and '
                                  'provide post-adoption updates as required.',
                              style: GoogleFonts.zain(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '*',
                            style: TextStyle(color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Once the animal is in treatment, the organization will '
                            'visit you at the veterinary clinic to discuss the '
                            'adoption process with you.',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () => setState(() => _adoptionCommitmentAccepted = !_adoptionCommitmentAccepted),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: Checkbox(
                                value: _adoptionCommitmentAccepted,
                                onChanged: (val) => setState(() => _adoptionCommitmentAccepted = val ?? false),
                                activeColor: AppColors.textPrimary,
                                side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('I agree.',
                                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
                            ),
                          ],
                        ),
                      ),
                    ],

                    if (_selectedRescueType == 'Neglect or Abuse') ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Keep my identity confidential from the alleged owner',
                              style: GoogleFonts.zain(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Switch(
                            value: _reportAnonymously,
                            activeColor: AppColors.textPrimary,
                            onChanged: (v) =>
                                setState(() => _reportAnonymously = v),
                          ),
                        ],
                      ),
                    ],
                  ] else ...[
                    ..._buildLostPetFields(),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Submit Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || (_isPetSurrenderType && _isRescueOrgAcquisition))
                      ? null
                      : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: AppColors.textPrimary))
                      : Text('Submit Report',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.textPrimary)),
                ),
              ),

            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {bool required = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.zain(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (required) ...[
          const SizedBox(width: 4),
          const Text(
            '*',
            style: TextStyle(
              color: Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ],
    );
  }

  // Species dropdown ('Dog' / 'Cat') shared by the owner's pet and every
  // found/stray animal card.
  Widget _speciesDropdown({
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isDense: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Select species',
        hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary),
        ),
      ),
      items: const [
        DropdownMenuItem(value: _dogSpecies, child: Text('Dog')),
        DropdownMenuItem(value: _catSpecies, child: Text('Cat')),
      ],
      onChanged: onChanged,
    );
  }

  // Breed dropdown, filtered by whichever species is selected. Picking
  // "Others / Not sure" reveals a small text field for a custom breed.
  Widget _breedDropdown({
    required String? species,
    required String? breedValue,
    required ValueChanged<String?> onChanged,
    required TextEditingController otherController,
  }) {
    final options = _breedOptionsFor(species);
    final validValue =
    (breedValue != null && options.contains(breedValue)) ? breedValue : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: validValue,
          isDense: true,
          decoration: InputDecoration(
            isDense: true,
            hintText: species == null ? 'Select species first' : 'Select breed',
            hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
            border: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary),
            ),
          ),
          items: species == null
              ? const []
              : options
              .map((b) => DropdownMenuItem(
            value: b,
            child: Text(
              b,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
            ),
          ))
              .toList(),
          onChanged: species == null ? null : onChanged,
        ),
        if (validValue == _othersBreedLabel) ...[
          const SizedBox(height: 8),
          _lostPetTextField(otherController, 'Enter breed'),
        ],
      ],
    );
  }

  Widget _buildMediaBox(int index) {
    final item = _mediaFiles[index];
    final progress = _uploadProgress[index];
    return GestureDetector(
      onTap: _isLoading ? null: () => _pickMedia(index),

      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: item != null ? AppColors.greenrspwn : AppColors.textPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(8),
          color: item != null ? AppColors.greenrspwn.withOpacity(0.05) : Colors.transparent,
        ),

        clipBehavior: Clip.hardEdge,
        child: item != null ? Stack(
          fit: StackFit.expand,
          children: [
            item.isVideo ? Container(
              color: Colors.black87,
              child: const Center(
                child: Icon(Icons.play_circle_outline, size: 28, color: AppColors.textPrimary),
              ),
            )
                :Image.file(File(item.file.path), fit:BoxFit.cover),
            if (progress != null)
              Container(
                color: Colors.black54,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 36, height: 36,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 3,
                          color: AppColors.yellowrspwn,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('${(progress * 100).toInt()}%',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        )
            : const Center(
            child: Icon(Icons.add, size: 28, color: AppColors.textPrimary)
        ),
      ),
    );
  }

  Widget _buildCheckboxOption(String label) {
    return GestureDetector(
      onTap: () => setState(() => _selectedUrgency = label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _selectedUrgency == label,
                onChanged: (val) => setState(() => _selectedUrgency = label),
                activeColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.zain(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxOption2(
      String label, String? selected, Function(String) onSelect) {
    return GestureDetector(
      onTap: () => onSelect(label),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: selected == label,
                onChanged: (_) => onSelect(label),
                activeColor: AppColors.textPrimary,
                side: const BorderSide(
                    color: AppColors.textPrimary, width: 1.5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  // Pet Surrender — its own question set, replacing the generic on-site /
  // coordinate-with-shelter / willing-to-adopt questions (none of which
  // make sense when the owner is voluntarily surrendering their own pet
  // and is already right there with it).
  List<Widget> _buildSurrenderFields() {
    return [
      // Describe Condition — still relevant (helps staff prep for intake).
      _buildLabel('Describe Condition', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_conditionController, 'Enter condition'),
      const SizedBox(height: 20),

      _buildLabel('Type of Animal', required: true),
      const SizedBox(height: 4),
      Text(
        'Surrendering more than one? Add each animal below — they will '
            'be tracked together as one case.',
        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 10),
      ..._buildAnimalEntryFields(),
      const SizedBox(height: 20),

      _buildLabel('How long has the pet been staying with you?', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_surrenderDurationController, 'e.g. 2 years, since it was a puppy'),
      const SizedBox(height: 20),

      _buildLabel('Age of the pet', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_surrenderAgeController, 'e.g. 3 years old, 6 months',
          keyboardType: TextInputType.text),
      const SizedBox(height: 20),

      _buildLabel('Why are you surrendering this pet?', required: true),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _surrenderReason,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Select a reason',
          hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        ),
        items: [
          for (final reason in _surrenderReasonOptions)
            DropdownMenuItem(
              value: reason,
              child: Text(reason,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            ),
        ],
        onChanged: (v) => setState(() => _surrenderReason = v),
      ),
      if (_surrenderReason == 'Other (please specify)') ...[
        const SizedBox(height: 6),
        _lostPetTextField(_surrenderReasonOtherController, 'Please specify'),
      ],
      const SizedBox(height: 20),

      if (_surrenderNeedsExplanation) ...[
        _buildLabel(
          _surrenderReason == 'Behavioral issues'
              ? 'Please explain the behavior and what actions you\'ve taken to try to solve it'
              : 'Please explain the medical issue and what actions you\'ve taken to try to solve it',
          required: true,
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _surrenderExplanationController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Describe the issue and what you\'ve already tried…',
            hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
            ),
            isDense: true,
            contentPadding: const EdgeInsets.only(bottom: 8),
          ),
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 20),
      ],

      _buildLabel('Where did you acquire this pet?', required: true),
      const SizedBox(height: 6),
      DropdownButtonFormField<String>(
        value: _petAcquisitionSource,
        isDense: true,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Select source',
          hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
        ),
        items: [
          for (final source in _acquisitionSourceOptions)
            DropdownMenuItem(
              value: source,
              child: Text(source, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary)),
            ),
        ],
        onChanged: (v) => setState(() => _petAcquisitionSource = v),
      ),

      if (_isRescueOrgAcquisition) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.yellowrspwn.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Please contact the previous organization and inquire to them about return pets.',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }


  Future<void> _pickLastSeenDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _lastSeenDate ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.yellowrspwn,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _lastSeenDate = picked);
  }

  Future<void> _pickLastSeenTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _lastSeenTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.yellowrspwn,
              onPrimary: AppColors.textPrimary,
              surface: AppColors.background,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _lastSeenTime = picked);
  }

  String _formatDate(DateTime d) =>
      '${_monthName(d.month)} ${d.day}, ${d.year}';

  String _monthName(int m) => const [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ][m];

  Widget _pickerField({
    required String label,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: AppColors.textPrimary, width: 1),
          ),
        ),
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppColors.textPrimary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildLostPetFields() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              'Are you the owner?',
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Text('*',
              style: TextStyle(
                  color: Colors.red, fontSize: 14, fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 8),
      _buildOwnerToggle('Yes, I am the owner.', true),
      const SizedBox(height: 4),
      _buildOwnerToggle(
          'No, I am a rescuer reporting a suspected lost pet.', false),

      if (_scannedTagId != null) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.greenrspwn.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_outlined,
                  size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'A registered ID tag was found on scan — the owner will be '
                      'notified directly instead of a manual match.',
                  style: GoogleFonts.zain(
                      fontSize: 12, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ],

      if (_isOwner == true) ..._buildOwnerFields(),
      if (_isOwner == false) ..._buildFinderFields(),
    ];
  }

  Widget _buildOwnerToggle(String label, bool value) {
    return GestureDetector(
      onTap: () => setState(() => _isOwner = value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _isOwner == value,
                onChanged: (_) => setState(() => _isOwner = value),
                activeColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
                shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lostPetTextField(TextEditingController controller, String hint,
      {TextInputType? keyboardType, List<TextInputFormatter>? inputFormatters}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
        GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary, width: 1),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.only(bottom: 8),
      ),
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
    );
  }

  // Owner side: reporting their own lost pet
  List<Widget> _buildOwnerFields() {
    return [
      const SizedBox(height: 20),
      _buildLabel('Pet Name', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_petNameController, 'Enter pet name',
          inputFormatters: [AppInputFormatters.nameOnly]),
      const SizedBox(height: 20),
      _buildLabel('Species', required: true),
      const SizedBox(height: 6),
      _speciesDropdown(
        value: _selectedAnimalType,
        onChanged: (v) => setState(() {
          _selectedAnimalType = v;
          _lostBreed = null;
        }),
      ),
      const SizedBox(height: 20),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Breed', required: false),
                const SizedBox(height: 6),
                _breedDropdown(
                  species: _selectedAnimalType,
                  breedValue: _lostBreed,
                  onChanged: (v) => setState(() => _lostBreed = v),
                  otherController: _lostBreedOtherController,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Sex', required: false),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: _lostSex,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: UnderlineInputBorder(
                        borderSide:
                        BorderSide(color: AppColors.textPrimary)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                  ],
                  onChanged: (v) => setState(() => _lostSex = v),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildLabel('Color / Distinguishing markings', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(
          _lostColorController, 'e.g. Brown and white, torn left ear'),
      const SizedBox(height: 20),
      _buildLabel('Last seen location', required: true),
      const SizedBox(height: 6),
      Text(
        _pinnedAddress,
        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
      ),
      Text(
        'Uses the pin on the map above — adjust it if this isn\'t right.',
        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Date last seen', required: true),
                const SizedBox(height: 6),
                _pickerField(
                  label: _lastSeenDate != null
                      ? _formatDate(_lastSeenDate!)
                      : 'Select date',
                  onTap: _pickLastSeenDate,
                  icon: Icons.calendar_today_outlined,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLabel('Time last seen', required: false),
                const SizedBox(height: 6),
                _pickerField(
                  label: _lastSeenTime != null
                      ? _lastSeenTime!.format(context)
                      : 'Select time',
                  onTap: _pickLastSeenTime,
                  icon: Icons.access_time,
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _buildLabel('Temperament', required: false),
      const SizedBox(height: 8),
      _buildCheckboxOption2('Friendly, approachable', _temperament,
              (val) => setState(() => _temperament = val)),
      _buildCheckboxOption2('Nervous, may run', _temperament,
              (val) => setState(() => _temperament = val)),
      _buildCheckboxOption2('Can be defensive / bite risk', _temperament,
              (val) => setState(() => _temperament = val)),
      const SizedBox(height: 20),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Offer a reward',
              style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          Switch(
            value: _offerReward,
            activeColor: AppColors.textPrimary,
            onChanged: (v) => setState(() => _offerReward = v),
          ),
        ],
      ),
      if (_offerReward) ...[
        const SizedBox(height: 6),
        _lostPetTextField(_rewardAmountController, 'Enter amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [AppInputFormatters.decimal]),
      ],
      const SizedBox(height: 20),
      _buildLabel('Contact Number', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_ownerContactController, 'Mobile number',
          keyboardType: TextInputType.phone,
          inputFormatters: AppInputFormatters.phoneFlexible),
      const SizedBox(height: 6),
      Text(
        'Only revealed to a finder once you confirm a match.',
        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
      ),
    ];
  }

  // Finder side: someone reporting a stray they suspect is lost
  List<Widget> _buildFinderFields() {
    return [
      const SizedBox(height: 20),
      _buildLabel('Location Found', required: true),
      const SizedBox(height: 6),
      Text(
        _pinnedAddress,
        style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 20),
      _buildLabel('Animal(s) found', required: true),
      const SizedBox(height: 4),
      Text(
        'Found more than one? Add each animal below — they will be tracked '
            'together as one case.',
        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 10),
      ..._buildAnimalEntryFields(),
      const SizedBox(height: 12),
      _buildLabel('Describe Condition', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_conditionController, 'Calm, scared, injured…'),
      const SizedBox(height: 20),
      _buildLabel('Right now, the animal is', required: true),
      const SizedBox(height: 8),
      _buildCheckboxOption2('With me, I can hold it for now', _animalStatus,
              (val) => setState(() => _animalStatus = val)),
      _buildCheckboxOption2("Still roaming, can't approach it", _animalStatus,
              (val) => setState(() => _animalStatus = val)),
      _buildCheckboxOption2('Already brought to a vet/shelter', _animalStatus,
              (val) => setState(() => _animalStatus = val)),
      const SizedBox(height: 16),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.pinkrspwn.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text('This animal needs pickup or medical help',
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            Switch(
              value: _finderNeedsRescue,
              activeColor: AppColors.textPrimary,
              onChanged: (v) => setState(() => _finderNeedsRescue = v),
            ),
          ],
        ),
      ),
      if (_finderNeedsRescue) ...[
        const SizedBox(height: 16),
        _buildLabel('Select Urgency', required: true),
        const SizedBox(height: 8),
        _buildCheckboxOption('Low'),
        _buildCheckboxOption('Medium'),
        _buildCheckboxOption('Critical'),
      ],
      const SizedBox(height: 20),
      _buildLabel('Contact Number', required: true),
      const SizedBox(height: 6),
      _lostPetTextField(_finderContactController, 'Mobile number',
          keyboardType: TextInputType.phone,
          inputFormatters: AppInputFormatters.phoneFlexible),
      const SizedBox(height: 6),
      Text(
        "We'll check this against open lost pet alerts nearby.",
        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary),
      ),
    ];
  }

  List<Widget> _buildAnimalEntryFields() {
    return [
      for (int i = 0; i < _foundAnimals.length; i++) _buildFoundAnimalCard(i),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => setState(() => _foundAnimals.add(_FoundAnimalEntry())),
          icon: const Icon(Icons.add, size: 18, color: AppColors.textPrimary),
          label: Text('Add another animal',
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
        ),
      ),
    ];
  }

  Widget _buildFoundAnimalCard(int index) {
    final entry = _foundAnimals[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.slaterspwn),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Animal ${index + 1}',
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              if (_foundAnimals.length > 1)
                GestureDetector(
                  onTap: () {
                    entry.dispose();
                    setState(() => _foundAnimals.removeAt(index));
                  },
                  child: const Icon(Icons.close,
                      size: 18, color: AppColors.textSecondary),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _speciesDropdown(
                  value: entry.species,
                  onChanged: (v) => setState(() {
                    entry.species = v;
                    entry.breed = null;
                  }),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _breedDropdown(
                  species: entry.species,
                  breedValue: entry.breed,
                  onChanged: (v) => setState(() => entry.breed = v),
                  otherController: entry.breedOtherController,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: entry.sex,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Sex',
                    border: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.textPrimary)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Unsure', child: Text('Unsure')),
                  ],
                  onChanged: (v) => setState(() => entry.sex = v),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: entry.size,
                  isDense: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Size',
                    border: UnderlineInputBorder(
                        borderSide: BorderSide(color: AppColors.textPrimary)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Small', child: Text('Small')),
                    DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                    DropdownMenuItem(value: 'Large', child: Text('Large')),
                  ],
                  onChanged: (v) => setState(() => entry.size = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _lostPetTextField(entry.colorController, 'Color / Distinguishing markings'),
          const SizedBox(height: 14),
          _buildHealthBehaviorAssessment(entry),
          const SizedBox(height: 10),
          _buildRiskFieldsRow(entry),
        ],
      ),
    );
  }

  /// Health & Behavior Assessment — restored per-animal section, below the
  /// base Species/Breed/Sex/Size/Color fields and above Bite/Escape Risk.
  /// Every option list/conflict rule comes from the shared
  /// core/utils/animal_health_assessment.dart constants — never duplicated
  /// here — so this page can't drift from any other reader of the same
  /// values.
  Widget _buildHealthBehaviorAssessment(_FoundAnimalEntry entry) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Health & Behavior Assessment',
            style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        _assessmentDropdown(
          hintText: 'Body Condition',
          value: entry.bodyCondition,
          options: kBodyConditionOptions,
          onChanged: (v) => setState(() => entry.bodyCondition = v),
        ),
        const SizedBox(height: 10),
        _assessmentDropdown(
          hintText: 'Mobility',
          value: entry.mobility,
          options: kMobilityOptions,
          onChanged: (v) => setState(() => entry.mobility = v),
        ),
        const SizedBox(height: 10),
        _assessmentDropdown(
          hintText: 'Alertness',
          value: entry.alertness,
          options: kAlertnessOptions,
          onChanged: (v) => setState(() => entry.alertness = v),
        ),
        const SizedBox(height: 10),
        _assessmentDropdown(
          hintText: 'Eyes, Nose, Mouth',
          value: entry.eyesNoseMouth,
          options: kEyesNoseMouthOptions,
          onChanged: (v) => setState(() => entry.eyesNoseMouth = v),
        ),
        const SizedBox(height: 10),
        _assessmentDropdown(
          hintText: 'Skin and Coat',
          value: entry.skinAndCoat,
          options: kSkinAndCoatOptions,
          onChanged: (v) => setState(() => entry.skinAndCoat = v),
        ),
        const SizedBox(height: 10),
        _assessmentDropdown(
          hintText: 'Appetite and Hydration',
          value: entry.appetiteHydration,
          options: kAppetiteHydrationOptions,
          onChanged: (v) => setState(() => entry.appetiteHydration = v),
        ),
        const SizedBox(height: 12),
        Text('Behavior', style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kBehaviorOptions)
              _toggleChip(
                label: option,
                selected: entry.behavior.contains(option),
                onTap: () => setState(() {
                  if (entry.behavior.contains(option)) {
                    entry.behavior.remove(option);
                  } else {
                    entry.behavior.add(option);
                    // Deselect anything this option conflicts with, in
                    // both directions — 'Calm' clears 'Aggressive' and
                    // vice versa.
                    final conflicts = kBehaviorConflicts[option] ?? const {};
                    entry.behavior.removeWhere((b) => conflicts.contains(b));
                    for (final other in List.of(entry.behavior)) {
                      if ((kBehaviorConflicts[other] ?? const {}).contains(option)) {
                        entry.behavior.remove(other);
                      }
                    }
                  }
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        _EnvironmentSafetySection(entry: entry, onChanged: () => setState(() {})),
      ],
    );
  }

  Widget _assessmentDropdown({
    required String hintText,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isDense: true,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
        border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
      ),
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(o, overflow: TextOverflow.ellipsis, style: GoogleFonts.zain(fontSize: 13)),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Widget _toggleChip({required String label, required bool selected, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.yellowrspwn : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? AppColors.yellowrspwn : AppColors.slaterspwn),
        ),
        child: Text(
          label,
          style: GoogleFonts.zain(
              fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// Bite risk / Escape risk side by side when there's enough width for
  /// both dropdowns to stay legible, stacked full-width otherwise — fixes
  /// the "RIGHT OVERFLOWED BY 25 PIXELS" this row produced on narrow
  /// devices (the long option strings, e.g. "Has attempted to bite", plus
  /// two Expanded halves in a Row, didn't leave enough room). Each
  /// dropdown also gets isExpanded + ellipsis so a long value never
  /// overflows even at the breakpoint boundary or under text scaling.
  Widget _buildRiskFieldsRow(_FoundAnimalEntry entry) {
    const breakpoint = 340.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bite = _riskDropdown(
          hintText: 'Bite risk',
          value: entry.biteRisk,
          options: kBiteRiskLevels,
          onChanged: (v) => setState(() => entry.biteRisk = v),
        );
        final escape = _riskDropdown(
          hintText: 'Escape risk',
          value: entry.escapeRisk,
          options: kEscapeRiskLevels,
          onChanged: (v) => setState(() => entry.escapeRisk = v),
        );
        if (constraints.maxWidth < breakpoint) {
          return Column(
            children: [
              bite,
              const SizedBox(height: 10),
              escape,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: bite),
            const SizedBox(width: 10),
            Expanded(child: escape),
          ],
        );
      },
    );
  }

  Widget _riskDropdown({
    required String hintText,
    required String? value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isDense: true,
      isExpanded: true, // lets the selected-value Text shrink to fit instead of overflowing
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        border: const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
      ),
      items: [
        for (final level in options)
          DropdownMenuItem(
            value: level,
            child: Text(level, overflow: TextOverflow.ellipsis),
          ),
      ],
      selectedItemBuilder: (context) => [
        for (final _ in options)
          Align(
            alignment: Alignment.centerLeft,
            child: Text(value ?? '', overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _handleSubmit() async {
    if (_isLostPetType) {
      await _submitLostPetReport();
      return;
    }

    final condition = _conditionController.text.trim();
    final filledCount = _mediaFiles.where((f) => f != null).length;
    final validAnimals =
    _foundAnimals.where((a) => a.speciesText.isNotEmpty).toList();

    if (_isPetSurrenderType) {
      if (condition.isEmpty ||
          _selectedUrgency == null ||
          validAnimals.isEmpty ||
          _surrenderDurationController.text.trim().isEmpty ||
          _surrenderAgeController.text.trim().isEmpty ||
          _surrenderReason == null ||
          _petAcquisitionSource == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_surrenderReason == 'Other (please specify)' &&
          _surrenderReasonOtherController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please specify the reason for surrendering.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      if (_surrenderNeedsExplanation &&
          _surrenderExplanationController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please explain the issue and what you\'ve tried.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
    } else if (condition.isEmpty ||
        _selectedRescueType == null ||
        _selectedUrgency == null ||
        validAnimals.isEmpty ||
        _onSiteChoice == null ||
        _coordinateChoice == null ||
        _adoptionChoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_isPetSurrenderType && _adoptionChoice == 'yes' && !_adoptionCommitmentAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the adoption-interest terms before submitting.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (!_isPetSurrenderType && _coordinateChoice == 'no') {
      final witnessNameError =
      AppValidators.name(_witnessNameController.text, fieldName: 'Witness name');
      if (witnessNameError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(witnessNameError), backgroundColor: Colors.redAccent),
        );
        return;
      }
      final witnessPhoneError =
      AppValidators.phFlexiblePhone(_witnessNumberController.text);
      if (witnessPhoneError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(witnessPhoneError), backgroundColor: Colors.redAccent),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    if(filledCount < 2){
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
          Text('Please add at least 2 media files.'),
          backgroundColor: Colors.redAccent));
      return;
    }

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final reporterName =
      '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();

      final casesCollection = FirebaseFirestore.instance.collection('cases');

      // One case document covers every animal in this report — an
      // `animals[]` entry per animal, not a separate case doc per animal.
      // Every phase downstream (Treatment's animal selector, Intake,
      // Animal Record creation via sourceAnimalIndex, findPossibleDuplicates,
      // etc.) already reads this array as the primary source, falling back
      // to the legacy top-level animalType/breed/... fields only for
      // reports saved before this array existed — so this is the only
      // write-side change needed to keep every animal attached through the
      // whole workflow instead of losing all but one to a since-removed
      // per-animal-doc split.
      final animalsArray = [
        for (final animal in validAnimals)
          {
            'species': animal.speciesText,
            'breed': animal.breedText,
            'sex': animal.sex,
            'size': animal.size,
            'colorMarkings': animal.colorController.text.trim(),
            // Health & Behavior Assessment (spec) — per animal, never
            // collapsed into a shared/first-animal value.
            'bodyCondition': animal.bodyCondition,
            'mobility': animal.mobility,
            'alertness': animal.alertness,
            'eyesNoseMouth': animal.eyesNoseMouth,
            'skinAndCoat': animal.skinAndCoat,
            'appetiteHydration': animal.appetiteHydration,
            'behavior': animal.behavior.toList(),
            'environmentSafety': animal.environmentSafety.toList(),
            'biteRisk': animal.biteRisk,
            'escapeRisk': animal.escapeRisk,
          },
      ];

      final surrenderReasonValue = _surrenderReason == 'Other (please specify)'
          ? 'Other: ${_surrenderReasonOtherController.text.trim()}'
          : _surrenderReason;

      final docRef = await casesCollection.add({
        'reporterId': uid,
        'reporterName': reporterName,
        'reporterPhone': userData?['phone'] ?? '',
        'animals': animalsArray,
        // Legacy singular fields, kept for any code path that hasn't been
        // migrated to read `animals[]` yet — mirrors the first animal,
        // same as every other reader's own fallback convention.
        'animalType': animalsArray.first['species'],
        'breed': animalsArray.first['breed'],
        'sex': animalsArray.first['sex'],
        'size': animalsArray.first['size'],
        'colorMarkings': animalsArray.first['colorMarkings'],
        'biteRisk': animalsArray.first['biteRisk'],
        'escapeRisk': animalsArray.first['escapeRisk'],
        'rescueType': _selectedRescueType,
        'condition': condition,
        'urgency': _selectedUrgency,
        if (!_isPetSurrenderType) 'onSite': _onSiteChoice,
        if (!_isPetSurrenderType)
          'accessInstructions': _accessInstructionsController.text.trim(),
        if (!_isPetSurrenderType)
          'bestTimeToContact': _bestTimeContactController.text.trim(),
        'reportAnonymously':
        _selectedRescueType == 'Neglect or Abuse' ? _reportAnonymously : false,
        'address': _addressController.text.trim().isEmpty
            ? _pinnedAddress
            : _addressController.text.trim(),
        'lat': _pinnedLocation.latitude,
        'lng': _pinnedLocation.longitude,
        if (!_isPetSurrenderType) 'coordinateWithShelter': _coordinateChoice,
        if (!_isPetSurrenderType) 'witnessName': _witnessNameController.text.trim(),
        if (!_isPetSurrenderType) 'witnessPhone': _witnessNumberController.text.trim(),
        if (!_isPetSurrenderType) 'interestedToAdopt': _adoptionChoice,
        // Pet Surrender's own question set — see _buildSurrenderFields.
        if (_isPetSurrenderType) 'surrenderDuration': _surrenderDurationController.text.trim(),
        if (_isPetSurrenderType) 'surrenderAge': _surrenderAgeController.text.trim(),
        if (_isPetSurrenderType) 'surrenderReason': surrenderReasonValue,
        if (_isPetSurrenderType && _surrenderNeedsExplanation)
          'surrenderExplanation': _surrenderExplanationController.text.trim(),
        if (_isPetSurrenderType) 'petAcquisitionSource': _petAcquisitionSource,
        'scannedTagId': _scannedTagId,
        'status': 'pending',
        'statusHistory': [
          {
            'status': 'Rescue case is being reviewed.',
            'timestamp': Timestamp.now(),
          }
        ],
        'photoUrls': [],
        'createdAt': Timestamp.now(),
        'serverCreatedAt' : FieldValue.serverTimestamp(),
      });

      final primaryCaseId = docRef.id;
      final media = await _uploadAllMedia(primaryCaseId);
      if (media.photoUrls.isNotEmpty || media.videoUrls.isNotEmpty) {
        await casesCollection.doc(primaryCaseId).update({
          'photoUrls': media.photoUrls,
          'videoUrls': media.videoUrls,
        });
      }


      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TrackCasePage(caseId: primaryCaseId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitLostPetReport() async {
    if (_isOwner == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please tell us whether you are the owner.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final filledCount = _mediaFiles.where((f) => f != null).length;
    if (filledCount < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least 1 photo.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    if (_isOwner == true) {
      if (_petNameController.text.trim().isEmpty ||
          _selectedAnimalType == null ||
          _lostColorController.text.trim().isEmpty ||
          _lastSeenDate == null ||
          _ownerContactController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final ownerPhoneError =
      AppValidators.phFlexiblePhone(_ownerContactController.text);
      if (ownerPhoneError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ownerPhoneError), backgroundColor: Colors.redAccent),
        );
        return;
      }

      if (_offerReward) {
        final amountError = AppValidators.amount(
          _rewardAmountController.text,
          fieldName: 'Reward amount',
        );
        if (amountError != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(amountError), backgroundColor: Colors.redAccent),
          );
          return;
        }
      }
    } else {
      final hasEmptySpecies = _foundAnimals
          .any((a) => a.speciesText.isEmpty);
      if (hasEmptySpecies ||
          _conditionController.text.trim().isEmpty ||
          _animalStatus == null ||
          _finderContactController.text.trim().isEmpty ||
          (_finderNeedsRescue && _selectedUrgency == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please fill in all required fields.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final finderPhoneError =
      AppValidators.phFlexiblePhone(_finderContactController.text);
      if (finderPhoneError != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(finderPhoneError), backgroundColor: Colors.redAccent),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() as Map<String, dynamic>?;
      final reporterName =
      '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();

      final alertsCollection = FirebaseFirestore.instance.collection('petAlerts');
      String? groupId;
      final createdDocIds = <String>[];
      String? linkedCaseId;

      if (_isOwner == true) {
        final docRef = await alertsCollection.add({
          'type': 'lost',
          'groupId': null, // set to own id right after creation
          'reporterId': uid,
          'reporterName': reporterName,
          'contactNumber': _ownerContactController.text.trim(),
          'petName': _petNameController.text.trim(),
          'species': _selectedAnimalType,
          'breed': _lostBreedText,
          'sex': _lostSex,
          'colorMarkings': _lostColorController.text.trim(),
          'temperament': _temperament,
          'offerReward': _offerReward,
          'rewardAmount': _offerReward ? _rewardAmountController.text.trim() : null,
          'lastSeenDate': _lastSeenDate != null
              ? Timestamp.fromDate(_lastSeenDate!)
              : null,
          'lastSeenTime': _lastSeenTime?.format(context),
          'address': _addressController.text.trim().isEmpty
              ? _pinnedAddress
              : _addressController.text.trim(),
          'lat': _pinnedLocation.latitude,
          'lng': _pinnedLocation.longitude,
          'scannedTagId': _scannedTagId,
          'photoUrls': [],
          'status': 'open',
          'createdAt': Timestamp.now(),
          'serverCreatedAt': FieldValue.serverTimestamp(),
        });
        groupId = docRef.id;
        createdDocIds.add(docRef.id);
        await docRef.update({'groupId': groupId});
      } else {
        // Optional linked rescue case if the finder needs pickup/medical help.
        if (_finderNeedsRescue) {
          final caseRef = await FirebaseFirestore.instance.collection('cases').add({
            'reporterId': uid,
            'reporterName': reporterName,
            'reporterPhone': _finderContactController.text.trim(),
            'animalType': _foundAnimals.first.speciesText,
            'rescueType': 'Lost Pet',
            'condition': _conditionController.text.trim(),
            'urgency': _selectedUrgency,
            'address': _addressController.text.trim().isEmpty
                ? _pinnedAddress
                : _addressController.text.trim(),
            'lat': _pinnedLocation.latitude,
            'lng': _pinnedLocation.longitude,
            'scannedTagId': _scannedTagId,
            'status': 'pending',
            'statusHistory': [
              {
                'status': 'Suspected lost pet reported — awaiting pickup assignment.',
                'timestamp': Timestamp.now(),
              }
            ],
            'photoUrls': [],
            'createdAt': Timestamp.now(),
            'serverCreatedAt': FieldValue.serverTimestamp(),
          });
          linkedCaseId = caseRef.id;
        }

        for (int i = 0; i < _foundAnimals.length; i++) {
          final a = _foundAnimals[i];
          final docRef = await alertsCollection.add({
            'type': 'found',
            'groupId': groupId, // filled in after the first doc is created
            'reporterId': uid,
            'reporterName': reporterName,
            'contactNumber': _finderContactController.text.trim(),
            'species': a.speciesText,
            'breed': a.breedText,
            'sex': a.sex,
            'size': a.size,
            'colorMarkings': a.colorController.text.trim(),
            'describeCondition': _conditionController.text.trim(),
            'animalStatus': _animalStatus,
            'needsRescue': _finderNeedsRescue,
            'linkedCaseId': linkedCaseId,
            'address': _addressController.text.trim().isEmpty
                ? _pinnedAddress
                : _addressController.text.trim(),
            'lat': _pinnedLocation.latitude,
            'lng': _pinnedLocation.longitude,
            'scannedTagId': _scannedTagId,
            'photoUrls': [],
            'status': 'open',
            'createdAt': Timestamp.now(),
            'serverCreatedAt': FieldValue.serverTimestamp(),
          });
          groupId ??= docRef.id;
          createdDocIds.add(docRef.id);
        }
        // Backfill groupId on every doc in the group (first doc included).
        for (final id in createdDocIds) {
          await alertsCollection.doc(id).update({'groupId': groupId});
        }
      }

      // Media is shared across the whole group (same sighting/animal(s)).
      final media = await _uploadAllMedia('lostpet_$groupId');
      if (media.photoUrls.isNotEmpty || media.videoUrls.isNotEmpty) {
        for (final id in createdDocIds) {
          await alertsCollection.doc(id).update({
            'photoUrls': media.photoUrls,
            'videoUrls': media.videoUrls,
          });
        }
      }

      final oppositeType = _isOwner == true ? 'found' : 'lost';
      final firstSpecies = _isOwner == true
          ? _selectedAnimalType
          : _foundAnimals.first.speciesText;
      final candidates = await alertsCollection
          .where('type', isEqualTo: oppositeType)
          .where('status', isEqualTo: 'open')
          .where('species', isEqualTo: firstSpecies)
          .limit(20)
          .get();

      for (final candidate in candidates.docs) {
        final lostAlertId = _isOwner == true ? groupId : candidate.id;
        final foundAlertId = _isOwner == true ? candidate.id : groupId;
        final lostReporterId = _isOwner == true ? uid : candidate['reporterId'];
        final foundReporterId = _isOwner == true ? candidate['reporterId'] : uid;

        await FirebaseFirestore.instance.collection('possibleMatches').add({
          'lostAlertId': lostAlertId,
          'foundAlertId': foundAlertId,
          'lostReporterId': lostReporterId,
          'foundReporterId': foundReporterId,
          'species': firstSpecies,
          'status': 'pending_review',
          'createdAt': Timestamp.now(),
          'serverCreatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              _isOwner == true ? 'Lost pet alert sent' : 'Found pet report sent',
              style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
            ),
            content: Text(
              candidates.docs.isNotEmpty
                  ? 'We found ${candidates.docs.length} possible match(es). '
                  'Open this report from your Activity feed and check the '
                  'Possible Matches section once our team verifies them.'
                  : "We'll notify you the moment a possible match comes in — "
                  'check the Possible Matches section on this report from '
                  'your Activity feed.',
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: Text('Done', style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to submit: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}

/// Environment and Safety chips for one animal — the predefined options
/// plus an optional reporter-added custom entry. Values belong to this
/// [entry] only; [onChanged] just triggers the parent's setState since the
/// actual data lives on the entry, not local widget state.
class _EnvironmentSafetySection extends StatefulWidget {
  final _FoundAnimalEntry entry;
  final VoidCallback onChanged;
  const _EnvironmentSafetySection({required this.entry, required this.onChanged});

  @override
  State<_EnvironmentSafetySection> createState() => _EnvironmentSafetySectionState();
}

class _EnvironmentSafetySectionState extends State<_EnvironmentSafetySection> {
  bool _addingCustom = false;

  void _addCustomValue() {
    final value = widget.entry.environmentSafetyOtherController.text.trim();
    if (value.isEmpty) return;
    // Case-insensitive de-dupe against both the predefined list and
    // whatever custom values this animal already has.
    final alreadyPresent = widget.entry.environmentSafety.any((v) => v.toLowerCase() == value.toLowerCase()) ||
        kEnvironmentSafetyOptions.any((v) => v.toLowerCase() == value.toLowerCase());
    if (alreadyPresent) {
      widget.entry.environmentSafetyOtherController.clear();
      setState(() => _addingCustom = false);
      return;
    }
    widget.entry.environmentSafety.add(value);
    widget.entry.environmentSafetyOtherController.clear();
    setState(() => _addingCustom = false);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    // Custom values are whatever's in the set beyond the predefined list —
    // shown as their own removable chips alongside it.
    final customValues = entry.environmentSafety.where((v) => !kEnvironmentSafetyOptions.contains(v)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Environment and Safety',
            style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final option in kEnvironmentSafetyOptions)
              GestureDetector(
                onTap: () {
                  setState(() {
                    if (entry.environmentSafety.contains(option)) {
                      entry.environmentSafety.remove(option);
                    } else {
                      entry.environmentSafety.add(option);
                    }
                  });
                  widget.onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: entry.environmentSafety.contains(option) ? AppColors.yellowrspwn : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: entry.environmentSafety.contains(option)
                            ? AppColors.yellowrspwn
                            : AppColors.slaterspwn),
                  ),
                  child: Text(option,
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight:
                          entry.environmentSafety.contains(option) ? FontWeight.w700 : FontWeight.w500,
                          color: AppColors.textPrimary)),
                ),
              ),
            for (final custom in customValues)
              GestureDetector(
                onTap: () {
                  setState(() => entry.environmentSafety.remove(custom));
                  widget.onChanged();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.yellowrspwn),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(custom,
                          style: GoogleFonts.zain(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(width: 4),
                      const Icon(Icons.close, size: 14, color: AppColors.textPrimary),
                    ],
                  ),
                ),
              ),
            if (!_addingCustom)
              GestureDetector(
                onTap: () => setState(() => _addingCustom = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.slaterspwn, style: BorderStyle.solid),
                  ),
                  child: Text('Add another (optional)',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                ),
              ),
          ],
        ),
        if (_addingCustom) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: entry.environmentSafetyOtherController,
                  autofocus: true,
                  onSubmitted: (_) => _addCustomValue(),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Enter a custom value',
                    hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                    enabledBorder:
                    const UnderlineInputBorder(borderSide: BorderSide(color: AppColors.textPrimary)),
                  ),
                  style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
              IconButton(
                onPressed: _addCustomValue,
                icon: const Icon(Icons.check, color: AppColors.greenrspwn),
              ),
              IconButton(
                onPressed: () {
                  entry.environmentSafetyOtherController.clear();
                  setState(() => _addingCustom = false);
                },
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(
          'Scan QR Code',
          style: GoogleFonts.zain(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_scanned) return;
              final barcode = capture.barcodes.firstOrNull;
              if (barcode?.rawValue != null) {
                _scanned = true;
                Navigator.pop(context, barcode!.rawValue);
              }
            },
          ),
          // Overlay frame
          Center(
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Text(
              'Align QR code within the frame',
              textAlign: TextAlign.center,
              style: GoogleFonts.zain(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );

  }
}
void _showScanInfo(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Text(
            'Scan for NFC or QR code',
            style: GoogleFonts.zain(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
      content: Text(
        'This animal may have an ID tag. Scan the NFC or QR code to help identify the owner.',
        style: GoogleFonts.zain(
          fontSize: 18,
          color: AppColors.textSecondary,
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
            child: Text('OK', style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    ),
  );
}
// Full-screen local-file video preview — lets someone actually watch a
// video before submitting it, instead of the report form's play-icon
// thumbnail (which never played anything; tapping it just re-opened the
// file picker to replace that slot).
class _VideoPreviewPage extends StatefulWidget {
  final File file;
  const _VideoPreviewPage({required this.file});

  @override
  State<_VideoPreviewPage> createState() => _VideoPreviewPageState();
}

class _VideoPreviewPageState extends State<_VideoPreviewPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _failed
            ? const Text(
          'Could not play this video.',
          style: TextStyle(color: Colors.white),
        )
            : !_ready
            ? const CircularProgressIndicator(color: Colors.white)
            : AspectRatio(
          aspectRatio: _controller.value.aspectRatio == 0
              ? 16 / 9
              : _controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_controller),
              GestureDetector(
                onTap: () => setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                }),
                child: AnimatedOpacity(
                  opacity: _controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}