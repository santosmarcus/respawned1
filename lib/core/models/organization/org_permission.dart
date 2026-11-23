import 'package:respawnd1/core/constants/feature_flags.dart';

/// What an organization's Staff member may do. Admins and the owner have
/// every permission. Mirrors functions/org_permissions.json (kept in step by
/// test/core/models/org_permission_sync_test.dart), which functions and
/// firestore.rules also follow — the app only uses these to decide what to
/// show; the backend enforces them.
enum OrgPermission {
  rescue('Rescue cases', 'Review, accept, assign, refer and close rescue reports; collar tags.', OrgPermissionGroup.operations),
  animals('Animal records & medical', 'Create and edit animal records, medical history and medication plans.',
      OrgPermissionGroup.operations),
  care('Daily care', 'Record doses, add care updates, tick care rounds, manage stock.', OrgPermissionGroup.operations),
  adoptions('Adoptions', 'Applications, interviews, release, follow-ups and returns.', OrgPermissionGroup.operations),
  campaigns('Fundraising campaigns', 'Create and edit listings, post updates, handle in-kind donations.',
      OrgPermissionGroup.money),
  financeView('View donations & funds', 'Donor records, campaign history, fund transfers and case expenses.',
      OrgPermissionGroup.money),
  financeManage('Manage money',
      'Record, allocate and refund donations; approve expenses; settle payments; general expenses and staff pay.',
      OrgPermissionGroup.money),
  // Rescue volunteers are left out of the wording while they're off
  // (FeatureFlags.independentRescuersEnabled).
  volunteers(
      FeatureFlags.independentRescuersEnabled
          ? 'Events, rescue volunteers & transporters'
          : 'Events & transporters',
      FeatureFlags.independentRescuersEnabled
          ? 'Events and their volunteers, external rescue volunteers and transporter verification.'
          : 'Events and their volunteers, and transporter verification.',
      OrgPermissionGroup.other),
  insights('Analytics & audit', 'Dashboard analytics, reports and the audit log.', OrgPermissionGroup.other),
  facebookPublish('Post to Facebook', 'Share animal records to the organization\'s Facebook Page.',
      OrgPermissionGroup.other);

  const OrgPermission(this.label, this.description, this.group);

  final String label;
  final String description;
  final OrgPermissionGroup group;

  /// The key stored in `members/{uid}.permissions`.
  String get key => name;

  static OrgPermission? fromKey(String? key) {
    for (final p in values) {
      if (p.name == key) return p;
    }
    return null;
  }
}

enum OrgPermissionGroup {
  operations('Operations'),
  money('Money'),
  other('Other');

  const OrgPermissionGroup(this.label);
  final String label;
}

/// The one default Staff permission set, and [custom] for any member whose
/// boxes differ from it. Carers were merged into Staff, and money
/// permissions (campaigns, donations, managing money) and Facebook posting
/// are never in the default: an Admin ticks them by hand.
enum OrgPreset {
  staff('Default', {
    OrgPermission.rescue,
    OrgPermission.animals,
    OrgPermission.care,
    OrgPermission.adoptions,
    OrgPermission.volunteers,
    OrgPermission.insights,
  }),
  custom('Custom', {});

  const OrgPreset(this.label, this.permissions);

  final String label;
  final Set<OrgPermission> permissions;

  /// The named sets (everything but [custom]).
  static List<OrgPreset> get choices => values.where((p) => p != custom).toList();

  /// [staff] when these are exactly the default permissions, else [custom].
  static OrgPreset matching(Set<OrgPermission> perms) {
    for (final p in choices) {
      if (p.permissions.length == perms.length && p.permissions.containsAll(perms)) return p;
    }
    return custom;
  }

  static OrgPreset? fromName(String? name) {
    for (final p in values) {
      if (p.name == name) return p;
    }
    return null;
  }
}

/// [OrgPermission.financeManage] always brings [OrgPermission.financeView].
Set<OrgPermission> normalizePermissions(Iterable<OrgPermission> perms) {
  final out = {...perms};
  if (out.contains(OrgPermission.financeManage)) out.add(OrgPermission.financeView);
  return out;
}

/// A Staff member's permissions from their members doc, with the same legacy
/// fallback as functions/org_access.js and firestore.rules: an explicit
/// `permissions` list wins; any other Staff, the old role 'carer' and no
/// members doc get the default set, plus Facebook posting when the old
/// `facebookPublisher` flag is set. Unknown keys are ignored.
Set<OrgPermission> staffPermissionsFrom(Map<String, dynamic>? member) {
  final raw = member?['permissions'];
  if (raw is List) {
    return normalizePermissions(raw.map((k) => OrgPermission.fromKey(k as String?)).whereType<OrgPermission>());
  }
  return {
    ...OrgPreset.staff.permissions,
    if (member?['facebookPublisher'] == true) OrgPermission.facebookPublish,
  };
}

/// How a Staff member is described in the app: "Staff" with the default
/// set, "Staff · Custom access" otherwise.
String staffTitle(OrgPreset? preset) =>
    preset == null || preset == OrgPreset.staff ? 'Staff' : 'Staff · Custom access';

/// What kind of organization: a shelter or rescue group, or an independent
/// rescuer (one person or a small team) with fewer modules, a member cap and
/// case capacity. `organizations/{id}.kind`; missing means [shelter].
enum OrgKind {
  shelter,
  independent;

  static OrgKind fromName(String? name) => name == 'independent' ? independent : shelter;
}

/// Limits for independent rescuers. Mirrors `independent` in
/// functions/org_permissions.json.
class IndependentRescuer {
  const IndependentRescuer._();

  /// The most a system admin may turn on for an independent rescuer.
  static const allowed = {
    OrgPermission.rescue,
    OrgPermission.animals,
    OrgPermission.care,
    OrgPermission.adoptions,
    OrgPermission.insights,
  };

  /// What an independent rescuer has until a system admin changes it.
  static const defaults = {OrgPermission.rescue, OrgPermission.animals, OrgPermission.care};

  static const memberCap = 5;
  static const maxActiveCases = 3;
  static const maxAnimalsInCare = 5;
  static const minRadiusKm = 1.0;
  static const maxRadiusKm = 5.0;
  static const defaultRadiusKm = 3.0;

  /// How long shelters alone see a new non-critical report.
  static const headStartMinutes = 15;
}

/// The permissions an organization has at all, from its document: every
/// permission for a shelter; for an independent rescuer its
/// `enabledPermissions` (set by a system admin), else the defaults, never
/// more than [IndependentRescuer.allowed].
Set<OrgPermission> orgEnabledPermissions(Map<String, dynamic>? org) {
  if (OrgKind.fromName(org?['kind'] as String?) != OrgKind.independent) return OrgPermission.values.toSet();
  final raw = org?['enabledPermissions'];
  final listed = raw is List
      ? raw.map((k) => OrgPermission.fromKey(k as String?)).whereType<OrgPermission>().toSet()
      : IndependentRescuer.defaults;
  return listed.intersection(IndependentRescuer.allowed);
}

/// Permissions in the stored order (the enum order), for writes and display.
List<String> permissionKeys(Iterable<OrgPermission> perms) =>
    OrgPermission.values.where(perms.contains).map((p) => p.key).toList();
