import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/transporter_notif.dart';
import 'package:respawnd1/features/pettransporter/transporter_profile.dart';
import 'package:respawnd1/core/repos/directions_repository.dart';
import 'package:respawnd1/features/pettransporter/services/transit_case_service.dart';
import 'package:respawnd1/features/pettransporter/transit_rules.dart';
import 'package:respawnd1/features/pettransporter/widgets/close_transit_dialog.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/awaiting_adopter_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/clinic_decision_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/searching_clinic_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/standard_progress_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/panels/verification_panel.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_info_widgets.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_messages.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_result_page.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_tracking_map.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_unread_badge.dart';
import 'package:respawnd1/features/pettransporter/widgets/treatment_reject_dialog.dart';

// Moved out of this file; re-exported so existing imports of
// transit_progress_page.dart that use these keep compiling unchanged.
export 'package:respawnd1/core/repos/directions_repository.dart'
    show DirectionsRoute, fetchDirectionsRoute, decodePolyline;
export 'package:respawnd1/features/pettransporter/widgets/transit_result_page.dart'
    show TransitResultPage;

// Transit status strings, the fallback shelter and the End Reason rules
// live in transit_rules.dart; every Firestore/Storage/Places write lives in
// services/transit_case_service.dart.

class TransitProgressPage extends StatefulWidget {
  final String caseId;
  const TransitProgressPage({super.key, required this.caseId});

  @override
  State<TransitProgressPage> createState() => _TransitProgressPageState();
}

class _TransitProgressPageState extends State<TransitProgressPage> {
  final _messageController = TextEditingController();
  final _picker = ImagePicker();
  late final TransitCaseService _service = TransitCaseService(widget.caseId);
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _positionSub;

  bool _isActing = false;
  bool _isSearchingClinic = false;
  bool _autoSearchAttempted = false;
  bool _isVerifyingArrival = false;
  Timestamp? _lastReadAt;

  @override
  void initState() {
    super.initState();
    _lastReadAt = Timestamp.now();
  }

  // Verification images
  final List<File?> _pickupImages = [null, null];
  final List<File?> _clinicImages = [
    null,
    null,
  ]; // arrived-at-clinic verification
  final List<File?> _shelterImages = [
    null,
    null,
  ]; // final shelter drop-off verification

  @override
  void dispose() {
    _messageController.dispose();
    _positionSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// False (with a snackbar) when none of [images] has been taken yet.
  bool _hasVerificationImage(List<File?> images) {
    if (images.every((f) => f == null)) {
      _showError('Please add at least one verification image.');
      return false;
    }
    return true;
  }

  void _openResultPage({required bool completed, String? reason}) {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TransitResultPage(completed: completed, reason: reason),
      ),
    );
  }

  // Location streaming
  void _beginLocationStreaming() {
    if (_positionSub != null) return;
    _positionSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 15,
          ),
        ).listen((pos) {
          _service.recordPosition(pos.latitude, pos.longitude);
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(pos.latitude, pos.longitude)),
          );
        });
  }

  // Status transitions
  Future<void> _setStatus(String status, String statusLabel) async {
    setState(() => _isActing = true);
    try {
      await _service.setStatus(status, statusLabel);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _startTrip() async {
    await _setStatus('ongoing', 'On the way to pick up location.');
    _beginLocationStreaming();
  }

  Future<void> _launchNavigation(LatLng destination, String label) async {
    final uri = Uri(
      scheme: 'https',
      host: 'www.google.com',
      path: '/maps/dir/',
      queryParameters: {
        'api': '1',
        'destination': '${destination.latitude},${destination.longitude}',
        'travelmode': 'driving',
      },
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _showMessage('Could not open Google Maps.');
    } catch (_) {
      _showMessage('Could not open Google Maps.');
    }
  }

  // Places a phone call to the given number, if available.
  Future<void> _launchCall(String? phone) async {
    final number = phone?.trim();
    if (number == null || number.isEmpty) {
      _showMessage('No phone number available.');
      return;
    }
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) _showMessage('Could not start the call.');
    } catch (_) {
      _showMessage('Could not start the call.');
    }
  }

  Future<bool> _verifyArrivalViaDirections(
    LatLng? destination,
    String destinationLabel,
  ) async {
    if (destination == null) return true;

    setState(() => _isVerifyingArrival = true);
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final origin = LatLng(pos.latitude, pos.longitude);
      final route = await fetchDirectionsRoute(origin, destination);

      if (route == null) {
        final straightLineMeters = Geolocator.distanceBetween(
          origin.latitude,
          origin.longitude,
          destination.latitude,
          destination.longitude,
        );

        if (straightLineMeters <= kArrivalThresholdMeters) {
          return true;
        }

        _showError(
          "Couldn't verify your route to $destinationLabel via Google Maps, and you're still "
          '~${straightLineMeters.round()}m away by straight-line distance — keep heading there before confirming arrival.',
        );
        return false;
      }

      if (route.distanceMeters > kArrivalThresholdMeters) {
        _showError(
          "You're still ${route.distanceText} from $destinationLabel according to Google Maps — keep heading there before confirming arrival.",
        );
        return false;
      }

      return true;
    } catch (e) {
      _showError('Could not check your location: $e');
      return false;
    } finally {
      if (mounted) setState(() => _isVerifyingArrival = false);
    }
  }

  Future<void> _markArrived() async {
    final data = await _service.fetchCase();
    final destination = latLngFrom(data, 'lat', 'lng');

    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the pick up location',
    );
    if (!arrived) return;

    await _setStatus('arrived', 'Arrived at pick up location.');
  }

  Future<void> _arriveAtClinic() async {
    final data = await _service.fetchCase();
    final destination = clinicLatLngFrom(data);

    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the clinic',
    );
    if (!arrived) return;

    await _setStatus('dropoff', 'Arrived at clinic for treatment.');
  }

  Future<void> _submitPickupVerification() async {
    if (!_hasVerificationImage(_pickupImages)) return;
    setState(() => _isActing = true);
    try {
      final urls = await _service.uploadVerificationImages(
        _pickupImages,
        'pickup',
      );
      await _service.submitPickupVerification(urls);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // Shelter destination, interested-adopter routing and clinic logging are
  // handled by TransitCaseService.acceptTreatment.
  Future<void> _acceptTreatment() async {
    if (!_hasVerificationImage(_clinicImages)) return;
    setState(() => _isActing = true);
    try {
      final urls = await _service.uploadVerificationImages(
        _clinicImages,
        'clinic',
      );
      await _service.acceptTreatment(urls);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _rejectTreatment() async {
    if (!_hasVerificationImage(_clinicImages)) return;
    final reason = await showTreatmentRejectDialog(context);
    if (reason == null) return; // dismissed via X / back

    setState(() => _isActing = true);
    try {
      await _service.rejectTreatment(reason);

      // reset verification images for the next clinic attempt
      setState(() {
        for (int i = 0; i < _clinicImages.length; i++) {
          _clinicImages[i] = null;
        }
      });
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _findAndRouteToNextClinic() async {
    if (_isSearchingClinic) return;
    setState(() => _isSearchingClinic = true);
    try {
      await _service.findAndRouteToNextClinic();
    } catch (e) {
      _showError('Clinic search failed: $e');
    } finally {
      if (mounted) setState(() => _isSearchingClinic = false);
    }
  }

  Future<void> _completeShelterDropoff() async {
    if (!_hasVerificationImage(_shelterImages)) return;

    final data = await _service.fetchCase();
    final destination = latLngFrom(data, 'shelterLat', 'shelterLng');
    final arrived = await _verifyArrivalViaDirections(
      destination,
      'the shelter',
    );
    if (!arrived) return;

    setState(() => _isActing = true);
    try {
      final urls = await _service.uploadVerificationImages(
        _shelterImages,
        'shelter',
      );
      await _service.completeShelterDropoff(urls);
      _positionSub?.cancel();
      _openResultPage(completed: true);
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  // Triggered by the "Adopter Arrived" action in AwaitingAdopterPanel
  // — only reachable once the reporter has already tapped their own
  // "Arrived at Treatment" button in TrackCasePage (adopterArrivedAtTreatment
  // == true). This is the transporter's own in-person check: the reporter
  // tapping a button on their phone doesn't prove they're actually there,
  // so this asks the transporter — who can see with their own eyes — to
  // confirm before the case concludes. Answering "not yet" is a pure no-op:
  // the case stays at 'awaiting_adopter_pickup' exactly as it was, i.e.
  // "the pet transporter remains in progress with the transit".
  Future<void> _confirmAdopterPresent() async {
    final confirmed = await showConfirmAdopterPickupDialog(context);
    if (!confirmed) return; // "Not yet" — stay exactly as is.

    setState(() => _isActing = true);
    try {
      await _service.confirmAdopterPickup();
      _positionSub?.cancel();
      _openResultPage(completed: true);
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _pickImage(List<File?> slot, int index) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked != null && mounted) {
      setState(() => slot[index] = File(picked.path));
    }
  }

  Future<void> _showCloseTransitDialog() async {
    final selection = await showCloseTransitDialog(context);
    if (selection == null) return; // closed with the X
    await _resolveEndReason(selection);
  }

  // The status decision for each End Reason is documented on
  // resolveEndReason (transit_rules.dart).
  Future<void> _resolveEndReason(EndReasonSelection selection) async {
    setState(() => _isActing = true);
    try {
      final outcome = resolveEndReason(selection);
      await _service.applyEndReason(outcome);

      _positionSub?.cancel();
      if (mounted) {
        if (outcome.isTerminal) {
          // A genuine terminal cancellation (Deceased, Vehicle breakdown,
          // Other) — show the same result screen used for a successful
          // completion, just with the cancelled variant + reason.
          _openResultPage(completed: false, reason: outcome.reasonText);
        } else {
          // Not Found / Reporter Unreachable / Aggressive / Specialized
          // transport don't end the case — it's still active (awaiting the
          // reporter, or escalated) — so just return the transporter to
          // where they came from instead of showing a "Cancelled" screen.
          Navigator.pop(context);
        }
      }
    } catch (e) {
      _showError('Error: $e');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  void _openMessageSheet() {
    setState(() => _lastReadAt = Timestamp.now());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),

              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Messages',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),

              const SizedBox(height: 12),

              Expanded(child: TransitMessagesList(caseId: widget.caseId)),

              SafeArea(
                child: TransitMessageInput(
                  controller: _messageController,
                  onSend: _sendMessage,
                ),
              ),
            ],
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() => _lastReadAt = Timestamp.now());
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await _service.sendMessage(text);
    _messageController.clear();
  }

  // Build
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data!.data() as Map<String, dynamic>?;
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('Case no longer exists.')),
          );
        }

        final status = data['status'] ?? 'accepted';

        if ((status == 'ongoing' ||
                status == 'arrived' ||
                status == 'treatment' ||
                status == 'dropoff' ||
                status == 'searching_clinic' ||
                status == 'in_transit_shelter' ||
                status == 'awaiting_adopter_pickup') &&
            _positionSub == null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _beginLocationStreaming(),
          );
        }

        if (status == 'searching_clinic') {
          if (!_isSearchingClinic && !_autoSearchAttempted) {
            _autoSearchAttempted = true;
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => _findAndRouteToNextClinic(),
            );
          }
        } else {
          _autoSearchAttempted = false;
        }

        LatLng? currentDestination;
        String currentDestinationLabel = '';
        if (status == 'ongoing' || status == 'arrived') {
          currentDestination = latLngFrom(data, 'lat', 'lng');
          currentDestinationLabel = 'Pick up location';
        } else if (status == 'treatment' || status == 'dropoff') {
          currentDestination = clinicLatLngFrom(data);
          currentDestinationLabel = 'Clinic';
        } else if (status == 'awaiting_adopter_pickup') {
          // Waiting at the clinic for the interested adopter — same
          // location as 'dropoff', just a later phase of the same stop.
          currentDestination = clinicLatLngFrom(data);
          currentDestinationLabel = 'Clinic';
        } else if (status == 'in_transit_shelter') {
          currentDestination = latLngFrom(data, 'shelterLat', 'shelterLng');
          currentDestinationLabel = 'Shelter';
        }

        return Theme(
          data: AppTheme.rescuerTheme,
          child: Scaffold(
            backgroundColor: AppColors.background,
            bottomNavigationBar: _buildBottomNav(),
            body: Column(
              children: [
                // Map
                Expanded(
                  flex: 2,
                  child: Stack(
                    children: [
                      TransitTrackingMap(
                        caseId: widget.caseId,
                        onMapCreated: (ctrl) => _mapController = ctrl,
                        destination: currentDestination,
                        destinationLabel: currentDestinationLabel,
                      ),

                      // Online badge
                      Positioned(
                        top: 48,
                        left: 16,
                        child: TransitOnlineBadge(),
                      ),

                      // Navigate button — opens turn-by-turn driving
                      // directions in the native Google Maps app, the same
                      // pattern Grab/Foodpanda driver apps use. Only shown
                      // once there's an actual destination to navigate to.
                      if (currentDestination != null)
                        Positioned(
                          bottom: 20,
                          left: 16,
                          child: FloatingActionButton.extended(
                            heroTag: 'navigate_btn',
                            backgroundColor: AppColors.textPrimary,
                            onPressed: () => _launchNavigation(
                              currentDestination!,
                              currentDestinationLabel,
                            ),
                            icon: const Icon(
                              Icons.navigation,
                              color: Colors.white,
                            ),
                            label: Text(
                              'Navigate',
                              style: GoogleFonts.tiltWarp(
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        bottom: 20,
                        right: 16,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            FloatingActionButton(
                              heroTag: 'chat_btn',
                              backgroundColor: AppColors.yellowrspwn,
                              onPressed: _openMessageSheet,
                              child: const Icon(
                                Icons.chat_bubble,
                                color: AppColors.textPrimary,
                              ),
                            ),

                            TransitUnreadBadge(
                              caseId: widget.caseId,
                              lastReadAt: _lastReadAt,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom panel
                Expanded(flex: 1, child: _buildBottomPanel(status, data)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Picks the bottom panel for the current transit [status].
  Widget _buildBottomPanel(String status, Map<String, dynamic> data) {
    switch (status) {
      // Arrived at pickup — verification
      case 'arrived':
        final clinicAddress = clinicAddressFrom(data);
        return VerificationPanel(
          title: 'Arrived at pick up location',
          address: data['address'] ?? '',
          destinationAddress: clinicAddress.isEmpty
              ? 'Clinic not yet assigned'
              : clinicAddress,
          images: _pickupImages,
          onImageTap: (i) => _pickImage(_pickupImages, i),
          onConfirm: _submitPickupVerification,
          onEnd: _showCloseTransitDialog,
          confirmLabel: 'Animal Rescued',
          isActing: _isActing,
          contactRows: buildTransitContactRows(data, onCall: _launchCall),
        );

      // Arrived at a clinic — Treatment Accepted / Treatment Rejected decision
      case 'dropoff':
        final address = clinicAddressFrom(data);
        return ClinicDecisionPanel(
          address: address,
          images: _clinicImages,
          isActing: _isActing,
          clinicProfileFuture: _service.fetchClinicProfile(
            data['dropoffPlaceId'] as String?,
            address.toString(),
          ),
          onImageTap: (i) =>
              _pickImage(_clinicImages, i).then((_) => setState(() {})),
          onAccept: _acceptTreatment,
          onReject: _rejectTreatment,
        );

      // A clinic just rejected treatment — auto-searching for the next one
      case 'searching_clinic':
        return SearchingClinicPanel(
          lastAddress: clinicAddressFrom(data),
          rejectionReason: data['lastRejectionReason'] ?? '',
          isSearching: _isSearchingClinic,
          onRetry: _findAndRouteToNextClinic,
        );

      // Treatment accepted, and the reporter marked interest to adopt on the
      // original report — waiting at the clinic for that adopter instead of
      // heading to the shelter.
      case 'awaiting_adopter_pickup':
        return AwaitingAdopterPanel(
          address: clinicAddressFrom(data),
          adopterArrived: data['adopterArrivedAtTreatment'] == true,
          isActing: _isActing,
          onAdopterArrived: _confirmAdopterPresent,
        );

      // Treatment accepted — final leg to the shelter
      case 'in_transit_shelter':
        final shelterAddress =
            (data['shelterAddress'] as String?)?.isNotEmpty == true
            ? data['shelterAddress'] as String
            : (data['shelterName'] as String?) ??
                  'Shelter address not available';
        return VerificationPanel(
          title: 'In transit to shelter',
          address: shelterAddress,
          images: _shelterImages,
          onImageTap: (i) => _pickImage(_shelterImages, i),
          onConfirm: _completeShelterDropoff,
          confirmLabel: 'Complete',
          isActing: _isActing,
        );

      // Standard panel for other statuses
      default:
        return StandardProgressPanel(
          status: status,
          pickupAddress: data['address'] ?? '',
          clinicAddress: clinicAddressFrom(data),
          contactRows: buildTransitContactRows(data, onCall: _launchCall),
          isBusy: _isActing || _isVerifyingArrival,
          onStartTrip: _startTrip,
          onMarkArrived: _markArrived,
          onArriveAtClinic: _arriveAtClinic,
        );
    }
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
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
          if (Navigator.canPop(context)) {
            Navigator.pop(context);
          }
        } else if (index == 1) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransporterNotifications()),
          );
        } else if (index == 2) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const TransporterProfile()),
          );
        }
      },
    );
  }
}
