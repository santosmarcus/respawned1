import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/features/collartag/scan_tag_flow.dart';
import 'package:respawnd1/features/collartag/pet_found_chat.dart';
import 'package:respawnd1/features/rescue/rescue_form_controller.dart';
import 'package:respawnd1/features/rescue/rescue_form_options.dart';
import 'package:respawnd1/features/rescue/services/rescue_geocoding_service.dart';
import 'package:respawnd1/features/rescue/services/rescue_report_service.dart';
import 'package:respawnd1/features/rescue/widgets/lost_pet_fields.dart';
import 'package:respawnd1/features/rescue/widgets/media_source_sheet.dart';
import 'package:respawnd1/features/rescue/widgets/qr_scanner_page.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_location_section.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_media_box.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_type_picker_sheet.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_video_preview_page.dart';
import 'package:respawnd1/features/rescue/widgets/scan_tag_button.dart';
import 'package:respawnd1/features/rescue/widgets/stray_report_fields.dart';
import 'package:respawnd1/features/rescue/widgets/surrender_fields.dart';

// QRScannerPage moved to widgets/qr_scanner_page.dart; re-exported so
// existing `import 'rescue_page.dart' show QRScannerPage` call sites
// (e.g. collartag/scan_tag_flow.dart) keep working unchanged.
export 'package:respawnd1/features/rescue/widgets/qr_scanner_page.dart'
    show QRScannerPage;

class RescuePage extends StatefulWidget {
  const RescuePage({super.key});

  @override
  State<RescuePage> createState() => _RescuePageState();
}

/// Report a Stray page. Composes the form's sections (each in
/// `features/rescue/widgets/`) and coordinates what spans them: the map
/// pin / geocoding, media picking, tag scanning and submission. The form's
/// values and validation live in [RescueFormController]; Firestore/Storage
/// writes live in [RescueReportService].
class _RescuePageState extends State<RescuePage> {
  final RescueFormController _form = RescueFormController();
  final RescueReportService _reportService = RescueReportService();
  final RescueGeocodingService _geocoder = const RescueGeocodingService();

  bool _isLoading = false;

  final ImagePicker _picker = ImagePicker();

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
    _form.dispose();
    super.dispose();
  }

  /// Rebuild after a section widget mutated [_form] (the sections call this
  /// where the page used to call `setState` directly).
  void _onFormChanged() => setState(() {});

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
      } catch (_) {}
    }

    try {
      // Check if location service is on
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Please enable location services for accurate pinning.',
              ),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () => Geolocator.openLocationSettings(),
              ),
            ),
          );
        }
        await _fallbackToLastKnownOrDefault(
          'Location services disabled — tap map to pin manually.',
        );
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
          'Location permission denied — tap map to pin manually.',
        );
        return;
      }

      // Get a fresh, accurate fix. On timeout, fall back to whatever cached
      // position is available rather than ever substituting the hardcoded
      // default coordinate as if it were a real resolved location.
      final pos =
          await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.high,
              )
              .then<Position?>((p) => p)
              .timeout(
                const Duration(seconds: 15),
                onTimeout: () => Geolocator.getLastKnownPosition(),
              );

      if (pos != null) {
        await _updatePin(LatLng(pos.latitude, pos.longitude));
      } else {
        await _fallbackToLastKnownOrDefault(
          'Could not get your location — tap map to pin manually.',
        );
      }
    } catch (e) {
      await _fallbackToLastKnownOrDefault(
        'Could not get location — tap map to pin manually.',
      );
    }
  }

  Future<void> _updatePin(LatLng pos) async {
    // Reached after awaits (GPS / geocoding); the page may be gone by then.
    if (!mounted) return;
    setState(() {
      _pinnedLocation = pos;
      _hasResolvedLocation = true;
      _pinnedAddress = 'Resolving address…';
      _loadingLocation = true;
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: pos, zoom: 17)),
    );

    final resolvedAddress = await _geocoder.reverseGeocode(pos);

    // Try to attach a nearby landmark name, without blocking on failure
    final landmark = await _geocoder.nearbyLandmark(pos);

    if (!mounted) return;
    setState(() {
      _pinnedAddress = (landmark != null && landmark.trim().isNotEmpty)
          ? 'Near $landmark • $resolvedAddress'
          : resolvedAddress;
      _loadingLocation = false;
    });
  }

  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() => _loadingLocation = true);

    try {
      final result = await _geocoder.geocodeAddress(address);
      if (!mounted) return;
      if (result != null) {
        _form.addressController.text = result.formattedAddress;
        await _updatePin(result.latLng);
      } else {
        setState(() => _loadingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Address not found. Try a different search.'),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  //Rescue Type picker
  Future<void> _pickRescueType() async {
    final selected = await showRescueTypePickerSheet(
      context,
      selectedType: _form.selectedRescueType,
    );

    if (selected != null) {
      setState(() {
        _form.selectedRescueType = selected;
        _form.selectedUrgency = urgencyForRescueType(selected);
      });
    }
  }

  //Media picker
  Future<void> _previewVideo(XFile file) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RescueVideoPreviewPage(file: File(file.path)),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _pickMedia(int index) async {
    final action = await showMediaSourceSheet(
      context,
      maxSlots: _form.mediaFiles.length,
      current: _form.mediaFiles[index],
      onPreview: () => _previewVideo(_form.mediaFiles[index]!.file),
      onRemove: () => setState(() => _form.mediaFiles[index] = null),
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
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1280,
        );
        break;
      case 'video_camera':
        file = await _picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(seconds: 60),
        );
        isVideo = true;
        break;
      case 'video_gallery':
        file = await _picker.pickVideo(
          source: ImageSource.gallery,
          maxDuration: const Duration(seconds: 60),
        );
        isVideo = true;
        break;
    }

    if (file != null && mounted) {
      setState(
        () => _form.mediaFiles[index] = RescueMediaItem(
          file: file!,
          isVideo: isVideo,
        ),
      );
    }
  }

  Future<void> _pickMultipleImages({required int startIndex}) async {
    final picked = await _picker.pickMultiImage(
      imageQuality: 80,
      maxWidth: 1280,
    );
    if (picked.isEmpty || !mounted) return;

    final emptySlots = [
      if (_form.mediaFiles[startIndex] == null) startIndex,
      for (int i = 0; i < _form.mediaFiles.length; i++)
        if (i != startIndex && _form.mediaFiles[i] == null) i,
    ];

    final placeCount = picked.length < emptySlots.length
        ? picked.length
        : emptySlots.length;

    setState(() {
      for (int i = 0; i < placeCount; i++) {
        _form.mediaFiles[emptySlots[i]] = RescueMediaItem(
          file: picked[i],
          isVideo: false,
        );
      }
    });

    if (placeCount < picked.length && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            placeCount == 0
                ? 'You already have ${_form.mediaFiles.length} photos/videos added — remove one first.'
                : 'Only $placeCount of ${picked.length} photos were added (max ${_form.mediaFiles.length} total).',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  //NFC and QR
  void _showScanOptions() {
    showScanOptionsSheet(context, onScanQr: _scanQR, onScanNfc: _scanNFC);
  }

  Future<void> _scanQR() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const QRScannerPage()),
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

      final tag = await FlutterNfcKit.poll(
        timeout: const Duration(seconds: 10),
      );
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
    setState(() => _form.scannedTagId = result);

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
              _form.isLostPetType
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
          } else if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          } else if (index == 2) {
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

            RescueLocationSection(
              pinnedLocation: _pinnedLocation,
              hasResolvedLocation: _hasResolvedLocation,
              pinnedAddress: _pinnedAddress,
              loadingLocation: _loadingLocation,
              addressController: _form.addressController,
              onMapCreated: (ctrl) => _mapController = ctrl,
              onMapTap: _updatePin,
              onLocateMe: _fetchCurrentLocation,
              onSearch: _geocodeAddress,
            ),

            const SizedBox(height: 20),

            // Include images and videos
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RescueFieldLabel('Include images and videos', required: true),
                  const SizedBox(height: 4),
                  Text(
                    'Provide actual images or videos of the animal. '
                    'At least 2 are required.',
                    style: GoogleFonts.zain(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: List.generate(
                      4,
                      (i) => RescueMediaBox(
                        item: _form.mediaFiles[i],
                        progress: _form.uploadProgress[i],
                        onTap: _isLoading ? null : () => _pickMedia(i),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Scan NFC / QR
            ScanTagButton(onPressed: _showScanOptions),
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
                  RescueFieldLabel('Rescue Type', required: true),
                  const SizedBox(height: 6),
                  GestureDetector(
                    onTap: _pickRescueType,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.slaterspwn),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _form.selectedRescueType ?? 'Select',
                            style: GoogleFonts.zain(
                              fontSize: 14,
                              color: _form.selectedRescueType == null
                                  ? AppColors.textSecondary
                                  : AppColors.textPrimary,
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: AppColors.textPrimary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (_form.isPetSurrenderType) ...[
                    SurrenderFields(form: _form, onChanged: _onFormChanged),
                  ] else if (!_form.isLostPetType) ...[
                    StrayReportFields(form: _form, onChanged: _onFormChanged),
                  ] else ...[
                    LostPetFields(
                      form: _form,
                      pinnedAddress: _pinnedAddress,
                      onChanged: _onFormChanged,
                    ),
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
                  onPressed:
                      (_isLoading ||
                          (_form.isPetSurrenderType &&
                              _form.isRescueOrgAcquisition))
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
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : Text(
                          'Submit Report',
                          style: GoogleFonts.tiltWarp(
                            fontSize: 16,
                            color: AppColors.textPrimary,
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _onUploadProgress(int slot, double? progress) {
    if (!mounted) return;
    setState(() => _form.uploadProgress[slot] = progress);
  }

  Future<void> _handleSubmit() async {
    if (_form.isLostPetType) {
      await _submitLostPetReport();
      return;
    }

    final validationError = _form.validateRescueReport();
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    final validAnimals = _form.validAnimals;

    // Health & Behavior Assessment required per animal (spec §12-14) —
    // every animal in validAnimals must independently pass, never just the
    // first one. On failure: highlight + scroll to the FIRST incomplete
    // animal's own card, name it in the error, and never clear anything
    // already entered.
    for (final entry in _form.foundAnimals) {
      if (entry.hasAssessmentError)
        setState(() => entry.hasAssessmentError = false);
    }
    for (var i = 0; i < validAnimals.length; i++) {
      final entry = validAnimals[i];
      if (!entry.hasCompleteAssessment) {
        setState(() => entry.hasAssessmentError = true);
        _showError(
          'Complete the Health & Behavior Assessment for Animal ${i + 1}.',
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final cardContext = entry.cardKey.currentContext;
          if (cardContext != null) {
            Scrollable.ensureVisible(
              cardContext,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        });
        return;
      }
    }

    setState(() => _isLoading = true);

    if (_form.filledMediaCount < 2) {
      setState(() => _isLoading = false);
      _showError('Please add at least 2 media files.');
      return;
    }

    try {
      final primaryCaseId = await _reportService.submitRescueCase(
        form: _form,
        location: _pinnedLocation,
        pinnedAddress: _pinnedAddress,
        onProgress: _onUploadProgress,
      );

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
    final validationError = _form.validateLostPetReport();
    if (validationError != null) {
      _showError(validationError);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final matchCount = await _reportService.submitLostPetReport(
        form: _form,
        location: _pinnedLocation,
        pinnedAddress: _pinnedAddress,
        lastSeenTimeLabel: _form.lastSeenTime?.format(context),
        onProgress: _onUploadProgress,
      );

      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            backgroundColor: AppColors.background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              _form.isOwner == true
                  ? 'Lost pet alert sent'
                  : 'Found pet report sent',
              style: GoogleFonts.tiltWarp(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
            ),
            content: Text(
              matchCount > 0
                  ? 'We found $matchCount possible match(es). '
                        'Open this report from your Activity feed and check the '
                        'Possible Matches section once our team verifies them.'
                  : "We'll notify you the moment a possible match comes in — "
                        'check the Possible Matches section on this report from '
                        'your Activity feed.',
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Done',
                    style: GoogleFonts.zain(fontWeight: FontWeight.w600),
                  ),
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
