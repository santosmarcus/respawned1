import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/rescue/pet_alert_chat.dart';
import 'package:respawnd1/features/rescue/widgets/case_report_details.dart';


class LostFoundTrackCasePage extends StatefulWidget {
  final String alertId;

  /// The viewer's own report they came from (a Possible Match card on it),
  /// linked to the chat if they message about this report.
  final String? fromAlertId;

  const LostFoundTrackCasePage({
    super.key,
    required this.alertId,
    this.fromAlertId,
  });

  @override
  State<LostFoundTrackCasePage> createState() =>
      _LostFoundTrackCasePageState();
}

class _LostFoundTrackCasePageState extends State<LostFoundTrackCasePage> {
  bool _openedSuccess = false;

  DocumentReference<Map<String, dynamic>> get _alertRef => FirebaseFirestore
      .instance
      .collection('petAlerts')
      .doc(widget.alertId);

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
          final status = (data['status'] as String? ?? 'open').toLowerCase();
          final isReunited = status == 'reunited';

          // Reunited by the other person: the one who filed the report sees
          // the success page once (Done there archives it to History).
          if (isReporter &&
              isReunited &&
              data['reporterAcknowledgedReunion'] != true &&
              !_openedSuccess) {
            _openedSuccess = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ReunitedSuccessPage(alertId: widget.alertId),
                ),
              );
            });
          }
          final isClosed = isReunited || status == 'resolved';
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

                      if (isReunited) ...[
                        _ReunitedBanner(
                          // Who is looking: the owner who filed a lost
                          // report, the finder who filed a found one, or
                          // someone else.
                          viewer: !isReporter
                              ? null
                              : (data['type'] == 'found' ? 'finder' : 'owner'),
                          reunitedAt:
                          (data['reunitedAt'] as Timestamp?)?.toDate(),
                        ),
                        const SizedBox(height: 16),
                      ],

                      _CaseRow(
                        label: isLost ? 'Last Seen' : 'Location Found',
                        value: (data['address'] as String?)?.trim().isNotEmpty ==
                            true
                            ? data['address'] as String
                            : '-',
                      ),
                      const SizedBox(height: 10),

                      if (isLost)
                        _LostPetDetails(data: data)
                      else
                        _FoundPetDetails(alertId: widget.alertId, data: data),

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
                        isReporter: isReporter,
                      ),

                      const SizedBox(height: 16),
                      const Divider(color: AppColors.slaterspwn),
                      const SizedBox(height: 12),

                      Text('Messages',
                          style: GoogleFonts.zain(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      const SizedBox(height: 10),

                      // The person who filed the report sees one private
                      // chat per person who messaged; everyone else gets a
                      // button to message them (marketplace style).
                      if (isReporter)
                        PetAlertChatList(
                          alertId: widget.alertId,
                          alertType: data['type'] as String?,
                          footer: (confirmed) => _ReunitePrompt(
                            alertId: widget.alertId,
                            // The person who filed it: the owner on a lost
                            // report, the finder on a found one.
                            isOwner: data['type'] != 'found',
                            confirmedChats: confirmed,
                            isClosed: isClosed,
                          ),
                        )
                      else
                        _InquirerChatEntry(
                          alertId: widget.alertId,
                          alert: data,
                          fromAlertId: widget.fromAlertId,
                          isClosed: isClosed,
                        ),

                      // Messages from before chats were private, if any.
                      _LegacyMessages(
                        alertId: widget.alertId,
                        reporterId: data['reporterId'] as String?,
                        alertType: data['type'] as String?,
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
                errorBuilder: (context, _, _) => Container(
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

/// Shown at the top of a report the owner or finder marked reunited.
class _ReunitedBanner extends StatelessWidget {
  final DateTime? reunitedAt;

  /// 'owner', 'finder', or null for anyone else.
  final String? viewer;
  const _ReunitedBanner({this.reunitedAt, this.viewer});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.greenrspwn.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.favorite, size: 20, color: AppColors.textPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              switch (viewer) {
                'owner' => 'Back home with you',
                'finder' => 'Returned to its owner',
                _ => 'Reunited with owner',
              } +
                  (reunitedAt != null ? ' on ${formatDate(reunitedAt!)}' : ''),
              style: GoogleFonts.zain(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Everything the owner entered on the lost-pet form.
class _LostPetDetails extends StatelessWidget {
  final Map<String, dynamic> data;
  const _LostPetDetails({required this.data});

  @override
  Widget build(BuildContext context) {
    final lastSeenDate = (data['lastSeenDate'] as Timestamp?)?.toDate();
    final lastSeenTime = (data['lastSeenTime'] as String?)?.trim() ?? '';
    final lastSeen = lastSeenDate == null
        ? null
        : lastSeenTime.isEmpty
        ? formatDate(lastSeenDate)
        : '${formatDate(lastSeenDate)} · $lastSeenTime';
    final size = (data['size'] as String?)?.trim() ?? '';
    final tagId = (data['scannedTagId'] as String?)?.trim() ?? '';
    // Reports from before the form asked Behavior and Bite Risk.
    final temperament = (data['temperament'] as String?)?.trim() ?? '';
    final behavior = (data['behavior'] as List?)?.whereType<String>().toList() ?? const <String>[];
    final hasHealth = [
      'bodyCondition', 'mobility', 'alertness', 'eyesNoseMouth',
      'skinAndCoat', 'appetiteHydration', 'biteRisk',
    ].any((k) => (data[k] as String?)?.isNotEmpty == true) || behavior.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Column(
            children: [
              _CaseRow(label: 'Pet Name', value: data['petName'] as String?),
              _CaseRow(label: 'Species', value: data['species'] as String?),
              _CaseRow(label: 'Breed', value: data['breed'] as String?),
              _CaseRow(label: 'Sex', value: data['sex'] as String?),
              if (size.isNotEmpty) _CaseRow(label: 'Size', value: size),
              _CaseRow(
                  label: 'Color/Markings',
                  value: data['colorMarkings'] as String?),
              _CaseRow(label: 'Date/Time Last Seen', value: lastSeen),
              if (temperament.isNotEmpty)
                _CaseRow(label: 'Temperament', value: temperament),
              if (tagId.isNotEmpty) _CaseRow(label: 'ID Tag', value: tagId),
            ],
          ),
        ),
        // The owner's Health & Behavior Assessment and Bite Risk, laid out
        // like a found animal's card so the two can be compared.
        if (hasHealth) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.slaterspwn),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Health & behavior',
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                CaseDetailRow.optional('Body Condition', data['bodyCondition']),
                CaseDetailRow.optional('Mobility', data['mobility']),
                CaseDetailRow.optional('Alertness', data['alertness']),
                CaseDetailRow.optional('Eyes, Nose, Mouth', data['eyesNoseMouth']),
                CaseDetailRow.optional('Skin and Coat', data['skinAndCoat']),
                CaseDetailRow.optional('Appetite and Hydration', data['appetiteHydration']),
                CaseDetailRow.optional('Behavior', behavior.isEmpty ? null : behavior.join(', ')),
                CaseDetailRow.optional('Bite Risk', data['biteRisk']),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        _CaseRow(
          label: 'Reward',
          value: formatRewardDisplay(
            offerReward: data['offerReward'],
            rewardAmount: data['rewardAmount'],
          ),
        ),
      ],
    );
  }
}

/// Everything the finder entered: each animal's card (basic details,
/// Health & Behavior Assessment, risk) and the report-wide answers. A
/// found report with several animals is one petAlerts doc per animal
/// sharing this report's id as their groupId.
class _FoundPetDetails extends StatelessWidget {
  final String alertId;
  final Map<String, dynamic> data;
  const _FoundPetDetails({required this.alertId, required this.data});

  @override
  Widget build(BuildContext context) {
    final needsRescue = data['needsRescue'] == true;
    final tagId = (data['scannedTagId'] as String?)?.trim() ?? '';
    // Reports from before the finder form lost its free-text condition.
    final oldCondition = (data['describeCondition'] as String?)?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('petAlerts')
              .where('groupId', isEqualTo: alertId)
              .snapshots(),
          builder: (context, snap) {
            final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[
              ...?snap.data?.docs,
            ];
            docs.sort((a, b) {
              final ta = a.data()['createdAt'] as Timestamp?;
              final tb = b.data()['createdAt'] as Timestamp?;
              return (ta ?? Timestamp(0, 0)).compareTo(tb ?? Timestamp(0, 0));
            });
            final animals = <Map<String, dynamic>>[
              if (docs.isEmpty) data else for (final d in docs) d.data(),
            ];
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.slaterspwn),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    animals.length == 1 ? 'Animal details' : 'Animals found',
                    style: GoogleFonts.zain(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  AnimalDetailsList(animals: animals),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        if (oldCondition.isNotEmpty)
          _CaseRow(label: 'Condition', value: oldCondition),
        _CaseRow(
            label: 'Right now, the animal is',
            value: data['animalStatus'] as String?),
        _CaseRow(
            label: 'Needs pickup or medical help',
            value: needsRescue ? 'Yes' : 'No'),
        if (needsRescue)
          _CaseRow(label: 'Urgency', value: data['urgency'] as String?),
        if (tagId.isNotEmpty) _CaseRow(label: 'ID Tag', value: tagId),
      ],
    );
  }
}

class _PossibleMatchesSection extends StatelessWidget {
  final String alertId;
  final bool isLost;
  final bool isReporter;
  const _PossibleMatchesSection({
    required this.alertId,
    required this.isLost,
    required this.isReporter,
  });

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

        // Staff-rejected matches are hidden from reporters.
        final docs = (snap.data?.docs ?? const [])
            .where((d) => d.data()['status'] != 'rejected')
            .toList();
        if (docs.isEmpty) {
          return Text('No matches for now.',
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary));
        }

        // Best match first (score from scorePetAlertMatches,
        // functions/pet_matching.js); newest first on ties and for older
        // matches saved before scoring existed.
        docs.sort((a, b) {
          final sa = (a.data()['score'] as num?) ?? -1;
          final sb = (b.data()['score'] as num?) ?? -1;
          if (sa != sb) return sb.compareTo(sa);
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
              // Messaging from the counterpart links the viewer's own
              // report to the chat (only when this report is theirs).
              fromAlertId: isReporter ? alertId : null,
              status: status,
              species: m['species'] as String? ?? '',
              score: (m['score'] as num?)?.round(),
              breakdown: m['breakdown'] is Map
                  ? Map<String, dynamic>.from(m['breakdown'] as Map)
                  : null,
            );
          }).toList(),
        );
      },
    );
  }
}

class _MatchCard extends StatelessWidget {
  final String? counterpartId;
  final String? fromAlertId;
  final String status;
  final String species;
  final int? score;
  final Map<String, dynamic>? breakdown;

  const _MatchCard({
    required this.counterpartId,
    this.fromAlertId,
    required this.status,
    required this.species,
    this.score,
    this.breakdown,
  });

  /// Short "why it matched" line, e.g. "2.1 km away · same breed ·
  /// found 1 day after last seen". Empty for unscored (older) matches.
  String get _reasons {
    final b = breakdown;
    if (b == null) return '';
    final parts = <String>[];
    final km = b['distanceKm'] as num?;
    if (km != null) {
      parts.add(km < 1 ? 'under 1 km away' : '${km.toStringAsFixed(1)} km away');
    }
    if (b['breed'] == 20) parts.add('same breed');
    if (b['sex'] == 10) parts.add('same sex');
    if ((b['color'] as num? ?? 0) >= 12) parts.add('similar markings');
    final days = (b['dayGap'] as num?)?.round();
    if (days != null) {
      parts.add(days <= 0
          ? 'found the same day'
          : 'found $days day${days == 1 ? '' : 's'} after last seen');
    }
    return parts.join(' · ');
  }

  String get _statusLabel => switch (status) {
    'verified' => 'Match verified',
    'resolved' => 'Resolved',
    _ when score != null => '$score% match',
    _ => 'Pending review',
  };

  Color get _statusColor => switch (status) {
    'verified' => AppColors.greenrspwn,
    'resolved' => AppColors.slaterspwn,
    _ when score != null && score! >= 70 => AppColors.greenrspwn,
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
        final reasons = _reasons;

        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LostFoundTrackCasePage(
                  alertId: counterpartId!,
                  fromAlertId: fromAlertId,
                ),
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
                      if (reasons.isNotEmpty)
                        Text(reasons,
                            maxLines: 2,
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

/// For someone who didn't file the report: a button to message the person
/// who did, or their existing chat with its match status.
class _InquirerChatEntry extends StatelessWidget {
  final String alertId;
  final Map<String, dynamic> alert;
  final String? fromAlertId;
  final bool isClosed;

  const _InquirerChatEntry({
    required this.alertId,
    required this.alert,
    required this.fromAlertId,
    required this.isClosed,
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();
    final reporterRole = petAlertRole(
      alertType: alert['type'] as String?,
      isReporter: true,
    );
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('petAlertChats')
          .doc(petAlertChatId(alertId, uid))
          .snapshots(),
      builder: (context, snap) {
        final chat = snap.data?.data();
        if (chat == null && isClosed) {
          return Text(
            'This report is closed.',
            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
          );
        }
        final status = chat?['matchStatus'] as String? ?? 'pending';
        final statusText = chat == null
            ? null
            : chat['reunitedAt'] != null
            ? 'Reunited with owner'
            : switch (status) {
          'confirmed' => 'Right match confirmed',
          'rejected' => 'Marked as not a match',
          _ => 'Waiting for the ${reporterRole.toLowerCase()} to confirm the match',
        };
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (statusText != null) ...[
              Text(statusText,
                  style: GoogleFonts.zain(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
            ],
            ElevatedButton.icon(
              onPressed: () => openPetAlertChat(
                context,
                alertId: alertId,
                alert: alert,
                fromAlertId: fromAlertId,
              ),
              style: AppButtons.primary,
              icon: const Icon(Icons.chat_bubble_outline,
                  size: 18, color: AppColors.textPrimary),
              label: Text(
                chat == null ? 'Message the $reporterRole' : 'Open chat',
                style: GoogleFonts.tiltWarp(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Under the report owner's chats: the Reunited with Owner button once a
/// match is confirmed in one of them, or a hint until then.
class _ReunitePrompt extends StatelessWidget {
  final String alertId;
  final List<Map<String, dynamic>> confirmedChats;
  final bool isClosed;
  final bool isOwner;

  const _ReunitePrompt({
    required this.alertId,
    required this.isOwner,
    required this.confirmedChats,
    required this.isClosed,
  });

  @override
  Widget build(BuildContext context) {
    if (isClosed) return const SizedBox.shrink();
    if (confirmedChats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Once you confirm a right match in a chat and meet up, the '
              '${reunitedButtonLabel(isOwner: isOwner)} button appears here.',
          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: OutlinedButton.icon(
        onPressed: () => confirmAndMarkReunited(
          context,
          isOwner: isOwner,
          reportIds: [
            alertId,
            for (final c in confirmedChats)
              if ((c['linkedAlertId'] as String?)?.isNotEmpty == true)
                c['linkedAlertId'] as String,
          ],
          chatId: confirmedChats.length == 1
              ? confirmedChats.first['id'] as String?
              : null,
        ),
        icon: const Icon(Icons.favorite_outline,
            size: 18, color: AppColors.textPrimary),
        label: Text(
          reunitedButtonLabel(isOwner: isOwner),
          style: GoogleFonts.tiltWarp(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary),
        ),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: const BorderSide(color: AppColors.textPrimary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
      ),
    );
  }
}

/// The public thread every report used to have
/// (petAlerts/{alertId}/messages), read-only now that messaging is a
/// private chat. Hidden when the report has no such messages.
class _LegacyMessages extends StatelessWidget {
  final String alertId;
  final String? reporterId;
  final String? alertType;
  const _LegacyMessages({
    required this.alertId,
    required this.reporterId,
    required this.alertType,
  });

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
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text('Earlier public messages',
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            for (final d in docs)
              Builder(builder: (context) {
                final msg = d.data();
                final senderId = msg['senderId'] as String?;
                final role = petAlertRole(
                  alertType: alertType,
                  isReporter: senderId == reporterId,
                );
                final fromMe = senderId == uid;
                final ts = msg['timestamp'] as Timestamp?;
                return Align(
                  alignment:
                  fromMe ? Alignment.centerRight : Alignment.centerLeft,
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
                        Text(
                          fromMe
                              ? 'You · $role'
                              : petAlertSenderLabel(
                              msg['senderName'] as String?, role),
                          style: GoogleFonts.zain(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary),
                        ),
                        Text(msg['text'] as String? ?? '',
                            style: GoogleFonts.zain(
                                fontSize: 13, color: AppColors.textPrimary)),
                        if (ts != null)
                          Text(formatDateTime(ts.toDate()),
                              style: GoogleFonts.zain(
                                  fontSize: 10,
                                  color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}
