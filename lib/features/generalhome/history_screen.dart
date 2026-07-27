import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rejection_reason.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';
import 'package:respawnd1/features/adoption/community_adoption_track_page.dart';
import 'package:respawnd1/features/rescue/case_summary_page.dart';
import 'package:respawnd1/features/rescue/track_case_page.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  int _tabIndex = 0;
  static const _tabs = ['Rescue', 'Adoption', 'Donation', 'Volunteer'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _HistoryFavoritesHeader(
              title: 'History',
              tabs: _tabs,
              selectedIndex: _tabIndex,
              onTabSelected: (i) => setState(() => _tabIndex = i),
            ),
            Expanded(
              child: switch (_tabIndex) {
                0 => const _RescueHistoryTab(),
                1 => const _AdoptionWithdrawnTab(),
                2 => const _DonationHistoryTab(),
                _ => const _VolunteerHistoryTab(),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RescueHistoryTab extends StatelessWidget {
  const _RescueHistoryTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Center(
        child: Text('Please log in to view your rescue history.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // Scoped to this user's own reports only — never anyone else's.
      stream: FirebaseFirestore.instance
          .collection('cases')
          .where('reporterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        if (snap.hasError) {
          return Center(
            child: Text('Could not load your history right now.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
          );
        }

        // Completed/closed rescues, plus rejected ones (Rejected Rescue
        // Reports spec §2 — rejected reports must remain visible in the
        // reporter's history, not just disappear); still-active cases stay
        // in Activity only.
        final docs = (snap.data?.docs ?? const [])
            .where((d) {
          final s = (d.data()['status'] as String? ?? '').toLowerCase();
          return s == 'closed' || s.contains('completed') || s.contains('ended') || s == 'rejected';
        })
            .toList();

        docs.sort((a, b) {
          final ta = a.data()['serverCreatedAt'] as Timestamp?;
          final tb = b.data()['serverCreatedAt'] as Timestamp?;
          return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
        });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No completed rescues yet.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final doc = docs[i];
            return _RescueHistoryCard(caseId: doc.id, data: doc.data());
          },
        );
      },
    );
  }
}

class _RescueHistoryCard extends StatelessWidget {
  final String caseId;
  final Map<String, dynamic> data;
  const _RescueHistoryCard({required this.caseId, required this.data});

  bool get _isRejected => (data['status'] as String? ?? '').toLowerCase() == 'rejected';

  bool get _isFinal {
    final s = (data['status'] as String? ?? '').toLowerCase();
    return s == 'closed' || s.contains('completed') || s.contains('ended');
  }

  bool get _communityAdoptionEligible => isCommunityAdoptionEligible(
        status: data['status'] as String?,
        rejectionReason: data['rejectionReason'] as String?,
        rescueType: data['rescueType'] as String?,
      );

  String get _rejectionReasonLabel {
    final reason = RejectionReason.fromName(data['rejectionReason'] as String?);
    if (reason == RejectionReason.other) {
      final other = data['rejectionReasonOther'] as String?;
      return (other?.trim().isNotEmpty ?? false) ? other! : 'Other';
    }
    return reason.label;
  }

  String get _statusLabel {
    final s = (data['status'] as String? ?? 'pending');
    final lower = s.toLowerCase();
    if (lower == 'rejected') return 'Rejected';
    if (lower == 'closed' || lower.contains('ended')) return 'Case Closed';
    if (lower.contains('completed')) return 'Case Completed';
    if (lower == 'pending') return 'Pending';
    // Fall back to a title-cased version of whatever the raw status is.
    return s.isEmpty
        ? 'Pending'
        : s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  }

  String get _dateLabel {
    final ts = data['serverCreatedAt'] as Timestamp? ?? data['createdAt'] as Timestamp?;
    final d = ts?.toDate();
    if (d == null) return '-';
    const months = [
      '', 'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${months[d.month]} ${d.day}, ${d.year} $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context) {
    final photoUrls = List<String>.from(data['photoUrls'] ?? []);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _isRejected
                ? (_communityAdoptionEligible
                    ? CommunityAdoptionTrackPage(caseId: caseId)
                    : TrackCasePage(caseId: caseId))
                : _isFinal
                    ? CaseSummaryPage(
                        caseId: caseId,
                        caseData: data,
                        fromCompletionFlow: false,
                      )
                    : TrackCasePage(caseId: caseId),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.slaterspwn,
              blurRadius: 1,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: photoUrls.isNotEmpty
                  ? Image.network(
                photoUrls.first,
                width: 64,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _placeholderThumb(),
              )
                  : _placeholderThumb(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '#${shortCaseId(caseId)}',
                    style: GoogleFonts.tiltWarp(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.access_time,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_dateLabel,
                          style: GoogleFonts.zain(
                              fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          (data['address'] as String?) ?? '-',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(
                              fontSize: 12, color: AppColors.textPrimary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.info_outline,
                        size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Text(_statusLabel,
                        style: GoogleFonts.zain(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isRejected ? const Color(0xFFE05353) : AppColors.textPrimary)),
                  ]),
                  if (_isRejected) ...[
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.comment_outlined,
                          size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Reason: $_rejectionReasonLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                        ),
                      ),
                    ]),
                    if (_communityAdoptionEligible) ...[
                      const SizedBox(height: 4),
                      Text('Eligible for Community Adoption — tap to view',
                          style: GoogleFonts.zain(
                              fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.greenrspwn)),
                    ],
                  ],
                  const SizedBox(height: 4),
                  _MessageCountRow(caseId: caseId),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholderThumb() {
    return Container(
      width: 64,
      height: 64,
      color: AppColors.slaterspwn,
      child: const Icon(Icons.image_outlined, color: AppColors.textSecondary),
    );
  }
}

class _MessageCountRow extends StatelessWidget {
  final String caseId;
  const _MessageCountRow({required this.caseId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .doc(caseId)
          .collection('messages')
          .snapshots(),
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Row(
          children: [
            const Icon(Icons.chat_bubble_outline,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              count == 0
                  ? 'No messages yet'
                  : '$count message${count == 1 ? '' : 's'}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
            ),
          ],
        );
      },
    );
  }
}


// Adoption — withdrawn applications only.
class _AdoptionWithdrawnTab extends StatelessWidget {
  const _AdoptionWithdrawnTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Center(
        child: Text('Please log in to view your adoption history.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('adoptions')
          .where('personal.adopterId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        if (snap.hasError) {
          return Center(
            child: Text('Could not load your adoption history right now.',
                style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
          );
        }

        final docs = (snap.data?.docs ?? const [])
            .where((d) => (d.data()['status'] as String? ?? '').toLowerCase() == 'withdrawn')
            .toList();

        docs.sort((a, b) {
          final ta = a.data()['createdAt'] as Timestamp?;
          final tb = b.data()['createdAt'] as Timestamp?;
          return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
        });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No withdrawn adoption applications.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final personal = (data['personal'] as Map?) ?? {};
            final ts = data['createdAt'] as Timestamp?;
            return _SimpleHistoryCard(
              title: (personal['animalName'] as String?) ?? 'Adoption Application',
              dateLabel: _formatTimestamp(ts),
              statusLabel: 'Withdrawn',
              icon: Icons.favorite_border,
            );
          },
        );
      },
    );
  }
}


// Donation — participated donations.
class _DonationHistoryTab extends StatelessWidget {
  const _DonationHistoryTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Center(
        child: Text('Please log in to view your donation history.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('donations')
          .where('donorId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load donation history — this page assumes a '
                    '"donations" collection with a "donorId" field; update '
                    'it if your schema is named differently.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          );
        }

        final docs = List.of(snap.data?.docs ?? const []);
        docs.sort((a, b) {
          final ta = a.data()['createdAt'] as Timestamp?;
          final tb = b.data()['createdAt'] as Timestamp?;
          return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
        });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No donations yet.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final ts = data['createdAt'] as Timestamp?;
            final amount = data['amount'];
            final cause = (data['campaignName'] as String?) ??
                (data['organizationName'] as String?) ??
                'Donation';
            return _SimpleHistoryCard(
              title: cause,
              dateLabel: _formatTimestamp(ts),
              statusLabel: amount != null ? '₱$amount' : (data['status'] as String? ?? 'Completed'),
              icon: Icons.volunteer_activism_outlined,
            );
          },
        );
      },
    );
  }
}


// Volunteer — participated volunteer activity.
class _VolunteerHistoryTab extends StatelessWidget {
  const _VolunteerHistoryTab();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Center(
        child: Text('Please log in to view your volunteer history.',
            style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      );
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('volunteerSignups')
          .where('volunteerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.greenrspwn));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load volunteer history — this page assumes a '
                    '"volunteerSignups" collection with a "volunteerId" '
                    'field; update it if your schema is named differently.',
                textAlign: TextAlign.center,
                style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
              ),
            ),
          );
        }

        final docs = List.of(snap.data?.docs ?? const []);
        docs.sort((a, b) {
          final ta = a.data()['createdAt'] as Timestamp?;
          final tb = b.data()['createdAt'] as Timestamp?;
          return (tb ?? Timestamp(0, 0)).compareTo(ta ?? Timestamp(0, 0));
        });

        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('No volunteer activity yet.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final ts = data['createdAt'] as Timestamp?;
            return _SimpleHistoryCard(
              title: (data['eventName'] as String?) ?? 'Volunteer Activity',
              dateLabel: _formatTimestamp(ts),
              statusLabel: (data['status'] as String?) ?? 'Participated',
              icon: Icons.groups_outlined,
            );
          },
        );
      },
    );
  }
}

String _formatTimestamp(Timestamp? ts) {
  final d = ts?.toDate();
  if (d == null) return '-';
  const months = [
    '', 'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  final min = d.minute.toString().padLeft(2, '0');
  return '${months[d.month]} ${d.day}, ${d.year} $h:$min $ampm';
}

class _SimpleHistoryCard extends StatelessWidget {
  final String title;
  final String dateLabel;
  final String statusLabel;
  final IconData icon;

  const _SimpleHistoryCard({
    required this.title,
    required this.dateLabel,
    required this.statusLabel,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.slaterspwn,
            blurRadius: 1,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.tearspwn,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.tiltWarp(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.access_time,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(dateLabel,
                        style: GoogleFonts.zain(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(statusLabel,
                      style: GoogleFonts.zain(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryFavoritesHeader extends StatelessWidget {
  final String title;
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;

  const _HistoryFavoritesHeader({
    required this.title,
    required this.tabs,
    required this.selectedIndex,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: const Icon(Icons.chevron_left,
                size: 28, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            title,
            style: GoogleFonts.tiltWarp(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: List.generate(tabs.length, (i) {
              final selected = i == selectedIndex;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onTabSelected(i),
                  child: Column(
                    children: [
                      Text(
                        tabs[i],
                        style: GoogleFonts.zain(
                          fontSize: 13,
                          fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 2,
                        color: selected
                            ? AppColors.textPrimary
                            : Colors.transparent,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
        const Divider(height: 1, color: AppColors.slaterspwn),
        const SizedBox(height: 4),
      ],
    );
  }
}