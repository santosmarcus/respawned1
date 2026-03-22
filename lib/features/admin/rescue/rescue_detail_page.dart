import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'assign_rider_page.dart';

class RescueDetailPage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const RescueDetailPage({super.key, required this.caseId, required this.data});

  @override
  State<RescueDetailPage> createState() => _RescueDetailPageState();
}

class _RescueDetailPageState extends State<RescueDetailPage> {
  bool _isLoading = false;
  String? _rejectionReason;
  String? _otherReason;
  final _otherController = TextEditingController();

  final List<String> _rejectionReasons = [
    'No available riders',
    'Not an emergency',
    'Invalid / fake report',
    'Animal already rescued',
    'Other:',
  ];

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  Future<void> _acceptCase() async {
    setState(() => _isLoading = true);
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'accepted',
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Rescue case has been accepted.', 'timestamp': Timestamp.now()}
      ]),
    });
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => AssignRiderPage(
              caseId: widget.caseId, data: widget.data)));
    }
  }

  Future<void> _rejectCase(String reason) async {
    setState(() => _isLoading = true);
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'rejected',
      'rejectionReason': reason,
      'statusHistory': FieldValue.arrayUnion([
        {'status': 'Case rejected: $reason', 'timestamp': Timestamp.now()}
      ]),
    });
    if (mounted) Navigator.pop(context);
  }

  void _showRejectionSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Text('Rejection Reason',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 18, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 16),
              ..._rejectionReasons.map((reason) {
                final isOther = reason == 'Other:';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 20, height: 20,
                          child: Checkbox(
                            value: _rejectionReason == reason,
                            onChanged: (_) =>
                                setSheetState(() => _rejectionReason = reason),
                            activeColor: AppColors.textPrimary,
                            side: const BorderSide(
                                color: AppColors.textPrimary, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(2)),
                            materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (isOther) ...[
                          Text('Other: ',
                              style: GoogleFonts.zain(
                                  fontSize: 14, color: AppColors.textPrimary)),
                          Expanded(
                            child: TextField(
                              controller: _otherController,
                              style: GoogleFonts.zain(fontSize: 14),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding:
                                EdgeInsets.only(bottom: 4),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.textPrimary),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.textPrimary, width: 2),
                                ),
                              ),
                            ),
                          ),
                        ] else
                          Text(reason,
                              style: GoogleFonts.zain(
                                  fontSize: 14, color: AppColors.textPrimary)),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                );
              }),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _rejectionReason == null
                      ? null
                      : () {
                    final reason = _rejectionReason == 'Other:'
                        ? _otherController.text.trim()
                        : _rejectionReason!;
                    Navigator.pop(context);
                    _rejectCase(reason);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: Text('Confirm Rejection',
                      style: GoogleFonts.tiltWarp(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final photoUrls = List<String>.from(d['photoUrls'] ?? []);
    final urgency = d['urgency'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Rescue Details',
            style: GoogleFonts.tiltWarp(
                fontSize: 18, color: AppColors.background)),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined,
                color: AppColors.background),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Animal type + urgency
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(d['animalType'] ?? 'Animal',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: urgency == 'Critical' ? Colors.red : AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(urgency,
                      style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                ),
              ],
            ),
            Text('CASE ID: ${widget.caseId.substring(0, 5).toUpperCase()}',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary)),

            const SizedBox(height: 16),

            // Photo carousel
            if (photoUrls.isNotEmpty)
              _PhotoCarousel(photoUrls: photoUrls)
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: AppColors.tearspwn,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 48, color: AppColors.textSecondary),
                ),
              ),

            const SizedBox(height: 16),

            // Description
            _DetailSection(
              label: 'Description',
              trailing: _formatDateTime(d['createdAt'] as Timestamp?),
              value: d['condition'] ?? '-',
            ),

            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: _DetailSection(
                      label: 'Interest to adopt',
                      value: d['interestedToAdopt'] == 'yes' ? 'Yes' : 'No'),
                ),
                Expanded(
                  child: _DetailSection(
                      label: 'QR/NFC',
                      value: 'No'), // placeholder
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Location map placeholder
            _DetailSection(label: 'Location', value: ''),
            Container(
              height: 160,
              decoration: BoxDecoration(
                color: AppColors.slaterspwn,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.location_on_outlined,
                    size: 40, color: AppColors.textSecondary),
              ),
            ),

            const SizedBox(height: 16),

            // Message input
            TextField(
              decoration: InputDecoration(
                hintText: 'Type a message',
                hintStyle:
                GoogleFonts.zain(color: AppColors.textSecondary),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Reporter info
            Text('Reported by: ${d['reporterName'] ?? '-'}',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary)),

            const SizedBox(height: 24),

            // Reject + Accept buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : _showRejectionSheet,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Reject',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 15, color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _acceptCase,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.textPrimary))
                        : Text('Accept',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 15,
                            color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(Timestamp? ts) {
    if (ts == null) return '';
    final d = ts.toDate();
    final h = d.hour > 12 ? d.hour - 12 : d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm, March ${d.day}, ${d.year}';
  }
}

class _PhotoCarousel extends StatefulWidget {
  final List<String> photoUrls;
  const _PhotoCarousel({required this.photoUrls});

  @override
  State<_PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<_PhotoCarousel> {
  int _current = 0;
  final PageController _ctrl = PageController();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          height: 220,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.photoUrls.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                widget.photoUrls[i],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.tearspwn,
                  child: const Icon(Icons.broken_image,
                      size: 48, color: AppColors.textSecondary),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: 10, right: 14,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_current + 1}/${widget.photoUrls.length}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String label;
  final String value;
  final String? trailing;
  const _DetailSection(
      {required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (trailing != null)
                Text(trailing!,
                    style: GoogleFonts.zain(
                        fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
          if (value.isNotEmpty)
            Text(value,
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}