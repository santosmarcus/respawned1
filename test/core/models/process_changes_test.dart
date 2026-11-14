import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/media_ref.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/models/rescue/expense.dart';
import 'package:respawnd1/core/utils/stream_merge.dart';

AnimalRecord _animal(Map<String, dynamic> data) => AnimalRecord.fromMap('a1', {'name': 'Mochi', 'species': 'Dog', ...data});

void main() {
  group('animal care status', () {
    test('reads and labels each care status', () {
      expect(_animal({'careStatus': 'isolation'}).statusLabel, 'Isolation');
      expect(_animal({'careStatus': 'recovering'}).statusLabel, 'Recovering');
      expect(_animal({'careStatus': 'in_shelter'}).statusLabel, 'In Shelter');
      expect(_animal({}).statusLabel, 'Not Ready for Adoption');
      expect(_animal({'careStatus': 'nonsense'}).careStatus, isNull);
    });

    test('isolation is shown before adoptable; treatment and terminal states win', () {
      expect(_animal({'careStatus': 'isolation', 'adoptionStatus': 'adoptable'}).statusLabel, 'Isolation');
      expect(_animal({'careStatus': 'in_shelter', 'adoptionStatus': 'adoptable'}).statusLabel, 'Adoptable');
      expect(_animal({'careStatus': 'isolation', 'currentCaseId': 'c1'}).statusLabel, 'In Treatment');
      expect(_animal({'careStatus': 'isolation', 'adoptionStatus': 'deceased'}).statusLabel, 'Deceased');
      expect(_animal({'careStatus': 'isolation', 'archived': true}).statusLabel, 'Archived');
    });

    test('a returned animal reads Returned until it gets a new status or is listed again', () {
      final returned = {'adoptionStatus': 'not_ready', 'currentStatus': 'returned'};
      expect(_animal(returned).statusLabel, 'Returned');
      expect(_animal({...returned, 'careStatus': 'recovering'}).statusLabel, 'Recovering');
      expect(_animal({...returned, 'adoptionStatus': 'adoptable'}).statusLabel, 'Adoptable');
      // Returned after adoption: no longer reads Adopted.
      expect(_animal({'adoptionStatus': 'adopted', 'currentStatus': 'returned'}).statusLabel, 'Returned');
    });
  });

  group('expense funding links', () {
    test('a campaign link survives a save and load', () {
      const line = ExpenseFunding(
        source: FundingSource.fundraiser,
        amount: 1200,
        campaignId: 'camp1',
        campaignTitle: 'Bantay surgery',
        allocationId: 'alloc1',
      );
      final back = ExpenseFunding.fromMap(line.toMap())!;
      expect(back.campaignId, 'camp1');
      expect(back.campaignTitle, 'Bantay surgery');
      expect(back.allocationId, 'alloc1');
      expect(back.isLinked, isTrue);
      expect(const ExpenseFunding(source: FundingSource.organizationBudget, amount: 5).toMap().keys,
          unorderedEquals(['source', 'amount']));
    });

    test('the funding label names the campaign that paid', () {
      final e = Expense(
        id: 'e',
        caseId: '',
        title: 'Rent',
        category: ExpenseCategory.rent,
        amount: 5000,
        fundings: const [
          ExpenseFunding(source: FundingSource.fundraiser, amount: 3000, campaignId: 'c', campaignTitle: 'Shelter fund'),
          ExpenseFunding(source: FundingSource.organizationBudget, amount: 2000),
        ],
      );
      expect(e.fundingLabel, 'Shelter fund + Organization Budget');
      expect(e.isFullyFunded, isTrue);
    });

    test('every category maps to a category the backend accepts', () {
      const backend = {'Food', 'Medicine and Treatment', 'Administrative', 'Bills and Utilities', 'Shelter', 'Transport', 'Other'};
      for (final c in ExpenseCategory.values) {
        expect(backend, contains(c.allocationCategory), reason: c.name);
      }
      expect(ExpenseCategory.forCase, isNot(contains(ExpenseCategory.rent)));
      expect(ExpenseCategory.forGeneral, contains(ExpenseCategory.staffCompensation));
    });
  });

  group('attachments', () {
    test('photos and videos keep their type; older records count as photos', () {
      final refs = MediaRef.fromLists(['a', 'b', 'c'], ['image', 'video']);
      expect([for (final r in refs) r.isVideo], [false, true, false]);
      final fields = attachmentFields(refs);
      expect(attachmentsFrom(fields).map((r) => r.url), ['a', 'b', 'c']);
      expect(attachmentFields(const []), isEmpty);
    });
  });

  group('stream merge', () {
    test('passes events from both streams and closes when both are done', () async {
      final a = StreamController<int>();
      final b = StreamController<String>();
      final events = <(int?, String?)>[];
      final done = Completer<void>();
      StreamGroupLite.merge2(a.stream, b.stream).listen(events.add, onDone: done.complete);
      a.add(1);
      b.add('x');
      await a.close();
      b.add('y');
      await b.close();
      await done.future;
      expect(events, [(1, null), (null, 'x'), (null, 'y')]);
    });
  });
}
