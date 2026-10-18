import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/app_theme.dart';


class LostFoundTrackCasePage extends StatefulWidget {
  final String alertId;

  const LostFoundTrackCasePage({super.key, required this.alertId});

  @override
  State<LostFoundTrackCasePage> createState() =>
      _LostFoundTrackCasePageState();
}

class _LostFoundTrackCasePageState extends State<LostFoundTrackCasePage> {
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _alertRef => FirebaseFirestore
      .instance
      .collection('petAlerts')
      .doc(widget.alertId);

  @override
  void dispose() {
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final userDoc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final name =
      '${userDoc.data()?['firstName'] ?? ''} ${userDoc.data()?['lastName'] ?? ''}'
          .trim();

      await _alertRef.collection('messages').add({
        'senderId': uid,
        'senderName': name.isEmpty ? 'User' : name,
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _showContactSheet(
      BuildContext context, {
        required String title,
        required String? phone,
      }) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: GoogleFonts.tiltWarp(
                fontSize: 16, color: AppColors.textPrimary)),
        content: Text(
          (phone == null || phone.isEmpty)
              ? 'No contact number on file yet. Use the Messages thread below instead.'
              : phone,
          style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          if (phone != null && phone.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: phone));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Number copied.')),
                );
              },
              child: Text('Copy',
                  style: GoogleFonts.zain(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _messageFocusNode.requestFocus();
            },
            child: Text('Message instead',
                style: GoogleFonts.zain(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _alertRef.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'This report is no longer available.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            );
          }

          final data = snap.data!.data()!;
          final isLost = (data['type'] as String? ?? 'lost') == 'lost';
          final uid = FirebaseAuth.instance.currentUser?.uid;
          final isReporter = uid != null && uid == data['reporterId'];
          final photoUrls = List<String>.from(data['photoUrls'] ?? []);

          final title = (data['petName'] as String?)?.trim().isNotEmpty == true
              ? data['petName'] as String
              : ((data['breed'] as String?)?.trim().isNotEmpty == true
              ? '${data['breed']}'
              : (data['species'] as String? ?? 'Unknown Pet'));

          return Column(
            children: [
              _PhotoHeader(photoUrls: photoUrls),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.yellowrspwn,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            isLost ? 'LOST PET' : 'FOUND PET',
                            style: GoogleFonts.tiltWarp(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tiltWarp(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary),
                        ),
                      ),
                      const SizedBox(height: 18),

                      _CaseRow(
                        label: isLost ? 'Last Seen' : 'Location Found',
                        value: (data['address'] as String?)?.trim().isNotEmpty ==
                            true
                            ? data['address'] as String
                            : '-',
                      ),
                      const SizedBox(height: 10),

                      Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Column(
                          children: [
                            _CaseRow(
                                label: 'Species',
                                value: data['species'] as String?),
                            _CaseRow(
                                label: 'Breed',
                                value: data['breed'] as String?),
                            _CaseRow(label: 'Sex', value: data['sex'] as String?),
                            _CaseRow(
                                label: 'Color/Markings',
                                value: data['colorMarkings'] as String?),
                            _CaseRow(
                                label: 'Size',
                                value: data['size'] as String?),
                            if (isLost)
                              _CaseRow(
                                  label: 'Temperament',
                                  value: data['temperament'] as String?),
                            if (!isLost) ...[
                              _CaseRow(
                                  label: 'Describe Condition',
                                  value: data['describeCondition'] as String?),
                              _CaseRow(
                                  label: 'Right now, the animal is',
                                  value: data['animalStatus'] as String?),
                            ],
                          ],
                        ),
                      ),

                      if (isLost) ...[
                        const SizedBox(height: 4),
                        _CaseRow(
                          label: 'Reward',
                          value: formatRewardDisplay(
                            offerReward: data['offerReward'],
                            rewardAmount: data['rewardAmount'],
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),
                      const Divider(color: AppColors.slaterspwn),
                      const SizedBox(height: 12),

                      Text('Possible Matches',
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      _PossibleMatchesSection(
                        alertId: widget.alertId,
                        isLost: isLost,
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: AppColors.slaterspwn),
                      const SizedBox(height: 12),

                      if (!isReporter) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _showContactSheet(
                              context,
                              title: isLost ? 'Contact Owner' : 'Contact Finder',
                              phone: data['contactNumber'] as String?,
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.yellowrspwn,
                              foregroundColor: AppColors.textPrimary,
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(30)),
                            ),
                            child: Text(
                              isLost ? 'Contact Owner' : 'Contact Finder',
                              style: GoogleFonts.tiltWarp(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      Text('Messages',
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 10),

                      SizedBox(
                        height: 220,
                        child: _MessagesList(alertId: widget.alertId),
                      ),

                      const SizedBox(height: 10),

                      // Message input
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              decoration: InputDecoration(
                                hintText: 'Type a message',
                                hintStyle: GoogleFonts.zain(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(50),
                                  borderSide: const BorderSide(
                                      color: AppColors.slaterspwn),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(50),
                                  borderSide: const BorderSide(
                                      color: AppColors.textPrimary),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _sending ? null : _sendMessage,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: AppColors.yellowrspwn,
                                shape: BoxShape.circle,
                              ),
                              child: _sending
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.textPrimary),
                              )
                                  : const Icon(Icons.send,
                                  size: 18, color: AppColors.textPrimary),
                            ),
                          ),
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
    );
  }
}


class _PhotoHeader extends StatefulWidget {
  final List<String> photoUrls;
  const _PhotoHeader({required this.photoUrls});

  @override
  State<_PhotoHeader> createState() => _PhotoHeaderState();
}

class _PhotoHeaderState extends State<_PhotoHeader> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final urls = widget.photoUrls;
    return SizedBox(
      height: 250,
      child: Stack(
        fit: StackFit.expand,
        children: [
          urls.isEmpty
              ? Container(
            color: AppColors.slaterspwn,
            child: const Center(
              child: Icon(Icons.pets, size: 48, color: AppColors.textSecondary),
            ),
          )
              : PageView.builder(
            itemCount: urls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              return Image.network(
                urls[i],
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: AppColors.slaterspwn,
                    child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (context, _, __) => Container(
                  color: AppColors.slaterspwn,
                  child: const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 40, color: AppColors.textSecondary),
                  ),
                ),
              );
            },
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 4,
                        offset: const Offset(0, 2)),
                  ],
                ),
                padding: const EdgeInsets.all(4),
                child: const Icon(Icons.chevron_left,
                    size: 26, color: AppColors.textPrimary),
              ),
            ),
          ),

          // Title
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Track Case',
                style: GoogleFonts.tiltWarp(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
            ),
          ),

          // Page indicator dots (only when there is more than one photo)
          if (urls.length > 1)
            Positioned(
              bottom: 10,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(urls.length, (i) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _page
                          ? AppColors.textPrimary
                          : Colors.white.withValues(alpha: 0.8),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaseRow extends StatelessWidget {
  final String label;
  final String? value;
  const _CaseRow({required this.label, this.value});

  @override
  Widget build(BuildContext context) {
    final display = (value == null || value!.trim().isEmpty) ? '-' : value!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: GoogleFonts.zain(
                  fontSize: 15, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PossibleMatchesSection extends StatelessWidget {
  final String alertId;
  final bool isLost;
  const _PossibleMatchesSection({required this.alertId, required this.isLost});

  @override
  Widget build(BuildContext context) {
    final field = isLost ? 'lostAlertId' : 'foundAlertId';
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('possibleMatches')
          .where(field, isEqualTo: alertId)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final docs = List.of(snap.data?.docs ?? const []);
        if (docs.isEmpty) {
          return Text('No matches for now.',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary));
        }

        docs.sort((a, b) {
          final ta = a.data()['createdAt'] as Timestamp?;
          final tb = b.data()['createdAt'] as Timestamp?;
          return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
        });

        return Column(
          children: docs.map((doc) {
            final m = doc.data();
            final counterpartId =
            isLost ? m['foundAlertId'] as String? : m['lostAlertId'] as String?;
            final status = m['status'] as String? ?? 'pending_review';
            return _MatchCard(
              counterpartId: counterpartId,
              status: status,
              species: m['species'] as String? ?? '',
            );
          }).toList(),
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  final String? counterpartId;
  final String status;
  final String species;

  const _MatchCard({
    required this.counterpartId,
    required this.status,
    required this.species,
  });

  String get _statusLabel => switch (status) {
    'verified' => 'Match verified',
    'resolved' => 'Resolved',
    _ => 'Pending review',
  };

  Color get _statusColor => switch (status) {
    'verified' => AppColors.greenrspwn,
    'resolved' => AppColors.slaterspwn,
    _ => AppColors.yellowrspwn,
  };

  @override
  Widget build(BuildContext context) {
    if (counterpartId == null) return const SizedBox.shrink();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('petAlerts')
          .doc(counterpartId)
          .get(),
      builder: (context, snap) {
        final counterpart = snap.data?.data();
        final photoUrls = List<String>.from(counterpart?['photoUrls'] ?? []);
        final title = (counterpart?['petName'] as String?)?.trim().isNotEmpty ==
            true
            ? counterpart!['petName'] as String
            : (counterpart?['breed'] as String?)?.trim().isNotEmpty == true
            ? '${counterpart!['breed']} · $species'
            : species;
        final address = counterpart?['address'] as String? ?? '';

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    LostFoundTrackCasePage(alertId: counterpartId!),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.slaterspwn),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photoUrls.isNotEmpty
                      ? Image.network(photoUrls.first,
                      width: 44, height: 44, fit: BoxFit.cover)
                      : Container(
                    width: 44,
                    height: 44,
                    color: AppColors.slaterspwn,
                    child: const Icon(Icons.pets,
                        size: 20, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title.isEmpty ? 'Unnamed pet' : title,
                          style: GoogleFonts.zain(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if (address.isNotEmpty)
                        Text(address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.zain(
                                fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusLabel,
                      style: GoogleFonts.zain(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Live messages thread for this alert (petAlerts/{alertId}/messages).
class _MessagesList extends StatelessWidget {
  final String alertId;
  const _MessagesList({required this.alertId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('petAlerts')
          .doc(alertId)
          .collection('messages')
          .orderBy('timestamp')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text('No messages for now.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          reverse: true,
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final msg = docs[docs.length - 1 - i].data();
            final fromMe = msg['senderId'] == uid;
            final ts = msg['timestamp'] as Timestamp?;
            final timeLabel = ts != null
                ? DateFormat('h:mm a · MMMM d, yyyy').format(ts.toDate())
                : '';
            return Align(
              alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.7),
                decoration: BoxDecoration(
                  color: fromMe
                      ? AppColors.yellowrspwn
                      : AppColors.tearspwn.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!fromMe)
                      Text(msg['senderName'] as String? ?? 'User',
                          style: GoogleFonts.zain(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    Text(msg['text'] as String? ?? '',
                        style: GoogleFonts.zain(
                            fontSize: 13, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(timeLabel,
                        style: GoogleFonts.zain(
                            fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}