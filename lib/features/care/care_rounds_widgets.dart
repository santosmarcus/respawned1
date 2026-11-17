import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:respawnd1/app_theme.dart';
import 'package:respawnd1/core/utils/app_date_format.dart';
import 'package:respawnd1/features/care/care_rounds.dart';

/// Today's care rounds for [organizationId]: every area's tasks with who
/// ticked them and when, and who is on shift today. Carers (Care tasks
/// screen) and staff (dashboard Shelter care card) both tick here.
///
/// With [compact], only the progress, the open tasks and today's shifts are
/// shown, with a button to the full checklist.
class CareRoundsChecklist extends ConsumerWidget {
  const CareRoundsChecklist({
    super.key,
    required this.organizationId,
    this.compact = false,
    this.canEditSetup = false,
  });

  final String organizationId;
  final bool compact;
  final bool canEditSetup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final setupAsync = ref.watch(careSetupProvider(organizationId));
    final roundAsync = ref.watch(careRoundProvider(careRoundKey(organizationId, today)));

    if (setupAsync.hasError || roundAsync.hasError) {
      return _muted('Could not load today’s care rounds.');
    }
    final setup = setupAsync.asData?.value;
    final round = roundAsync.asData?.value;
    if (setup == null || round == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }

    final total = setup.roundKeys.length;
    final done = round.doneCount(setup);
    final open = [
      for (final a in setup.areas)
        for (final t in setup.tasks)
          if (!round.done.containsKey(roundKey(a.id, t.id))) (area: a, task: t),
    ];

    final header = Row(
      children: [
        Expanded(
          child: Text(
            total == 0 ? 'No round tasks set' : '$done of $total done today',
            style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
        ),
        if (canEditSetup)
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => CareRosterPage(organizationId: organizationId)),
            ),
            child: Text('Roster & tasks',
                style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
      ],
    );

    final progress = ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: total == 0 ? 0 : done / total,
        minHeight: 8,
        backgroundColor: const Color(0xFFE6E3DA),
        color: done == total && total > 0 ? AppColors.greenrspwn : AppColors.yellowrspwn,
      ),
    );

    final shifts = _TodayShifts(setup: setup, day: today);

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          progress,
          const SizedBox(height: 6),
          shifts,
          if (open.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Still open: ${open.take(4).map((o) => setup.areas.length > 1 ? '${o.task.label} (${o.area.label})' : o.task.label).join(', ')}'
              '${open.length > 4 ? ' +${open.length - 4} more' : ''}',
              style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CareRoundsPage(organizationId: organizationId, canEditSetup: canEditSetup),
                ),
              ),
              icon: const Icon(Icons.checklist, size: 16, color: AppColors.textPrimary),
              label: Text('Open today’s checklist',
                  style: GoogleFonts.zain(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        progress,
        const SizedBox(height: 6),
        shifts,
        for (final a in setup.areas) ...[
          if (setup.areas.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 2),
              child: Text(a.label, style: GoogleFonts.tiltWarp(fontSize: 14, color: AppColors.textPrimary)),
            ),
          for (final t in setup.tasks)
            _TaskTile(
              organizationId: organizationId,
              day: today,
              keyName: roundKey(a.id, t.id),
              label: t.label,
              tick: round.done[roundKey(a.id, t.id)],
            ),
        ],
      ],
    );
  }

  static Widget _muted(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text, style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
      );
}

class _TodayShifts extends StatelessWidget {
  const _TodayShifts({required this.setup, required this.day});
  final CareSetup setup;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    if (!setup.hasRoster) {
      return Text('Carer roster not set', style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary));
    }
    return Wrap(
      spacing: 10,
      runSpacing: 2,
      children: [
        for (final s in setup.shifts)
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${s.label}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(
                text: setup.onShift(day.weekday, s.id).isEmpty
                    ? 'no one'
                    : setup.onShift(day.weekday, s.id).map((e) => e.name).join(', '),
                style: TextStyle(color: setup.onShift(day.weekday, s.id).isEmpty ? AppColors.error : null),
              ),
            ]),
            style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textPrimary),
          ),
      ],
    );
  }
}

class _TaskTile extends StatefulWidget {
  const _TaskTile({
    required this.organizationId,
    required this.day,
    required this.keyName,
    required this.label,
    required this.tick,
  });

  final String organizationId;
  final DateTime day;
  final String keyName;
  final String label;
  final RoundTick? tick;

  @override
  State<_TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends State<_TaskTile> {
  bool _busy = false;

  Future<void> _toggle(bool on) async {
    setState(() => _busy = true);
    try {
      final svc = CareRoundsService(widget.organizationId);
      if (on) {
        await svc.tick(widget.day, widget.keyName);
      } else {
        await svc.untick(widget.day, widget.keyName);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tick;
    return CheckboxListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      activeColor: AppColors.textPrimary,
      value: t != null,
      onChanged: _busy ? null : (v) => _toggle(v ?? false),
      title: Text(widget.label,
          style: GoogleFonts.zain(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      subtitle: t == null
          ? null
          : Text('${t.byName}${t.at == null ? '' : ' · ${formatTime(t.at!)}'}',
              style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary)),
    );
  }
}

/// Full-screen checklist (from the dashboard).
class CareRoundsPage extends StatelessWidget {
  const CareRoundsPage({super.key, required this.organizationId, this.canEditSetup = false});
  final String organizationId;
  final bool canEditSetup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Today’s care rounds', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(formatDate(DateTime.now()), style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          CareRoundsChecklist(organizationId: organizationId, canEditSetup: canEditSetup),
        ],
      ),
    );
  }
}

// ─── Roster & tasks (admins) ─────────────────────────────────────────────

class CareRosterPage extends ConsumerStatefulWidget {
  const CareRosterPage({super.key, required this.organizationId});
  final String organizationId;

  @override
  ConsumerState<CareRosterPage> createState() => _CareRosterPageState();
}

class _CareRosterPageState extends ConsumerState<CareRosterPage> {
  CareSetup? _draft;
  bool _dirty = false;
  bool _saving = false;

  void _edit(CareSetup next) => setState(() {
        _draft = next;
        _dirty = true;
      });

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    setState(() => _saving = true);
    try {
      await CareRoundsService(widget.organizationId).saveSetup(d);
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Roster and tasks saved.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save. Only organization admins can change the roster. ($e)'),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _askLabel(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.sentences),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim().isEmpty ? null : c.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPeople(CareSetup d, int weekday, CareShift shift) async {
    final candidates = await ref.read(rosterCandidatesProvider(widget.organizationId).future);
    if (!mounted) return;
    final current = {...d.onShift(weekday, shift.id)};
    final picked = await showDialog<Set<RosterEntry>>(
      context: context,
      builder: (ctx) => _PeopleDialog(
        title: '${kWeekdayShort[weekday - 1]} · ${shift.label}',
        candidates: candidates,
        selected: current,
      ),
    );
    if (picked == null) return;
    _edit(d.copyWith(roster: {...d.roster, rosterKey(weekday, shift.id): picked.toList()}));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(careSetupProvider(widget.organizationId));
    final loaded = async.asData?.value;
    if (_draft == null && loaded != null) _draft = loaded;
    final d = _draft;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        title: Text('Care roster & tasks', style: GoogleFonts.tiltWarp(color: AppColors.textPrimary)),
        actions: [
          TextButton(
            onPressed: !_dirty || _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save',
                style: GoogleFonts.zain(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ],
      ),
      body: d == null
          ? (async.hasError
              ? Center(child: Text('Could not load: ${async.error}'))
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!d.saved)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'These are starting suggestions. Change them to match your shelter, then save.',
                      style: GoogleFonts.zain(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ),
                _sectionTitle('Weekly roster', 'Tap a shift to choose who is on it. An empty shift makes '
                    '“Care coverage” read Constrained on the dashboard.'),
                _RosterGrid(setup: d, onTap: (w, s) => _pickPeople(d, w, s)),
                const SizedBox(height: 18),
                _sectionTitle('Shelter areas', 'Each area gets its own copy of the round tasks.'),
                _EditableList(
                  items: [for (final a in d.areas) (id: a.id, label: a.label)],
                  minItems: 1,
                  onAdd: () async {
                    final l = await _askLabel('New area');
                    if (l == null) return;
                    _edit(d.copyWith(areas: [...d.areas, CareArea(careId(l, d.areas.map((a) => a.id)), l)]));
                  },
                  onRename: (id) async {
                    final a = d.areas.firstWhere((a) => a.id == id);
                    final l = await _askLabel('Rename area', initial: a.label);
                    if (l == null) return;
                    _edit(d.copyWith(areas: [for (final x in d.areas) x.id == id ? CareArea(id, l) : x]));
                  },
                  onRemove: (id) => _edit(d.copyWith(areas: d.areas.where((a) => a.id != id).toList())),
                ),
                const SizedBox(height: 18),
                _sectionTitle('Round tasks', 'Ticked once a day per area.'),
                _EditableList(
                  items: [for (final t in d.tasks) (id: t.id, label: t.label)],
                  minItems: 1,
                  onAdd: () async {
                    final l = await _askLabel('New task');
                    if (l == null) return;
                    _edit(d.copyWith(tasks: [...d.tasks, CareTask(careId(l, d.tasks.map((t) => t.id)), l)]));
                  },
                  onRename: (id) async {
                    final t = d.tasks.firstWhere((t) => t.id == id);
                    final l = await _askLabel('Rename task', initial: t.label);
                    if (l == null) return;
                    _edit(d.copyWith(tasks: [for (final x in d.tasks) x.id == id ? CareTask(id, l) : x]));
                  },
                  onRemove: (id) => _edit(d.copyWith(tasks: d.tasks.where((t) => t.id != id).toList())),
                ),
                const SizedBox(height: 18),
                _sectionTitle('Shifts', 'Names only; times are shown on the checklist.'),
                _EditableList(
                  items: [for (final s in d.shifts) (id: s.id, label: '${s.label}  ${s.start}–${s.end}')],
                  minItems: 1,
                  onAdd: () async {
                    final l = await _askLabel('New shift name');
                    if (l == null) return;
                    _edit(d.copyWith(
                        shifts: [...d.shifts, CareShift(careId(l, d.shifts.map((s) => s.id)), l, '', '')]));
                  },
                  onRename: (id) async {
                    final s = d.shifts.firstWhere((s) => s.id == id);
                    final l = await _askLabel('Rename shift (and times, e.g. "Morning 06:00-14:00")',
                        initial: '${s.label} ${s.start}-${s.end}'.trim());
                    if (l == null) return;
                    final m = RegExp(r'^(.*?)\s*(\d{1,2}:\d{2})\s*[-–]\s*(\d{1,2}:\d{2})$').firstMatch(l);
                    final next = m == null
                        ? CareShift(id, l, s.start, s.end)
                        : CareShift(id, m.group(1)!.trim().isEmpty ? s.label : m.group(1)!.trim(), m.group(2)!, m.group(3)!);
                    _edit(d.copyWith(shifts: [for (final x in d.shifts) x.id == id ? next : x]));
                  },
                  onRemove: (id) => _edit(d.copyWith(
                    shifts: d.shifts.where((s) => s.id != id).toList(),
                    roster: {
                      for (final e in d.roster.entries)
                        if (!e.key.endsWith('_$id')) e.key: e.value,
                    },
                  )),
                ),
                if (d.updatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      'Last saved ${formatDateTime(d.updatedAt!)}${d.updatedByName == null ? '' : ' by ${d.updatedByName}'}',
                      style: GoogleFonts.zain(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String title, String help) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: GoogleFonts.tiltWarp(fontSize: 15, color: AppColors.textPrimary)),
            Text(help, style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textSecondary)),
          ],
        ),
      );
}

class _RosterGrid extends StatelessWidget {
  const _RosterGrid({required this.setup, required this.onTap});
  final CareSetup setup;
  final void Function(int weekday, CareShift shift) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          for (var w = 1; w <= 7; w++)
            Container(
              decoration: BoxDecoration(
                border: w == 7 ? null : Border(bottom: BorderSide(color: AppColors.textPrimary.withValues(alpha: 0.10))),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 40,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(kWeekdayShort[w - 1],
                          style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in setup.shifts)
                          ActionChip(
                            onPressed: () => onTap(w, s),
                            backgroundColor: setup.onShift(w, s.id).isEmpty
                                ? AppColors.error.withValues(alpha: 0.08)
                                : AppColors.background,
                            side: BorderSide(
                              color: setup.onShift(w, s.id).isEmpty
                                  ? AppColors.error.withValues(alpha: 0.4)
                                  : AppColors.textPrimary.withValues(alpha: 0.2),
                            ),
                            label: Text(
                              '${s.label}: ${setup.onShift(w, s.id).isEmpty ? 'no one' : setup.onShift(w, s.id).map((e) => e.name.split(' ').first).join(', ')}',
                              style: GoogleFonts.zain(fontSize: 12.5, color: AppColors.textPrimary),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EditableList extends StatelessWidget {
  const _EditableList({
    required this.items,
    required this.onAdd,
    required this.onRename,
    required this.onRemove,
    this.minItems = 0,
  });

  final List<({String id, String label})> items;
  final VoidCallback onAdd;
  final void Function(String id) onRename;
  final void Function(String id) onRemove;
  final int minItems;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in items)
          Card(
            color: AppColors.surface,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(i.label, style: GoogleFonts.zain(fontSize: 15, color: AppColors.textPrimary)),
              onTap: () => onRename(i.id),
              trailing: IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.close, size: 18),
                onPressed: items.length <= minItems ? null : () => onRemove(i.id),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18, color: AppColors.textPrimary),
            label: Text('Add', style: GoogleFonts.zain(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
        ),
      ],
    );
  }
}

class _PeopleDialog extends StatefulWidget {
  const _PeopleDialog({required this.title, required this.candidates, required this.selected});
  final String title;
  final List<({RosterEntry entry, String role})> candidates;
  final Set<RosterEntry> selected;

  @override
  State<_PeopleDialog> createState() => _PeopleDialogState();
}

class _PeopleDialogState extends State<_PeopleDialog> {
  late final Set<RosterEntry> _sel = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: widget.candidates.isEmpty
            ? const Text('No active members in this organization yet.')
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final c in widget.candidates)
                    CheckboxListTile(
                      dense: true,
                      value: _sel.contains(c.entry),
                      onChanged: (v) => setState(() => v == true ? _sel.add(c.entry) : _sel.remove(c.entry)),
                      title: Text(c.entry.name),
                      subtitle: Text(c.role[0].toUpperCase() + c.role.substring(1)),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _sel), child: const Text('Done')),
      ],
    );
  }
}
