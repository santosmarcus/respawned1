/// How much the organization is expected to do for a report
/// (`cases/{id}.orgInvolvement`). Mirrored in functions/org_involvement.js.
///
/// * [orgAssist]: the reporter asks the organization to act (every stray
///   rescue type, and Neglect or Abuse when the reporter asks for help).
///   Reports saved before this field existed read as this, which is how
///   they were treated.
/// * [independentReport]: Neglect or Abuse where the reporter takes the
///   complaint to the authorities themselves, with the app's guide. Staff
///   see it, but it is not organization workload until they take it on.
/// * [notFacilitated]: Pet Surrender. The organization does not facilitate
///   surrenders; the report is informational and never organization
///   workload unless staff take it on.
enum OrgInvolvement {
  orgAssist('org_assist'),
  independentReport('independent_report'),
  notFacilitated('not_org_facilitated');

  const OrgInvolvement(this.firestoreValue);
  final String firestoreValue;

  static OrgInvolvement fromFirestoreValue(Object? value) {
    for (final v in values) {
      if (v.firestoreValue == value) return v;
    }
    return orgAssist;
  }

  /// Short label for chips and filters.
  String get label => switch (this) {
        OrgInvolvement.orgAssist => 'Organization assistance',
        OrgInvolvement.independentReport => 'Reporter-led report',
        OrgInvolvement.notFacilitated => 'Not org-facilitated',
      };

  String get description => switch (this) {
        OrgInvolvement.orgAssist => 'The reporter asked the organization to help.',
        OrgInvolvement.independentReport =>
          'The reporter is taking the complaint to the authorities themselves. '
              'Assist only if your capacity and coverage allow.',
        OrgInvolvement.notFacilitated =>
          'The organization does not facilitate this type of report. '
              'It is shown for awareness only.',
      };

  /// Whether the report needs an urgency rating. Surrenders are not
  /// emergencies the organization triages, so they carry none.
  bool get ratesUrgency => this != OrgInvolvement.notFacilitated;
}

const String kRescueTypePetSurrender = 'Pet Surrender';
const String kRescueTypeLostPet = 'Lost Pet';
const String kRescueTypeNeglectAbuse = 'Neglect or Abuse';

/// Neglect or Abuse: the path the reporter chose
/// (`cases/{id}.abuseReportPath`).
const String kAbusePathOrgAssistance = 'org_assistance';
const String kAbusePathIndependent = 'independent';

/// Rescue types the organization does not facilitate. Lost Pet reports go
/// to the community lost-and-found board (petAlerts), never a case.
bool isNonOrgFacilitatedRescueType(String? type) =>
    type == kRescueTypePetSurrender || type == kRescueTypeLostPet;

/// What a new report's `orgInvolvement` should be.
OrgInvolvement orgInvolvementFor({required String? rescueType, String? abuseReportPath}) {
  if (isNonOrgFacilitatedRescueType(rescueType)) return OrgInvolvement.notFacilitated;
  if (rescueType == kRescueTypeNeglectAbuse && abuseReportPath == kAbusePathIndependent) {
    return OrgInvolvement.independentReport;
  }
  return OrgInvolvement.orgAssist;
}

/// Whether a case belongs in the organization's operational workload
/// (dashboard counts, alerts, escalations). Reporter-led and
/// not-facilitated reports only become workload once staff take them on,
/// i.e. once they are no longer waiting in review.
bool countsAsOrgWorkload({required Object? orgInvolvement, required String? status}) {
  final inv = OrgInvolvement.fromFirestoreValue(orgInvolvement);
  if (inv == OrgInvolvement.orgAssist) return true;
  return !const {'pending', 'verifying'}.contains(status);
}
