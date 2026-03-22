import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';

class AssignRiderPage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const AssignRiderPage(
      {super.key, required this.caseId, required this.data});

  @override
  State<AssignRiderPage> createState() => _AssignRiderPageState();
}

class _AssignRiderPageState extends State<AssignRiderPage> {
  String _sortBy = 'Distance';
  String? _pendingVolunteerId;

  final List<String> _sortOptions = ['Distance', 'In-House', 'Volunteer'];

  // Hardcoded riders for demo — replace with Firestore query when GPS available
  final List<Map<String, dynamic>> _hardcodedRiders = [
    {
      'uid': 'rider1',
      'name': 'David Ramos',
      'type': 'In-house',
      'distance': 1.9,
      'plateNumber': 'ABC 123',
      'vehicle': 'Yamaha NMAX',
      'available': true,
    },
    {
      'uid': 'rider2',
      'name': 'Jhon Diaz',
      'type': 'Volunteer',
      'distance': 0.9,
      'plateNumber': 'ZXC 321',
      'vehicle': 'Honda Click',
      'available': true,
    },
    {
      'uid': 'rider3',
      'name': 'Maria Santos',
      'type': 'Volunteer',
      'distance': 2.3,
      'plateNumber': 'DEF 456',
      'vehicle': 'Honda Beat',
      'available': true,
    },
  ];

  List<Map<String, dynamic>> get _sortedRiders {
    final list = List<Map<String, dynamic>>.from(_hardcodedRiders);
    switch (_sortBy) {
      case 'Distance':
        list.sort((a, b) =>
            (a['distance'] as double).compareTo(b['distance'] as double));
        break;
      case 'In-House':
        list.sort((a, b) {
          if (a['type'] == 'In-house' && b['type'] != 'In-house') return -1;
          if (a['type'] != 'In-house' && b['type'] == 'In-house') return 1;
          return (a['distance'] as double)
              .compareTo(b['distance'] as double);
        });
        break;
      case 'Volunteer':
        list.sort((a, b) {
          if (a['type'] == 'Volunteer' && b['type'] != 'Volunteer') return -1;
          if (a['type'] != 'Volunteer' && b['type'] == 'Volunteer') return 1;
          return (a['distance'] as double)
              .compareTo(b['distance'] as double);
        });
        break;
    }
    return list;
  }

  Future<void> _assignRider(Map<String, dynamic> rider) async {
    setState(() => _pendingVolunteerId = rider['uid']);

    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'assigned',
      'assignedVolunteerId': rider['uid'],
      'assignedVolunteerName': rider['name'],
      'assignedVehicle': rider['vehicle'],
      'assignedPlate': rider['plateNumber'],
      'statusHistory': FieldValue.arrayUnion([
        {
          'status': 'Searching for Pet Transporter...',
          'timestamp': Timestamp.now(),
        }
      ]),
    });

    // Show confirmation
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${rider['name']} has been assigned.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final urgency = d['urgency'] ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Assign Rider',
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
        children: [
          // Case header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d['animalType'] ?? 'Animal',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 22, color: AppColors.textPrimary)),
                    Text(
                        'CASE ID: ${widget.caseId.substring(0, 5).toUpperCase()}',
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: urgency == 'Critical'
                        ? Colors.red
                        : AppColors.yellowrspwn,
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
          ),

          // Map placeholder with dots for riders
          Container(
            height: 180,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.slaterspwn,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              children: [
                // Rescue location dot (dark)
                const Positioned(
                  top: 90, left: 140,
                  child: CircleAvatar(radius: 8, backgroundColor: AppColors.textPrimary),
                ),
                // Rider dots (yellow/olive)
                Positioned(
                  top: 50, left: 220,
                  child: CircleAvatar(
                      radius: 8, backgroundColor: AppColors.yellowrspwn),
                ),
                Positioned(
                  top: 110, left: 80,
                  child: CircleAvatar(
                      radius: 8, backgroundColor: AppColors.greenrspwn),
                ),
                Center(
                  child: Text('Map — riders shown as dots',
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Available Riders header + sort
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Available Riders',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 16, color: AppColors.textPrimary)),
                GestureDetector(
                  onTap: _showSortSheet,
                  child: const Icon(Icons.sort,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Rider list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _sortedRiders.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final rider = _sortedRiders[index];
                final isPending = _pendingVolunteerId == rider['uid'];
                return _RiderCard(
                  rider: rider,
                  isPending: isPending,
                  onAssign: () => _assignRider(rider),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showSortSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sort by',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            ..._sortOptions.map((opt) => ListTile(
              title: Text(opt,
                  style: GoogleFonts.zain(
                      fontSize: 15, color: AppColors.textPrimary)),
              trailing: _sortBy == opt
                  ? const Icon(Icons.check, color: AppColors.greenrspwn)
                  : null,
              onTap: () {
                setState(() => _sortBy = opt);
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  final Map<String, dynamic> rider;
  final bool isPending;
  final VoidCallback onAssign;

  const _RiderCard({
    required this.rider,
    required this.isPending,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final isInHouse = rider['type'] == 'In-house';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.tearspwn,
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(rider['name'],
                        style: GoogleFonts.zain(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isInHouse
                            ? AppColors.yellowrspwn
                            : AppColors.greenrspwn,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(rider['type'],
                          style: GoogleFonts.zain(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary)),
                    ),
                  ],
                ),
                Text('${rider['distance']} km',
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary)),
                Text('${rider['plateNumber']}  ${rider['vehicle']}',
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),

          Column(
            children: [
              // Message + call
              Row(
                children: [
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.chat_outlined,
                          size: 20, color: AppColors.textPrimary),
                    ),
                  ),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      child: const Icon(Icons.phone_outlined,
                          size: 20, color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Assign button
              ElevatedButton(
                onPressed: isPending ? null : onAssign,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isPending
                      ? AppColors.slaterspwn
                      : AppColors.yellowrspwn,
                  elevation: 0,
                  minimumSize: const Size(80, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                ),
                child: Text(
                  isPending ? 'Pending' : 'Assign',
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isPending
                          ? AppColors.textSecondary
                          : AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}