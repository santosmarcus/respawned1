import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/case_claim_rules.dart';

void main() {
  final now = DateTime(2026, 11, 20, 10);
  final opened = Timestamp.fromDate(now.subtract(const Duration(minutes: 1)));
  final notYet = Timestamp.fromDate(now.add(const Duration(minutes: 10)));
  const shelter = <String, dynamic>{'name': 'Shelter'};
  Map<String, dynamic> independent([Map<String, dynamic> extra = const {}]) =>
      {'kind': 'independent', 'activeCaseCount': 0, 'animalsInCareCount': 0, ...extra};
  Map<String, dynamic> pool([Map<String, dynamic> extra = const {}]) => {
        'organizationId': '',
        'status': 'pending',
        'nearbyIndependentIds': ['ind'],
        'independentsOpenAt': opened,
        ...extra,
      };

  CaseClaimException? refusal(Map<String, dynamic> c, String me, Map<String, dynamic>? org) =>
      caseClaimRefusal(caseData: c, myOrgId: me, org: org, now: now);

  test('the first organization to accept wins', () {
    expect(refusal(pool(), 'shelter', shelter), isNull);
    final taken = refusal(pool({'organizationId': 'other'}), 'shelter', shelter);
    expect(taken?.alreadyTaken, isTrue);
    expect(refusal(pool({'organizationId': 'other'}), 'ind', independent())?.alreadyTaken, isTrue);
    // Already ours (accepting again): fine.
    expect(refusal(pool({'organizationId': 'shelter'}), 'shelter', shelter), isNull);
    // Referred elsewhere.
    expect(refusal(pool({'referredToOrgId': 'x'}), 'shelter', shelter)?.alreadyTaken, isTrue);
  });

  test('shelters get the head start; independents only once the case opened to them', () {
    expect(refusal(pool({'independentsOpenAt': notYet}), 'shelter', shelter), isNull);
    expect(refusal(pool({'independentsOpenAt': notYet}), 'ind', independent())?.message, contains('first look'));
    expect(refusal(pool(), 'ind', independent()), isNull);
    expect(refusal(pool({'nearbyIndependentIds': ['someone']}), 'ind', independent())?.message,
        contains('outside your area'));
    expect(refusal(pool({'independentsOpenAt': null}), 'ind', independent())?.message, contains('outside your area'));
  });

  test('a case referred to an independent needs no head start', () {
    final referred = pool({'nearbyIndependentIds': <String>[], 'independentsOpenAt': null, 'referredToOrgId': 'ind'});
    expect(refusal(referred, 'ind', independent()), isNull);
  });

  test('independents at capacity or paused are refused; shelters never', () {
    expect(refusal(pool(), 'ind', independent({'activeCaseCount': 3}))?.message, contains('3 active'));
    expect(refusal(pool(), 'ind', independent({'activeCaseCount': 3, 'maxActiveCases': 4})), isNull);
    expect(refusal(pool(), 'ind', independent({'animalsInCareCount': 5}))?.message, contains('animal'));
    expect(refusal(pool(), 'ind', independent({'acceptingCases': false}))?.message, contains('paused'));
    expect(independentCapacityRefusal(shelter), isNull);
    expect(independentCapacityRefusal({'kind': 'independent', 'activeCaseCount': 9}), isNotNull);
  });
}
