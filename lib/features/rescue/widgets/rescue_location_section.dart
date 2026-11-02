// Extracted from rescue_page.dart (behavior-preserving refactor).
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/rescue/widgets/rescue_form_fields.dart';

/// Map (tap to pin), locate-me button, address search bar and the pinned
/// address readout at the top of the Report a Stray form. Stateless — the
/// page owns the location state and the geocoding calls.
class RescueLocationSection extends StatelessWidget {
  const RescueLocationSection({
    super.key,
    required this.pinnedLocation,
    required this.hasResolvedLocation,
    required this.pinnedAddress,
    required this.loadingLocation,
    required this.addressController,
    required this.onMapCreated,
    required this.onMapTap,
    required this.onLocateMe,
    required this.onSearch,
  });

  final LatLng pinnedLocation;
  final bool hasResolvedLocation;
  final String pinnedAddress;
  final bool loadingLocation;
  final TextEditingController addressController;
  final ValueChanged<GoogleMapController> onMapCreated;
  final ValueChanged<LatLng> onMapTap;
  final VoidCallback onLocateMe;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
                onMapCreated: onMapCreated,
                initialCameraPosition: CameraPosition(
                  target: pinnedLocation,
                  zoom: 15,
                ),
                onTap: onMapTap,
                markers: hasResolvedLocation
                    ? {
                        Marker(
                          markerId: const MarkerId('rescue_pin'),
                          position: pinnedLocation,
                          infoWindow: const InfoWindow(
                            title: 'Rescue Location',
                          ),
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
                onTap: onLocateMe,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: loadingLocation
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary,
                          ),
                        )
                      : const Icon(
                          Icons.my_location,
                          size: 20,
                          color: AppColors.textPrimary,
                        ),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Row(
              children: [
                const Icon(
                  Icons.search,
                  size: 20,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: addressController,
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
                    onSubmitted: onSearch,
                  ),
                ),
                GestureDetector(
                  onTap: () => onSearch(addressController.text),
                  child: const Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppColors.textPrimary,
                  ),
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
              RescueFieldLabel('Pinned location', required: true),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.textPrimary, width: 1),
                  ),
                ),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: loadingLocation
                          ? const LinearProgressIndicator(
                              minHeight: 2,
                              color: AppColors.greenrspwn,
                              backgroundColor: AppColors.slaterspwn,
                            )
                          : Text(
                              pinnedAddress,
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
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
