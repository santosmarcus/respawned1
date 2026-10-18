import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../app_theme.dart';

class PetFoundChatScreen extends StatefulWidget {
  final String tagId;
  final String sessionId;
  final String petName;
  final bool isOwner;

  const PetFoundChatScreen({
    super.key,
    required this.tagId,
    required this.sessionId,
    required this.petName,
    this.isOwner = true,
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
        'sender': widget.isOwner ? 'owner' : 'finder',
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

      final tagRef =
      FirebaseFirestore.instance.collection('collarTags').doc(widget.tagId);
      final update = <String, dynamic>{
        'status': 'active',
        'activeRescueSessionId': FieldValue.delete(),
      };
      await tagRef.set(update, SetOptions(merge: true));

      // Keep the owner's users/{uid}/collarTags mirror in sync too — this
      // screen previously only wrote the root collarTags doc, so a pet
      // resolved from here (rather than the ID card's own toggle) left
      // the mirrored copy stuck showing status:'lost' forever, which is
      // what CollarTagsListScreen actually reads from.
      final tagSnap = await tagRef.get();
      final ownerId = tagSnap.data()?['ownerId'] as String?;
      if (ownerId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .collection('collarTags')
            .doc(widget.tagId)
            .set(update, SetOptions(merge: true));
      }

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

  // Places a phone call to the owner's contact number, if available.
  Future<void> _launchCall(String phone) async {
    final number = phone.trim();
    if (number.isEmpty) return;
    final uri = Uri(scheme: 'tel', path: number);
    try {
      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not start the call.')),
        );
      }
    }
  }

  // Opens the owner's Facebook link, adding a scheme if it was saved
  // without one (e.g. "facebook.com/name" instead of "https://...").
  Future<void> _launchFacebook(String link) async {
    final raw = link.trim();
    if (raw.isEmpty) return;
    final normalized =
    raw.startsWith('http://') || raw.startsWith('https://')
        ? raw
        : 'https://$raw';
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this Facebook link.')),
        );
      }
      return;
    }
    try {
      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this Facebook link.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this Facebook link.')),
        );
      }
    }
  }

  // Opens a pre-filled email draft addressed to the owner.
  Future<void> _launchEmail(String email) async {
    final address = email.trim();
    if (address.isEmpty) return;
    final subject = 'Found ${widget.petName.isNotEmpty ? widget.petName : 'your pet'}';
    final uri = Uri(
      scheme: 'mailto',
      path: address,
      query: 'subject=${Uri.encodeComponent(subject)}',
    );
    try {
      final launched =
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open an email draft.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open an email draft.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _sessionRef.snapshots(),
      builder: (context, snap) {
        // Still waiting on the very first response from Firestore.
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: _backAppBar(context),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load this session:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }
        if (!snap.hasData || !snap.data!.exists) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: _backAppBar(context),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No rescue session found for ID:\n${widget.sessionId}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ),
            ),
          );
        }

        final session = snap.data!.data()!;
        final status = session['status'] as String? ?? 'active';

        // The owner exits immediately via _markAsFound once they resolve
        // the session, so this only ever shows up for the finder — a clean
        // completion screen instead of the now-closed chat.
        if (!widget.isOwner && status == 'resolved') {
          return _RescueCompletedScreen(petName: widget.petName);
        }

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

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _backAppBar(context),
          body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('collarTags')
                .doc(widget.tagId)
                .snapshots(),
            builder: (context, tagSnap) {
              final tagData = tagSnap.data?.data();
              final petImageUrl = tagData?['petImageUrl'] as String?;
              final ownerMobile =
              (tagData?['ownerMobile'] as String? ?? '').trim();
              final ownerEmail =
              (tagData?['ownerEmail'] as String? ?? '').trim();
              final ownerFacebookLink =
              (tagData?['ownerFacebookLink'] as String? ?? '').trim();

              return SingleChildScrollView(
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
                      clipBehavior: Clip.antiAlias,
                      child: (petImageUrl != null && petImageUrl.isNotEmpty)
                          ? Image.network(
                        petImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.pets,
                            size: 44, color: AppColors.textPrimary),
                      )
                          : const Icon(Icons.pets,
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
                      widget.isOwner
                          ? 'A rescuer has found your pet at this location:'
                          : "Thanks for helping! We've notified ${widget.petName.isNotEmpty ? widget.petName : 'the pet'}'s "
                          'owner. Here\'s where you scanned the tag:',
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Enable Live-Chat',
                              style: GoogleFonts.tiltWarp(
                                  fontSize: 14, color: AppColors.textPrimary)),
                          if (!widget.isOwner) ...[
                            if (ownerMobile.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _launchCall(ownerMobile),
                                child: const Icon(Icons.phone,
                                    size: 16, color: AppColors.textSecondary),
                              ),
                            ],
                            if (ownerFacebookLink.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _launchFacebook(ownerFacebookLink),
                                child: const Icon(Icons.facebook,
                                    size: 16, color: AppColors.textSecondary),
                              ),
                            ],
                            if (ownerEmail.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () => _launchEmail(ownerEmail),
                                child: const Icon(Icons.email_outlined,
                                    size: 16, color: AppColors.textSecondary),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    SizedBox(
                      height: 260,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.slaterspwn),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: chatEnabled
                            ? _ChatThread(
                            sessionRef: _sessionRef, isOwner: widget.isOwner)
                            : Center(
                          child: widget.isOwner
                              ? TextButton(
                            onPressed: _enableChat,
                            child: Text(
                              'Tap to enable live chat with the finder',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.zain(
                                  fontSize: 13, color: AppColors.textSecondary),
                            ),
                          )
                              : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              "Waiting for ${widget.petName.isNotEmpty ? widget.petName : 'the pet'}'s "
                                  'owner to enable live chat…',
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

                    // Only the owner can resolve/close out the session — the
                    // finder just chats and waits; they get the completion
                    // screen automatically once the owner confirms reunion.
                    if (widget.isOwner) ...[
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
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  AppBar _backAppBar(BuildContext context) => AppBar(
    backgroundColor: AppColors.background,
    elevation: 0,
    scrolledUnderElevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.chevron_left,
          color: AppColors.textPrimary, size: 28),
      onPressed: () => Navigator.pop(context),
    ),
  );
}


class _RescueCompletedScreen extends StatelessWidget {
  final String petName;

  const _RescueCompletedScreen({required this.petName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Rescue Completed!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tiltWarp(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 28),
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppColors.textPrimary,
                        shape: BoxShape.circle,
                        border:
                        Border.all(color: AppColors.lavenderrspwn, width: 4),
                      ),
                      child: const Icon(Icons.pets,
                          size: 42, color: AppColors.lavenderrspwn),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'The pet has been safely returned to its owner.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Thank you for making this rescue successful. Every '
                          'successful reunion helps create a safer community '
                          'for pets and their owners.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'This rescue session has now ended. The temporary chat '
                          'has been closed.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.55,
                height: 50,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.yellowrspwn,
                    foregroundColor: AppColors.textPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30)),
                    elevation: 0,
                  ),
                  child: Text('Done',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary)),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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