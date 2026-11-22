import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/rescue_status.dart';
import 'package:respawnd1/core/models/rescue/surrender_withdrawal.dart';
import 'package:respawnd1/core/utils/community_adoption_eligibility.dart';

void main() {
  group('Community Adoption eligibility', () {
    test('a surrender is listed while community_adoption, not once withdrawn', () {
      bool eligible(String status, String type) =>
          isCommunityAdoptionEligible(status: status, rejectionReason: null, rescueType: type);
      expect(eligible('community_adoption', 'Pet Surrender'), isTrue);
      expect(eligible('withdrawn', 'Pet Surrender'), isFalse);
      expect(eligible('community_adoption', 'Injury'), isFalse);
      expect(eligible('community_adoption', 'Lost Pet'), isFalse);
    });

    test('the new statuses parse; withdrawn is terminal', () {
      expect(RescueStatus.fromFirestoreValue('community_adoption'), RescueStatus.communityAdoption);
      expect(RescueStatus.fromFirestoreValue('withdrawn'), RescueStatus.withdrawn);
      expect(RescueStatus.withdrawn.isTerminal, isTrue);
      expect(RescueStatus.communityAdoption.isTerminal, isFalse);
    });
  });

  group('surrender withdrawal', () {
    test('only an active surrender can be withdrawn', () {
      bool can(String status, [String type = 'Pet Surrender']) =>
          canWithdrawSurrender({'rescueType': type, 'status': status});
      expect(can('community_adoption'), isTrue);
      expect(can('pending'), isTrue);
      expect(can('withdrawn'), isFalse);
      expect(can('rejected'), isFalse);
      expect(can('pending', 'Injury'), isFalse);
    });

    test('reads the stored reason; Other shows what was typed', () {
      final at = DateTime(2026, 11, 1, 9);
      final w = SurrenderWithdrawal.fromCase({
        'surrenderWithdrawal': {
          'reason': 'other',
          'otherText': ' Moving with family ',
          'details': 'Thanks to everyone who asked',
          'withdrawnAt': Timestamp.fromDate(at),
        },
      })!;
      expect(w.reason, SurrenderWithdrawalReason.other);
      expect(w.reasonLabel, 'Moving with family');
      expect(w.details, 'Thanks to everyone who asked');
      expect(w.withdrawnAt, at);

      expect(SurrenderWithdrawal.fromCase({'surrenderWithdrawal': {'reason': 'keeping'}})!.reasonLabel,
          SurrenderWithdrawalReason.keeping.label);
      expect(SurrenderWithdrawal.fromCase({'surrenderWithdrawal': {'reason': 'unknown'}})!.reasonLabel, 'Not stated');
      expect(SurrenderWithdrawal.fromCase({}), isNull);
    });
  });
}
