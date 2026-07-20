import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../app_theme.dart';

class PetFoundChatScreen extends StatefulWidget {
  final String tagId;
  final String sessionId;
  final String petName;

  const PetFoundChatScreen({
    super.key,
    required this.tagId,
    required this.sessionId,
    required this.petName,
  });

  @override
  State<PetFoundChatScreen> createState() => _PetFoundChatScreenState();
}

class _PetFoundChatScreenState extends State<PetFoundChatScreen> {
  final _messageCtrl = TextEditingController();
  bool _resolving = false;
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _sessionRef => FirebaseFirestore
      .instance
      .collection('rescueSessions')
      .doc(widget.sessionId);

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _enableChat() async {
    await _sessionRef.set(
      {'chatEnabledByOwner': true},
      SetOptions(merge: true),
    );
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await _sessionRef.collection('messages').add({
        'sender': 'owner',
        'text': text,
        'sentAt': FieldValue.serverTimestamp(),
      });
      _messageCtrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _markAsFound() async {
    setState(() => _resolving = true);
    try {
      await _sessionRef.set({'status': 'resolved'}, SetOptions(merge: true));

      await FirebaseFirestore.instance
          .collection('collarTags')
          .doc(widget.tagId)
          .set({
        'status': 'active',
        'activeRescueSessionId': FieldValue.delete(),
      }, SetOptions(merge: true));

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not update: $e')));
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left,
              color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _sessionRef.snapshots(),
        builder: (context, snap) {
          // Still waiting on the very first response from Firestore.
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load this session:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          if (!snap.hasData || !snap.data!.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No rescue session found for ID:\n${widget.sessionId}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          final session = snap.data!.data()!;
          final chatEnabled = session['chatEnabledByOwner'] as bool? ?? false;
          final lat = session['lat'] as num?;
          final lng = session['lng'] as num?;
          final address = session['address'] as String?;
          final foundAt = session['createdAt'] as Timestamp?;

          final locationLabel = address?.isNotEmpty == true
              ? address!
              : (lat != null && lng != null)
              ? '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}'
              : 'Location not shared';
          final timeLabel = foundAt != null
              ? DateFormat('MMM d, h:mm a').format(foundAt.toDate())
              : '';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text(
                  'Pet Found!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tiltWarp(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 18),

                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.tearspwn,
                  ),
                  child: const Icon(Icons.pets,
                      size: 44, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 10),
                Text(
                  widget.petName.isNotEmpty ? widget.petName : '—',
                  style: GoogleFonts.tiltWarp(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 10),
                const Divider(thickness: 0.5, color: AppColors.textPrimary),
                const SizedBox(height: 8),
                Text(
                  'A rescuer has found your pet at this location:',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13.5, color: AppColors.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  timeLabel.isNotEmpty
                      ? '$locationLabel | $timeLabel'
                      : locationLabel,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
                const SizedBox(height: 18),

                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Enable Live-Chat',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 14, color: AppColors.textPrimary)),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      border: Border.all(color: AppColors.slaterspwn),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: chatEnabled
                        ? _ChatThread(sessionRef: _sessionRef, isOwner: true)
                        : Center(
                      child: TextButton(
                        onPressed: _enableChat,
                        child: Text(
                          'Tap to enable live chat with the finder',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.zain(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                  ),
                ),

                if (chatEnabled) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageCtrl,
                          decoration: InputDecoration(
                            hintText: 'Type a message',
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            filled: true,
                            fillColor: AppColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide:
                              const BorderSide(color: AppColors.slaterspwn),
                            ),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send,
                            color: AppColors.textPrimary),
                        onPressed: _sending ? null : _sendMessage,
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _resolving ? null : _markAsFound,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      foregroundColor: AppColors.textPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                    ),
                    child: _resolving
                        ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textPrimary),
                    )
                        : Text('Mark as Found',
                        style: GoogleFonts.tiltWarp(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatThread extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> sessionRef;
  final bool isOwner;

  const _ChatThread({required this.sessionRef, required this.isOwner});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: sessionRef
          .collection('messages')
          .orderBy('sentAt')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return Center(
            child: Text('No messages yet.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary)),
          );
        }
        return ListView.builder(
          reverse: true,
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final m = docs[docs.length - 1 - i].data();
            final fromMe = (m['sender'] as String?) ==
                (isOwner ? 'owner' : 'finder');
            return Align(
              alignment:
              fromMe ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: fromMe
                      ? AppColors.yellowrspwn
                      : AppColors.tearspwn.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  m['text'] as String? ?? '',
                  style: GoogleFonts.zain(
                      fontSize: 13.5, color: AppColors.textPrimary),
                ),
              ),
            );
          },
        );
      },
    );
  }
}