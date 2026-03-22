import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/features/generalhome/notifications_screen.dart';
import 'package:respawnd1/features/generalhome/user_profile.dart';
import '../../../app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/rescue/case_completed_page.dart';

class TrackCasePage extends StatefulWidget {
  final String caseId;
  const TrackCasePage({super.key, required this.caseId});

  @override
  State<TrackCasePage> createState() => _TrackCasePageState();
}

class _TrackCasePageState extends State<TrackCasePage> {
  int _tabIndex = 0; // 0 = Tracking Detail, 1 = Case Detail
  final _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String caseId) async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final name =
    '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
        .trim();

    await FirebaseFirestore.instance
        .collection('cases')
        .doc(caseId)
        .collection('messages')
        .add({
      'senderId': uid,
      'senderName': name,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(widget.caseId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        final data = snapshot.data!.data() as Map<String, dynamic>?;
        final status = data?['status'] ?? 'pending';
        final statusHistory = List<Map<String, dynamic>>.from(
            data?['statusHistory'] ?? []);

        // Navigate to completed page when case is done
        if (status == 'completed') {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => CaseCompletedPage(
                  caseId: widget.caseId,
                  caseData: data!,
                ),
              ),
            );
          });
        }

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('Track Case',
                style: Theme.of(context).textTheme.displaySmall),
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
          body: Column(
            children: [
              // Map area placeholder
              Container(
                height: 200,
                color: AppColors.slaterspwn,
                child: Center(
                  child: Icon(Icons.map_outlined,
                      size: 48,
                      color: AppColors.textSecondary),
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
                        margin:
                        const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.slaterspwn,
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Row(
                          children: [
                            _TabButton(
                              label: 'Tracking Detail',
                              selected: _tabIndex == 0,
                              onTap: () =>
                                  setState(() => _tabIndex = 0),
                            ),
                            _TabButton(
                              label: 'Case Detail',
                              selected: _tabIndex == 1,
                              onTap: () =>
                                  setState(() => _tabIndex = 1),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Case ID
                      Padding(
                        padding:
                        const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '#${widget.caseId.substring(0, 7).toUpperCase()}',
                            style: GoogleFonts.tiltWarp(
                                fontSize: 18,
                                color: AppColors.textPrimary),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Tab content
                      Expanded(
                        child: _tabIndex == 0
                            ? _TrackingTab(
                          statusHistory: statusHistory,
                          caseId: widget.caseId,
                          messageController: _messageController,
                          onSend: () =>
                              _sendMessage(widget.caseId),
                        )
                            : _CaseDetailTab(data: data ?? {}),
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

// Tab button widget
class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.yellowrspwn : Colors.transparent,
            borderRadius: BorderRadius.circular(50),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Tracking detail tab
class _TrackingTab extends StatelessWidget {
  final List<Map<String, dynamic>> statusHistory;
  final String caseId;
  final TextEditingController messageController;
  final VoidCallback onSend;

  const _TrackingTab({
    required this.statusHistory,
    required this.caseId,
    required this.messageController,
    required this.onSend,
  });

  String _formatTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$min $ampm';
  }

  String _formatDate(DateTime d) {
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[d.month]} ${d.day}, ${d.year}';
  }

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
              final ts = item['timestamp'];
              final date = ts is Timestamp ? ts.toDate() : null;
              final timeStr = date != null ? _formatTime(date) : '';
              final dateStr = date != null ? _formatDate(date) : '';

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isLast
                              ? AppColors.textPrimary
                              : AppColors.textPrimary,
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
                            width: 2,
                            height: 40,
                            color: AppColors.textPrimary),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item['status'] ?? '',
                              style: GoogleFonts.zain(
                                  fontSize: 13,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                          Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.end,
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

        // Message list
        SizedBox(
          height: 100,
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('cases')
                .doc(caseId)
                .collection('messages')
                .orderBy('timestamp')
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData || snap.data!.docs.isEmpty) {
                return const SizedBox();
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: snap.data!.docs.length,
                itemBuilder: (context, i) {
                  final msg = snap.data!.docs[i].data()
                  as Map<String, dynamic>;
                  final ts = msg['timestamp'] as Timestamp?;
                  final timeStr = ts != null
                      ? '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')} ${ts.toDate().hour >= 12 ? 'PM' : 'AM'}'
                      : '';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.slaterspwn,
                          child: Text(
                            (msg['senderName'] ?? 'U')[0],
                            style: GoogleFonts.zain(
                                fontSize: 12,
                                color: AppColors.textPrimary),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(msg['senderName'] ?? '',
                                      style: GoogleFonts.zain(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary)),
                                  Text(timeStr,
                                      style: GoogleFonts.zain(
                                          fontSize: 10,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                              Text(msg['text'] ?? '',
                                  style: GoogleFonts.zain(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
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
      ],
    );
  }
}

// Case detail tab
class _CaseDetailTab extends StatelessWidget {
  final Map<String, dynamic> data;
  const _CaseDetailTab({required this.data});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Case media placeholders
          Text('Case Media',
              style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(
            children: [
              _MediaBox(),
              const SizedBox(width: 12),
              _MediaBox(),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow('Reporter Name', data['reporterName']),
          _DetailRow('Reporter Mobile Number', data['reporterPhone']),
          _DetailRow('Address', data['address']),
          _DetailRow('Description', data['condition']),
          _DetailRow('Type of Animal', data['animalType']),
          _DetailRow('Urgency', data['urgency']),
          _DetailRow('Coordination', data['coordinateWithShelter']),
          if (data['coordinateWithShelter'] == 'no') ...[
            _DetailRow('Witness Name', data['witnessName']),
            _DetailRow('Witness Mobile Number', data['witnessPhone']),
          ],
          _DetailRow('Interest to adopt', data['interestedToAdopt']),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _MediaBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.slaterspwn,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.textSecondary),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String? value;
  const _DetailRow(this.label, this.value);

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