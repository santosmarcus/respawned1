import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';
import 'package:respawnd1/features/rescue/lost_found_track_case.dart';

// Lost/found report chats, marketplace style: anyone who messages the
// person who filed a report gets a private chat with them,
// petAlertChats/{alertId}_{inquirerId}, linked to the report (and to the
// sender's own report when they have one). The person who filed the report
// decides whether the sender is the right match; once confirmed, either of
// them can mark the pet reunited with its owner.
//
// Notifications, last-message previews and the decision notes come from
// functions/pet_alerts.js; firestore.rules (petAlertChats) limits each chat
// to its two people.

String petAlertChatId(String alertId, String inquirerId) =>
    '${alertId}_$inquirerId';

/// 'Owner' or 'Finder'. On a lost report the person who filed it is the
/// owner and whoever messages is a finder; on a found report it's reversed.
String petAlertRole({required String? alertType, required bool isReporter}) =>
    (alertType == 'found') != isReporter ? 'Owner' : 'Finder';

/// The current user's name as other people should see it: their profile
/// display name, else first + last name, else `name`, else the sign-in
/// display name. Empty when none is set (callers then show the role only).
Future<String> currentUserDisplayName() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return '';
  String s(Object? v) => v == null ? '' : v.toString().trim();
  try {
    final d = (await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get())
        .data() ??
        const <String, dynamic>{};
    final display = s(d['displayName']);
    if (display.isNotEmpty) return display;
    final full = '${s(d['firstName'])} ${s(d['lastName'])}'.trim();
    if (full.isNotEmpty) return full;
    final name = s(d['name']);
    if (name.isNotEmpty) return name;
  } catch (_) {}
  return s(user.displayName);
}

/// "Ana · Owner", or just "Owner" when there is no name.
String petAlertSenderLabel(String? name, String role) {
  final n = (name ?? '').trim();
  if (n.isEmpty || n == 'User') return role;
  return '$n · $role';
}

/// Opens the current user's chat about [alertId], starting it if needed.
/// [fromAlertId] is the user's own report they came from (a Possible Match
/// card); otherwise their newest open report of the opposite kind and the
/// same species is linked, if they have one.
Future<void> openPetAlertChat(
    BuildContext context, {
      required String alertId,
      required Map<String, dynamic> alert,
      String? fromAlertId,
    }) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final db = FirebaseFirestore.instance;
  final chatId = petAlertChatId(alertId, uid);
  final ref = db.collection('petAlertChats').doc(chatId);

  try {
    final existing = await ref.get();
    if (!existing.exists) {
      final linked = fromAlertId ?? await _ownMatchingReport(uid, alert);
      await ref.set({
        'alertId': alertId,
        'alertType': alert['type'] ?? 'lost',
        'alertSpecies': alert['species'],
        'reporterId': alert['reporterId'],
        'reporterName': alert['reporterName'] ?? '',
        'inquirerId': uid,
        'inquirerName': await currentUserDisplayName(),
        'linkedAlertId': linked,
        'matchStatus': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageAt': FieldValue.serverTimestamp(),
      });
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Could not open the chat: $e'),
      );
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => PetAlertChatPage(chatId: chatId)),
  );
}

/// The user's newest open report of the opposite kind and the same species
/// (the first doc of its group), to link to a new chat.
Future<String?> _ownMatchingReport(String uid, Map<String, dynamic> alert) async {
  final opposite = alert['type'] == 'found' ? 'lost' : 'found';
  final species = (alert['species'] as String? ?? '').toLowerCase();
  try {
    final mine = await FirebaseFirestore.instance
        .collection('petAlerts')
        .where('reporterId', isEqualTo: uid)
        .get();
    final candidates = mine.docs.where((d) {
      final a = d.data();
      final groupId = a['groupId'] as String?;
      return a['type'] == opposite &&
          (a['status'] ?? 'open') == 'open' &&
          (a['species'] as String? ?? '').toLowerCase() == species &&
          (groupId == null || groupId == d.id);
    }).toList()
      ..sort((a, b) {
        final ta = a.data()['createdAt'] as Timestamp?;
        final tb = b.data()['createdAt'] as Timestamp?;
        return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
      });
    return candidates.isEmpty ? null : candidates.first.id;
  } catch (_) {
    return null;
  }
}

/// The Reunited button, from each side: the owner got their pet back,
/// the finder returned it.
String reunitedButtonLabel({required bool isOwner}) =>
    isOwner ? 'I Got My Pet Back' : 'Returned to Owner';

/// Asks for confirmation, then marks [reportIds] (each with every doc of
/// its group) reunited with the owner, and the chat too when given.
/// onPetAlertReunited (functions/pet_alerts.js) resolves the reports'
/// possible matches and tells everyone who messaged about them.
Future<bool> confirmAndMarkReunited(
    BuildContext context, {
      required List<String> reportIds,
      required bool isOwner,
      String? chatId,
    }) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(isOwner ? 'Got your pet back?' : 'Returned to its owner?',
          style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
      content: Text(
        '${isOwner ? 'Confirm that your pet is back home with you.' : 'Confirm that you handed the pet back to its owner.'} '
            'This closes the '
            'report${reportIds.length > 1 ? 's' : ''}, stops new match alerts and '
            'lets everyone who helped know.',
        style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('Cancel',
              style: GoogleFonts.zain(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(isOwner ? 'Yes, they\'re home' : 'Yes, returned',
              style: GoogleFonts.zain(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;

  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final db = FirebaseFirestore.instance;
    // Every doc of each report's group, with who filed it: the user's own
    // report is marked acknowledged right away (they see the success page
    // now), the other person's shows it the next time they open theirs.
    final reporterOf = <String, String?>{};
    String? ownReportId;
    for (final reportId in reportIds) {
      final head = await db.collection('petAlerts').doc(reportId).get();
      final reporterId = head.data()?['reporterId'] as String?;
      reporterOf[reportId] = reporterId;
      if (reporterId == uid) ownReportId ??= reportId;
      final group = await db
          .collection('petAlerts')
          .where('groupId', isEqualTo: reportId)
          .get();
      for (final d in group.docs) {
        reporterOf[d.id] = d.data()['reporterId'] as String?;
      }
    }
    final batch = db.batch();
    for (final entry in reporterOf.entries) {
      batch.update(db.collection('petAlerts').doc(entry.key), {
        'status': 'reunited',
        'reunitedAt': FieldValue.serverTimestamp(),
        'reunitedBy': uid,
        if (entry.value == uid) 'reporterAcknowledgedReunion': true,
      });
    }
    if (chatId != null) {
      batch.update(db.collection('petAlertChats').doc(chatId), {
        'reunitedAt': FieldValue.serverTimestamp(),
        'reunitedBy': uid,
      });
    }
    await batch.commit();
    if (context.mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReunitedSuccessPage(
            alertId: ownReportId ?? reportIds.first,
            isOwner: isOwner,
          ),
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        appSnackBar('Could not update the report: $e'),
      );
    }
    return false;
  }
}

/// One private chat about a lost/found report.
class PetAlertChatPage extends StatefulWidget {
  final String chatId;
  const PetAlertChatPage({super.key, required this.chatId});

  @override
  State<PetAlertChatPage> createState() => _PetAlertChatPageState();
}

class _PetAlertChatPageState extends State<PetAlertChatPage> {
  final _controller = TextEditingController();
  bool _sending = false;
  bool _deciding = false;

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('petAlertChats').doc(widget.chatId);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send(Map<String, dynamic> chat) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    if (await _sendText(chat, text)) _controller.clear();
  }

  /// Posts [text] as the current user. Returns whether it was sent.
  Future<bool> _sendText(Map<String, dynamic> chat, String text) async {
    if (_sending) return false;
    setState(() => _sending = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await _chatRef.collection('messages').add({
        'senderId': uid,
        'senderName': await currentUserDisplayName(),
        'senderRole': petAlertRole(
          alertType: chat['alertType'] as String?,
          isReporter: uid == chat['reporterId'],
        ),
        'kind': 'text',
        'text': text,
        'timestamp': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not send message: $e'),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// The person who messaged met up and it isn't the pet: they tell the
  /// person who filed the report, who makes the call ("Not the right pet").
  Future<void> _flagNotThePet(Map<String, dynamic> chat) async {
    final reporterRole = petAlertRole(
      alertType: chat['alertType'] as String?,
      isReporter: true,
    ).toLowerCase();
    final ok = await showConfirmActionDialog(
      context,
      title: "Not the right pet?",
      message: 'We\'ll let the $reporterRole know you met and this isn\'t the '
          'pet. They can then mark it as not a match, and the report stays '
          'open for other people.',
      confirmLabel: 'Let them know',
    );
    if (!ok || !mounted) return;
    await _sendText(
      chat,
      'We met up and this isn\'t the right pet. Please mark it as not a match '
          'so the report stays open for others.',
    );
  }

  Future<void> _decide(String status) async {
    if (_deciding) return;
    setState(() => _deciding = true);
    try {
      await _chatRef.update({
        'matchStatus': status,
        'matchDecidedAt': FieldValue.serverTimestamp(),
        'matchDecidedBy': FirebaseAuth.instance.currentUser!.uid,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Could not save your answer: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _chatRef.snapshots(),
      builder: (context, snap) {
        final chat = snap.data?.data();
        if (chat == null) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(),
            body: Center(
              child: snap.connectionState == ConnectionState.waiting
                  ? const CircularProgressIndicator()
                  : Text('This chat is no longer available.',
                  style: GoogleFonts.zain(
                      fontSize: 14, color: AppColors.textSecondary)),
            ),
          );
        }

        final alertType = chat['alertType'] as String?;
        final isReporter = uid == chat['reporterId'];
        final otherRole =
        petAlertRole(alertType: alertType, isReporter: !isReporter);
        final otherName = (isReporter
            ? chat['inquirerName']
            : chat['reporterName']) as String?;

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            centerTitle: true,
            title: Text(
              petAlertSenderLabel(otherName, otherRole),
              style: GoogleFonts.tiltWarp(
                  fontSize: 18, color: AppColors.textPrimary),
            ),
          ),
          body: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _ReportCard(
                    alertId: chat['alertId'] as String,
                    label: isReporter ? 'Your report' : 'Asking about',
                  ),
                ),
                if ((chat['linkedAlertId'] as String?)?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _ReportCard(
                      alertId: chat['linkedAlertId'] as String,
                      label: isReporter
                          ? "The ${otherRole.toLowerCase()}'s report"
                          : 'Your report',
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _MatchPanel(
                    chat: chat,
                    chatId: widget.chatId,
                    isReporter: isReporter,
                    deciding: _deciding,
                    onDecide: _decide,
                    onNotThePet: () => _flagNotThePet(chat),
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(height: 1, color: AppColors.slaterspwn),
                Expanded(
                  child: _ChatMessages(chatRef: _chatRef, chat: chat),
                ),
                _Composer(
                  controller: _controller,
                  sending: _sending,
                  onSend: () => _send(chat),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The report a chat is about, like the item card in a marketplace chat.
/// Tapping it opens the report.
class _ReportCard extends StatelessWidget {
  final String alertId;
  final String label;
  const _ReportCard({required this.alertId, required this.label});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('petAlerts')
          .doc(alertId)
          .snapshots(),
      builder: (context, snap) {
        final a = snap.data?.data();
        final photos = List<String>.from(a?['photoUrls'] ?? const []);
        final isLost = (a?['type'] as String? ?? 'lost') == 'lost';
        final name = (a?['petName'] as String?)?.trim() ?? '';
        final breed = (a?['breed'] as String?)?.trim() ?? '';
        final species = a?['species'] as String? ?? '';
        final title = name.isNotEmpty
            ? name
            : breed.isNotEmpty
            ? '$breed · $species'
            : (species.isEmpty ? 'Pet' : species);
        final status = (a?['status'] as String? ?? 'open').toLowerCase();

        return GestureDetector(
          onTap: a == null
              ? null
              : () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LostFoundTrackCasePage(alertId: alertId),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.slaterspwn),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: photos.isNotEmpty
                      ? Image.network(photos.first,
                      width: 52, height: 52, fit: BoxFit.cover)
                      : Container(
                    width: 52,
                    height: 52,
                    color: AppColors.slaterspwn,
                    child: const Icon(Icons.pets,
                        size: 22, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: GoogleFonts.zain(
                              fontSize: 11, color: AppColors.textSecondary)),
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                      if ((a?['address'] as String?)?.isNotEmpty == true)
                        Text(a!['address'] as String,
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
                    color: status == 'reunited'
                        ? AppColors.greenrspwn
                        : AppColors.yellowrspwn,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status == 'reunited'
                        ? 'REUNITED'
                        : (isLost ? 'LOST' : 'FOUND'),
                    style: GoogleFonts.zain(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The match decision: the person who filed the report answers "Right
/// match" or "Not a match"; once confirmed, the owner's contact number is
/// shared and either of them can mark the pet reunited.
class _MatchPanel extends StatelessWidget {
  final Map<String, dynamic> chat;
  final String chatId;
  final bool isReporter;
  final bool deciding;
  final ValueChanged<String> onDecide;

  /// For the person who messaged: tell the one who filed the report that
  /// they met and it isn't the pet.
  final VoidCallback onNotThePet;

  const _MatchPanel({
    required this.chat,
    required this.chatId,
    required this.isReporter,
    required this.deciding,
    required this.onDecide,
    required this.onNotThePet,
  });

  /// After meeting, the person who filed the report found it isn't the
  /// pet: the match goes back to "not a match" (onPetAlertChatDecision in
  /// functions/pet_alerts.js posts a note, tells the other person and
  /// unlinks the two reports). The contact number and the Reunited button
  /// go away; the report stays open for other people.
  Future<void> _notTheRightPet(BuildContext context) async {
    final ok = await showConfirmActionDialog(
      context,
      title: 'Not the right pet?',
      message: 'This marks the match as not a match. Your contact number is '
          'hidden from them again, and your report stays open so others can '
          'still reach you.',
      confirmLabel: 'Not a match',
      destructive: true,
    );
    if (ok) onDecide('rejected');
  }

  @override
  Widget build(BuildContext context) {
    final status = chat['matchStatus'] as String? ?? 'pending';
    final alertType = chat['alertType'] as String?;
    final reporterRole =
    petAlertRole(alertType: alertType, isReporter: true).toLowerCase();
    final otherRole =
    petAlertRole(alertType: alertType, isReporter: !isReporter);
    final reunited = chat['reunitedAt'] != null;
    final isOwner =
        petAlertRole(alertType: alertType, isReporter: isReporter) == 'Owner';

    if (reunited) {
      return _panel(
        color: AppColors.greenrspwn.withValues(alpha: 0.35),
        icon: isOwner ? Icons.home_outlined : Icons.favorite,
        text: isOwner
            ? 'Your pet is back home. Thank you for using ResPAWnd!'
            : 'Returned to its owner. Thank you for helping!',
      );
    }

    switch (status) {
      case 'confirmed':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panel(
              color: AppColors.greenrspwn.withValues(alpha: 0.35),
              icon: Icons.check_circle_outline,
              text: 'Right match confirmed. Arrange a safe, public place to '
                  'meet, then mark the pet reunited.',
            ),
            if (!isReporter) _ReporterContact(alertId: chat['alertId'] as String),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => confirmAndMarkReunited(
                context,
                isOwner: isOwner,
                reportIds: [
                  chat['alertId'] as String,
                  if ((chat['linkedAlertId'] as String?)?.isNotEmpty == true)
                    chat['linkedAlertId'] as String,
                ],
                chatId: chatId,
              ),
              icon: const Icon(Icons.favorite_outline,
                  size: 18, color: AppColors.textPrimary),
              label: Text(reunitedButtonLabel(isOwner: isOwner),
                  style: GoogleFonts.tiltWarp(
                      fontSize: 14, color: AppColors.textPrimary)),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.textPrimary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
            ),
            // Met up and it turned out to be a different animal.
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: deciding
                    ? null
                    : (isReporter ? () => _notTheRightPet(context) : onNotThePet),
                child: Text(
                  isReporter ? 'Not the right pet' : "This isn't the pet",
                  style: GoogleFonts.zain(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary),
                ),
              ),
            ),
          ],
        );
      case 'rejected':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panel(
              color: AppColors.slaterspwn.withValues(alpha: 0.6),
              icon: Icons.block,
              text: isReporter
                  ? 'You marked this as not a match.'
                  : 'The $reporterRole marked this as not a match.',
            ),
            if (isReporter)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: deciding ? null : () => onDecide('confirmed'),
                  child: Text('Change to right match',
                      style: GoogleFonts.zain(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ),
              ),
          ],
        );
      default:
        if (!isReporter) {
          return _panel(
            color: AppColors.yellowrspwn.withValues(alpha: 0.35),
            icon: Icons.hourglass_empty,
            text: 'Waiting for the $reporterRole to confirm whether this is '
                'the right match.',
          );
        }
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.yellowrspwn.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                alertType == 'found'
                    ? 'Is this person the pet\'s owner?'
                    : 'Does this person have your pet?',
                style: GoogleFonts.zain(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
              Text(
                'Compare their photos and details first. Confirming lets the '
                    '${otherRole.toLowerCase()} see your contact number.',
                style: GoogleFonts.zain(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: deciding ? null : () => onDecide('rejected'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.textPrimary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text('Not a match',
                          style: GoogleFonts.zain(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: deciding ? null : () => onDecide('confirmed'),
                      style: AppButtons.primary,
                      child: Text('Right match',
                          style: GoogleFonts.zain(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
    }
  }

  Widget _panel({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ),
        ],
      ),
    );
  }
}

/// The contact number from the report, shown to the other person once the
/// match is confirmed (the lost-pet form promises it stays hidden until then).
class _ReporterContact extends StatelessWidget {
  final String alertId;
  const _ReporterContact({required this.alertId});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('petAlerts')
          .doc(alertId)
          .get(),
      builder: (context, snap) {
        final phone =
            (snap.data?.data()?['contactNumber'] as String?)?.trim() ?? '';
        if (phone.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              const Icon(Icons.phone_outlined,
                  size: 18, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(phone,
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
              TextButton(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: phone));
                  ScaffoldMessenger.of(context).showSnackBar(
                    appSnackBar('Number copied.'),
                  );
                },
                child: Text('Copy',
                    style: GoogleFonts.zain(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatMessages extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> chatRef;
  final Map<String, dynamic> chat;
  const _ChatMessages({required this.chatRef, required this.chat});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: chatRef.collection('messages').orderBy('timestamp').snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                uid == chat['reporterId']
                    ? 'No messages yet.'
                    : 'Say hello and share what you know — where and when '
                    'you saw the pet, or what makes it yours.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          );
        }
        return ListView.builder(
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final msg = docs[docs.length - 1 - i].data();
            if (msg['kind'] == 'system') {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  msg['text'] as String? ?? '',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary),
                ),
              );
            }
            final senderId = msg['senderId'] as String?;
            final fromMe = senderId == uid;
            final role = msg['senderRole'] as String? ??
                petAlertRole(
                  alertType: chat['alertType'] as String?,
                  isReporter: senderId == chat['reporterId'],
                );
            final ts = msg['timestamp'] as Timestamp?;
            return _Bubble(
              fromMe: fromMe,
              label: fromMe
                  ? 'You · $role'
                  : petAlertSenderLabel(msg['senderName'] as String?, role),
              text: msg['text'] as String? ?? '',
              time: ts != null ? formatDateTime(ts.toDate()) : '',
            );
          },
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final bool fromMe;
  final String label;
  final String text;
  final String time;
  const _Bubble({
    required this.fromMe,
    required this.label,
    required this.text,
    required this.time,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints:
        BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
            Text(label,
                style: GoogleFonts.zain(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            Text(text,
                style: GoogleFonts.zain(
                    fontSize: 14, color: AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text(time,
                style: GoogleFonts.zain(
                    fontSize: 10, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Type a message',
                hintStyle: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.slaterspwn),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: AppColors.textPrimary),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: AppColors.yellowrspwn,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textPrimary),
              )
                  : const Icon(Icons.send,
                  size: 18, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// The report owner's inbox for one report: one row per person who
/// messaged, with their role, last message and match status. Also tells
/// the report page whether a match is confirmed (for the Reunited button).
class PetAlertChatList extends StatelessWidget {
  final String alertId;
  final String? alertType;
  final Widget Function(List<Map<String, dynamic>> confirmedChats)? footer;

  const PetAlertChatList({
    super.key,
    required this.alertId,
    required this.alertType,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('petAlertChats')
          .where('alertId', isEqualTo: alertId)
          .where('reporterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
          ...?snap.data?.docs,
        ]..sort((a, b) {
          final ta = a.data()['lastMessageAt'] as Timestamp?;
          final tb = b.data()['lastMessageAt'] as Timestamp?;
          return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
        });
        final confirmed = [
          for (final d in docs)
            if (d.data()['matchStatus'] == 'confirmed') {...d.data(), 'id': d.id},
        ];
        final inquirerRole =
        petAlertRole(alertType: alertType, isReporter: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (docs.isEmpty)
              Text(
                'No messages yet. When someone messages you about this '
                    'report, it shows up here.',
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
            for (final d in docs)
              _ChatRow(
                chatId: d.id,
                chat: d.data(),
                role: inquirerRole,
              ),
            if (footer != null) footer!(confirmed),
          ],
        );
      },
    );
  }
}

class _ChatRow extends StatelessWidget {
  final String chatId;
  final Map<String, dynamic> chat;
  final String role;
  const _ChatRow({required this.chatId, required this.chat, required this.role});

  @override
  Widget build(BuildContext context) {
    final status = chat['matchStatus'] as String? ?? 'pending';
    final (label, color) = switch (status) {
      'confirmed' => ('Right match', AppColors.greenrspwn),
      'rejected' => ('Not a match', AppColors.slaterspwn),
      _ => ('Needs your answer', AppColors.yellowrspwn),
    };
    final last = (chat['lastMessage'] as String?)?.trim() ?? '';
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => PetAlertChatPage(chatId: chatId)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.slaterspwn),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.slaterspwn,
              child: Icon(Icons.person_outline,
                  size: 20, color: AppColors.textPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    petAlertSenderLabel(chat['inquirerName'] as String?, role),
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  Text(
                    last.isEmpty ? 'Started a chat' : last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.zain(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(label,
                  style: GoogleFonts.zain(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The success page after a lost/found pet is reunited with its owner,
/// shown to whoever marked it right away and, the first time they open it
/// afterwards, to the person who filed the report (LostFoundTrackCasePage).
/// Done records that the person who filed it has seen it
/// (reporterAcknowledgedReunion), which moves the report from Activity to
/// History.
class ReunitedSuccessPage extends StatelessWidget {
  final String alertId;

  /// Whether the person seeing this is the pet's owner (else the finder).
  /// Left out, it follows from the report: the person who filed a lost
  /// report is the owner, and on a found report it's the other person.
  final bool? isOwner;
  const ReunitedSuccessPage({super.key, required this.alertId, this.isOwner});

  Future<void> _done(BuildContext context, Map<String, dynamic>? alert) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && alert?['reporterId'] == uid &&
        alert?['reporterAcknowledgedReunion'] != true) {
      try {
        final db = FirebaseFirestore.instance;
        final group = await db
            .collection('petAlerts')
            .where('groupId', isEqualTo: alertId)
            .get();
        final batch = db.batch();
        for (final id in {alertId, ...group.docs.map((d) => d.id)}) {
          batch.update(db.collection('petAlerts').doc(id),
              {'reporterAcknowledgedReunion': true});
        }
        await batch.commit();
      } catch (_) {
        // Non-fatal: the report just stays in Activity a little longer.
      }
    }
    if (!context.mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('petAlerts')
          .doc(alertId)
          .snapshots(),
      builder: (context, snap) {
        final a = snap.data?.data();
        final uid = FirebaseAuth.instance.currentUser?.uid;
        final isLost = (a?['type'] as String? ?? 'lost') == 'lost';
        final isReporter = uid != null && uid == a?['reporterId'];
        final owner = isOwner ?? (isLost == isReporter);
        final name = (a?['petName'] as String?)?.trim().isNotEmpty == true
            ? a!['petName'] as String
            : (owner ? 'Your pet' : 'The pet');
        final title = owner ? 'Welcome Home!' : 'You Did It!';
        final headline = owner
            ? '$name is back home with you!'
            : '$name is back with its owner!';
        final body = owner
            ? 'Thank you to everyone who kept an eye out and reached out. '
            'We\'re so happy your pet is home safe.'
            : 'Thank you for helping a lost pet get back to its family. '
            'Your kindness made this reunion possible.';

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
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.lavenderrspwn,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.textPrimary.withValues(alpha: 0.2),
                                width: 4),
                          ),
                          child: Icon(
                              owner ? Icons.home_rounded : Icons.volunteer_activism,
                              size: 46,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          style: GoogleFonts.tiltWarp(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          headline,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$body This report is now closed — you can find it '
                              'any time in your History.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.zain(
                              fontSize: 13, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => _done(context, a),
                    style: AppButtons.primary.copyWith(
                        fixedSize: WidgetStatePropertyAll(
                            Size(MediaQuery.of(context).size.width * 0.55, 50))),
                    child: Text('Done',
                        style: Theme.of(context).textTheme.headlineLarge),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
