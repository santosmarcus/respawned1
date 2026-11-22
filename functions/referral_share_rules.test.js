// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {
  isValidToken,
  shareState,
  publicStatusLabel,
  buildReferralSnapshot,
  validateResponse,
} = require('./referral_share_rules');

test('tokens are 24 URL-safe characters', () => {
  assert.strictEqual(isValidToken('abcdefghijklmnopqrstuvwx'), true);
  assert.strictEqual(isValidToken('abc-_EFGHIJKLMNOPQRSTUV1'), true);
  assert.strictEqual(isValidToken('short'), false);
  assert.strictEqual(isValidToken('abcdefghijklmnopqrstuv/x'), false);
  assert.strictEqual(isValidToken(null), false);
});

test('a link is open until revoked or expired', () => {
  assert.strictEqual(shareState({revoked: false, expiresAtMs: 100, nowMs: 99}), 'active');
  assert.strictEqual(shareState({revoked: false, expiresAtMs: 100, nowMs: 100}), 'expired');
  assert.strictEqual(shareState({revoked: true, expiresAtMs: 100, nowMs: 1}), 'revoked');
});

test('case statuses in plain words', () => {
  assert.strictEqual(publicStatusLabel('pending'), 'Under review');
  assert.strictEqual(publicStatusLabel('referred'), 'Referred');
  assert.strictEqual(publicStatusLabel('ongoing'), 'Rescue in progress');
  assert.strictEqual(publicStatusLabel('in_treatment'), 'In treatment');
  assert.strictEqual(publicStatusLabel('completed'), 'Rescued');
  assert.strictEqual(publicStatusLabel('cancelled'), 'Closed');
  assert.strictEqual(publicStatusLabel(undefined), 'Under review');
});

const caseData = {
  rescueType: 'Stray',
  urgency: 'Critical',
  condition: 'Limping',
  animals: [{species: 'Dog', breed: 'Aspin', sex: 'Male', mobility: 'Limping', environmentSafety: 'x'}],
  photoUrls: ['https://firebasestorage.googleapis.com/a.jpg', '/local/path.jpg'],
  lat: 14.6,
  lng: 121.1,
  address: 'Rizal St, Rodriguez',
  reporterName: 'Rina',
  reporterPhone: '0917',
  notes: 'internal',
  verification: {deskBy: 'x'},
  riderLastLat: 1,
  statusHistory: [{status: 'x'}],
  createdAt: {toMillis: () => 1000},
};
const referral = {type: 'localGovernmentUnit', barangay: 'San Isidro', lguReason: 'shelterAtCapacity',
  lguExplanation: 'Full this week', createdAt: {toMillis: () => 2000}, createdByName: 'Ana',
  attachedMediaUrls: ['https://firebasestorage.googleapis.com/a.jpg']};
const org = {name: 'Loved by the Gapz', phone: '0918', email: 'a@b.ph', facebookUrl: 'javascript:alert(1)'};

test('the copy keeps what a responder needs', () => {
  const s = buildReferralSnapshot({caseId: 'abcdefghij', c: caseData, referral, org});
  assert.strictEqual(s.caseRef, 'ABCDEFG');
  assert.strictEqual(s.urgency, 'Critical');
  assert.deepStrictEqual(s.animals, [{species: 'Dog', breed: 'Aspin', sex: 'Male', mobility: 'Limping'}]);
  assert.deepStrictEqual(s.photoUrls, ['https://firebasestorage.googleapis.com/a.jpg']);
  assert.deepStrictEqual(s.location, {lat: 14.6, lng: 121.1, address: 'Rizal St, Rodriguez'});
  assert.strictEqual(s.reportedAtMs, 1000);
  assert.deepStrictEqual(s.referral, {type: 'localGovernmentUnit', barangay: 'San Isidro',
    reason: 'Shelter at capacity', explanation: 'Full this week', referredAtMs: 2000, referredByName: 'Ana'});
  assert.deepStrictEqual(s.organization, {name: 'Loved by the Gapz', phone: '0918', email: 'a@b.ph'});
});

test('the copy never carries internal fields, and the reporter only when chosen', () => {
  const s = buildReferralSnapshot({caseId: 'abcdefghij', c: caseData, referral, org});
  for (const key of ['notes', 'verification', 'riderLastLat', 'statusHistory', 'reporter']) {
    assert.strictEqual(key in s, false, key);
  }
  const withReporter = buildReferralSnapshot({caseId: 'x', c: caseData, referral, org, includeReporter: true});
  assert.deepStrictEqual(withReporter.reporter, {name: 'Rina', phone: '0917'});
  const anonymous = buildReferralSnapshot({caseId: 'x', c: {...caseData, reportAnonymously: true}, referral, org,
    includeReporter: true});
  assert.strictEqual('reporter' in anonymous, false);
});

test('answers need a choice and a name; declining or asking needs a note', () => {
  assert.ok(validateResponse({response: 'maybe', name: 'A'}).error);
  assert.ok(validateResponse({response: 'will_handle', name: '  '}).error);
  assert.deepStrictEqual(validateResponse({response: 'will_handle', name: ' Brgy San Isidro ', contact: ''}),
    {value: {response: 'will_handle', name: 'Brgy San Isidro'}});
  assert.ok(validateResponse({response: 'cannot_handle', name: 'A'}).error);
  assert.ok(validateResponse({response: 'need_info', name: 'A', note: ' '}).error);
  assert.deepStrictEqual(validateResponse({response: 'cannot_handle', name: 'A', note: 'No vehicle'}).value,
    {response: 'cannot_handle', name: 'A', note: 'No vehicle'});
  assert.ok(validateResponse({response: 'will_handle', name: 'x'.repeat(121)}).error);
});

test('an LGU referral shows only the media staff attached', () => {
  const withVideo = {...caseData, videoUrls: ['https://firebasestorage.googleapis.com/v.mp4']};
  const attached = buildReferralSnapshot({caseId: 'x', c: withVideo, referral, org});
  assert.deepStrictEqual(attached.photoUrls, ['https://firebasestorage.googleapis.com/a.jpg']);
  assert.deepStrictEqual(attached.videoUrls, ['https://firebasestorage.googleapis.com/v.mp4']);
  const none = buildReferralSnapshot({caseId: 'x', c: withVideo, referral: {...referral, attachedMediaUrls: []}, org});
  assert.strictEqual('photoUrls' in none, false);
  assert.strictEqual('videoUrls' in none, false);
  // Other referral types show the report's own photos.
  const orgReferral = buildReferralSnapshot({caseId: 'x', c: withVideo, referral: {type: 'anotherOrganization'}, org});
  assert.deepStrictEqual(orgReferral.photoUrls, ['https://firebasestorage.googleapis.com/a.jpg']);
});

test('shared-link referral: answers set the case state', () => {
  const {linkReferralUpdate} = require('./referral_share_rules');
  const link = {referralId: 'r1', state: 'waiting', previousStatus: 'pending_review'};
  const at = 'now';
  const taken = linkReferralUpdate(link, 'r1', {response: 'will_handle', name: 'Brgy 5', contact: '0917'}, at);
  assert.strictEqual(taken.state, 'accepted');
  assert.strictEqual(taken.answeredByName, 'Brgy 5');
  assert.strictEqual(taken.answeredByContact, '0917');
  assert.strictEqual(taken.previousStatus, 'pending_review');
  assert.strictEqual(linkReferralUpdate(link, 'r1', {response: 'cannot_handle', name: 'A', note: 'full'}, at).state, 'declined');
  assert.strictEqual(linkReferralUpdate(link, 'r1', {response: 'need_info', name: 'A', note: '?'}, at).state, 'needs_info');
});

test('shared-link referral: other referrals and taken cases are left alone', () => {
  const {linkReferralUpdate} = require('./referral_share_rules');
  const answer = {response: 'cannot_handle', name: 'B', note: 'no'};
  assert.strictEqual(linkReferralUpdate(undefined, 'r1', answer, 'now'), null);
  assert.strictEqual(linkReferralUpdate({referralId: 'r2', state: 'waiting'}, 'r1', answer, 'now'), null);
  assert.strictEqual(linkReferralUpdate({referralId: 'r1', state: 'accepted'}, 'r1', answer, 'now'), null);
});
