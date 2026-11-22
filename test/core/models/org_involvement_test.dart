import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/org_involvement.dart';
import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/utils/urgency_assessment.dart';

void main() {
  group('orgInvolvementFor', () {
    test('surrender and lost pet are not org-facilitated', () {
      expect(orgInvolvementFor(rescueType: kRescueTypePetSurrender), OrgInvolvement.notFacilitated);
      expect(orgInvolvementFor(rescueType: kRescueTypeLostPet), OrgInvolvement.notFacilitated);
    });

    test('neglect or abuse follows the reporter\'s chosen path', () {
      expect(
        orgInvolvementFor(rescueType: kRescueTypeNeglectAbuse, abuseReportPath: kAbusePathIndependent),
        OrgInvolvement.independentReport,
      );
      expect(
        orgInvolvementFor(rescueType: kRescueTypeNeglectAbuse, abuseReportPath: kAbusePathOrgAssistance),
        OrgInvolvement.orgAssist,
      );
    });

    test('a stale independent path on another type is ignored', () {
      expect(orgInvolvementFor(rescueType: 'Injury', abuseReportPath: kAbusePathIndependent), OrgInvolvement.orgAssist);
    });
  });

  group('workload', () {
    test('org assistance is always workload', () {
      expect(countsAsOrgWorkload(orgInvolvement: 'org_assist', status: 'pending'), isTrue);
    });

    test('reporter-led and surrender reports count only once taken on', () {
      for (final v in ['independent_report', 'not_org_facilitated']) {
        expect(countsAsOrgWorkload(orgInvolvement: v, status: 'pending'), isFalse);
        expect(countsAsOrgWorkload(orgInvolvement: v, status: 'verifying'), isFalse);
        expect(countsAsOrgWorkload(orgInvolvement: v, status: 'accepted_pending_clinic'), isTrue);
      }
    });
  });

  group('older case documents', () {
    test('a report saved before these fields existed still parses as before', () {
      final c = RescueCase.fromMap('legacy', {
        'status': 'pending',
        'urgency': 'Critical',
        'rescueType': 'Injury',
      });
      expect(c.orgInvolvement, OrgInvolvement.orgAssist);
      expect(c.urgencyAssessment, isNull);
      expect(c.urgency, 'Critical');
      expect(c.countsAsOrgWorkload, isTrue);
      expect(c.independentReport, isNull);
    });

    test('new fields are read from a new report', () {
      final c = RescueCase.fromMap('new', {
        'status': 'pending',
        'urgency': 'Medium',
        'orgInvolvement': 'independent_report',
        'abuseReportPath': 'independent',
        'independentReport': {'alreadyReported': true, 'reportedTo': 'Barangay hall'},
        'urgencyAssessment': {'level': 'Medium', 'reasons': ['Underweight'], 'method': kUrgencyAssessmentMethod},
      });
      expect(c.orgInvolvement, OrgInvolvement.independentReport);
      expect(c.abuseReportPath, kAbusePathIndependent);
      expect(c.urgencyAssessment!.reasons, ['Underweight']);
      expect(c.independentReport!['reportedTo'], 'Barangay hall');
      expect(c.countsAsOrgWorkload, isFalse);
    });
  });

  test('values match functions/org_involvement.js', () {
    final js = File('functions/org_involvement.js').readAsStringSync();
    for (final v in OrgInvolvement.values) {
      expect(js, contains("'${v.firestoreValue}'"), reason: v.name);
    }
  });
}
