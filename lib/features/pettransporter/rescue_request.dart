import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';

class RescueRequest extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;

  const RescueRequest({
    super.key,
    required this.caseId,
    required this.data,
  });

  @override
  State<RescueRequest> createState() =>
      _RescueRequestState();
}

class _RescueRequestState extends State<RescueRequest> {
  bool _isAccepting = false;

  Future<void> _startNow() async {
    setState(() => _isAccepting = true);

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final userData = userDoc.data();
      final riderName =
      '${userData?['firstName'] ?? ''} ${userData?['lastName'] ?? ''}'
          .trim();

      await FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .update({
        'status': 'accepted',
        'assignedVolunteerId': uid,
        'assignedVolunteerName':
        riderName.isEmpty ? (widget.data['assignedVolunteerName'] ?? '') : riderName,
        'statusHistory': FieldValue.arrayUnion([
          {
            'status': 'Rider accepted the rescue request.',
            'timestamp': Timestamp.now(),
          }
        ]),
      });

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TransitProgressPage(caseId: widget.caseId),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to accept request: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final urgency = d['urgency'] ?? '';
    final address = d['address'] ?? '';
    final dropoffAddress = d['dropoffAddress'] ?? address;
    final condition = d['condition'] ?? '';
    final animalType = d['animalType'] ?? '';
    final photoUrls = List<String>.from(d['photoUrls'] ?? []);
    final alreadyAccepted = d['status'] == 'accepted' || d['status'] == 'ongoing';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // Header banner
          Container(
            width: double.infinity,
            color: AppColors.textPrimary,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 12,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.arrow_back,
                          color: AppColors.background),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Rescue Now',
                        style: GoogleFonts.tiltWarp(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.background,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Text(
                    '~4KM from you',
                    style: GoogleFonts.zain(
                      fontSize: 12,
                      color: AppColors.background.withOpacity(0.8),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 36),
                  child: Row(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_shipping_outlined,
                              size: 16, color: AppColors.background),
                          const SizedBox(width: 6),
                          Text('Transport',
                              style: GoogleFonts.zain(
                                  fontSize: 13, color: AppColors.background)),
                        ],
                      ),
                      const SizedBox(width: 12),
                      if (urgency.toString().isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: urgency == 'Critical'
                                ? Colors.red
                                : AppColors.yellowrspwn,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            urgency,
                            style: GoogleFonts.zain(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.circle_outlined,
                          size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(address,
                            style: GoogleFonts.zain(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on,
                          size: 14, color: AppColors.textPrimary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(dropoffAddress,
                            style: GoogleFonts.zain(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  Text('Case Media',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 10),

                  photoUrls.isEmpty
                      ? Row(
                    children: List.generate(
                      2,
                          (i) => Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: AppColors.textPrimary, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.image_outlined,
                              color: AppColors.slaterspwn),
                        ),
                      ),
                    ),
                  )
                      : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: photoUrls.map((url) {
                      return GestureDetector(
                        onTap: () => _showFullImage(context, url),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            url,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, _, __) => Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: AppColors.slaterspwn,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                  Icons.broken_image_outlined,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),

                  Text('Type of Animal',
                      style: GoogleFonts.zain(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(animalType,
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textPrimary)),

                  const SizedBox(height: 16),

                  if (condition.toString().isNotEmpty)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.message_outlined,
                            size: 16, color: AppColors.textPrimary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Found in $condition',
                            style: GoogleFonts.zain(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),

          // Start now / already accepted footer
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: alreadyAccepted || _isAccepting ? null : _startNow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.yellowrspwn,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                  elevation: 0,
                ),
                child: _isAccepting
                    ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: AppColors.textPrimary),
                )
                    : Text(
                  alreadyAccepted ? 'Already Accepted' : 'Start now',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 16, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(6),
                  child: const Icon(Icons.close,
                      color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}