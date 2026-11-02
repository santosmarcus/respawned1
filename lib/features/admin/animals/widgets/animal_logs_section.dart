import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/features/admin/animals/state/animal_records_providers.dart';

/// One shared "Animal Logs" list, reading `animals/{id}/managementLogs` (the
/// single existing audit-log source of truth — see
/// AnimalRecordRepository.streamManagementLogs) — both the Management tab's
/// own "View Logs" action and the record header's overflow "View Logs" open
/// this same widget, so there is exactly one rendering of the log, not two
/// subtly different ones.
///
/// Not claimed as tamper-proof: this repo has no committed
/// `firestore.rules` file, so whether an ordinary (non-admin) user could
/// write directly to this subcollection is enforced — or not — entirely by
/// whatever security rules are configured outside this codebase, not by
/// anything here.
Future<void> showAnimalLogsSheet(BuildContext context, {required String animalId}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => AnimalLogsSheet(animalId: animalId),
  );
}

class AnimalLogsSheet extends ConsumerWidget {
  final String animalId;
  const AnimalLogsSheet({super.key, required this.animalId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(managementLogsProvider(animalId));
    // .value (not .asData?.value) carries the last-known list forward
    // through a transient reload, same rationale as the dashboard's own
    // stream providers.
    final logs = logsAsync.value ?? const <Map<String, dynamic>>[];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Animal Logs', style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
              'Newest first. Write access to this history depends on your Firebase security rules, not on this screen.',
              style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            if (!logsAsync.hasValue && logsAsync.isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(color: AppColors.greenrspwn)),
              )
            else if (logs.isEmpty && logsAsync.hasError)
              Text('Could not load logs: ${logsAsync.error}', style: GoogleFonts.zain(fontSize: 13, color: Colors.redAccent))
            else if (logs.isEmpty)
              Text('No actions recorded yet.', style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary))
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => const Divider(height: 20),
                  itemBuilder: (context, i) => _LogEntryTile(log: logs[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatefulWidget {
  final Map<String, dynamic> log;
  const _LogEntryTile({required this.log});

  @override
  State<_LogEntryTile> createState() => _LogEntryTileState();
}

class _LogEntryTileState extends State<_LogEntryTile> {
  bool _expanded = false;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _fmtTimestamp(dynamic ts) {
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
    final hour12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final minute = d.minute.toString().padLeft(2, '0');
    return '${_months[d.month - 1]} ${d.day}, ${d.year}, $hour12:$minute $ampm';
  }

  /// "Admin Maria · maria@example.com" — falls back to whichever half is
  /// actually on file rather than showing a raw UID or nothing at all.
  String? _actorLine(Map<String, dynamic> log) {
    final name = (log['actorName'] as String?)?.trim();
    final email = (log['actorEmail'] as String?)?.trim();
    final hasName = name != null && name.isNotEmpty;
    final hasEmail = email != null && email.isNotEmpty;
    if (hasName && hasEmail) return '$name · $email';
    if (hasName) return name;
    if (hasEmail) return email;
    return null;
  }

  String _formatValues(Map map) =>
      map.entries.map((e) => '${e.key}: ${e.value ?? '—'}').join('  ·  ');

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final previousValues = log['previousValues'] as Map?;
    final newValues = log['newValues'] as Map?;
    final hasValues = (previousValues?.isNotEmpty ?? false) || (newValues?.isNotEmpty ?? false);
    final actorLine = _actorLine(log);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(log['action'] as String? ?? '-',
                      style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  if ((log['details'] as String?)?.isNotEmpty ?? false)
                    Text(log['details'] as String, style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
                  if (actorLine != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(actorLine, style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(_fmtTimestamp(log['timestamp']),
                style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
          ],
        ),
        if (hasValues) ...[
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_expanded ? 'Hide details' : 'View details',
                      style: GoogleFonts.zain(fontSize: 11, color: AppColors.greenrspwn, decoration: TextDecoration.underline)),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more, size: 16, color: AppColors.greenrspwn),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (previousValues?.isNotEmpty ?? false)
                    Text('Before — ${_formatValues(previousValues!)}',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                  if (newValues?.isNotEmpty ?? false)
                    Text('After — ${_formatValues(newValues!)}',
                        style: GoogleFonts.zain(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
