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


class ServiceScreen extends StatefulWidget{
  const ServiceScreen({super.key});

  @override
  State<ServiceScreen> createState() =>
    _ServiceScreenState();
}

class _ServiceScreenState extends State<ServiceScreen> {
  bool _isOnline = false;

  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  bool _loadingLocation = false;

  @override
  void dispose(){
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _goOnline() async {
    setState(() => _loadingLocation = true);
    try{
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
      _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: _currentLocation!, zoom: 14),
    ),
    );
  } catch (e) {
      _showError('Could not get location.');
    } finally{
      if(mounted) setState(() => _loadingLocation = false);
      }
    }

    void _goOffline(){
    setState(() {
      _isOnline = false;
      _currentLocation = null;
    });
    }

    void _showError(String msg){
      if(!mounted) return;
      setState(() => _loadingLocation = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
      );
    }

   /* void _openFilter(){
      showModalBottomSheet(context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) )
    }*/

  @override
  Widget build(BuildContext context){
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,

        /*actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: AppColors.textPrimary),
            onPressed: //todo
            //tooltip: 'Filter',
          ),
        ],*/
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
       // body: _isOnline ? _buildOnlineView() : _buildOfflineView(),
    );
  }

  Widget _buildOfflineView(){
    return Column(
      children: [
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.slaterspwn
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(onPressed: _loadingLocation ? null : _goOnline,

                icon: _loadingLocation ?
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textPrimary))
                  : const Icon (Icons.power_settings_new,
                  size: 20, color: AppColors.textPrimary),

                label: Text(
                _loadingLocation ? 'Getting location...' :
                'Go Online',
                style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary),
                ),

              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.yellowrspwn,
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              ),
            ),
          ),

        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: AppColors.slaterspwn.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(10),
                ),
              child: Text('You are currently offline.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
              ),
            ),
        ),

      ],
    );
  }
}


