import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/rescue/widgets/section_card.dart';

/// Case Messages (spec §4) — reuses the exact same `cases/{caseId}/messages`
/// thread already read/written by the reporter-side track_case_page.dart
/// and the admin-side _AdminTrackingTab in admin_track_case_page.dart
/// (senderId 'admin' / senderName 'Loved by the Gapz' — same convention
/// reused here). No second messaging collection: this widget is a
/// self-contained, reusable read+write view over that one subcollection,
/// so it can be dropped onto Rescue Details without duplicating the
/// thread that already exists on Track Case.
///
/// Collapsed by default (spec: "keep the section collapsible if needed")
/// — the heading and a message-count summary stay visible either way, so
/// message availability is never hidden.
class CaseMessagesSection extends StatefulWidget {
  final String caseId;
  const CaseMessagesSection({super.key, required this.caseId});

  @override
  State<CaseMessagesSection> createState() => _CaseMessagesSectionState();
}

class _CaseMessagesSectionState extends State<CaseMessagesSection> {
  bool _expanded = false;
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
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
      _controller.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send message: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Messages',
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('cases')
            .doc(widget.caseId)
            .collection('messages')
            .orderBy('timestamp')
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Text('Could not load messages.',
                style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
          }
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final docs = snap.data?.docs ?? const [];
          final count = docs.length;
          final summary = count == 0 ? 'No messages yet' : '$count message${count == 1 ? '' : 's'}';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(summary, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        size: 18, color: AppColors.textSecondary),
                  ],
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 8),
                if (docs.isEmpty)
                  Text('No messages yet.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary))
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final msg = docs[i].data();
                        final sender = (msg['senderName'] as String?)?.trim();
                        final displayName = (sender != null && sender.isNotEmpty) ? sender : 'Unknown';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 12,
                                backgroundColor: AppColors.slaterspwn,
                                child: Text(displayName.characters.first.toUpperCase(),
                                    style: GoogleFonts.zain(fontSize: 10)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$displayName: ${msg['text'] ?? ''}',
                                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: 'Type a message',
                          hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(50),
                            borderSide: const BorderSide(color: AppColors.slaterspwn),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(50),
                            borderSide: const BorderSide(color: AppColors.textPrimary),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sending ? null : _send,
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _sending ? AppColors.slaterspwn : AppColors.yellowrspwn,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.send, size: 18, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
