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
  volunteers('Volunteers, events & transporters', 'Events, volunteer applications and transporter verification.',
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

/// Starting points an Admin picks for a Staff member; changing any box makes
/// the member [custom].
enum OrgPreset {
  fullStaff('Full staff', {
    OrgPermission.rescue,
    OrgPermission.animals,
    OrgPermission.care,
    OrgPermission.adoptions,
    OrgPermission.campaigns,
    OrgPermission.financeView,
    OrgPermission.volunteers,
    OrgPermission.insights,
  }),
  rescueCoordinator('Rescue coordinator', {
    OrgPermission.rescue,
    OrgPermission.animals,
    OrgPermission.care,
    OrgPermission.insights,
  }),
  animalCare('Animal care', {OrgPermission.care}),
  adoptionsOfficer('Adoptions officer', {OrgPermission.adoptions, OrgPermission.animals, OrgPermission.care}),
  treasurer('Treasurer', {
    OrgPermission.campaigns,
    OrgPermission.financeView,
    OrgPermission.financeManage,
    OrgPermission.insights,
  }),
  custom('Custom', {});

  const OrgPreset(this.label, this.permissions);

  final String label;
  final Set<OrgPermission> permissions;

  /// The presets an Admin can choose (everything but [custom]).
  static List<OrgPreset> get choices => values.where((p) => p != custom).toList();

  /// The preset with exactly these permissions, or [custom].
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
/// `permissions` list wins; role 'carer' is Animal care; any other Staff
/// (or no members doc) is Full staff, plus Facebook posting when the old
/// `facebookPublisher` flag is set. Unknown keys are ignored.
Set<OrgPermission> staffPermissionsFrom(Map<String, dynamic>? member) {
  final raw = member?['permissions'];
  if (raw is List) {
    return normalizePermissions(raw.map((k) => OrgPermission.fromKey(k as String?)).whereType<OrgPermission>());
  }
  if (member?['role'] == 'carer') return {...OrgPreset.animalCare.permissions};
  return {
    ...OrgPreset.fullStaff.permissions,
    if (member?['facebookPublisher'] == true) OrgPermission.facebookPublish,
  };
}

/// Permissions in the stored order (the enum order), for writes and display.
List<String> permissionKeys(Iterable<OrgPermission> perms) =>
    OrgPermission.values.where(perms.contains).map((p) => p.key).toList();
