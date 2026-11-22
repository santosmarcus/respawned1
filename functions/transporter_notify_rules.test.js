const test = require('node:test');
const assert = require('node:assert/strict');
const r = require('./transporter_notify_rules');

const ACTIVE = ['assigned', 'accepted', 'ongoing', 'arrived', 'treatment', 'dropoff'];
const onTrip = {status: 'ongoing', riderId: 'rider1'};

test('the transporter on the trip gets messages from others', () => {
  const p = r.messagePush({caseData: onTrip, message: {senderId: 'rep', senderName: 'Ana', text: 'Gate is open'}, activeStatuses: ACTIVE});
  assert.deepEqual(p, {uid: 'rider1', title: 'Message from Ana', body: 'Gate is open', type: 'transporter_message'});
  // Their own message, a case with no transporter, a finished trip: nothing.
  assert.equal(r.messagePush({caseData: onTrip, message: {senderId: 'rider1', text: 'hi'}, activeStatuses: ACTIVE}), null);
  assert.equal(r.messagePush({caseData: {status: 'ongoing'}, message: {senderId: 'rep', text: 'hi'}, activeStatuses: ACTIVE}), null);
  assert.equal(r.messagePush({caseData: {...onTrip, status: 'completed'}, message: {senderId: 'rep', text: 'hi'}, activeStatuses: ACTIVE}), null);
  // A volunteer doing the trip is reached the same way.
  assert.equal(r.messagePush({caseData: {status: 'arrived', assignedVolunteerId: 'vol'}, message: {senderId: 'org', text: 'ok'}, activeStatuses: ACTIVE}).uid, 'vol');
});

test('a shared location is pushed; questions for the reporter are not', () => {
  const loc = r.messagePush({caseData: onTrip, message: {senderId: 'rep', kind: 'location', address: 'Rizal St'}, activeStatuses: ACTIVE});
  assert.equal(loc.type, 'transporter_location_shared');
  assert.match(loc.body, /Rizal St/);
  assert.equal(r.messagePush({caseData: onTrip, message: {senderId: 'org', kind: 'location_request', text: '?'}, activeStatuses: ACTIVE}), null);
  assert.equal(r.messagePush({caseData: onTrip, message: {senderId: 'org', kind: 'confirm_request', text: '?'}, activeStatuses: ACTIVE}), null);
  assert.equal(r.messagePush({caseData: onTrip, message: {senderId: 'org', text: '   '}, activeStatuses: ACTIVE}), null);
  assert.equal(r.preview('x'.repeat(200)).length, 140);
});

test('location changes reach a transporter with a pending offer or checking the location', () => {
  const before = {status: 'awaiting_assignment', lat: 1, lng: 1, address: 'A'};
  const after = {...before, lat: 2, address: 'B'};
  assert.deepEqual(r.pendingLocationRecipients({before, after, offer: {status: 'pending', riderId: 'r2'}, offerId: 'o1', activeStatuses: ACTIVE}),
    [{uid: 'r2', data: {type: 'transporter_assignment', assignmentId: 'o1'}}]);
  assert.deepEqual(r.pendingLocationRecipients({before, after, offer: {status: 'rejected', riderId: 'r2'}, activeStatuses: ACTIVE}), []);
  assert.deepEqual(r.pendingLocationRecipients({before, after, offer: {status: 'pending', riderId: 'r2', isDemo: true}, activeStatuses: ACTIVE}), []);
  const verifying = {...after, status: 'verifying', verification: {riderId: 'r3'}};
  assert.deepEqual(r.pendingLocationRecipients({before, after: verifying, activeStatuses: ACTIVE}),
    [{uid: 'r3', data: {type: 'verification_visit'}}]);
  // Unchanged location, or the assigned transporter (already notified elsewhere).
  assert.deepEqual(r.pendingLocationRecipients({before, after: before, offer: {status: 'pending', riderId: 'r2'}, activeStatuses: ACTIVE}), []);
  assert.deepEqual(r.pendingLocationRecipients({before, after: {...after, status: 'ongoing', riderId: 'r1'}, activeStatuses: ACTIVE}), []);
});
