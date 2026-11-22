import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/case_message.dart';
import 'package:respawnd1/core/repos/rescue_case/case_messages_repository.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/core/widgets/app_messages.dart';
import 'package:respawnd1/features/rescue/services/rescue_geocoding_service.dart';

/// The case thread between the reporter and the organization, the same on
/// every screen that shows it (Rescue Details and Track Case for staff,
/// Track Case for the reporter): message bubbles, suggested replies, and
/// the structured messages that confirm community reports and update the
/// location (CaseMessageKind).
class CaseChat extends StatefulWidget {
  const CaseChat({
    super.key,
    required this.caseId,
    required this.staff,
    this.maxListHeight = 320,
  });

  final String caseId;

  /// The viewer is the organization's staff (else the reporter).
  final bool staff;
  final double maxListHeight;

  @override
  State<CaseChat> createState() => _CaseChatState();
}

class _CaseChatState extends State<CaseChat> {
  final _repo = CaseMessagesRepository();
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final Stream<List<CaseMessage>> _stream = _repo.watch(widget.caseId);
  bool _sending = false;
  bool _locating = false;
  int _lastCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _error(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(text, kind: AppMessageKind.error));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await action();
    } catch (e) {
      _error('Could not send: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await _run(() async {
      await _repo.sendText(widget.caseId, text, staff: widget.staff);
      _controller.clear();
    });
  }

  /// Detects the phone's location and shares it in the thread.
  Future<void> _shareLocation(List<CaseMessage> openRequests) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _error('Allow location access to share where the animal is.');
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      String? address;
      try {
        address = await RescueGeocodingService().reverseGeocode(LatLng(pos.latitude, pos.longitude));
      } catch (_) {}
      await _repo.shareLocation(widget.caseId,
          lat: pos.latitude, lng: pos.longitude, address: address, openRequests: openRequests);
    } catch (e) {
      _error('Could not get your location: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _scrollToEnd(int count) {
    if (count == _lastCount) return;
    _lastCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CaseMessage>>(
      stream: _stream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Text('Could not load messages.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
        }
        final messages = snap.data ?? const <CaseMessage>[];
        _scrollToEnd(messages.length);
        final openLocationRequests =
            messages.where((m) => m.kind == CaseMessageKind.locationRequest && m.isOpen).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!snap.hasData)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (messages.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('No messages yet.', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: widget.maxListHeight),
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: messages.length,
                  itemBuilder: (context, i) => _Bubble(
                    message: messages[i],
                    staffViewer: widget.staff,
                    caseId: widget.caseId,
                    repo: _repo,
                    onShareLocation: () => _shareLocation(openLocationRequests),
                    locating: _locating,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            // Suggested replies, plus the location actions.
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  if (widget.staff)
                    _chip(
                      icon: Icons.my_location,
                      label: 'Ask for location',
                      onTap: _sending ? null : () => _run(() => _repo.requestLocation(widget.caseId)),
                    )
                  else
                    _chip(
                      icon: Icons.my_location,
                      label: _locating ? 'Locating…' : 'Share my location',
                      onTap: _locating ? null : () => _shareLocation(openLocationRequests),
                    ),
                  for (final s in widget.staff ? kStaffSuggestedReplies : kReporterSuggestedReplies)
                    _chip(
                      label: s,
                      onTap: () {
                        _controller.text = s;
                        _controller.selection = TextSelection.collapsed(offset: s.length);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Type a message',
                      hintStyle: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                InkWell(
                  customBorder: const CircleBorder(),
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
        );
      },
    );
  }

  Widget _chip({required String label, IconData? icon, VoidCallback? onTap}) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ActionChip(
          avatar: icon == null ? null : Icon(icon, size: 16, color: AppColors.textPrimary),
          label: Text(label, style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textPrimary)),
          backgroundColor: AppColors.tearspwn.withValues(alpha: 0.5),
          side: const BorderSide(color: AppColors.slaterspwn),
          visualDensity: VisualDensity.compact,
          onPressed: onTap,
        ),
      );
}

class _Bubble extends StatefulWidget {
  const _Bubble({
    required this.message,
    required this.staffViewer,
    required this.caseId,
    required this.repo,
    required this.onShareLocation,
    required this.locating,
  });

  final CaseMessage message;
  final bool staffViewer;
  final String caseId;
  final CaseMessagesRepository repo;
  final VoidCallback onShareLocation;
  final bool locating;

  @override
  State<_Bubble> createState() => _BubbleState();
}

class _BubbleState extends State<_Bubble> {
  String? _rescuedBy;
  bool _busy = false;

  Future<void> _act(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(appSnackBar('Could not save: $e', kind: AppMessageKind.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  TextStyle _t({double size = 13, FontWeight w = FontWeight.w400, Color c = AppColors.textPrimary}) =>
      GoogleFonts.zain(fontSize: size, fontWeight: w, color: c);

  @override
  Widget build(BuildContext context) {
    final m = widget.message;
    // Staff see their organization's messages on the right; the reporter
    // sees their own there.
    final mine = widget.staffViewer
        ? (m.isStaff || m.isSystem)
        : m.senderId != null && m.senderId == FirebaseAuth.instance.currentUser?.uid;
    final name = (m.senderName?.trim().isNotEmpty ?? false) ? m.senderName!.trim() : (m.isSystem ? 'ResPAWnd' : 'Unknown');
    final structured = m.kind != CaseMessageKind.text;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: structured ? 340 : 280),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: structured
                ? AppColors.lavenderrspwn.withValues(alpha: 0.18)
                : (mine ? AppColors.yellowrspwn.withValues(alpha: 0.6) : Colors.white),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: structured ? AppColors.lavenderrspwn : AppColors.slaterspwn),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(child: Text(name, style: _t(size: 11.5, w: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                  if (m.timestamp != null) ...[
                    const SizedBox(width: 6),
                    Text(formatDateTime(m.timestamp!), style: _t(size: 10.5, c: AppColors.textSecondary)),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(m.text, style: _t()),
              ...switch (m.kind) {
                CaseMessageKind.confirmRequest => _confirm(m),
                CaseMessageKind.locationRequest => _locationRequest(m),
                CaseMessageKind.location => _location(m),
                CaseMessageKind.text => const <Widget>[],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _confirm(CaseMessage m) {
    if (!m.isOpen) {
      return [
        const SizedBox(height: 6),
        _status(
          m.confirmed ? Icons.check_circle : Icons.cancel,
          m.confirmed ? AppColors.greenrspwn : AppColors.error,
          'Reporter answered: ${m.confirmed ? 'Yes' : 'No'}'
          '${m.rescuedBy != null && m.rescuedBy!.isNotEmpty ? ' · Rescued by: ${m.rescuedBy}' : ''}',
        ),
      ];
    }
    if (widget.staffViewer) {
      return [const SizedBox(height: 6), _status(Icons.hourglass_top, AppColors.warning, 'Waiting for the reporter to confirm')];
    }
    final isRescued = m.reportType == 'rescued';
    return [
      if (isRescued) ...[
        const SizedBox(height: 8),
        Text('Who rescued it?', style: _t(size: 12.5, w: FontWeight.w700)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final o in kRescuedByOptions)
              ChoiceChip(
                label: Text(o, style: _t(size: 12)),
                selected: _rescuedBy == o,
                onSelected: (_) => setState(() => _rescuedBy = o),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ],
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _act(() => widget.repo.answerConfirmation(widget.caseId, m, yes: false)),
              style: AppButtons.outline,
              child: const Text('No'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: _busy || (isRescued && _rescuedBy == null)
                  ? null
                  : () => _act(() => widget.repo.answerConfirmation(widget.caseId, m, yes: true, rescuedBy: _rescuedBy)),
              style: AppButtons.primary,
              child: const Text('Yes, confirm'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _locationRequest(CaseMessage m) {
    if (!m.isOpen) return [const SizedBox(height: 6), _status(Icons.check_circle, AppColors.greenrspwn, 'Location shared')];
    if (widget.staffViewer) {
      return [const SizedBox(height: 6), _status(Icons.hourglass_top, AppColors.warning, 'Waiting for the reporter\'s location')];
    }
    return [
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: widget.locating ? null : widget.onShareLocation,
          style: AppButtons.primary,
          icon: const Icon(Icons.my_location, size: 18),
          label: Text(widget.locating ? 'Locating…' : 'Share my current location'),
        ),
      ),
    ];
  }

  List<Widget> _location(CaseMessage m) {
    final lat = m.lat, lng = m.lng;
    if (lat == null || lng == null) return const [];
    final pos = LatLng(lat, lng);
    return [
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 120,
          child: GoogleMap(
            liteModeEnabled: true,
            initialCameraPosition: CameraPosition(target: pos, zoom: 16),
            markers: {Marker(markerId: const MarkerId('shared'), position: pos)},
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            myLocationButtonEnabled: false,
          ),
        ),
      ),
      if (m.appliedAt != null) ...[
        const SizedBox(height: 6),
        _status(Icons.check_circle, AppColors.greenrspwn,
            'Set as the case location${m.appliedBy != null ? ' by ${m.appliedBy}' : ''}'),
      ] else if (widget.staffViewer) ...[
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _busy ? null : () => _act(() => widget.repo.applyLocation(widget.caseId, m)),
            style: AppButtons.primary,
            icon: const Icon(Icons.edit_location_alt, size: 18),
            label: const Text('Confirm & use as case location'),
          ),
        ),
      ],
    ];
  }

  Widget _status(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: _t(size: 12, w: FontWeight.w700, c: color))),
        ],
      );
}
