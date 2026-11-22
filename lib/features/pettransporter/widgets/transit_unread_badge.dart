// Extracted from transit_progress_page.dart (behavior-preserving refactor).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:respawnd1/app_theme.dart';

class TransitUnreadBadge extends StatefulWidget {
  final String caseId;
  final Timestamp? lastReadAt;
  const TransitUnreadBadge({
    super.key,
    required this.caseId,
    required this.lastReadAt,
  });

  @override
  State<TransitUnreadBadge> createState() => _TransitUnreadBadgeState();
}

class _TransitUnreadBadgeState extends State<TransitUnreadBadge> {
  // Created once: a new stream on every rebuild re-read every message each
  // time the transit page redrew.
  late Stream<QuerySnapshot> _messages = _messagesFor(widget.caseId);

  static Stream<QuerySnapshot> _messagesFor(String caseId) => FirebaseFirestore.instance
      .collection('cases')
      .doc(caseId)
      .collection('messages')
      .orderBy('timestamp')
      .snapshots();

  @override
  void didUpdateWidget(TransitUnreadBadge old) {
    super.didUpdateWidget(old);
    if (old.caseId != widget.caseId) _messages = _messagesFor(widget.caseId);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final lastReadAt = widget.lastReadAt;
    return StreamBuilder<QuerySnapshot>(
      stream: _messages,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();

        final unread = snap.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          final senderId = d['senderId'] as String?;
          if (senderId == uid) return false; // don't count your own messages
          final ts = d['timestamp'] as Timestamp?;
          if (ts == null) return true; // not yet committed server-side
          if (lastReadAt == null) return true;
          return ts.compareTo(lastReadAt) > 0;
        }).length;

        if (unread == 0) return const SizedBox.shrink();

        return Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                unread > 9 ? '9+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
