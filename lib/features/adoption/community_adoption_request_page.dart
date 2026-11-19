import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/adoption/community_adoption_request.dart';
import 'package:respawnd1/core/repos/community_adoption_request_repository.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/adoption/community_adoption_terms.dart';

/// One adopter's request for a Community Adoption listing, shared by both
/// sides: the reporter who listed the animal and the interested adopter.
///
/// Both can message each other here. The reporter chooses or declines the
/// adopter; once chosen, both sign the community adoption agreement, and
/// the second signature completes the adoption.
class CommunityAdoptionRequestPage extends StatelessWidget {
  const CommunityAdoptionRequestPage({super.key, required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context) {
    final repo = CommunityAdoptionRequestRepository();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.yellowrspwn,
        leading: IconButton(
          icon: const Icon(
            Icons.chevron_left,
            color: AppColors.textPrimary,
            size: 28,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Community Adoption',
          style: GoogleFonts.tiltWarp(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<CommunityAdoptionRequest?>(
        stream: repo.watchRequest(requestId),
        builder: (context, snap) {
          if (!snap.hasData) {
            return snap.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : _centered('This request is no longer available.');
          }
          return _RequestBody(request: snap.data!, repo: repo);
        },
      ),
    );
  }
}

Widget _centered(String text) => Center(
  child: Padding(
    padding: const EdgeInsets.all(24),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
    ),
  ),
);

class _RequestBody extends StatefulWidget {
  const _RequestBody({required this.request, required this.repo});

  final CommunityAdoptionRequest request;
  final CommunityAdoptionRequestRepository repo;

  @override
  State<_RequestBody> createState() => _RequestBodyState();
}

class _RequestBodyState extends State<_RequestBody> {
  final _messageController = TextEditingController();
  bool _busy = false;
  String _myName = '';

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
  CommunityAdoptionRequest get r => widget.request;
  bool get _isLister => r.isLister(_uid);

  @override
  void initState() {
    super.initState();
    _myName = _isLister ? r.listerName : r.adopterName;
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && done != null) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar(done));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnackBar('Something went wrong: $e', kind: AppMessageKind.error),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    final uid = _uid;
    if (text.isEmpty || uid == null) return;
    _messageController.clear();
    await _run(
          () => widget.repo.sendMessage(
        requestId: r.id,
        senderId: uid,
        senderName: _myName,
        text: text,
      ),
    );
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.background,
        title: Text(title, style: GoogleFonts.tiltWarp(fontSize: 16)),
        content: Text(message, style: GoogleFonts.zain(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.zain(color: AppColors.textPrimary),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              action,
              style: GoogleFonts.zain(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final otherName = _isLister ? r.adopterName : r.listerName;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _StatusHeader(request: r, isLister: _isLister),
              const SizedBox(height: 12),
              if (_isLister) ...[
                _InfoLine('Adopter', r.adopterName),
                if (r.adopterContact.isNotEmpty)
                  _InfoLine('Contact number', r.adopterContact),
              ] else
                _InfoLine('Listed by', r.listerName),
              _InfoLine('Animal(s)', r.animalsLabel),
              const SizedBox(height: 8),
              ..._actions(),
              if (r.status == CommunityRequestStatus.selected ||
                  r.status == CommunityRequestStatus.completed) ...[
                const SizedBox(height: 16),
                _AgreementSection(
                  request: r,
                  isLister: _isLister,
                  busy: _busy,
                  onSign: (name) => _run(() async {
                    final done = await widget.repo.sign(
                      request: r,
                      asLister: _isLister,
                      fullName: name,
                    );
                    if (done && mounted) {
                      await showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.background,
                          title: Text(
                            'Adoption Complete',
                            style: GoogleFonts.tiltWarp(fontSize: 16),
                          ),
                          content: Text(
                            'Both of you have signed. ${r.animalsLabel} '
                                '${r.animalIndexes.length > 1 ? 'are' : 'is'} now adopted '
                                'through Community Adoption. Use the chat to arrange the handover.',
                            style: GoogleFonts.zain(fontSize: 14),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text(
                                'OK',
                                style: GoogleFonts.zain(
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                  }),
                ),
              ],
              const SizedBox(height: 16),
              Text(
                'Messages with $otherName',
                style: GoogleFonts.tiltWarp(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _MessageList(repo: widget.repo, requestId: r.id, myUid: _uid),
            ],
          ),
        ),
        if (r.status != CommunityRequestStatus.declined &&
            r.status != CommunityRequestStatus.withdrawn)
          _Composer(
            controller: _messageController,
            onSend: _busy ? null : _send,
          ),
      ],
    );
  }

  List<Widget> _actions() {
    if (_isLister && r.status == CommunityRequestStatus.pending) {
      return [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: AppButtons.primary,
                onPressed: _busy
                    ? null
                    : () async {
                  if (await _confirm(
                    'Choose ${r.adopterName}?',
                    'You and ${r.adopterName} will both be asked to sign the '
                        'adoption agreement for ${r.animalsLabel}.',
                    'Choose',
                  )) {
                    await _run(
                          () => widget.repo.choose(r.id),
                      done: 'Adopter chosen.',
                    );
                  }
                },
                child: Text(
                  'Choose Adopter',
                  style: GoogleFonts.zain(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                style: AppButtons.outline,
                onPressed: _busy
                    ? null
                    : () async {
                  if (await _confirm(
                    'Decline ${r.adopterName}?',
                    'They will be told you went with someone else.',
                    'Decline',
                  )) {
                    await _run(
                          () => widget.repo.decline(r.id),
                      done: 'Request declined.',
                    );
                  }
                },
                child: Text(
                  'Decline',
                  style: GoogleFonts.zain(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ];
    }
    if (_isLister &&
        r.status == CommunityRequestStatus.selected &&
        r.adopterSignature == null) {
      return [
        TextButton(
          onPressed: _busy
              ? null
              : () async {
            if (await _confirm(
              'Undo your choice?',
              '${r.adopterName} will no longer be your chosen adopter.',
              'Undo',
            )) {
              await _run(() => widget.repo.decline(r.id));
            }
          },
          child: Text(
            'Undo choice',
            style: GoogleFonts.zain(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ];
    }
    if (!_isLister && r.status.isOpen && r.listerSignature == null) {
      return [
        TextButton(
          onPressed: _busy
              ? null
              : () async {
            if (await _confirm(
              'Withdraw your interest?',
              'The reporter will see that you are no longer interested.',
              'Withdraw',
            )) {
              await _run(() => widget.repo.withdraw(r.id));
            }
          },
          child: Text(
            'Withdraw interest',
            style: GoogleFonts.zain(
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ];
    }
    return const [];
  }
}

class _StatusHeader extends StatelessWidget {
  const _StatusHeader({required this.request, required this.isLister});

  final CommunityAdoptionRequest request;
  final bool isLister;

  @override
  Widget build(BuildContext context) {
    final r = request;
    final text = switch (r.status) {
      CommunityRequestStatus.pending =>
      isLister
          ? '${r.adopterName} is interested in adopting ${r.animalsLabel}. Chat '
          'with them, then choose or decline.'
          : 'The reporter has your request. Use the chat below to introduce '
          'yourself and ask about ${r.animalsLabel}.',
      CommunityRequestStatus.selected =>
      isLister
          ? 'You chose ${r.adopterName}. Both of you now sign the agreement below.'
          : 'You were chosen to adopt ${r.animalsLabel}! Please review and sign '
          'the agreement below.',
      CommunityRequestStatus.completed =>
      '${r.animalsLabel} ${r.animalIndexes.length > 1 ? 'were' : 'was'} '
          'adopted by ${r.adopterName}. Use the chat to arrange the handover.',
      CommunityRequestStatus.declined =>
      isLister
          ? 'You declined this request.'
          : 'The reporter went with another adopter. Thank you for your interest.',
      CommunityRequestStatus.withdrawn =>
      isLister
          ? '${r.adopterName} withdrew their interest.'
          : 'You withdrew your interest.',
    };
    final color = switch (r.status) {
      CommunityRequestStatus.completed => AppColors.greenrspwn,
      CommunityRequestStatus.selected => AppColors.yellowrspwn,
      CommunityRequestStatus.declined ||
      CommunityRequestStatus.withdrawn => AppColors.slaterspwn,
      _ => AppColors.lavenderrspwn,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r.status.label,
            style: GoogleFonts.zain(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: GoogleFonts.zain(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Terms for both parties and each party's signature.
class _AgreementSection extends StatefulWidget {
  const _AgreementSection({
    required this.request,
    required this.isLister,
    required this.busy,
    required this.onSign,
  });

  final CommunityAdoptionRequest request;
  final bool isLister;
  final bool busy;
  final Future<void> Function(String fullName) onSign;

  @override
  State<_AgreementSection> createState() => _AgreementSectionState();
}

class _AgreementSectionState extends State<_AgreementSection> {
  final _nameController = TextEditingController();
  bool _accepted = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    final mySignature = widget.isLister
        ? r.listerSignature
        : r.adopterSignature;
    final name = r.animalsLabel;

    TextStyle body() => GoogleFonts.zain(
      fontSize: 13,
      color: AppColors.textPrimary,
      height: 1.3,
    );
    Widget terms(String heading, List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          heading,
          style: GoogleFonts.zain(fontSize: 13.5, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${i + 1}. ${items[i]}', style: body()),
          ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Community Adoption Agreement',
            style: GoogleFonts.tiltWarp(
              fontSize: 15,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Between ${r.listerName} (rehoming the animal) and ${r.adopterName} '
                '(adopter), for $name.',
            style: GoogleFonts.zain(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          terms('The adopter agrees:', communityAdopterTermsFor(name)),
          const SizedBox(height: 8),
          terms(
            'The person rehoming the animal agrees:',
            communityListerTermsFor(name),
          ),
          const SizedBox(height: 12),
          _SignatureLine('Rehomed by', r.listerSignature),
          _SignatureLine('Adopter', r.adopterSignature),
          if (mySignature == null &&
              r.status == CommunityRequestStatus.selected) ...[
            const SizedBox(height: 12),
            Text(
              kCommunityAgreementNotice,
              style: GoogleFonts.zain(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Type your full name',
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _accepted = !_accepted),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _accepted,
                      onChanged: (v) => setState(() => _accepted = v ?? false),
                      activeColor: AppColors.textPrimary,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'I have read and agree to the terms that apply to me.',
                      style: body(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: AppButtons.primary,
                onPressed:
                widget.busy ||
                    !_accepted ||
                    _nameController.text.trim().length < 3
                    ? null
                    : () => widget.onSign(_nameController.text.trim()),
                child: Text(
                  'Sign Agreement',
                  style: GoogleFonts.zain(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ] else if (mySignature != null &&
              r.status == CommunityRequestStatus.selected) ...[
            const SizedBox(height: 8),
            Text(
              'You have signed. Waiting for '
                  '${widget.isLister ? r.adopterName : r.listerName} to sign.',
              style: GoogleFonts.zain(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignatureLine extends StatelessWidget {
  const _SignatureLine(this.role, this.signature);

  final String role;
  final AgreementSignature? signature;

  @override
  Widget build(BuildContext context) {
    final s = signature;
    final at = s?.signedAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(
            s == null ? Icons.radio_button_unchecked : Icons.check_circle,
            size: 16,
            color: s == null ? AppColors.textSecondary : AppColors.greenrspwn,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              s == null
                  ? '$role: not signed yet'
                  : '$role: signed by ${s.name}'
                  '${at == null ? '' : ' on ${at.month}/${at.day}/${at.year}'}',
              style: GoogleFonts.zain(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.repo,
    required this.requestId,
    required this.myUid,
  });

  final CommunityAdoptionRequestRepository repo;
  final String requestId;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CommunityRequestMessage>>(
      stream: repo.watchMessages(requestId),
      builder: (context, snap) {
        final messages = snap.data ?? const [];
        if (messages.isEmpty) {
          return Text(
            'No messages yet.',
            style: GoogleFonts.zain(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          );
        }
        return Column(
          children: [
            for (final m in messages)
              Align(
                alignment: m.senderId == myUid
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 280),
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: m.senderId == myUid
                        ? AppColors.yellowrspwn.withValues(alpha: 0.6)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.slaterspwn),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (m.senderId != myUid)
                        Text(
                          m.senderName,
                          style: GoogleFonts.zain(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      Text(
                        m.text,
                        style: GoogleFonts.zain(
                          fontSize: 13.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppColors.slaterspwn)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Write a message…',
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: AppColors.textPrimary),
              onPressed: onSend,
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the request page; used by notifications and listing screens.
void openCommunityAdoptionRequest(BuildContext context, String requestId) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => CommunityAdoptionRequestPage(requestId: requestId),
    ),
  );
}
