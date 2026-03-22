import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/rescue/rescue_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/assign_rider_page.dart';
import 'package:respawnd1/features/admin/rescue/admin_track_case_page.dart';
import 'package:respawnd1/features/admin/rescue/treatment_detail_page.dart';
import 'package:respawnd1/features/admin/rescue/intake_detail_page.dart';

class RescueReportsPage extends StatefulWidget {
  const RescueReportsPage({super.key});

  @override
  State<RescueReportsPage> createState() => _RescueReportsPageState();
}

class _RescueReportsPageState extends State<RescueReportsPage> {
  String _currentFilter = 'Review';

  final List<Map<String, dynamic>> _filters = [
    {'label': 'Review', 'icon': Icons.rate_review_outlined, 'badge': 2},
    {'label': 'Assign', 'icon': Icons.assignment_ind_outlined, 'badge': 0},
    {'label': 'Ongoing', 'icon': Icons.local_shipping_outlined, 'badge': 0},
    {'label': 'In Treatment', 'icon': Icons.medical_services_outlined, 'badge': 1},
    {'label': 'Intake', 'icon': Icons.pets_outlined, 'badge': 0},
  ];

  String _filterToStatus(String filter) {
    switch (filter) {
      case 'Review': return 'pending';
      case 'Assign': return 'accepted';
      case 'Ongoing': return 'assigned';
      case 'In Treatment': return 'in_treatment';
      case 'Intake': return 'intake';
      default: return 'pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.menu, color: AppColors.background),
          onPressed: () {},
        ),
        title: Text('Rescue Reports',
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
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),

          // Rescue Process label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Rescue Process',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)),
          ),

          const SizedBox(height: 16),

          // Filter tabs
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _currentFilter == filter['label'];
                return GestureDetector(
                  onTap: () =>
                      setState(() => _currentFilter = filter['label']),
                  child: Column(
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.slaterspwn,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              filter['icon'] as IconData,
                              color: isSelected
                                  ? AppColors.background
                                  : AppColors.textSecondary,
                              size: 22,
                            ),
                          ),
                          if ((filter['badge'] as int) > 0)
                            Positioned(
                              top: -6,
                              right: -6,
                              child: Container(
                                width: 18,
                                height: 18,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${filter['badge']}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        filter['label'] as String,
                        style: GoogleFonts.zain(
                          fontSize: 11,
                          color: isSelected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 16),

          // Cases list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('cases')
                  .where('status',
                  isEqualTo: _filterToStatus(_currentFilter))
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text('No cases in this stage.',
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return _CaseCard(
                      caseId: doc.id,
                      data: data,
                      currentFilter: _currentFilter,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  final String currentFilter;

  const _CaseCard({
    required this.caseId,
    required this.data,
    required this.currentFilter,
  });

  Color _urgencyColor(String? urgency) {
    switch (urgency) {
      case 'Critical': return Colors.red;
      case 'Medium':   return AppColors.yellowrspwn;
      case 'Low':      return Colors.green;
      default:         return AppColors.slaterspwn;
    }
  }

  String _previewText() {
    switch (currentFilter) {
      case 'Review':
        return data['condition'] ?? '';
      case 'Assign':
        return 'Searching for Pet Transporter...';
      case 'Ongoing':
        final history = List<Map<String, dynamic>>.from(
            data['statusHistory'] ?? []);
        return history.isNotEmpty
            ? history.last['status'] ?? ''
            : 'In progress';
      case 'In Treatment':
        return 'The animal has reached the clinic. Animal is now in treatment.';
      case 'Intake':
        return 'Animal marked ready for Intake';
      default:
        return data['condition'] ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ts = data['createdAt'] as Timestamp?;
    final timeStr = ts != null
        ? '${ts.toDate().hour.toString().padLeft(2,'0')}:${ts.toDate().minute.toString().padLeft(2,'0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
        : '';
    final dateStr = ts != null
        ? 'March ${ts.toDate().day}, ${ts.toDate().year}'
        : '';

    return GestureDetector(
      onTap: () => _navigateToDetail(context),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: currentFilter == 'Review'
              ? Border.all(color: AppColors.textPrimary.withValues(alpha: 0.3), width: 1.5)
              : null,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Photo placeholder
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.tearspwn,
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Animal type + urgency
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(data['animalType'] ?? 'Animal',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 15, color: AppColors.textPrimary)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: _urgencyColor(data['urgency']),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(data['urgency'] ?? '',
                            style: GoogleFonts.zain(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Description preview
                  Text(
                    _previewText(),
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 6),

                  // Location + time
                  Text(data['address'] ?? '',
                      style: GoogleFonts.zain(
                          fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '$timeStr\n$dateStr',
                        style: GoogleFonts.zain(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                      Text('',style: GoogleFonts.zain(fontSize: 10)),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Reporter + case ID
                  Text('Reported by: ${data['reporterName'] ?? '-'}',
                      style: GoogleFonts.zain(
                          fontSize: 11, color: AppColors.textSecondary)),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                          'CASE ID: ${caseId.substring(0, 5).toUpperCase()}',
                          style: GoogleFonts.zain(
                              fontSize: 11, color: AppColors.textSecondary)),
                      ElevatedButton(
                        onPressed: () => _navigateToDetail(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.yellowrspwn,
                          elevation: 0,
                          minimumSize: const Size(90, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                        child: Text('View Details',
                            style: GoogleFonts.zain(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToDetail(BuildContext context) {
    switch (currentFilter) {
      case 'Review':
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => RescueDetailPage(caseId: caseId, data: data)));
        break;
      case 'Assign':
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => AssignRiderPage(caseId: caseId, data: data)));
        break;
      case 'Ongoing':
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => AdminTrackCasePage(caseId: caseId, data: data)));
        break;
      case 'In Treatment':
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => TreatmentDetailPage(caseId: caseId, data: data)));
        break;
      case 'Intake':
        Navigator.push(context, MaterialPageRoute(
            builder: (_) => IntakeDetailPage(caseId: caseId, data: data)));
        break;
    }
  }
}


