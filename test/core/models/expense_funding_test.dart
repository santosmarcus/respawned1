import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';

Expense _expense(double amount, List<ExpenseFunding> fundings) => Expense(
      id: 'e',
      caseId: 'c',
      title: 'Vet bill',
      category: ExpenseCategory.consultation,
      amount: amount,
      fundings: fundings,
    );

void main() {
  group('Expense funding', () {
    test('no lines is unfunded', () {
      final e = _expense(5000, const []);
      expect(e.isUnfunded, isTrue);
      expect(e.outstandingAmount, 5000);
      expect(e.fundingLabel, 'Unfunded');
    });

    test('lines covering part of the cost leave the rest outstanding', () {
      final e = _expense(5000, const [
        ExpenseFunding(source: FundingSource.organizationBudget, amount: 3000),
        ExpenseFunding(source: FundingSource.fundraiser, amount: 1000),
      ]);
      expect(e.fundedAmount, 4000);
      expect(e.outstandingAmount, 1000);
      expect(e.isPartlyFunded, isTrue);
      expect(e.isFullyFunded, isFalse);
      expect(e.fundingLabel, 'Organization Budget + Fundraiser');
    });

    test('lines covering the whole cost are fully funded', () {
      final e = _expense(5000, const [ExpenseFunding(source: FundingSource.donationFund, amount: 5000)]);
      expect(e.isFullyFunded, isTrue);
      expect(e.outstandingAmount, 0);
    });

    test('over-funding is capped at the cost', () {
      final e = _expense(1000, const [ExpenseFunding(source: FundingSource.other, amount: 1500)]);
      expect(e.fundedAmount, 1000);
      expect(e.outstandingAmount, 0);
    });
  });

  group('reading Firestore data', () {
    test('legacy single source covers the whole amount', () {
      final lines = Expense.fundingsFromFirestore({'fundingSource': 'Donation Fund'}, 2500);
      expect(lines, hasLength(1));
      expect(lines.single.source, FundingSource.donationFund);
      expect(lines.single.amount, 2500);
    });

    test('legacy Unfunded has no lines', () {
      expect(Expense.fundingsFromFirestore({'fundingSource': 'Unfunded'}, 2500), isEmpty);
    });

    test('funding lines win over the legacy field and skip bad entries', () {
      final lines = Expense.fundingsFromFirestore({
        'fundingSource': 'Mixed',
        'fundings': [
          {'source': 'Fundraiser', 'amount': 800},
          {'source': 'Unfunded', 'amount': 100},
          {'source': 'Donation Fund', 'amount': 0},
          'garbage',
        ],
      }, 2000);
      expect(lines, hasLength(1));
      expect(lines.single.source, FundingSource.fundraiser);
      expect(lines.single.amount, 800);
    });

    test('toFirestore keeps the legacy field readable', () {
      expect(
        _expense(100, const [ExpenseFunding(source: FundingSource.fundraiser, amount: 100)]).toFirestore()['fundingSource'],
        'Fundraiser',
      );
      expect(_expense(100, const []).toFirestore()['fundingSource'], 'Unfunded');
      expect(
        _expense(100, const [ExpenseFunding(source: FundingSource.fundraiser, amount: 40)]).toFirestore()['fundingSource'],
        'Mixed',
      );
    });
  });
}
