import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Dashboard gaps 2 and 3: daily care rounds and the carer roster.
///
/// Setup (areas, round tasks, shifts and the weekly roster) lives in
/// `organizations/{orgId}/settings/care`: the organization's admins change
/// it, its staff and carers read it (firestore.rules). Each day's ticks are
/// `organizations/{orgId}/careRounds/{yyyy-MM-dd}`, field
/// `done.<areaId>__<taskId>` = who ticked it and when; staff and carers of
/// the organization write them.
///
/// Nothing here guesses: an organization with no roster reads "not set",
/// never "covered".

class CareArea {
  final String id;
  final String label;
  const CareArea(this.id, this.label);

  Map<String, dynamic> toMap() => {'id': id, 'label': label};
  static CareArea? fromMap(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], label = m['label'];
    if (id is! String || id.isEmpty || label is! String) return null;
    return CareArea(id, label);
  }
}

class CareTask {
  final String id;
  final String label;
  const CareTask(this.id, this.label);

  Map<String, dynamic> toMap() => {'id': id, 'label': label};
  static CareTask? fromMap(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], label = m['label'];
    if (id is! String || id.isEmpty || label is! String) return null;
    return CareTask(id, label);
  }
}

class CareShift {
  final String id;
  final String label;

  /// 'HH:mm', for display only.
  final String start;
  final String end;
  const CareShift(this.id, this.label, this.start, this.end);

  Map<String, dynamic> toMap() => {'id': id, 'label': label, 'start': start, 'end': end};
  static CareShift? fromMap(Object? m) {
    if (m is! Map) return null;
    final id = m['id'], label = m['label'];
    if (id is! String || id.isEmpty || label is! String) return null;
    return CareShift(id, label, (m['start'] as String?) ?? '', (m['end'] as String?) ?? '');
  }
}

class RosterEntry {
  final String uid;
  final String name;
  const RosterEntry(this.uid, this.name);

  Map<String, dynamic> toMap() => {'uid': uid, 'name': name};
  static RosterEntry? fromMap(Object? m) {
    if (m is! Map) return null;
    final uid = m['uid'];
    if (uid is! String || uid.isEmpty) return null;
    return RosterEntry(uid, (m['name'] as String?) ?? 'Carer');
  }

  @override
  bool operator ==(Object other) => other is RosterEntry && other.uid == uid;
  @override
  int get hashCode => uid.hashCode;
}

/// Weekday names, Monday = 1 as in [DateTime.weekday].
const kWeekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Roster key for a weekday (1-7) and shift.
String rosterKey(int weekday, String shiftId) => '${weekday}_$shiftId';

class CareSetup {
  final List<CareArea> areas;
  final List<CareTask> tasks;
  final List<CareShift> shifts;

  /// [rosterKey] → carers on that shift every week.
  final Map<String, List<RosterEntry>> roster;
  final DateTime? updatedAt;
  final String? updatedByName;

  /// False until an admin saves the setup: the defaults below are shown,
  /// and the roster is empty.
  final bool saved;

  const CareSetup({
    required this.areas,
    required this.tasks,
    required this.shifts,
    required this.roster,
    this.updatedAt,
    this.updatedByName,
    this.saved = false,
  });

  /// What an organization starts with. Pending the organization's own list.
  static const defaults = CareSetup(
    areas: [CareArea('main', 'Main shelter')],
    tasks: [
      CareTask('am_feed', 'Morning feeding'),
      CareTask('water', 'Fresh water'),
      CareTask('cleaning', 'Cleaning'),
      CareTask('pm_feed', 'Evening feeding'),
    ],
    shifts: [
      CareShift('am', 'Morning', '06:00', '14:00'),
      CareShift('pm', 'Evening', '14:00', '22:00'),
    ],
    roster: {},
  );

  bool get hasRoster => roster.values.any((l) => l.isNotEmpty);

  List<RosterEntry> onShift(int weekday, String shiftId) => roster[rosterKey(weekday, shiftId)] ?? const [];

  /// Every tick a day has: one per area and task.
  List<String> get roundKeys => [for (final a in areas) for (final t in tasks) roundKey(a.id, t.id)];

  CareSetup copyWith({
    List<CareArea>? areas,
    List<CareTask>? tasks,
    List<CareShift>? shifts,
    Map<String, List<RosterEntry>>? roster,
  }) =>
      CareSetup(
        areas: areas ?? this.areas,
        tasks: tasks ?? this.tasks,
        shifts: shifts ?? this.shifts,
        roster: roster ?? this.roster,
        updatedAt: updatedAt,
        updatedByName: updatedByName,
        saved: saved,
      );

  Map<String, dynamic> toMap() => {
        'areas': [for (final a in areas) a.toMap()],
        'tasks': [for (final t in tasks) t.toMap()],
        'shifts': [for (final s in shifts) s.toMap()],
        'roster': {
          for (final e in roster.entries)
            if (e.value.isNotEmpty) e.key: [for (final r in e.value) r.toMap()],
        },
      };

  factory CareSetup.fromMap(Map<String, dynamic>? m) {
    if (m == null) return defaults;
    List<T> list<T>(Object? raw, T? Function(Object?) parse) =>
        raw is List ? raw.map(parse).whereType<T>().toList() : <T>[];
    final areas = list(m['areas'], CareArea.fromMap);
    final tasks = list(m['tasks'], CareTask.fromMap);
    final shifts = list(m['shifts'], CareShift.fromMap);
    final rawRoster = m['roster'];
    final roster = <String, List<RosterEntry>>{};
    if (rawRoster is Map) {
      rawRoster.forEach((k, v) {
        if (k is String) roster[k] = list(v, RosterEntry.fromMap);
      });
    }
    final ts = m['updatedAt'];
    return CareSetup(
      areas: areas.isEmpty ? defaults.areas : areas,
      tasks: tasks.isEmpty ? defaults.tasks : tasks,
      shifts: shifts.isEmpty ? defaults.shifts : shifts,
      roster: roster,
      updatedAt: ts is Timestamp ? ts.toDate() : null,
      updatedByName: m['updatedByName'] as String?,
      saved: true,
    );
  }
}

/// The field name of one tick in a day's round document.
String roundKey(String areaId, String taskId) => '${areaId}__$taskId';

/// The round document id for [day] (local date).
String careDayKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

/// A short id for a new area, task or shift: letters and digits only, so it
/// is safe in a Firestore field path.
String careId(String label, Iterable<String> taken) {
  var base = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  if (base.isEmpty) base = 'item';
  if (base.length > 24) base = base.substring(0, 24);
  var id = base;
  var n = 2;
  while (taken.contains(id)) {
    id = '${base}_${n++}';
  }
  return id;
}

class RoundTick {
  final DateTime? at;
  final String? byUid;
  final String byName;
  const RoundTick({this.at, this.byUid, required this.byName});

  static RoundTick? fromMap(Object? m) {
    if (m is! Map) return null;
    final at = m['at'];
    return RoundTick(
      at: at is Timestamp ? at.toDate() : null,
      byUid: m['byUid'] as String?,
      byName: (m['byName'] as String?) ?? 'Someone',
    );
  }
}

class CareRound {
  final Map<String, RoundTick> done;
  const CareRound(this.done);
  static const empty = CareRound({});

  factory CareRound.fromMap(Map<String, dynamic>? m) {
    final raw = m?['done'];
    if (raw is! Map) return empty;
    final out = <String, RoundTick>{};
    raw.forEach((k, v) {
      final t = RoundTick.fromMap(v);
      if (k is String && t != null) out[k] = t;
    });
    return CareRound(out);
  }

  /// Ticks that count against [setup] (an area or task removed since then
  /// doesn't).
  int doneCount(CareSetup setup) => setup.roundKeys.where(done.containsKey).length;
}

/// Shifts in the next [days] days (from [from], inclusive) that have no
/// carer on the roster. Empty when every shift is covered — or when there is
/// no roster at all, which callers check with [CareSetup.hasRoster] first.
List<({DateTime day, CareShift shift})> rosterGaps(CareSetup setup, DateTime from, {int days = 7}) {
  final start = DateTime(from.year, from.month, from.day);
  return [
    for (var i = 0; i < days; i++)
      for (final s in setup.shifts)
        if (setup.onShift(start.add(Duration(days: i)).weekday, s.id).isEmpty)
          (day: start.add(Duration(days: i)), shift: s),
  ];
}

// ─── Firestore ───────────────────────────────────────────────────────────

FirebaseFirestore get _db => FirebaseFirestore.instance;

DocumentReference<Map<String, dynamic>> careSetupDoc(String orgId) =>
    _db.collection('organizations').doc(orgId).collection('settings').doc('care');

DocumentReference<Map<String, dynamic>> careRoundDoc(String orgId, DateTime day) =>
    _db.collection('organizations').doc(orgId).collection('careRounds').doc(careDayKey(day));

final careSetupProvider = StreamProvider.autoDispose.family<CareSetup, String>((ref, orgId) {
  return careSetupDoc(orgId).snapshots().map((d) => CareSetup.fromMap(d.exists ? d.data() : null));
});

/// Today's round. The key is `orgId|yyyy-MM-dd`, so the day rolls over when
/// the widget rebuilds after midnight.
final careRoundProvider = StreamProvider.autoDispose.family<CareRound, String>((ref, key) {
  final parts = key.split('|');
  return _db
      .collection('organizations')
      .doc(parts[0])
      .collection('careRounds')
      .doc(parts[1])
      .snapshots()
      .map((d) => CareRound.fromMap(d.data()));
});

String careRoundKey(String orgId, DateTime day) => '$orgId|${careDayKey(day)}';

String get _actorName {
  final u = FirebaseAuth.instance.currentUser;
  return (u?.displayName?.trim().isNotEmpty ?? false) ? u!.displayName!.trim() : (u?.email ?? 'Carer');
}

class CareRoundsService {
  CareRoundsService(this.organizationId);
  final String organizationId;

  Future<void> tick(DateTime day, String key) {
    final d = DateTime(day.year, day.month, day.day);
    return careRoundDoc(organizationId, d).set({
      'organizationId': organizationId,
      'date': Timestamp.fromDate(d),
      'done': {
        key: {
          'at': FieldValue.serverTimestamp(),
          'byUid': FirebaseAuth.instance.currentUser?.uid,
          'byName': _actorName,
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> untick(DateTime day, String key) =>
      careRoundDoc(organizationId, day).update({'done.$key': FieldValue.delete()});

  /// Admins only (firestore.rules).
  Future<void> saveSetup(CareSetup setup) {
    final u = FirebaseAuth.instance.currentUser;
    return careSetupDoc(organizationId).set({
      ...setup.toMap(),
      'organizationId': organizationId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': u?.uid,
      'updatedByName': _actorName,
    });
  }
}

/// Active members of the organization who can be put on the roster
/// (carers first, then staff and admins), from `organizations/{orgId}/members`.
final rosterCandidatesProvider = FutureProvider.autoDispose.family<List<({RosterEntry entry, String role})>, String>(
  (ref, orgId) async {
    final snap = await _db.collection('organizations').doc(orgId).collection('members').get();
    final out = <({RosterEntry entry, String role})>[];
    for (final d in snap.docs) {
      final m = d.data();
      if (const ['inactive', 'removed', 'disabled'].contains(m['status'])) continue;
      final name = (m['displayName'] as String?)?.trim();
      final email = (m['email'] as String?)?.trim();
      out.add((
        entry: RosterEntry(d.id, (name?.isNotEmpty ?? false) ? name! : (email?.isNotEmpty ?? false) ? email! : 'Member'),
        role: (m['role'] as String?) ?? 'staff',
      ));
    }
    int rank(String r) => r == 'carer' ? 0 : (r == 'staff' ? 1 : 2);
    out.sort((a, b) {
      final c = rank(a.role).compareTo(rank(b.role));
      return c != 0 ? c : a.entry.name.toLowerCase().compareTo(b.entry.name.toLowerCase());
    });
    return out;
  },
);
