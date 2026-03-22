import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/volunteerhome/volhome_screen.dart';
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
                onPressed: _openFilter
                tooltip: 'Filter',
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

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.greenrspwn,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.greenrspwn, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.greenrspwn,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You are online - ${_serviceRangeKm.toInt()} km service range',
                  style: GoogleFonts.zain(fontSize: 14, color:AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Text: 'Service Request',
                    style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)
              ),
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
                        Text('Waiting for nearby rescue requests...',
                          style: GoogleFonts.tiltWarp(
                          fontSize: 16, color: AppColors.slaterspwn)),
                      ],
                    ),
              ),
            ],
          ),
        ),

          const SizedBox(height: 12),

      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
                onPressed: _goOffline,
                icon: const Icon(Icons.power_settings_new,
                      size: 20, color: Colors.redAccent),
                label: Text(
                'Go Offline',
                style: GoogleFonts.tiltWarp(
                  fontSize: 16, color: Colors.redAccent,
                ),
              ),
            style: OutlinedButton.styleFrom(
              side:
                const BorderSide(color: Colors.redAccent, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              ),
            ),

          ),
          ),
          const SizedBox(height: 24),
      ],
    );
  }
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
        builder: (_) => _ServiceFilterSheet(
          initialRange: _serviceRangeKm,
          onApply: (km) => setState(() => _serviceRangeKm = km),
        ),);
  }

}



