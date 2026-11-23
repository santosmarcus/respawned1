import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/features/donation/models.dart';

DonationListing listing({bool autoRenew = true, int notice = 3, int grace = 3}) => DonationListing(
      id: 's1', title: 'Bantay', target: 0, collected: 0, organizer: 'Shelter', time: '', description: '',
      numdonated: 0, address: '', type: 'sponsorship',
      autoRenew: autoRenew, renewalNoticeDays: notice, renewalGraceDays: grace,
    );

void main() {
  test('listings renew monthly by default with the server defaults', () {
    final l = DonationListing(
      id: 's1', title: 'Bantay', target: 0, collected: 0, organizer: '', time: '', description: '',
      numdonated: 0, address: '', type: 'sponsorship',
    );
    expect([l.autoRenew, l.renewalNoticeDays, l.renewalGraceDays], [true, 3, 3]);
  });

  test('an auto-renewing listing tells the sponsor when the payment comes and the grace period', () {
    final text = sponsorshipRenewalText(listing(notice: 5, grace: 7));
    expect(text, contains('Renews every month'));
    expect(text, contains('5 days before each month ends'));
    expect(text, contains('within 7 days after it ends'));
    expect(text, contains('nothing is charged without you'));
  });

  test('no grace period and no auto-renew read differently', () {
    expect(sponsorshipRenewalText(listing(grace: 0)), contains('by the time it ends'));
    final off = sponsorshipRenewalText(listing(autoRenew: false, notice: 1, grace: 0));
    expect(off, contains('1 day before it ends'));
    expect(off, isNot(contains('Renews every month')));
  });
}
