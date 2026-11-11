import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/admin/donation/donation_admin_filters.dart';
import 'package:respawnd1/features/donation/models.dart';

DonationListing listing(
  String id, {
  String type = 'donation',
  String status = 'active',
  DateTime? endDate,
  bool needsDecision = false,
  double collected = 0,
  double allocated = 0,
}) =>
    DonationListing(
      id: id,
      title: 'Listing $id',
      target: 1000,
      collected: collected,
      organizer: 'Shelter',
      endDate: endDate,
      time: '',
      description: '',
      numdonated: 0,
      address: '',
      type: type,
      status: status,
      needsExtensionDecision: needsDecision,
      allocatedAmount: allocated,
    );

void main() {
  final future = DateTime.now().add(const Duration(days: 10));
  final past = DateTime.now().subtract(const Duration(days: 1));

  final all = [
    listing('d-active', endDate: future),
    listing('d-draft', status: 'draft'),
    listing('d-paused', status: 'paused', endDate: past),
    listing('d-overdue', endDate: past), // ended, hourly job not run yet
    listing('d-met', status: 'goal_met', collected: 500, allocated: 100),
    listing('d-closed', status: 'closed', collected: 900),
    listing('d-decide', status: 'goal_not_met', needsDecision: true),
    listing('d-archived', status: 'archived'),
    listing('s-active', type: 'sponsorship'),
    listing('s-closed', type: 'sponsorship', status: 'closed'),
  ];

  List<String> ids(Iterable<DonationListing> l) => l.map((e) => e.id).toList();

  test('current listings are per type and exclude ended ones', () {
    expect(ids(currentListings(all, 'donation')), ['d-active', 'd-draft', 'd-paused']);
    expect(ids(currentListings(all, 'sponsorship')), ['s-active']);
  });

  test('completed listings skip pending decisions and sort by unallocated money', () {
    expect(ids(completedListings(all, 'donation')), ['d-closed', 'd-met']);
    expect(ids(completedListings(all, 'sponsorship')), ['s-closed']);
  });

  test('View All for a type shows its current and completed listings only', () {
    final donations = all.where((l) => matchesListingSearch(l, type: 'donation', statuses: defaultSearchStatuses));
    expect(ids(donations), [
      'd-active', 'd-draft', 'd-paused', 'd-overdue', 'd-met', 'd-closed', 'd-decide', //
    ]);
    final sponsorships = all.where((l) => matchesListingSearch(l, type: 'sponsorship', statuses: defaultSearchStatuses));
    expect(ids(sponsorships), ['s-active', 's-closed']);
  });

  test('search query matches title case-insensitively', () {
    final hits = all.where((l) => matchesListingSearch(l, statuses: defaultSearchStatuses, query: 'd-met'));
    expect(ids(hits), ['d-met']);
  });
}
