import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/generalhome/home_screen.dart';

class CaseSummaryPage extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> caseData;
  final bool fromCompletionFlow;

  const CaseSummaryPage({
    super.key,
    required this.caseId,
    required this.caseData,
    this.fromCompletionFlow = false,
  });


  bool get _isClosed {
    final s = (caseData['status'] as String? ?? '').toLowerCase();
    return s == 'closed' || s.contains('ended');
  }


  Future<void> _close(BuildContext context) async {
    try {
      await FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .update({'hiddenFromExplore': true});
    } catch (_) {
      // Non-fatal — worst case it briefly still shows in Explore Reports.
    }

    if (!context.mounted) return;

    if (fromCompletionFlow) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false,
      );
    } else {
      Navigator.pop(context);
    }
  }

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

  Widget _timelineItem(Map<String, dynamic> item, bool isLast) {
    final ts = item['timestamp'];
    final date = ts is Timestamp ? ts.toDate() : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: AppColors.textPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.textPrimary, width: 2),
              ),
              child: isLast
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            if (!isLast)
              Container(width: 2, height: 40, color: AppColors.textPrimary),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(item['status'] ?? '',
                      style: GoogleFonts.zain(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
                if (date != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_formatTime(date),
                          style: GoogleFonts.zain(
                              fontSize: 11, color: AppColors.textSecondary)),
                      Text(_formatDate(date),
                          style: GoogleFonts.zain(
                              fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _reportTypeLabel(String? t) => switch (t) {
    'still_here' => 'Animal still here',
    'moved' => 'Animal moved',
    'rescued' => 'Animal rescued',
    'no_animal' => 'No animal present',
    _ => 'Update',
  };

  Widget _communityReportTile(Map<String, dynamic> r) {
    final ts = r['timestamp'] as Timestamp?;
    final date = ts?.toDate();
    final newAddress = r['newAddress'] as String?;
    final comment = r['comment'] as String?;
    final photoUrl = r['photoUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 12,
            backgroundColor: AppColors.tearspwn,
            child: Icon(Icons.info_outline,
                size: 12, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${r['reporterName'] ?? 'Someone'} · ${_reportTypeLabel(r['type'] as String?)}',
                        style: GoogleFonts.zain(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary),
                      ),
                    ),
                    if (date != null)
                      Text(_formatTime(date),
                          style: GoogleFonts.zain(
                              fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
                if (newAddress != null && newAddress.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(newAddress,
                        style: GoogleFonts.zain(
                            fontSize: 11, color: AppColors.textPrimary)),
                  ),
                if (comment != null && comment.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(comment,
                        style: GoogleFonts.zain(
                            fontSize: 11, color: AppColors.textSecondary)),
                  ),
              ],
            ),
          ),
          if (photoUrl != null && photoUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(photoUrl,
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                      width: 36, height: 36, color: AppColors.slaterspwn)),
            ),
          ],
        ],
      ),
    );
  }


  Widget _mediaSection(String label, List<String> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: urls.map((url) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  url,
                  width: 100,
                  height: 100,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _MediaBox(),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusHistory =
    List<Map<String, dynamic>>.from(caseData['statusHistory'] ?? []);
    final photoUrls = List<String>.from(caseData['photoUrls'] ?? []);
    final videoUrls = List<String>.from(caseData['videoUrls'] ?? []);
    final pickupVerificationUrls =
    List<String>.from(caseData['pickupVerificationUrls'] ?? []);
    final clinicVerificationUrls =
    List<String>.from(caseData['clinicVerificationUrls'] ?? []);
    final shelterVerificationUrls =
    List<String>.from(caseData['shelterVerificationUrls'] ?? []);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(context),
        ),
        title: Text(_isClosed ? 'Case Closed' : 'Case Completed',
            style: Theme.of(context).textTheme.displaySmall),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary',
                style: GoogleFonts.tiltWarp(
                    fontSize: 16, color: AppColors.textPrimary)),
            const SizedBox(height: 12),

            if (statusHistory.isEmpty)
              Text('No status updates were recorded for this case.',
                  style: GoogleFonts.zain(
                      fontSize: 13, color: AppColors.textSecondary))
            else
              for (int i = 0; i < statusHistory.length; i++)
                _timelineItem(statusHistory[i], i == statusHistory.length - 1),

            const SizedBox(height: 12),
            const Divider(color: AppColors.slaterspwn),
            const SizedBox(height: 12),

            Text('Community Reports',
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('cases')
                  .doc(caseId)
                  .collection('communityReports')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return Text('No community reports were submitted.',
                      style: GoogleFonts.zain(
                          fontSize: 12, color: AppColors.textSecondary));
                }
                return Column(
                  children:
                  docs.map((d) => _communityReportTile(d.data())).toList(),
                );
              },
            ),

            const SizedBox(height: 24),

            // Case media
            Text('Case Media',
                style: GoogleFonts.zain(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            (photoUrls.isEmpty && videoUrls.isEmpty)
                ? Row(
              children: [
                _MediaBox(),
                const SizedBox(width: 12),
                _MediaBox(),
              ],
            )
                : Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ...photoUrls.map((url) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      url,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _MediaBox(),
                    ),
                  );
                }),
                ...videoUrls.map((url) {
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => _CaseMediaVideoPage(url: url),
                        fullscreenDialog: true,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 100,
                        height: 100,
                        color: Colors.black87,
                        child: const Center(
                          child: Icon(Icons.play_circle_outline,
                              size: 32, color: Colors.white70),
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),

            const SizedBox(height: 16),

            _mediaSection('Rescue / Pickup Verification', pickupVerificationUrls),
            _mediaSection('Clinic / Treatment Verification', clinicVerificationUrls),
            _mediaSection('Shelter Drop-off Verification', shelterVerificationUrls),

            const SizedBox(height: 16),

            _DetailRow('Reporter Name', caseData['reporterName']),
            _DetailRow(
                'Pet Transporter Name', caseData['transporterName'] ?? '-'),
            _DetailRow('Pet Transporter Mobile Number',
                caseData['transporterPhone'] ?? '-'),
            _DetailRow('Address', caseData['address']),
            _DetailRow(
                'Vet Clinic Address', caseData['vetClinicAddress'] ?? '-'),
            _DetailRow('Type of Rescue', caseData['rescueType']),
            _DetailRow('Description', caseData['condition']),
            _AnimalGroupSection(caseId: caseId, data: caseData),
            _DetailRow('Urgency', caseData['urgency']),
            _DetailRow('Containment Status', caseData['containmentStatus']),
            if ((caseData['strayTemperament'] as String?)?.isNotEmpty ?? false)
              _DetailRow('Approachability / Bite Risk',
                  caseData['strayTemperament']),
            _DetailRow('On-site', caseData['onSite']),
            if ((caseData['accessInstructions'] as String?)?.isNotEmpty ??
                false)
              _DetailRow(
                  'Access Instructions', caseData['accessInstructions']),
            if ((caseData['bestTimeToContact'] as String?)?.isNotEmpty ??
                false)
              _DetailRow(
                  'Best Time to Contact', caseData['bestTimeToContact']),
            if ((caseData['scannedTagId'] as String?)?.isNotEmpty ?? false)
              _DetailRow('Scanned Tag ID', caseData['scannedTagId']),
            _DetailRow('Coordination', caseData['coordinateWithShelter']),
            if (caseData['coordinateWithShelter'] == 'no') ...[
              _DetailRow('Witness Name', caseData['witnessName']),
              _DetailRow('Witness Mobile Number', caseData['witnessPhone']),
            ],
            _DetailRow('Interest to adopt', caseData['interestedToAdopt']),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _AnimalGroupSection extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _AnimalGroupSection({required this.caseId, required this.data});

  Map<String, dynamic> _animalMap(Map raw) => {
    'animalType': raw['species'],
    'breed': raw['breed'],
    'sex': raw['sex'],
    'size': raw['size'],
    'colorMarkings': raw['colorMarkings'],
  };

  @override
  Widget build(BuildContext context) {
    final animals = data['animals'] as List?;
    if (animals != null && animals.isNotEmpty) {
      final total = animals.length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow('No. of Animals', '$total'),
          for (var i = 0; i < animals.length; i++)
            _AnimalDetailBlock(
              data: _animalMap(animals[i] as Map),
              index: i + 1,
              total: total,
            ),
        ],
      );
    }

    final groupId = data['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) {
      return _AnimalDetailBlock(data: data, index: 1, total: 1);
    }

    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('cases')
          .where('groupId', isEqualTo: groupId)
          .get(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return _AnimalDetailBlock(data: data, index: 1, total: 1);
        }
        final docs = snapshot.data!.docs;
        final total = docs.length;
        if (total <= 1) {
          return _AnimalDetailBlock(data: data, index: 1, total: 1);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow('No. of Animals', '$total'),
            for (var i = 0; i < docs.length; i++)
              _AnimalDetailBlock(
                data: docs[i].data(),
                index: i + 1,
                total: total,
              ),
          ],
        );
      },
    );
  }
}

class _AnimalDetailBlock extends StatelessWidget {
  final Map<String, dynamic> data;
  final int index;
  final int total;
  const _AnimalDetailBlock(
      {required this.data, required this.index, required this.total});

  List<Widget> _fields() => [
    _DetailRow('Species', data['animalType']),
    _DetailRow('Breed / Mixed', data['breed']),
    _DetailRow('Sex', data['sex']),
    _DetailRow('Size', data['size']),
    _DetailRow('Color / Distinguishing Markings', data['colorMarkings']),
  ];

  @override
  Widget build(BuildContext context) {
    if (total <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _fields(),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.slaterspwn),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Animal $index of $total',
              style: GoogleFonts.zain(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          ..._fields(),
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
// Full-screen network video player for a case's attached video evidence —
// previously these urls were fed straight into Image.network alongside
// photos and silently failed to render at all.
class _CaseMediaVideoPage extends StatefulWidget {
  final String url;
  const _CaseMediaVideoPage({required this.url});

  @override
  State<_CaseMediaVideoPage> createState() => _CaseMediaVideoPageState();
}

class _CaseMediaVideoPageState extends State<_CaseMediaVideoPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        _controller.play();
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _failed = true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: _failed
            ? const Text('Could not play this video.',
            style: TextStyle(color: Colors.white))
            : !_ready
            ? const CircularProgressIndicator(color: Colors.white)
            : AspectRatio(
          aspectRatio: _controller.value.aspectRatio == 0
              ? 16 / 9
              : _controller.value.aspectRatio,
          child: GestureDetector(
            onTap: () => setState(() {
              _controller.value.isPlaying
                  ? _controller.pause()
                  : _controller.play();
            }),
            child: Stack(
              alignment: Alignment.center,
              children: [
                VideoPlayer(_controller),
                AnimatedOpacity(
                  opacity: _controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.play_circle_fill,
                      size: 64, color: Colors.white70),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}