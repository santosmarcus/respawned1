import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/models/rescue/medication.dart';
import 'package:respawnd1/features/adminhome/dashboard/dashboard_data.dart';
import 'package:respawnd1/features/adminhome/dashboard/today_view.dart';
import 'package:respawnd1/features/donation/models.dart';

AnimalRecord _animal(Map<String, dynamic> data) => AnimalRecord.fromMap('a1', {'name': 'Mochi', 'species': 'Dog', ...data});

MedicationPlan _plan(String drug) =>
    MedicationPlan(id: drug, animalId: 'a1', drug: drug, dose: '1 tab', timesPerDay: 1, startDate: DateTime(2026, 11, 1));

DonationListing _campaign({List<String> tags = const [], String fundKind = 'campaign'}) => DonationListing(
  id: 'c1',
  title: 'Campaign',
  target: 1000,
  collected: 0,
  organizer: 'Shelter',
  time: '',
  description: '',
  numdonated: 0,
  address: '',
  type: 'donation',
  purposeTags: tags,
  fundKind: fundKind,
);

void main() {
  group('continuing care', () {
    test('an animal with nothing recorded needs no continuing care', () {
      expect(continuingCareNeedsOf(_animal({})), isEmpty);
    });

    test('medication orders, isolation and missed doses are listed, most urgent first', () {
      final needs = continuingCareNeedsOf(
        _animal({'careStatus': 'isolation'}),
        plans: [_plan('Amoxicillin')],
        missedDoses: 2,
      );
      expect(needs.map((n) => n.label), ['2 missed doses this week', 'Medication: Amoxicillin', 'Isolation']);
      expect(careNeedRank(needs), lessThan(careNeedRank(continuingCareNeedsOf(_animal({'careStatus': 'recovering'})))));
    });

    test('free-text medication on the record counts when no order exists', () {
      final needs = continuingCareNeedsOf(_animal({'currentMedications': 'Vitamins'}));
      expect(needs.single.label, 'Medication: Vitamins');
    });
  });

  group('turnover checks', () {
    test('all four done: vaccinated, spayed, no medication, behavior confirmed', () {
      final a = _animal({
        'vaccinated': true,
        'spayedNeutered': true,
        'adoptionReadiness': {
          'checks': {
            'behavior': {'confirmed': true},
          },
        },
      });
      final checks = turnoverChecksFor(a, vaccines: HealthRecordStatus.notRecorded);
      expect(checks.map((c) => c.done), [true, true, true, true]);
    });

    test('an active medication order and an overdue vaccine block turnover', () {
      final checks = turnoverChecksFor(
        _animal({'spayedNeutered': true}),
        vaccines: HealthRecordStatus.overdue,
        plans: [_plan('Doxycycline')],
      );
      expect(checks[0].done, isFalse);
      expect(checks[2].done, isFalse);
      expect(checks[2].detail, contains('Doxycycline'));
    });

    test('temperament alone is not a behavior assessment', () {
      final checks = turnoverChecksFor(
        _animal({'keyCharacteristics': ['Friendly']}),
        vaccines: HealthRecordStatus.completed,
      );
      expect(checks[3].done, isNull);
      expect(checks[1].done, isNull); // spay/neuter not recorded
    });
  });

  group('fund levels', () {
    test('sufficient, low and critical by how much of the need is set aside', () {
      expect(FundLevel.of(500, 0), FundLevel.sufficient);
      expect(FundLevel.of(1000, 1000), FundLevel.sufficient);
      expect(FundLevel.of(500, 1000), FundLevel.low);
      expect(FundLevel.of(499, 1000), FundLevel.critical);
      expect(FundLevel.of(0, 10), FundLevel.critical);
    });

    test('bills map to the allocation categories', () {
      expect(fundCategoryOfExpense(ExpenseCategory.vaccination), 'Medicine and Treatment');
      expect(fundCategoryOfExpense(ExpenseCategory.foodAndSupplies), 'Food');
      expect(fundCategoryOfExpense(ExpenseCategory.utilities), 'Bills and Utilities');
      expect(fundCategoryOfExpense(ExpenseCategory.rent), 'Shelter');
    });

    test('campaign money is set aside by purpose tag, else by fund kind, else general', () {
      expect(fundCategoriesOfCampaign(_campaign(tags: ['Food and Supplies', 'General Operations'])), ['Food']);
      expect(fundCategoriesOfCampaign(_campaign(fundKind: 'medical')), ['Medicine and Treatment']);
      expect(fundCategoriesOfCampaign(_campaign(tags: ['General Operations'])), isEmpty);
    });
  });
}
