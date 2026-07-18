import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';

class AdminTrackCasePage extends StatefulWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const AdminTrackCasePage(
      {super.key, required this.caseId, required this.data});

  @override
  State<AdminTrackCasePage> createState() => _AdminTrackCasePageState();
}

class _AdminTrackCasePageState extends State<AdminTrackCasePage> {
  int _tabIndex = 0;
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .collection('messages')
        .add({
      'senderId': 'admin',
      'senderName': 'Loved by the Gapz',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _messageController.clear();
  }

  Future<void> _markInTreatment() async {
    await FirebaseFirestore.instance
        .collection('cases')
        .doc(widget.caseId)
        .update({
      'status': 'in_treatment',
      'dateAdmitted': Timestamp.now(),
      'statusHistory': FieldValue.arrayUnion([
        {
          'status':
          'The animal has reached the clinic. Animal is now in treatment.',
          'timestamp': Timestamp.now(),
        }
      ]),
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.hasData
            ? (snapshot.data!.data() as Map<String, dynamic>? ?? widget.data)
            : widget.data;
        final statusHistory = List<Map<String, dynamic>>.from(
            data['statusHistory'] ?? []);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.textPrimary,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.background),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Track Case',
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
              // Map placeholder
              Container(
                height: 180,
                color: AppColors.slaterspwn,
                child: Center(
                  child: Text('Live route map',
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
              ),

              // Bottom panel
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 12),

                      // Tab switcher
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          children: [
                            _AdminTabButton(
                              label: 'Tracking Detail',
                              selected: _tabIndex == 0,
                              onTap: () => setState(() => _tabIndex = 0),
                            ),
                            _AdminTabButton(
                              label: 'Case Detail',
                              selected: _tabIndex == 1,
                              onTap: () => setState(() => _tabIndex = 1),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '#${widget.caseId.substring(0, 7).toUpperCase()}',
                            style: GoogleFonts.tiltWarp(
                                fontSize: 18, color: AppColors.textPrimary),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: _tabIndex == 0
                            ? _AdminTrackingTab(
                          statusHistory: statusHistory,
                          caseId: widget.caseId,
                          messageController: _messageController,
                          onSend: _sendMessage,
                          onMarkInTreatment: _markInTreatment,
                        )
                            : _AdminCaseDetailTab(data: data),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AdminTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AdminTabButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.textPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(label,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? AppColors.background
                        : AppColors.textPrimary)),
          ),
        ),
      ),
    );
  }
}

class _AdminTrackingTab extends StatelessWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final VoidCallback onSend;
  final VoidCallback onMarkInTreatment;

  const _AdminTrackingTab({
    required this.statusHistory,
    required this.caseId,
    required this.messageController,
    required this.onSend,
    required this.onMarkInTreatment,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Status timeline
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: statusHistory.length,
            itemBuilder: (context, index) {
              final item = statusHistory[index];
              final isLast = index == statusHistory.length - 1;
              final ts = item['timestamp'] as Timestamp?;
              final timeStr = ts != null
                  ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
                  : '';
              final dateStr = ts != null
                  ? 'February ${ts.toDate().day}, ${ts.toDate().year}'
                  : '';

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 20, height: 20,
                        decoration: BoxDecoration(
                          color: isLast
                              ? AppColors.textPrimary
                              : AppColors.slaterspwn,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.textPrimary, width: 2),
                        ),
                        child: isLast
                            ? const Icon(Icons.check,
                            size: 12, color: Colors.white)
                            : null,
                      ),
                      if (index < statusHistory.length - 1)
                        Container(
                            width: 2, height: 40,
                            color: AppColors.textPrimary),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(item['status'] ?? '',
                                style: GoogleFonts.zain(
                                    fontSize: 13,
                                    color: AppColors.textPrimary)),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(timeStr,
                                  style: GoogleFonts.zain(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                              Text(dateStr,
                                  style: GoogleFonts.zain(
                                      fontSize: 11,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        /* todo for manual testing
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Demo Controls',
                  style: GoogleFonts.zain(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                children: [
                  _DemoButton(
                    label: 'Transporter Accepted',
                    caseId: caseId,
                    status: 'Pet Transporter has been assigned, in transit to pick up location.',
                  ),
                  _DemoButton(
                    label: 'Reached Animal',
                    caseId: caseId,
                    status: 'Pet Transporter has reached the animal.',
                  ),
                ],
              ),
            ],
          ),
        ),
        */

        const Divider(),

        // Messages
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Messages',
                style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ),

        SizedBox(
          height: 80,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('cases')
                .doc(caseId)
                .collection('messages')
                .orderBy('timestamp')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return Center(
                  child: Text('No messages yet.',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: snap.data!.docs.length,
                itemBuilder: (context, i) {
                  final msg =
                  snap.data!.docs[i].data() as Map<String, dynamic>;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: AppColors.slaterspwn,
                          child: Text((msg['senderName'] ?? 'U')[0],
                              style: GoogleFonts.zain(fontSize: 10)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${msg['senderName']}: ${msg['text']}',
                            style: GoogleFonts.zain(
                                fontSize: 12, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),

        // Message input
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: messageController,
                  decoration: InputDecoration(
                    hintText: 'Type a message',
                    hintStyle: GoogleFonts.zain(
                        fontSize: 13, color: AppColors.textSecondary),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide:
                      const BorderSide(color: AppColors.slaterspwn),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(50),
                      borderSide: const BorderSide(
                          color: AppColors.textPrimary),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onSend,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: AppColors.yellowrspwn,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.send,
                      size: 18, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),

        // Mark in treatment button
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ElevatedButton(
            onPressed: onMarkInTreatment,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.yellowrspwn,
              minimumSize: const Size(double.infinity, 48),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30)),
            ),
            child: Text('Mark In Treatment',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}

class _AdminCaseDetailTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _AdminCaseDetailTab({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row('Reporter Name', data['reporterName']),
          _Row('Reporter Mobile Number', data['reporterPhone']),
          _Row('Pet Transporter Name', data['assignedVolunteerName']),
          _Row('Pet Transporter Mobile Number', '-'),
          _Row('Address', data['address']),
          _Row('Description', data['condition']),
          _Row('Type of Animal', data['animalType']),
          _Row('Urgency', data['urgency']),
          _Row('Coordination', data['coordinateWithShelter']),
          if (data['coordinateWithShelter'] == 'no') ...[
            _Row('Witness Name', data['witnessName']),
            _Row('Witness Mobile Number', data['witnessPhone']),
          ],
          _Row('Interest to adopt', data['interestedToAdopt']),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String? value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          Text(value ?? '-',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/* TODO: demo button
class _DemoButton extends StatelessWidget {
  final String label;
  final String caseId;
  final String status;
  const _DemoButton({required this.label, required this.caseId, required this.status});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () async {
        await FirebaseFirestore.instance
            .collection('cases')
            .doc(caseId)
            .update({
          'statusHistory': FieldValue.arrayUnion([
            {'status': status, 'timestamp': Timestamp.now()}
          ]),
        });
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        side: const BorderSide(color: AppColors.slaterspwn),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label,
          style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
    );
  }
}
*/
