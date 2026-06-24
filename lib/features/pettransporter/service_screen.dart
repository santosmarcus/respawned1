import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/pettransporter/service_filter_sheet.dart';
import 'package:respawnd1/features/pettransporter/rescue_request.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';
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
          /* onTap: (index) {
          if (index == 0) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
          if (index == 1) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          if (index == 2) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const UserProfile()),
            );
          }
        },*/
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

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
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

            ],),)
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
                : _ServiceRequestList(currentRiderUid: uid),
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

}

class _ServiceRequestList extends StatelessWidget {
  final String currentRiderUid;
  const _ServiceRequestList({required this.currentRiderUid});

  @override
  Widget build(BuildContext context) {
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

        final assignedToMe = <QueryDocumentSnapshot>[];
        final myActiveTrips = <QueryDocumentSnapshot>[];
        final openNearby = <QueryDocumentSnapshot>[];

        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final status = d['status'];
          final assignedId = d['assignedVolunteerId'];

          if (assignedId == currentRiderUid &&
              (status == 'accepted' || status == 'ongoing')) {
            myActiveTrips.add(doc);
          } else if (assignedId == currentRiderUid && status == 'assigned') {
            assignedToMe.add(doc);
          } else if (status == 'pending' &&
              (assignedId == null || assignedId == '')) {
            openNearby.add(doc);
          }
        }

        final ordered = [...myActiveTrips, ...assignedToMe, ...openNearby];

        if (ordered.isEmpty) {
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
                  itemCount: ordered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final doc = ordered[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final isMine = data['assignedVolunteerId'] == currentRiderUid;
                    final isActiveTrip = isMine &&
                        (data['status'] == 'accepted' ||
                            data['status'] == 'ongoing');

                    return _RequestCard(
                      caseId: doc.id,
                      data: data,
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

  const _RequestCard({
    required this.caseId,
    required this.data,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final urgency = data['urgency'] ?? '';
    final isCritical = urgency == 'Critical';
    final address = data['address'] ?? '';
    final dropoffAddress = data['dropoffAddress'] ?? address;
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

    if (status == 'accepted') badgeLabel = 'Accepted';
    if (status == 'ongoing') badgeLabel = 'Ongoing';

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