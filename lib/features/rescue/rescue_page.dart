import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
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
//import 'package:firebase_storage/firebase_storage.dart';

const String _mapsApiKey = 'AIzaSyAzqeI6uyCZW5VHQTeOyWqLdku6n-rzjTQ';

//Media
class _MediaItem {
  final XFile file;
  final bool isVideo;

  _MediaItem({
    required this.file, required this.isVideo
  });
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

  String? _selectedUrgency;
  String? _coordinateChoice;
  String? _adoptionChoice;
  String? _selectedAnimalType;
  bool _isLoading = false;

  final List<_MediaItem?> _mediaFiles = [null, null, null, null];
  final ImagePicker _picker = ImagePicker();
  final List<double?> _uploadProgress = [null, null, null, null];

  // Google Maps
  GoogleMapController? _mapController;
  LatLng _pinnedLocation = const LatLng(14.5995, 120.9842); // default: Manila
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
    super.dispose();
  }

  //Geolocation
  Future<void> _fetchCurrentLocation() async {
    setState(() => _loadingLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _setError('Location services are disabled.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _setError('Location permission denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final latLng = LatLng(pos.latitude, pos.longitude);
      await _updatePin(latLng);
    } catch (e) {
      _setError('Could not get location.');
    }
  }

  void _setError(String msg) {
    setState(() {
      _loadingLocation = false;
      _pinnedAddress = msg;
    });
  }

  // Reverse-geocode from LatLng to address --- still not working
  Future<void> _updatePin(LatLng pos) async {
    setState(() {
      _pinnedLocation = pos;
      _pinnedAddress = 'Resolving address…';
    });

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: pos, zoom: 17),
      ),
    );

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?latlng=${pos.latitude},${pos.longitude}'
            '&key=$_mapsApiKey',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final address =
              data['results'][0]['formatted_address'] as String? ?? '';
          setState(() => _pinnedAddress = address);
        } else {
          setState(() => _pinnedAddress =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
        }
      }
    } catch (_) {
      setState(() => _pinnedAddress =
      '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}');
    } finally {
      setState(() => _loadingLocation = false);
    }
  }

  // Forward-geocode a typed address to LatLng
  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;

    FocusManager.instance.primaryFocus?.unfocus();

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(address)}'
            '&key=$_mapsApiKey',
      );

      final res = await http.get(url);
      final data = jsonDecode(res.body);

      if (res.statusCode == 200) {
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          final loc = data['results'][0]['geometry']['location'];
          final latLng = LatLng(
              (loc['lat'] as num).toDouble(),
              (loc['lng'] as num).toDouble(),);

          _addressController.text = data['results'][0]['formatted_address'];

          await _updatePin(latLng);
        }
      }
    } catch (_) {}
  }

  //Media picker
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
                  title: Text('Choose photo from gallery',
                      style: GoogleFonts.zain(
                          fontSize: 15, color: AppColors.textPrimary)),
                  onTap: () => Navigator.pop(context, 'photo_gallery'),
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

    XFile? file;
    bool isVideo = false;

    switch (action) {
      case 'photo_camera':
        file = await _picker.pickImage(
            source: ImageSource.camera, imageQuality: 80, maxWidth: 1280);
        break;
      case 'photo_gallery':
        file = await _picker.pickImage(
            source: ImageSource.gallery, imageQuality: 80, maxWidth: 1280);
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

  // Firebase Storage upload, uploads media slots to firebase storage
  /*Future<List<String>> _uploadAllMedia(String caseId) async {
    final urls = <String>[];

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
      urls.add(url);

      if (mounted) setState(() => _uploadProgress[i] = null);
    }

    return urls;
  }*/

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
        builder: (_) => const _QRScannerPage(),
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

  void _handleScanResult(String result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tag scanned: $result'),
        backgroundColor: Colors.green,
      ),
    );
  }

//build
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Report a Stray',
          style: Theme.of(context).textTheme.displaySmall,
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
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const NotificationsScreen()),
            );
          }
          else if (index == 2) {
            Navigator.pushReplacement(
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
                    onMapCreated: (ctrl) => _mapController = ctrl,
                    initialCameraPosition: CameraPosition(
                      target: _pinnedLocation,
                      zoom: 15,
                    ),
                    onTap: _updatePin,
                    markers: {
                      Marker(
                        markerId: const MarkerId('rescue_pin'),
                        position: _pinnedLocation,
                        infoWindow: const InfoWindow(title: 'Rescue Location'),
                      ),
                    },
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
                  // Type of Animal
                  _buildLabel('Type of Animal', required: true),
                  const SizedBox(height: 8),
                  _buildCheckboxOption2('Dog', _selectedAnimalType,
                          (val) => setState(() => _selectedAnimalType = val)),
                  _buildCheckboxOption2('Cat', _selectedAnimalType,
                          (val) => setState(() => _selectedAnimalType = val)),

                  const SizedBox(height: 20),

                  // Select Urgency
                  _buildLabel('Select Urgency', required: true),
                  const SizedBox(height: 8),
                  _buildCheckboxOption('Low'),
                  _buildCheckboxOption('Medium'),
                  _buildCheckboxOption('Critical'),

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
                      Text(
                        'No, but I can refer you to witnesses who can assist.',
                        style: GoogleFonts.zain(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  if (_coordinateChoice == 'no') ...[
                    const SizedBox(height: 6),
                    TextField(
                      controller: _witnessNameController,
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
                    const SizedBox(height: 6),
                    TextField(
                      controller: _witnessNumberController,
                      keyboardType: TextInputType.phone,
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
                          onChanged: (val) =>
                              setState(() => _adoptionChoice = 'no'),
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
                  onPressed: _isLoading ? null : _handleSubmit,
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
        Text(
          text,
          style: GoogleFonts.zain(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.textPrimary,
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
            Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 14,
                color: AppColors.textPrimary,
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
            Text(label,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final condition = _conditionController.text.trim();
    final filledCount = _mediaFiles.where((f) => f != null).length;

    if (condition.isEmpty ||
        _selectedUrgency == null ||
        _selectedAnimalType == null ||
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

      final docRef = await FirebaseFirestore.instance.collection('cases').add({
        'reporterId': uid,
        'reporterName':
        '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
            .trim(),
        'reporterPhone': userData?['phone'] ?? '',
        'animalType': _selectedAnimalType,
        'condition': condition,
        'urgency': _selectedUrgency,
        'address': _addressController.text.trim(),
        'coordinateWithShelter': _coordinateChoice,
        'witnessName': _witnessNameController.text.trim(),
        'witnessPhone': _witnessNumberController.text.trim(),
        'interestedToAdopt': _adoptionChoice,
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

     /* final photoUrls = await _uploadAllMedia(docRef.id);
      if(photoUrls.isNotEmpty){
        await docRef.update({
          'photoUrls':photoUrls
        });
      }*/

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TrackCasePage(caseId: docRef.id),
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

class _QRScannerPage extends StatefulWidget {
  const _QRScannerPage();

  @override
  State<_QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<_QRScannerPage> {
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
