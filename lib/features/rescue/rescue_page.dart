import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:respawnd1/features/home/home_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const String _mapsApiKey = 'AIzaSyAzqeI6uyCZW5VHQTeOyWqLdku6n-rzjTQ';

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

  final List<dynamic> _mediaFiles = [null, null];


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

  // Reverse-geocode a LatLng → human-readable address via Geocoding API
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

  // Forward-geocode a typed address → LatLng
  Future<void> _geocodeAddress(String address) async {
    if (address.trim().isEmpty) return;
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
            '?address=${Uri.encodeComponent(address)}'
            '&key=$_mapsApiKey',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final loc = data['results'][0]['geometry']['location'];
          final latLng = LatLng(loc['lat'] as double, loc['lng'] as double);
          await _updatePin(latLng);
        }
      }
    } catch (_) {}
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

                // Locate-me FAB overlay
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
                  borderRadius: BorderRadius.circular(30),
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
                  Row(
                    children: [
                      _buildMediaBox(),
                      const SizedBox(width: 12),
                      _buildMediaBox(),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Scan NFC / QR
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onTap: () {},
                child: Text(
                  'Scan for NFC or QR',
                  style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    decoration: TextDecoration.underline,
                  ),
                ),
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
                    style: Theme.of(context).textTheme.displaySmall,
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

  Widget _buildMediaBox() {
    return GestureDetector(
      onTap: () {
        // TODO: open image picker
      },
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.textPrimary, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: Icon(Icons.add, size: 28, color: AppColors.textPrimary),
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

  /*void _handleSubmit() {
    final condition = _conditionController.text.trim();

    if (condition.isEmpty || _selectedUrgency == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all required fields.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report submitted successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  }*/

  Future<void> _handleSubmit() async {
    final condition = _conditionController.text.trim();

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

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data() as Map<String, dynamic>?;

      final docRef =
      await FirebaseFirestore.instance.collection('cases').add({
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
        'createdAt': FieldValue.serverTimestamp(),
      });

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