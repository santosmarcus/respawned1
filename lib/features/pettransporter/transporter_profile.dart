import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/repos/auth_service.dart';
import 'package:respawnd1/features/pettransporter/service_screen.dart';
import 'package:respawnd1/features/pettransporter/transit_progress_page.dart';
import 'package:respawnd1/features/pettransporter/transporter_notif.dart';
import 'package:respawnd1/core/utils/case_id.dart';
import 'package:respawnd1/core/utils/transporter_trip_stats.dart';
import 'package:respawnd1/features/pettransporter/transporter_verification_screen.dart';
import 'package:respawnd1/core/widgets/app_dialogs.dart';

class TransporterProfile extends StatelessWidget {
  const TransporterProfile({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Theme(
      data: AppTheme.rescuerTheme,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          centerTitle: true,
          toolbarHeight: 80,
          title: Text(
            'My Profile',
            style: GoogleFonts.tiltWarp(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 2,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.notifications_outlined),
              activeIcon: Icon(Icons.notifications),
              label: 'Notifications',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'My Profile',
            ),
          ],
          onTap: (index) {
            if (index == 0) {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              } else {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (_) => const ServiceScreen()),
                );
              }
            } else if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (_) => const TransporterNotifications()),
              );
            }
          },
        ),
        body: uid == null
            ? Center(
          child: Text('Sign in to view your profile.',
              style: GoogleFonts.zain(
                  fontSize: 15, color: AppColors.textSecondary)),
        )
            : StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(
                    color: AppColors.greenrspwn),
              );
            }

            final data =
                snapshot.data?.data() as Map<String, dynamic>? ?? {};
            final firstName = data['firstName'] as String? ?? '';
            final lastName = data['lastName'] as String? ?? '';
            final phone = data['phone'] as String? ?? '';
            final verificationStatus =
                data['transporterVerificationStatus'] as String? ?? '';
            final verification = Map<String, dynamic>.from(
                data['transporterVerification'] as Map? ?? {});
            final portraitUrl = verification['portraitUrl'] as String?;
            final vehicleType = verification['vehicleType'] as String?;
            final licensePlate = verification['licensePlate'] as String?;

            final fullName = ('$firstName $lastName').trim();

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar + name + phone
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 44,
                          backgroundColor: AppColors.slaterspwn,
                          backgroundImage: (portraitUrl != null &&
                              portraitUrl.isNotEmpty)
                              ? NetworkImage(portraitUrl)
                              : null,
                          child: (portraitUrl == null || portraitUrl.isEmpty)
                              ? const Icon(Icons.person,
                              size: 44, color: AppColors.textSecondary)
                              : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          fullName.isNotEmpty ? fullName : 'Pet Transporter',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary),
                        ),
                        if (phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            phone,
                            style: GoogleFonts.zain(
                                fontSize: 13,
                                color: AppColors.textSecondary),
                          ),
                        ],
                        const SizedBox(height: 10),
                        _VerificationBadge(status: verificationStatus),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Stats
                  _StatsRow(uid: uid),

                  const SizedBox(height: 24),

                  Text('Vehicle',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  _InfoCard(
                    children: [
                      _InfoRow(
                        icon: Icons.local_shipping_outlined,
                        label: 'Vehicle Type',
                        value: (vehicleType != null && vehicleType.isNotEmpty)
                            ? vehicleType
                            : '—',
                      ),
                      const Divider(height: 20),
                      _InfoRow(
                        icon: Icons.confirmation_number_outlined,
                        label: 'License Plate',
                        value:
                        (licensePlate != null && licensePlate.isNotEmpty)
                            ? licensePlate
                            : '—',
                      ),
                    ],
                  ),

                  if (verificationStatus == 'rejected') ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TransporterVerificationScreen(
                                firstName: firstName,
                                lastName: lastName,
                                phone: phone,
                              ),
                            ),
                          );
                        },
                        style: AppButtons.outline,
                        child: Text('Resubmit Verification',
                            style: GoogleFonts.tiltWarp(
                                fontSize: 14, color: AppColors.textPrimary)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  Text('Settings',
                      style: GoogleFonts.tiltWarp(
                          fontSize: 15, color: AppColors.textPrimary)),
                  const SizedBox(height: 10),
                  _InfoCard(
                    children: [
                      _MenuRow(
                        icon: Icons.notifications_outlined,
                        label: 'Notifications',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                const TransporterNotifications()),
                          );
                        },
                      ),
                      const Divider(height: 20),
                      _MenuRow(
                        icon: Icons.help_outline,
                        label: 'Help & Support',
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              title: Text('Help & Support',
                                  style: GoogleFonts.tiltWarp(
                                      fontSize: 16,
                                      color: AppColors.textPrimary)),
                              content: Text(
                                'Need help with a rescue transport? Reach out to our support team through the app for assistance.',
                                style: GoogleFonts.zain(
                                    fontSize: 13,
                                    color: AppColors.textSecondary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('Got it',
                                      style: GoogleFonts.zain(
                                          color: AppColors.textPrimary)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmLogout(context),
                      icon: const Icon(Icons.logout, color: AppColors.error),
                      label: Text('Log Out',
                          style: GoogleFonts.tiltWarp(
                              fontSize: 14, color: AppColors.error)),
                      style: AppButtons.dangerOutline,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showConfirmActionDialog(
      context,
      title: 'Log Out',
      message: 'Are you sure you want to log out?',
      confirmLabel: 'Log Out',
      destructive: true,
    );

    if (confirmed == true) {
      await AuthService().signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }
}

// Verification status pill
class _VerificationBadge extends StatelessWidget {
  final String status;
  const _VerificationBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final String label;
    late final IconData icon;

    switch (status) {
      case 'approved':
      case 'verified':
        color = AppColors.greenrspwn;
        label = 'Verified';
        icon = Icons.verified_outlined;
        break;
      case 'rejected':
        color = AppColors.error;
        label = 'Verification Rejected';
        icon = Icons.error_outline;
        break;
      case 'pending':
        color = AppColors.yellowrspwn;
        label = 'Verification Pending';
        icon = Icons.hourglass_top_outlined;
        break;
      default:
        color = AppColors.slaterspwn;
        label = 'Not Verified';
        icon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textPrimary),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// Completed / ongoing rescue stats
class _StatsRow extends StatelessWidget {
  final String uid;
  const _StatsRow({required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('cases')
          .where('assignedVolunteerId', isEqualTo: uid)
          .snapshots(),
      builder: (context, snapshot) {
        int completed = 0;
        int ongoing = 0;
        // The specific case to jump to when "Ongoing" is tapped — the
        // rider is only ever meant to have one active job at a time (see
        // createAssignmentOffer's single-active-assignment guard), so the
        // first match found is the one to show.
        String? ongoingCaseId;

        final completedDocs = <QueryDocumentSnapshot>[];
        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            if (isCompletedTransit(data)) {
              completed++;
              completedDocs.add(doc);
            } else if (isOngoingTransit(data)) {
              ongoing++;
              ongoingCaseId ??= doc.id;
            }
          }
        }

        return Row(
          children: [
            Expanded(
              child: _StatCard(
                label: 'Completed',
                value: '$completed',
                icon: Icons.check_circle_outline,
                onTap: completedDocs.isEmpty
                    ? null
                    : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        _CompletedTransitsPage(docs: completedDocs),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                label: 'Ongoing',
                value: '$ongoing',
                icon: Icons.local_shipping_outlined,
                onTap: ongoingCaseId == null
                    ? null
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TransitProgressPage(caseId: ongoingCaseId!),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  const _StatCard(
      {required this.label,
        required this.value,
        required this.icon,
        this.onTap});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: AppColors.textPrimary, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.tiltWarp(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.zain(
                  fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );

    if (onTap == null) return card;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: card,
    );
  }
}

// Generic rounded card container
class _InfoCard extends StatelessWidget {
  final List<Widget> children;
  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6),
        ],
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(label,
              style: GoogleFonts.zain(
                  fontSize: 13, color: AppColors.textSecondary)),
        ),
        Text(value,
            style: GoogleFonts.zain(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuRow(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: GoogleFonts.zain(
                    fontSize: 13, color: AppColors.textPrimary)),
          ),
          const Icon(Icons.chevron_right,
              size: 18, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}

/// List of the transporter's completed transits (opened from the
/// "Completed" stat on the profile).
class _CompletedTransitsPage extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  const _CompletedTransitsPage({required this.docs});

  DateTime? _completedAt(Map<String, dynamic> data) {
    for (final key in ['transitCompletedAt', 'adopterPickupConfirmedAt']) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
    }
    final history = (data['statusHistory'] as List?) ?? const [];
    if (history.isNotEmpty) {
      final last = history.last;
      if (last is Map && last['timestamp'] is Timestamp) {
        return (last['timestamp'] as Timestamp).toDate();
      }
    }
    return null;
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...docs]..sort((a, b) {
      final da = _completedAt(a.data() as Map<String, dynamic>) ?? DateTime(2000);
      final db = _completedAt(b.data() as Map<String, dynamic>) ?? DateTime(2000);
      return db.compareTo(da);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Completed Transits',
            style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary)),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final data = sorted[i].data() as Map<String, dynamic>;
          final when = _completedAt(data);
          final species = (data['animalType'] ?? 'Animal').toString();
          final destination = (data['shelterAddress'] as String?)?.isNotEmpty == true
              ? data['shelterAddress'] as String
              : (data['dropoffAddress'] ?? data['vetClinicAddress'] ?? '').toString();
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle, color: AppColors.greenrspwn),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('#${shortCaseId(sorted[i].id)} · $species',
                          style: GoogleFonts.zain(
                              fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      Text((data['address'] ?? '').toString(),
                          style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                      if (destination.isNotEmpty)
                        Text('→ $destination',
                            style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
                      if (when != null)
                        Text('Completed ${_formatDate(when)}',
                            style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
