// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const r = require('./adoption_promotion_rules');

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const WEEK = 7 * DAY;
// Manila wall-clock time → epoch ms (UTC+8, no DST).
const manila = (y, mo, d, h = 0) => Date.UTC(y, mo - 1, d, h) - 8 * HOUR;

const weekly = {enabled: true, smartSuggestions: false, intervalWeeks: 1, dayOfWeek: 6, hour: 10, animalsPerPost: 3};

test('validates the schedule an Admin sends', () => {
  assert.deepStrictEqual(r.validateSchedule(weekly), {schedule: weekly});
  assert.ok(r.validateSchedule({...weekly, intervalWeeks: 3}).error);
  assert.ok(r.validateSchedule({...weekly, dayOfWeek: 0}).error);
  assert.ok(r.validateSchedule({...weekly, hour: 24}).error);
  assert.ok(r.validateSchedule({...weekly, animalsPerPost: 7}).error);
  assert.ok(r.validateSchedule({...weekly, enabled: 'yes'}).error);
  assert.deepStrictEqual(Object.keys(r.validateSchedule({...weekly, nextDueAt: 1, extra: 2}).schedule).sort(),
      Object.keys(weekly).sort());
});

test('the first slot is the next chosen weekday and hour in Manila', () => {
  // 2026-11-21 is a Saturday.
  assert.deepStrictEqual(r.manilaParts(manila(2026, 11, 21, 9)), {dayOfWeek: 6, hour: 9});
  assert.strictEqual(r.firstSlotAfter(weekly, manila(2026, 11, 21, 9)), manila(2026, 11, 21, 10));
  assert.strictEqual(r.firstSlotAfter(weekly, manila(2026, 11, 21, 10)), manila(2026, 11, 28, 10));
  assert.strictEqual(r.firstSlotAfter({dayOfWeek: 1, hour: 8}, manila(2026, 11, 21, 23)), manila(2026, 11, 23, 8));
  // Sunday, late evening Manila (still Sunday morning UTC).
  assert.strictEqual(r.firstSlotAfter({dayOfWeek: 7, hour: 20}, manila(2026, 11, 22, 19)), manila(2026, 11, 22, 20));
});

test('missed slots collapse into one reminder', () => {
  const due = manila(2026, 11, 7, 10);
  assert.strictEqual(r.advanceSlot(due, 1, due + HOUR), due + WEEK);
  assert.strictEqual(r.advanceSlot(due, 1, due + 3 * WEEK + HOUR), due + 4 * WEEK);
  assert.strictEqual(r.advanceSlot(due, 2, due + HOUR), due + 2 * WEEK);
});

test('a due slot reminds, unless a recent post covered it', () => {
  const due = manila(2026, 11, 21, 10);
  const now = due + 5 * 60 * 1000;
  assert.deepStrictEqual(r.scheduleDecision({schedule: {...weekly, nextDueAt: due}, nowMs: now}),
      {action: 'remind', kind: 'scheduled', nextDueMs: due + WEEK});
  assert.deepStrictEqual(
      r.scheduleDecision({schedule: {...weekly, nextDueAt: due, lastPostedAt: due - 2 * DAY}, nowMs: now}),
      {action: 'skip', nextDueMs: due + WEEK});
  assert.strictEqual(
      r.scheduleDecision({schedule: {...weekly, nextDueAt: due, lastPostedAt: due - 5 * DAY}, nowMs: now}).action,
      'remind');
  assert.deepStrictEqual(r.scheduleDecision({schedule: {...weekly, nextDueAt: due}, nowMs: due - HOUR}),
      {action: 'none'});
  assert.deepStrictEqual(r.scheduleDecision({schedule: {...weekly, nextDueAt: null}, nowMs: due - HOUR}),
      {action: 'init', nextDueMs: due});
  assert.deepStrictEqual(r.scheduleDecision({schedule: {...weekly, enabled: false, nextDueAt: due}, nowMs: now}),
      {action: 'none'});
});

test('smart nudges go out at the chosen hour, away from posts and slots', () => {
  const smart = {kind: 'never_shared', count: 1};
  const s = {...weekly, enabled: false, smartSuggestions: true};
  const at10 = manila(2026, 11, 18, 10); // a Wednesday
  assert.deepStrictEqual(r.scheduleDecision({schedule: s, nowMs: at10, smart}),
      {action: 'remind', kind: 'smart', nextDueMs: null});
  assert.strictEqual(r.scheduleDecision({schedule: s, nowMs: at10 + HOUR, smart}).action, 'none');
  assert.strictEqual(r.scheduleDecision({schedule: s, nowMs: at10, smart: null}).action, 'none');
  assert.strictEqual(r.scheduleDecision({schedule: {...s, lastPostedAt: at10 - DAY}, nowMs: at10, smart}).action,
      'none');
  assert.strictEqual(r.scheduleDecision({schedule: {...s, lastReminderAt: at10 - 2 * DAY}, nowMs: at10, smart}).action,
      'none');
  assert.strictEqual(r.scheduleDecision({schedule: {...s, lastReminderAt: at10 - 4 * DAY}, nowMs: at10, smart}).action,
      'remind');
  // Scheduled slot on Saturday is 3 days away: fine. One day away: wait.
  const both = {...weekly, smartSuggestions: true};
  assert.strictEqual(
      r.scheduleDecision({schedule: {...both, nextDueAt: manila(2026, 11, 21, 10)}, nowMs: at10, smart}).action,
      'remind');
  assert.strictEqual(
      r.scheduleDecision({schedule: {...both, nextDueAt: manila(2026, 11, 19, 10)}, nowMs: at10, smart}).action,
      'none');
});

const now = manila(2026, 11, 21, 10);
const animal = (id, extra = {}) => ({
  id, name: id, adoptionStatus: 'adoptable', photoUrls: ['https://x/y.jpg'], createdAt: now - 60 * DAY, ...extra,
});

test('only adoptable, public animals with a photo can be posted', () => {
  const ids = r.promotableAnimals([
    animal('ok'),
    animal('reserved', {adoptionStatus: 'reserved'}),
    animal('archived', {archived: true}),
    animal('hidden', {publicProfileHidden: true}),
    animal('deceased', {status: 'deceased'}),
    animal('nophoto', {photoUrls: []}),
    animal('legacy', {photoUrls: undefined, images: ['https://x/z.jpg']}),
  ]).map((a) => a.id);
  assert.deepStrictEqual(ids, ['ok', 'legacy']);
});

test('ranks never shared first, then no applicants, then longest since shared', () => {
  const ranked = r.rankAnimals({
    animals: [animal('sharedLongAgo'), animal('sharedRecently'), animal('fresh'), animal('applied')],
    shares: [
      {animalRecordIds: ['sharedLongAgo'], createdAt: now - 40 * DAY},
      {animalRecordIds: ['sharedRecently', 'applied'], createdAt: now - 3 * DAY},
      {animalRecordIds: ['sharedLongAgo'], createdAt: now - 50 * DAY},
    ],
    adoptions: [
      {status: 'pending', personal: {animalRecordId: 'applied'}},
      {status: 'rejected', personal: {animalRecordId: 'sharedRecently'}},
    ],
    nowMs: now,
  });
  assert.deepStrictEqual(ranked.map((x) => x.id), ['fresh', 'sharedLongAgo', 'sharedRecently', 'applied']);
  const byId = Object.fromEntries(ranked.map((x) => [x.id, x]));
  assert.strictEqual(byId.sharedLongAgo.lastSharedMs, now - 40 * DAY);
  assert.strictEqual(byId.sharedLongAgo.waiting, true);
  assert.strictEqual(byId.sharedRecently.waiting, false);
  assert.strictEqual(byId.applied.hasApplicants, true);
});

test('smart nudge reasons', () => {
  const rank = (animals, shares = []) => r.rankAnimals({animals, shares, nowMs: now});
  assert.deepStrictEqual(r.smartNudgeReason(rank([animal('a')])), {kind: 'never_shared', count: 1});
  const old = [{animalRecordIds: ['a', 'b'], createdAt: now - 45 * DAY}];
  assert.deepStrictEqual(r.smartNudgeReason(rank([animal('a'), animal('b')], old)), {kind: 'waiting', count: 2});
  assert.strictEqual(r.smartNudgeReason(rank([animal('a')], old)), null);
  assert.strictEqual(r.smartNudgeReason([]), null);
});

test('reminder copy names the suggested animals', () => {
  const picks = [{name: 'Bantay'}, {name: 'Mingming'}, {name: 'Choco'}];
  assert.deepStrictEqual(r.reminderMessage({kind: 'scheduled', intervalWeeks: 1, picks, total: 5}), {
    title: 'Weekly adoption post is due',
    body: '5 animals open for adoption. Suggested: Bantay, Mingming and Choco. Tap to review and post to Facebook.',
  });
  assert.match(
      r.reminderMessage({kind: 'smart', picks: picks.slice(0, 1), total: 1, reason: {kind: 'never_shared', count: 1}})
          .body,
      /^1 animal open for adoption has never been shared\. Suggested: Bantay\./);
  assert.strictEqual(r.reminderMessage({kind: 'scheduled', intervalWeeks: 1, picks: [], total: 0}), null);
  assert.match(r.defaultCaption(['Bantay']), /^Meet Bantay! This animal is/);
  assert.match(r.defaultCaption(['A', 'B']), /^Meet A and B! They are/);
});
