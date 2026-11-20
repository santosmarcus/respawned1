import 'package:respawnd1/core/utils/user_autofill.dart';
import 'package:respawnd1/core/utils/photo_metadata.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:respawnd1/features/admin/collarTags/nfc_service.dart';
import 'package:image_picker/image_picker.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/features/collartag/scan_tag_flow.dart';
import 'package:respawnd1/features/collartag/pet_found_chat.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';
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
import 'package:respawnd1/core/widgets/app_messages.dart';

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

  // Evidence saved with the report (see ReportEvidence): where the phone
  // itself was, and how the pin got to where it is.
  Position? _deviceFix;
  PinSource _pinSource = PinSource.gps;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
    _prefillContact();
  }

  /// The reporter's own mobile number in the Lost Pet owner/finder contact
  /// fields, so they don't have to type what they gave at sign-up.
  Future<void> _prefillContact() async {
    final me = await UserAutofill.load();
    if (me == null || !mounted) return;
    setState(() {
      fillIfEmpty(_form.ownerContactController, me.phone);
      fillIfEmpty(_form.finderContactController, me.phone);
    });
  }

  @override
  void dispose() {
    _nfcService.stopSession();
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
      _deviceFix = lastKnown;
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
          _deviceFix = cached;
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
            appSnackBar('Please enable location services for accurate pinning.', action: SnackBarAction(
              label: 'Settings',
              onPressed: () => Geolocator.openLocationSettings(),
            )),
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
            appSnackBar('Location permission permanently denied.', action: SnackBarAction(
              label: 'App Settings',
              onPressed: () => Geolocator.openAppSettings(),
            )),
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      )
          .then<Position?>((p) => p)
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () => Geolocator.getLastKnownPosition(),
      );

      if (pos != null) {
        _deviceFix = pos;
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

  Future<void> _updatePin(LatLng pos, {PinSource source = PinSource.gps}) async {
    // Reached after awaits (GPS / geocoding); the page may be gone by then.
    if (!mounted) return;
    setState(() {
      _pinSource = source;
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
        await _updatePin(result.latLng, source: PinSource.search);
      } else {
        setState(() => _loadingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            appSnackBar('Address not found. Try a different search.'),
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
          fromCamera: action == 'photo_camera' || action == 'video_camera',
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
        appSnackBar(placeCount == 0
            ? 'You already have ${_form.mediaFiles.length} photos/videos added — remove one first.'
            : 'Only $placeCount of ${picked.length} photos were added (max ${_form.mediaFiles.length} total).', kind: AppMessageKind.error),
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

  final _nfcService = NfcService();

  Future<void> _scanNFC() async {
    if (!await _nfcService.isAvailable()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('NFC is not available or is turned off on this device.',
              kind: AppMessageKind.error),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Hold your device near the NFC tag…',
            duration: const Duration(seconds: 15)),
      );
    }

    try {
      // Reads the link written on the chip (the same link as the QR code),
      // not the chip's hardware serial number, which matches no collar tag.
      final raw = await _nfcService.readTag(timeout: const Duration(seconds: 15));
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      _handleScanResult(raw);
    } on NfcCancelledException {
      if (mounted) ScaffoldMessenger.of(context).hideCurrentSnackBar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('NFC scan failed: $e', kind: AppMessageKind.error),
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
        appSnackBar('Tag scanned: $result', kind: AppMessageKind.success),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar('Tag scanned — checking for a registered pet…', kind: AppMessageKind.success),
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
          appSnackBar(_form.isLostPetType
              ? 'Tag scanned, but no registered profile was found for it.'
              : 'Tag scanned: $result', kind: AppMessageKind.success),
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
          appSnackBar('Could not check this tag: $e', kind: AppMessageKind.error),
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
          _form.isPetSurrenderType
              ? 'Surrender a Pet'
              : _form.isLostPetType
              ? 'Report a Lost or Found Pet'
              : 'Report a Stray',
          style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary),
        ),
        automaticallyImplyLeading: true,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Text(
                'Three short steps: where the animal is, photos, and what you saw. '
                    'Our partner organizations review every report.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
              ),
            ),

            RescueFormSection(
              step: 1,
              title: 'Location',
              subtitle: 'Pin where the animal is right now.',
              child: RescueLocationSection(
                pinnedLocation: _pinnedLocation,
                hasResolvedLocation: _hasResolvedLocation,
                pinnedAddress: _pinnedAddress,
                loadingLocation: _loadingLocation,
                addressController: _form.addressController,
                onMapCreated: (ctrl) => _mapController = ctrl,
                onMapTap: (pos) => _updatePin(pos, source: PinSource.map),
                onLocateMe: _fetchCurrentLocation,
                onSearch: _geocodeAddress,
              ),
            ),

            const SizedBox(height: 14),

            RescueFormSection(
              step: 2,
              title: 'Photos and videos',
              subtitle: 'Actual photos or videos of the animal. At least 2 are required.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  const SizedBox(height: 14),
                  // Scan NFC / QR
                  ScanTagButton(onPressed: _showScanOptions),
                ],
              ),
            ),

            const SizedBox(height: 14),

            RescueFormSection(
              step: 3,
              title: 'Rescue details',
              subtitle: 'Tell us about the animal and its current condition.',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rescue Type
                  RescueFieldLabel('Rescue type', required: true),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickRescueType,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: double.infinity,
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kRescueFieldBorder),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _form.selectedRescueType ?? 'Select rescue type',
                              style: GoogleFonts.zain(
                                fontSize: 15,
                                color: _form.selectedRescueType == null
                                    ? AppColors.textSecondary
                                    : AppColors.textPrimary,
                              ),
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

                  const SizedBox(height: 16),

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

            const SizedBox(height: 20),

            // Declaration + notice, shown for every report type.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TruthfulnessDeclaration(
                    isSurrender: _form.isPetSurrenderType,
                    accepted: _form.truthfulnessDeclared,
                    onChanged: (v) =>
                        setState(() => _form.truthfulnessDeclared = v),
                  ),
                  const SizedBox(height: 16),
                  _SubmissionNotice(
                    message: _submissionNoticeText(),
                    highlight: _form.isPetSurrenderType
                        ? kSurrenderNoticeHighlight
                        : null,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

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
                  style: AppButtons.primary,
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

  /// The notice above the Submit button, worded for the selected type.
  String _submissionNoticeText() {
    if (_form.isPetSurrenderType) {
      return 'Surrender requests are reviewed according to shelter capacity '
          'and the needs of the animals already in our care, so intake '
          'cannot always be immediate. Please continue to provide food, '
          'shelter, and care for your pet $kSurrenderNoticeHighlight.';
    }
    if (_form.isLostPetType) {
      return 'Our team and the community will help look for your pet, but '
          'a reunion cannot be guaranteed. Please continue searching '
          'nearby areas, check with local shelters and your barangay, and '
          'share your alert as widely as possible. Your own efforts remain '
          'the most important part of bringing your pet home.';
    }
    return 'Our partner organizations review every report and will make '
        'every effort to respond as quickly as possible. However, response '
        'times depend on the availability of volunteers, transport, and '
        'shelter space, so a rescue cannot be guaranteed. If it is safe to '
        'do so, please stay near the animal, keep it in sight, and provide '
        'water or shelter until help arrives. Your continued assistance can '
        'make a critical difference.';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(message, kind: AppMessageKind.error),
    );
  }

  /// What staff see when they check this report: how many photos were
  /// taken here versus picked from the gallery, and where the phone was.
  Future<ReportEvidence> _reportEvidence() async {
    final media = _form.mediaFiles.whereType<RescueMediaItem>().toList();
    final camera = media.where((m) => m.fromCamera).length;
    final fix = _deviceFix;
    // Rescue gap 7: capture time/place inside each gallery photo.
    final galleryMeta = [
      for (final m in media.where((m) => !m.fromCamera && !m.isVideo)) await PhotoMetadata.read(m.file),
    ];
    return ReportEvidence(
      galleryPhotoMetadata: galleryMeta,
      cameraMediaCount: camera,
      galleryMediaCount: media.length - camera,
      pinSource: _pinSource,
      deviceLat: fix?.latitude,
      deviceLng: fix?.longitude,
      deviceAccuracyM: fix?.accuracy,
      deviceFixAt: fix?.timestamp,
    );
  }

  void _onUploadProgress(int slot, double? progress) {
    if (!mounted) return;
    setState(() => _form.uploadProgress[slot] = progress);
  }

  Future<void> _handleSubmit() async {
    final declarationError = _form.validateDeclaration();
    if (declarationError != null) {
      _showError(declarationError);
      return;
    }

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
      if (entry.hasAssessmentError) {
        setState(() => entry.hasAssessmentError = false);
      }
    }
    for (var i = 0; i < validAnimals.length; i++) {
      final entry = validAnimals[i];
      if (!entry.isAssessmentComplete(
        isSurrender: _form.isPetSurrenderType,
        requireVisibleSigns: _form.asksVisibleSigns,
      )) {
        setState(() {
          entry.hasAssessmentError = true;
          entry.expanded = true; // open it so the missing fields show
        });
        _showError(
          _form.isPetSurrenderType
              ? 'Complete all details for Animal ${i + 1}.'
              : 'Complete the Health & Behavior Assessment for Animal ${i + 1}.',
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
        evidence: await _reportEvidence(),
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
          appSnackBar('Failed to submit: $e', kind: AppMessageKind.error),
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
      await _reportService.submitLostPetReport(
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
              "We're checking open reports for possible matches now. "
                  "We'll notify you when a likely match comes in — you can "
                  'also check the Possible Matches section on this report '
                  'from your Activity feed.',
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
                    // Back to the existing home shell rather than
                    // stacking a second one on top of it.
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: AppButtons.primary,
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
          appSnackBar('Failed to submit: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}


/// The bold part of the Pet Surrender notice above the Submit button.
const String kSurrenderNoticeHighlight =
    'until the team approves your animal for community adoption';

/// Checkbox declaring the report is truthful and accurate. Required before
/// any report type can be submitted.
class _TruthfulnessDeclaration extends StatelessWidget {
  const _TruthfulnessDeclaration({
    required this.isSurrender,
    required this.accepted,
    required this.onChanged,
  });

  /// Pet Surrender adds a declaration of ownership.
  final bool isSurrender;
  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!accepted),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: accepted,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.textPrimary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(2),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Declaration of Accuracy. ',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text:
                    'I certify that the information, photos, and videos '
                        'in this report are true and accurate to the best of '
                        'my knowledge. ',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (isSurrender)
                    TextSpan(
                      text:
                      'I further declare that I am the lawful owner of the '
                          'animal(s) being surrendered and have the right to '
                          'transfer their ownership. ',
                      style: GoogleFonts.zain(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  TextSpan(
                    text:
                    'I understand that false or misleading reports take '
                        'rescue resources away from animals in genuine need '
                        'and may result in this report being declined.',
                    style: GoogleFonts.zain(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Informational notice shown directly above the Submit button.
class _SubmissionNotice extends StatelessWidget {
  const _SubmissionNotice({required this.message, this.highlight});

  final String message;

  /// Part of [message] to show in bold, if any.
  final String? highlight;

  TextSpan _highlighted() {
    final h = highlight;
    final at = h == null ? -1 : message.indexOf(h);
    if (h == null || at < 0) return TextSpan(text: message);
    return TextSpan(
      children: [
        TextSpan(text: message.substring(0, at)),
        TextSpan(
          text: h,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        TextSpan(text: message.substring(at + h.length)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please note',
                  style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  _highlighted(),
                  style: GoogleFonts.zain(
                    fontSize: 12.5,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
