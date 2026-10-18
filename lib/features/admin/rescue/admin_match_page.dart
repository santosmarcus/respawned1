import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/currency.dart';

// Admin/org-facing queue for verifying proposed lost  found pet matches.
class AdminMatchVerificationPage extends StatelessWidget {
  const AdminMatchVerificationPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.textPrimary,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.background),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Match Verification',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.background)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('possibleMatches')
            .where('status', isEqualTo: 'pending_review')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No pending matches right now.',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 14),
            itemBuilder: (context, i) => _MatchReviewCard(
              matchId: docs[i].id,
              match: docs[i].data(),
            ),
          );
        },
      ),
    );
  }
}

class _MatchReviewCard extends StatefulWidget {
  final String matchId;
  final Map<String, dynamic> match;

  const _MatchReviewCard({required this.matchId, required this.match});

  @override
  State<_MatchReviewCard> createState() => _MatchReviewCardState();
}

class _MatchReviewCardState extends State<_MatchReviewCard> {
  bool _busy = false;

  Future<Map<String, dynamic>?> _fetchAlert(String? id) async {
    if (id == null) return null;
    final doc = await FirebaseFirestore.instance.collection('petAlerts').doc(id).get();
    return doc.data();
  }

  Future<void> _resolve(bool approve) async {
    setState(() => _busy = true);
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? 'admin';
    final matchRef =
    FirebaseFirestore.instance.collection('possibleMatches').doc(widget.matchId);
    final lostAlertId = widget.match['lostAlertId'] as String?;
    final foundAlertId = widget.match['foundAlertId'] as String?;

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.update(matchRef, {
          'status': approve ? 'approved' : 'rejected',
          'reviewedBy': adminUid,
          'reviewedAt': Timestamp.now(),
        });

        if (approve && lostAlertId != null && foundAlertId != null) {
          final lostRef =
          FirebaseFirestore.instance.collection('petAlerts').doc(lostAlertId);
          final foundRef =
          FirebaseFirestore.instance.collection('petAlerts').doc(foundAlertId);
          tx.update(lostRef, {'status': 'verified', 'matchedAlertId': foundAlertId});
          tx.update(foundRef, {'status': 'verified', 'matchedAlertId': lostAlertId});
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approve ? 'Match approved' : 'Match rejected'),
            backgroundColor: approve ? Colors.green : Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update match: $e'),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>?>>(
      future: Future.wait([
        _fetchAlert(widget.match['lostAlertId'] as String?),
        _fetchAlert(widget.match['foundAlertId'] as String?),
      ]),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final lost = snapshot.data![0];
        final found = snapshot.data![1];

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.slaterspwn),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.pets, size: 16, color: AppColors.textPrimary),
                  const SizedBox(width: 6),
                  Text(
                    (widget.match['species'] as String?) ?? 'Animal',
                    style: GoogleFonts.tiltWarp(
                        fontSize: 14, color: AppColors.textPrimary),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _AlertColumn(title: 'Lost report', data: lost)),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 90, color: AppColors.slaterspwn),
                  const SizedBox(width: 10),
                  Expanded(child: _AlertColumn(title: 'Found report', data: found)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _resolve(false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Not a match',
                          style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => _resolve(true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.yellowrspwn,
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                      child: _busy
                          ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.textPrimary))
                          : Text('Verify ownership',
                          style: GoogleFonts.zain(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AlertColumn extends StatelessWidget {
  final String title;
  final Map<String, dynamic>? data;

  const _AlertColumn({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return Text('Not found', style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary));
    }
    final photoUrls = List<String>.from(data!['photoUrls'] ?? []);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.zain(
                fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        if (photoUrls.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(photoUrls.first,
                width: 70, height: 70, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 70, height: 70, color: AppColors.slaterspwn,
                )),
          ),
        const SizedBox(height: 6),
        Text(data!['breed']?.toString().isNotEmpty == true
            ? data!['breed'].toString()
            : 'Breed unknown',
            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textPrimary)),
        Text(data!['colorMarkings']?.toString() ?? '',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        Text(data!['address']?.toString() ?? '',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
        if (title == 'Lost report') ...[
          const SizedBox(height: 4),
          Text(
            'Reward: ${formatRewardDisplay(offerReward: data!['offerReward'], rewardAmount: data!['rewardAmount'])}',
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.zain(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
          ),
        ],
      ],
    );
  }
}