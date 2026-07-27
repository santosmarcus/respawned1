import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../app_theme.dart';

class TransparencyReportPage extends StatelessWidget {
  final String organizationId;
  final String organizationName;

  const TransparencyReportPage({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, color: AppColors.textPrimary, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Transparency Report',
          style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOrgHeader(),
            const SizedBox(height: 24),
            Text(
              'Fund Utilization Summary',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            _buildUtilizationSummary(),
            const SizedBox(height: 32),
            Text(
              'Detailed Expenditure Logs',
              style: GoogleFonts.tiltWarp(fontSize: 18, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            _buildExpenditureLogs(),
          ],
        ),
      ),
    );
  }

  Widget _buildOrgHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.yellowrspwn.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.yellowrspwn.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.yellowrspwn,
            child: Text(
              organizationName.substring(0, 1).toUpperCase(),
              style: GoogleFonts.tiltWarp(color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  organizationName,
                  style: GoogleFonts.tiltWarp(fontSize: 20, color: AppColors.textPrimary),
                ),
                Text(
                  'Verified Rescue Organization',
                  style: GoogleFonts.zain(fontSize: 14, color: AppColors.greenrspwn, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUtilizationSummary() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('campaigns')
          .where('organizer', isEqualTo: organizationName)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        double totalRaised = 0;
        int totalDonors = 0;
        
        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;
          totalRaised += (data['collectedAmount'] as num? ?? 0).toDouble();
          totalDonors += (data['numdonors'] as num? ?? 0).toInt();
        }

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _SummaryStat(label: 'Total Raised', value: '₱${NumberFormat('#,###').format(totalRaised)}'),
                Container(width: 1, height: 40, color: AppColors.textPrimary.withValues(alpha: 0.1)),
                _SummaryStat(label: 'Unique Donors', value: totalDonors.toString()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpenditureLogs() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('allocations')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                'No expenditure logs found.',
                style: GoogleFonts.zain(fontSize: 16, color: AppColors.textSecondary),
              ),
            ),
          );
        }

        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
            return _ExpenditureTile(data: data);
          },
        );
      },
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.tiltWarp(fontSize: 22, color: AppColors.textPrimary)),
        Text(label, style: GoogleFonts.zain(fontSize: 14, color: AppColors.textSecondary)),
      ],
    );
  }
}

class _ExpenditureTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ExpenditureTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final date = (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.tearspwn.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.outbound, color: AppColors.tearspwn, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data['label'] ?? 'General Expense',
                  style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  DateFormat('MMM dd, yyyy').format(date),
                  style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '- ₱${NumberFormat('#,###').format(data['amount'] ?? 0)}',
            style: GoogleFonts.tiltWarp(fontSize: 16, color: Colors.red[700]),
          ),
        ],
      ),
    );
  }
}
