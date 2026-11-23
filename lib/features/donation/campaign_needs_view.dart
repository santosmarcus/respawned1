import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/donation/models.dart';

/// An animal-in-treatment campaign's rescue reason, medical condition,
/// treatment log and treatment expenses (the target is their total). The
/// same view on the donation page and in the admin form's preview, in the
/// donation page's style.
class CampaignNeedsView extends StatelessWidget {
  const CampaignNeedsView({super.key, required this.needs});

  final CampaignAnimalNeeds needs;

  static String _peso(num v) => '₱${NumberFormat(v == v.roundToDouble() ? '#,##0' : '#,##0.00').format(v)}';
  static String _date(DateTime? d) => d == null ? '' : DateFormat('MMM d, yyyy').format(d);

  @override
  Widget build(BuildContext context) {
    final heading = GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary);
    final body = GoogleFonts.zain(fontSize: 16, color: AppColors.textPrimary);
    final small = GoogleFonts.zain(fontSize: 13, color: AppColors.textPrimary.withValues(alpha: 0.6));
    final bold = GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary);

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(title, style: heading), const SizedBox(height: 6), ...children],
          ),
        );

    final condition = [
      if ((needs.reportedCondition ?? '').isNotEmpty) needs.reportedCondition!,
      if ((needs.currentCondition ?? '').isNotEmpty) 'Latest: ${needs.currentCondition}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((needs.rescueType ?? '').isNotEmpty) section('Rescue Reason', [Text(needs.rescueType!, style: body)]),
        if (condition.isNotEmpty) section('Medical Condition', [for (final c in condition) Text(c, style: body)]),
        section('Treatment Log', [
          if (needs.treatmentLog.isEmpty) Text('No treatment updates recorded yet.', style: small),
          for (final l in needs.treatmentLog)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: body),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l.type}${l.date == null ? '' : ' · ${_date(l.date)}'}', style: bold),
                        if (l.details.isNotEmpty) Text(l.details, style: body),
                        if ((l.notes ?? '').isNotEmpty) Text(l.notes!, style: small),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ]),
        section('Treatment Expenses', [
          for (final e in needs.expenses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: body),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, style: body),
                        Text(
                          '${e.category}${e.date == null ? '' : ' · ${_date(e.date)}'}'
                          '${e.shared ? ' · share of ${_peso(e.fullAmount)} for the animals rescued together' : ''}',
                          style: small,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(_peso(e.amount), style: bold),
                ],
              ),
            ),
          Divider(color: AppColors.textPrimary.withValues(alpha: 0.2)),
          Row(
            children: [
              Expanded(child: Text('Target funds', style: bold)),
              Text(_peso(needs.expenseTotal), style: GoogleFonts.tiltWarp(fontSize: 16, color: AppColors.textPrimary)),
            ],
          ),
        ]),
      ],
    );
  }
}
