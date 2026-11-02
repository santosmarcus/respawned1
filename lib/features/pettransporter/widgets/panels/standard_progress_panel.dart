// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_swipe_button.dart';
import 'package:respawnd1/features/pettransporter/widgets/transit_info_widgets.dart';

/// "Ongoing Request" panel for the accepted / ongoing / treatment legs:
/// pickup + clinic addresses, contact rows, and the swipe action for the
/// current [status].
class StandardProgressPanel extends StatelessWidget {
  const StandardProgressPanel({
    super.key,
    required this.status,
    required this.pickupAddress,
    required this.clinicAddress,
    required this.contactRows,
    required this.isBusy,
    required this.onStartTrip,
    required this.onMarkArrived,
    required this.onArriveAtClinic,
  });

  final String status;
  final String pickupAddress;

  /// The assigned clinic's address, or '' when none is assigned yet.
  final String clinicAddress;
  final List<Widget> contactRows;

  /// True while an action or arrival verification is in flight (swipe locked).
  final bool isBusy;
  final VoidCallback onStartTrip;
  final VoidCallback onMarkArrived;
  final VoidCallback onArriveAtClinic;
  Widget _buildSwipeButton() {
    String label;
    VoidCallback? onSwipe;

    switch (status) {
      case 'assigned':
      case 'accepted':
        label = 'On the way to pick up location';
        onSwipe = onStartTrip;
        break;
      case 'ongoing':
        label = 'Arrived at pick up location';
        onSwipe = onMarkArrived;
        break;
      case 'treatment':
        label = 'On the way to Treatment';
        onSwipe = onArriveAtClinic;
        break;
      default:
        label = 'Processing…';
        onSwipe = null;
    }

    return TransitSwipeButton(label: label, onSwiped: isBusy ? null : onSwipe);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 16),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Ongoing Request',
                  style: GoogleFonts.tiltWarp(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Address card
            TransitAddressCard(
              pickup: pickupAddress,
              dropoff: clinicAddress.isEmpty
                  ? 'Clinic not yet assigned'
                  : clinicAddress,
            ),

            const SizedBox(height: 12),

            // Reporter/witness and organization contact rows
            ...contactRows,

            const SizedBox(height: 8),

            // Swipe button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _buildSwipeButton(),
            ),
          ],
        ),
      ),
    );
  }
}
