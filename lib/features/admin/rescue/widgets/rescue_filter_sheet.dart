import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/features/admin/rescue/state/rescue_reports_providers.dart';

/// Bottom sheet for the Rescue Reports list: urgency, status, species,
/// date range, and location filters. Status here reaches the
/// referred/possibleDuplicate/merged/rejected/completed/cancelled buckets
/// the five pipeline tabs don't cover; picking one overrides the active tab.
Future<void> showRescueFilterSheet(BuildContext context, {
  required RescueFilters current,
  required void Function(RescueFilters) onApply,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _RescueFilterSheetBody(current: current, onApply: onApply),
  );
}

class _RescueFilterSheetBody extends StatefulWidget {
  final RescueFilters current;
  final void Function(RescueFilters) onApply;
  const _RescueFilterSheetBody({required this.current, required this.onApply});

  @override
  State<_RescueFilterSheetBody> createState() => _RescueFilterSheetBodyState();
}

class _RescueFilterSheetBodyState extends State<_RescueFilterSheetBody> {
  late UrgencyLevel? _urgency = widget.current.urgency;
  late RescueStatus? _status = widget.current.statusOverride;
  late final TextEditingController _species =
      TextEditingController(text: widget.current.species ?? '');
  late final TextEditingController _location =
      TextEditingController(text: widget.current.locationQuery ?? '');
  late DateTime? _fromDate = widget.current.fromDate;
  late DateTime? _toDate = widget.current.toDate;

  @override
  void dispose() {
    _species.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _fromDate : _toDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  String _dateLabel(DateTime? d) =>
      d == null ? 'Any' : '${d.month}/${d.day}/${d.year}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.slaterspwn,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Filter Reports',
                style: GoogleFonts.tiltWarp(fontSize: 17, color: AppColors.textPrimary)),
            const SizedBox(height: 18),

            Text('Urgency',
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _choiceChip('Any', _urgency == null, () => setState(() => _urgency = null)),
                for (final level in UrgencyLevel.values)
                  _choiceChip(
                    level.firestoreValue,
                    _urgency == level,
                    () => setState(() => _urgency = level),
                  ),
              ],
            ),
            const SizedBox(height: 18),

            Text('Status',
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _choiceChip('Any (current tab)', _status == null, () => setState(() => _status = null)),
                for (final s in kSecondaryStatuses)
                  _choiceChip(s.label, _status == s, () => setState(() => _status = s)),
              ],
            ),
            const SizedBox(height: 18),

            Text('Species',
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: _species,
              decoration: InputDecoration(
                hintText: 'e.g. Dog, Cat',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 18),

            Text('Date reported',
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isFrom: true),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.slaterspwn),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('From: ${_dateLabel(_fromDate)}',
                        style: GoogleFonts.zain(fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickDate(isFrom: false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.slaterspwn),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text('To: ${_dateLabel(_toDate)}',
                        style: GoogleFonts.zain(fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            Text('Location',
                style: GoogleFonts.zain(
                    fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            TextField(
              controller: _location,
              decoration: InputDecoration(
                hintText: 'e.g. Malate, Manila',
                hintStyle: GoogleFonts.zain(color: AppColors.textSecondary, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.only(bottom: 8),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.textPrimary, width: 1.5),
                ),
              ),
              style: GoogleFonts.zain(fontSize: 14, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 28),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      widget.onApply(const RescueFilters());
                      Navigator.pop(context);
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.textPrimary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Clear All', style: GoogleFonts.tiltWarp(fontSize: 15)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      widget.onApply(
                        widget.current.copyWith(
                          urgency: _urgency,
                          clearUrgency: _urgency == null,
                          species: _species.text.trim(),
                          clearSpecies: _species.text.trim().isEmpty,
                          fromDate: _fromDate,
                          toDate: _toDate,
                          clearDateRange: _fromDate == null && _toDate == null,
                          locationQuery: _location.text.trim(),
                          clearLocationQuery: _location.text.trim().isEmpty,
                          statusOverride: _status,
                          clearStatusOverride: _status == null,
                        ),
                      );
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.yellowrspwn,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Apply',
                        style:
                            GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _choiceChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.zain(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: AppColors.yellowrspwn,
      backgroundColor: Colors.white,
      side: const BorderSide(color: AppColors.slaterspwn),
      labelStyle: GoogleFonts.zain(
        fontSize: 12,
        color: AppColors.textPrimary,
        fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
      ),
    );
  }
}
