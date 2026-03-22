
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../app_theme.dart';


class ServiceFilterSheet extends StatefulWidget {
  final double initialRange;
  final ValueChanged<double> onApply;

  const ServiceFilterSheet({
    required this.initialRange,
    required this.onApply,
  });

  @override
  State<ServiceFilterSheet> createState() =>
      _ServiceFilterSheetState();
}

class _ServiceFilterSheetState
    extends State<ServiceFilterSheet> {
  late double _range;

  @override
  void initState() {
    super.initState();
    _range = widget.initialRange;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F0DC),
        borderRadius:
        BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4)),
            ),
          ),
          const SizedBox(height: 16),

          // Back arrow + Title
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: const Icon(Icons.chevron_left, size: 28),
              ),
              const SizedBox(width: 4),
              Text(
                'Filter Service Availability',
                style: GoogleFonts.tiltWarp(
                    fontSize: 18,
                    color: AppColors.textPrimary),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Service Range label + value
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Service Range',
                  style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              Text('${_range.toInt()} KM radius',
                  style: GoogleFonts.nunito(
                      fontSize: 14,
                      color: AppColors.textPrimary)),
            ],
          ),

          const SizedBox(height: 12),

          // Map preview placeholder
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: AppColors.slaterspwn,
              borderRadius: BorderRadius.circular(16),
            ),
          ),

          const SizedBox(height: 16),

          // Range slider
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: AppColors.textPrimary,
              inactiveTrackColor: AppColors.slaterspwn,
              thumbColor: AppColors.textPrimary,
              overlayColor:
              AppColors.textPrimary.withOpacity(0.12),
              trackHeight: 3,
            ),
            child: Slider(
              value: _range,
              min: 1,
              max: 200,
              divisions: 199,
              onChanged: (v) => setState(() => _range = v),
            ),
          ),

          const SizedBox(height: 12),

          // Apply button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: () {
                widget.onApply(_range);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF5C842),
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: Text('Apply',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16,
                      color: AppColors.textPrimary)),
            ),
          ),
        ],
      ),
    );
  }
}