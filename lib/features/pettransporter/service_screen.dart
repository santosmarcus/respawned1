import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/pettransporter/service_filter_sheet.dart';
import 'package:respawnd1/features/pettransporter/rescue_request.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';
import 'package:respawnd1/features/pettransporter/transporter_notif.dart';
import 'package:respawnd1/features/pettransporter/transporter_profile.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';

const String _mapsApiKey = 'AIzaSyAzqeI6uyCZW5VHQTeOyWqLdku6n-rzjTQ';

class ServiceScreen extends StatefulWidget{
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() =>
      _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  bool _isOnline = false;
  bool _seedingTestData = false;

  GoogleMapController? _mapController;
  double _serviceRangeKm = 100;
  bool _loadingLocation = false;
  LatLng? _currentLocation;

  @override
  void dispose(){
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.rescuerTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,

          actions: [
            // TEMPORARY TEST AID — creates a couple of self-contained fake
            // cases + pending transportAssignments offers for THIS signed-in
            // rider, so the "see and accept reports assigned by admin" flow
            // (service_screen.dart / rescue_request.dart /
            // transporter_notif.dart) can be verified end-to-end without a
            // real admin walking through Assign Rider, and without a second
            // transporter account. Mirrors the existing demo-transporter
            // convention in assign_rider_page.dart (isDemo: true, clearly
            // labeled). Remove this button once real multi-case testing via
            // the actual admin flow is set up.
            IconButton(
              icon: _seedingTestData
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.science_outlined, color: AppColors.textPrimary),
              tooltip: 'Add test assignments (dev only)',
              onPressed: _seedingTestData ? null : _seedTestAssignments,
            ),
            IconButton(
              icon: const Icon(Icons.tune, color: AppColors.textPrimary),
              onPressed: _openFilter,
            ),
          ],
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
            if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                    const TransporterNotifications()),
              );
            }
            if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const TransporterProfile()),
              );
            }
          },
        ),
        body: _isOnline ? _buildOnlineView() : _buildOfflineView(),
      ),
    );
  }

  Widget _buildOfflineView() {
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.slaterspwn,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _loadingLocation ? null : _goOnline,
              icon: _loadingLocation ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textPrimary))
                  : const Icon(Icons.power_settings_new, size: 20,
                  color: AppColors.textPrimary),
              label: Text(
                _loadingLocation ? 'Getting Location...' : 'Go Online',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16,
                  color: AppColors.textPrimary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.background,
                foregroundColor: AppColors.textPrimary,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [ BoxShadow(
                color: AppColors.slaterspwn,
                blurRadius: 1,
                offset: Offset(0, 3),
              ),
              ],
            ),
            child: Text(
              'You are currently offline.',
              style: GoogleFonts.tiltWarp(
                  fontSize: 16, color: AppColors.textPrimary),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Pet transporters must not see any rescue cases — admin-assigned
        // or otherwise — while offline. No live query here at all; going
        // online is the only way to see anything in Service Request.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Service Request',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                decoration: BoxDecoration(color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(
                      color: AppColors.slaterspwn,
                      blurRadius: 1,
                      offset: Offset(0, 3),)
                    ]
                ),
                child: Column(
                  children: [
                    Text('There are no requests for now.',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 16, color: AppColors.slaterspwn)),
                    Text('Go Online.', style: GoogleFonts.tiltWarp(
                        fontSize: 16, color: AppColors.slaterspwn)),
                  ],
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineView(){
    final center = _currentLocation ?? const LatLng(14.5995, 120.9842);
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(20),
              color: AppColors.slaterspwn,),
            clipBehavior: Clip.hardEdge,
            child: GoogleMap(
              onMapCreated: (ctrl) {
                _mapController = ctrl;
                if(_currentLocation != null){
                  ctrl.animateCamera(CameraUpdate.newCameraPosition(
                    CameraPosition(target: _currentLocation!, zoom: 14),));
                }
              },
              initialCameraPosition:
              CameraPosition(target: center, zoom: 14),
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
              markers: _currentLocation == null ? {}
                  : {
                Marker(
                  markerId: const MarkerId('my_location'),
                  position: _currentLocation!,
                  infoWindow:
                  const InfoWindow(title: 'Your Location'),
                ),
              },
              circles: _currentLocation == null
                  ? {}
                  : {
                Circle(
                  circleId: const CircleId('service_range'),
                  center: _currentLocation!,
                  radius: _serviceRangeKm * 1000,
                  fillColor:
                  AppColors.greenrspwn.withOpacity(0.12),
                  strokeColor: AppColors.greenrspwn,
                  strokeWidth: 1,
                ),
              },
            ),
          ),
        ),

        const SizedBox(height: 12),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _goOffline,
              icon: const Icon(Icons.circle_rounded,
                  size: 10, color: Colors.green),
              label: Text(
                'Online',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16, color: AppColors.textPrimary,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.background,
                foregroundColor: AppColors.textPrimary,
                elevation: 3,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

          ),
        ),

        const SizedBox(height: 12),

        Expanded(
          flex: 0,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: uid == null
                ? const SizedBox()
                : _ServiceRequestList(currentRiderUid: uid, includeOpenPool: true),
          ),
        ),

        const SizedBox(height: 16),
      ],
    );
  }


  Future<void> _goOnline() async {
    setState(() => _loadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showError('Location services are disabled.');
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showError('Location permission denied.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentLocation = LatLng(pos.latitude, pos.longitude);
        _isOnline = true;
      });
    } catch (_) {
      _showError('Could not get location.');
    } finally {
      if (mounted) setState(() => _loadingLocation = false);
    }
  }

  void _goOffline() => setState(() {
    _isOnline = false;
    _currentLocation = null;
  });
  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _loadingLocation = false);
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.redAccent));
  }
  void _openFilter(){
    showModalBottomSheet(context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ServiceFilterSheet(
        initialRange: _serviceRangeKm,
        onApply: (km) => setState(() => _serviceRangeKm = km),
      ),);
  }

  // TEMPORARY TEST AID — see the comment on the AppBar action above. Seeds
  // a couple of fully self-contained fake cases, each already at the
  // 'accepted' (awaiting-assignment) status a real admin-assigned case
  // would be at, plus a pending transportAssignments offer addressed to
  // THIS rider — exactly what createAssignmentOffer() would have produced.
  // Lets the "multiple reports assigned at once" scenario be checked (job
  // board + Notifications, accept/decline via RescueRequest) without
  // waiting on a real admin to assign real cases one at a time.
  Future<void> _seedTestAssignments() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showError('Sign in first to add test assignments.');
      return;
    }

    setState(() => _seedingTestData = true);
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data();
      final riderName =
      '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'.trim();

      const testCases = [
        {
          'address': '123 Test Street, Marikina City (TEST DATA)',
          'condition': 'Found limping near a test intersection.',
          'urgency': 'Critical',
          'animalType': 'Dog',
        },
        {
          'address': '456 Sample Avenue, Marikina City (TEST DATA)',
          'condition': 'Stray reported sheltering under a test parked car.',
          'urgency': 'Medium',
          'animalType': 'Cat',
        },
      ];

      final casesCollection = FirebaseFirestore.instance.collection('cases');
      for (final t in testCases) {
        final caseRef = await casesCollection.add({
          'reporterId': 'test-reporter',
          'reporterName': 'Test Reporter',
          'reporterPhone': '',
          'animalType': t['animalType'],
          'condition': t['condition'],
          'urgency': t['urgency'],
          'address': t['address'],
          'lat': 14.6507,
          'lng': 121.1029,
          'status': 'accepted', // awaiting-assignment, same as a real case
          'statusHistory': [
            {
              'status': '[TEST] Case ready for transporter assignment.',
              'timestamp': Timestamp.now(),
            }
          ],
          'photoUrls': [],
          'createdAt': Timestamp.now(),
          'serverCreatedAt': FieldValue.serverTimestamp(),
          'isTestData': true,
        });

        final assignmentRef = await caseRef.collection('transportAssignments').add({
          'caseId': caseRef.id,
          'riderId': uid,
          'riderName': riderName.isEmpty ? 'Test Transporter' : riderName,
          'riderType': 'Pet Transporter',
          'status': 'pending',
          'offeredAt': Timestamp.now(),
          'respondedAt': null,
          'acceptedAt': null,
          'rejectedAt': null,
          'rejectionReason': null,
          'completedAt': null,
          'isDemo': true,
        });
        await caseRef.update({'currentAssignmentId': assignmentRef.id});
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Added ${testCases.length} test assignments — check Home and Notifications.'),
            backgroundColor: AppColors.greenrspwn,
          ),
        );
      }
    } catch (e) {
      _showError('Failed to add test assignments: $e');
    } finally {
      if (mounted) setState(() => _seedingTestData = false);
    }
  }

}

class _ServiceRequestList extends StatelessWidget {
  final String currentRiderUid;
  // The ambient "open, unassigned, nearby" pool only makes sense while the
  // rider has opted in to being visible/available (Online). An admin
  // assignment offer — or a job this rider is already actively on — is
  // NOT ambient nearby work and must still surface even while Offline, so
  // those buckets below are never gated by this flag.
  final bool includeOpenPool;
  const _ServiceRequestList({
    required this.currentRiderUid,
    this.includeOpenPool = true,
  });

  @override
  Widget build(BuildContext context) {
    // Admin assignments (assign_rider_page.dart) create a *pending* offer
    // doc under cases/{caseId}/transportAssignments instead of touching the
    // case's own status/assignedVolunteerId fields directly — those only
    // change once this rider actually accepts (see
    // RescueCaseRepository.createAssignmentOffer/acceptAssignment). So a
    // case freshly offered to this rider stays invisible to every bucket
    // below unless we also know about it from this collectionGroup stream.
    // Requires a Firestore composite collection-group index on
    // transportAssignments (riderId, status) — the first live query prints
    // the console's direct create-index link if it's still missing.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('transportAssignments')
          .where('riderId', isEqualTo: currentRiderUid)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, offersSnapshot) {
        if (offersSnapshot.hasError) {
          // Almost always a missing Firestore composite index the first
          // time this query ever runs (collection-group queries need one
          // created explicitly — Firestore does not auto-create it). Check
          // the debug console for a "The query requires an index" error
          // with a direct link to create it, or add it manually in the
          // Firebase Console: Firestore -> Indexes -> Composite ->
          // Collection group "transportAssignments", fields riderId (Asc),
          // status (Asc). Falls back to the rest of the list rather than
          // hard-failing the whole screen.
          debugPrint(
              'ServiceRequestList: transportAssignments offers query failed: '
                  '${offersSnapshot.error}');
        }

        // caseId -> assignmentId, for every offer currently awaiting this
        // rider's response.
        final offeredCaseIds = <String, String>{
          for (final doc in offersSnapshot.data?.docs ?? <QueryDocumentSnapshot>[])
            (doc.data() as Map<String, dynamic>)['caseId'] as String? ?? '':
            doc.id,
        }..remove('');

        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('cases')
              .where('status', whereIn: ['pending', 'assigned', 'accepted', 'ongoing'])
              .orderBy('createdAt', descending: true)
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _emptyState('Could not load requests.');
            }
            if (!snapshot.hasData) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppColors.textPrimary),
                ),
              );
            }

            final docs = snapshot.data!.docs;

            final visible = docs.where((doc) {
              final d = doc.data() as Map<String, dynamic>;
              final status = d['status'];
              final assignedId = d['assignedVolunteerId'];
              final declinedBy =
              List<String>.from(d['declinedBy'] ?? const <String>[]);

              // acceptAssignment() (the real admin-offer acceptance path)
              // sets status to 'assigned' — that's the only place in the
              // whole app that ever writes this status, and only after the
              // rider has already accepted, so it belongs alongside
              // 'accepted'/'ongoing' as an active trip. There's no longer a
              // reachable "offered but undecided, status already flipped to
              // assigned" case to distinguish it from — an undecided offer
              // now stays at 'accepted' (awaiting-assignment) until
              // acceptAssignment/rejectAssignment resolves it, and is
              // surfaced via isOfferedToMe below instead.
              final isMineActive = assignedId == currentRiderUid &&
                  (status == 'assigned' || status == 'accepted' || status == 'ongoing');
              final isOpenNearby = includeOpenPool &&
                  status == 'pending' &&
                  (assignedId == null || assignedId == '') &&
                  !declinedBy.contains(currentRiderUid);
              final isOfferedToMe = offeredCaseIds.containsKey(doc.id);

              return isMineActive || isOpenNearby || isOfferedToMe;
            }).toList();

            if (visible.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Service Request',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 16, color: AppColors.textPrimary)),
                    const SizedBox(height: 10),
                    _emptyState('There are no requests for now.'),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Service Request',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final doc = visible[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final assignmentId = offeredCaseIds[doc.id];
                        final isMine = data['assignedVolunteerId'] == currentRiderUid;
                        final isActiveTrip = isMine &&
                            (data['status'] == 'assigned' ||
                                data['status'] == 'accepted' ||
                                data['status'] == 'ongoing') &&
                            assignmentId == null;

                        return _RequestCard(
                          caseId: doc.id,
                          data: data,
                          isOfferedToMe: assignmentId != null,
                          onTap: () {
                            if (isActiveTrip) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TransitProgressPage(
                                    caseId: doc.id,
                                  ),
                                ),
                              );
                            } else {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => RescueRequest(
                                    caseId: doc.id,
                                    data: data,
                                    assignmentId: assignmentId,
                                  ),
                                ),
                              );
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _emptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.slaterspwn,
            blurRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          message,
          style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.slaterspwn),
        ),
      ),
    );
  }
}


class _RequestCard extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  final bool isOfferedToMe;

  const _RequestCard({
    required this.caseId,
    required this.data,
    required this.onTap,
    this.isOfferedToMe = false,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = data['urgency'] ?? '';
    final isCritical = urgency == 'Critical';
    final address = data['address'] ?? '';
    // Fallback to the admin's actual Select Clinic choice for any case
    // assigned before dropoff* was mirrored from it — see
    // RescueCaseRepository.assignClinic. Deliberately never falls back
    // further to the pickup address — that would misrepresent "no clinic
    // assigned yet" as an actual destination.
    final rawDropoffAddress =
    (data['dropoffAddress'] as String?)?.trim().isNotEmpty == true
        ? data['dropoffAddress'] as String
        : (data['vetClinicAddress'] as String?)?.trim();
    final dropoffAddress = (rawDropoffAddress == null || rawDropoffAddress.isEmpty)
        ? 'Clinic not yet assigned'
        : rawDropoffAddress;
    final condition = data['condition'] ?? '';
    final status = data['status'] ?? 'pending';

    Color badgeColor;
    String badgeLabel = urgency;
    switch (urgency) {
      case 'Critical':
        badgeColor = Colors.red;
        break;
      case 'Medium':
        badgeColor = Colors.orange;
        break;
      default:
        badgeColor = Colors.lightGreen;
    }

    if (status == 'assigned') badgeLabel = 'Accepted';
    if (status == 'accepted') badgeLabel = 'Accepted';
    if (status == 'ongoing') badgeLabel = 'Ongoing';
    // A pending admin offer leaves the case's own status at 'accepted' —
    // that badge would otherwise wrongly read as already-accepted-by-
    // someone-else, so this takes priority for a request specifically
    // awaiting THIS rider's response.
    if (isOfferedToMe) {
      badgeLabel = 'New Assignment';
      badgeColor = AppColors.greenrspwn;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: AppColors.yellowrspwn,
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      '(~4 Km) Rescue Now',
                      style: GoogleFonts.tiltWarp(
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badgeLabel,
                      style: GoogleFonts.zain(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_shipping_outlined,
                          size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Text('Transport',
                          style: GoogleFonts.zain(
                              fontSize: 14, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle_outlined,
                          size: 12, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(address,
                            style: GoogleFonts.zain(
                                fontSize: 14, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 12, color: AppColors.textPrimary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(dropoffAddress,
                            style: GoogleFonts.zain(
                                fontSize: 14, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  if (condition.toString().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.message_outlined,
                            size: 14, color: AppColors.textPrimary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Found in $condition',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(
                                fontSize: 14, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}