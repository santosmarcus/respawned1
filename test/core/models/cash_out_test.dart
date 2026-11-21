import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/donation/cash_out.dart';
import 'package:respawnd1/features/admin/donation/cash_out_sheets.dart';
import 'package:respawnd1/features/donation/models.dart';

DonationListing fund(String id, {double collected = 0, double allocated = 0, String title = 'Fund'}) =>
    DonationListing(
      id: id,
      title: title,
      target: 0,
      collected: collected,
      allocatedAmount: allocated,
      organizer: 'Org',
      time: '',
      description: '',
      numdonated: 0,
      address: '',
      type: 'donation',
    );

void main() {
  group('CashOut', () {
    test('reads a PayMongo payout waiting for a fund', () {
      final c = CashOut.fromMap('po_1', {
        'organizationId': 'org1',
        'source': 'paymongo',
        'amount': 5000,
        'assignedAmount': 1200.5,
        'status': 'partly_assigned',
        'occurredAt': Timestamp.fromDate(DateTime(2026, 11, 20)),
        'lines': [
          {'campaignId': 'general_org1', 'campaignTitle': 'General fund', 'category': 'Food', 'label': 'Dog food',
            'amount': 1200.5, 'byName': 'Ana'},
        ],
      });
      expect(c.isOpen, isTrue);
      expect(c.remaining, 3799.5);
      expect(c.sourceLabel, 'PayMongo payout');
      expect(c.statusLabel, 'Partly assigned');
      expect(c.lines.single.campaignTitle, 'General fund');
      expect(cashOutHeadline(c), startsWith('₱5,000'));
      expect(cashOutHeadline(c), contains('was paid out from PayMongo on'));
    });

    test('an unknown source or a sorted-out cash-out', () {
      final c = CashOut.fromMap('x', {'source': 'crypto', 'amount': 10, 'assignedAmount': 0, 'status': 'already_recorded'});
      expect(c.source, 'other');
      expect(c.isOpen, isFalse);
      expect(c.statusLabel, 'Already recorded');
    });
  });

  group('fundSplitProblem', () {
    final funds = {
      'general_org1': fund('general_org1', collected: 3000),
      'camp1': fund('camp1', collected: 1000, allocated: 400, title: 'Vet bills'),
    };
    FundSplitLine line(String? id, String amount, {String label = 'Dog food'}) =>
        FundSplitLine(campaignId: id, amount: amount)..label.text = label;

    test('asks for each missing piece in plain words', () {
      expect(fundSplitProblem([line(null, '100')], funds, limit: 500), contains('Choose which fund'));
      expect(fundSplitProblem([line('camp1', '')], funds, limit: 500), contains('Enter how much'));
      expect(fundSplitProblem([line('camp1', '100', label: ' ')], funds, limit: 500), contains('short description'));
    });

    test('never more than was taken out or than a fund has', () {
      expect(fundSplitProblem([line('general_org1', '600')], funds, limit: 500), contains('more than the'));
      expect(fundSplitProblem([line('camp1', '400'), line('camp1', '300')], funds, limit: 1000),
          contains('Vet bills only has'));
      expect(fundSplitProblem([line('general_org1', '300'), line('camp1', '200')], funds, limit: 500), isNull);
      expect(fundSplitTotal([line('general_org1', '300'), line('camp1', '200.50')]), 500.5);
    });

    test('General fund is offered first', () {
      final list = cashOutFunds([fund('camp1', collected: 9000), fund('general_org1', collected: 10)]);
      expect(list.first.id, 'general_org1');
    });
  });
}
