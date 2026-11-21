// Pure decisions for scheduled adoption posts to the organization's
// Facebook Page (functions/adoption_promotion.js). No Firebase here, so
// `node --test` checks them.
//
// An Admin sets a schedule (every 1, 2 or 4 weeks, a weekday and an hour,
// Manila time). When a slot comes due, every member of the organization
// gets a push and an in-app notification with the animals the system
// suggests (members allowed to share to Facebook post it); nothing is
// posted on its own. With smart suggestions on, they are also nudged
// between slots when animals have never been shared or have waited a long
// time without applicants.
//
// Keep the option lists equal to lib/core/models/organization/
// adoption_promotion_schedule.dart.

const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const WEEK_MS = 7 * DAY_MS;
/// Manila has no daylight saving time.
const MANILA_OFFSET_MS = 8 * HOUR_MS;

const INTERVAL_WEEKS = [1, 2, 4];
const MIN_ANIMALS_PER_POST = 1;
/// A Page post shows up to 10 photos well; keep it short.
const MAX_ANIMALS_PER_POST = 6;

/// A post made within this share of the interval before a slot counts for
/// that slot (posted on Thursday, weekly slot on Saturday: no reminder).
const COVERED_FRACTION = 0.5;
/// Smart nudges: no nudge within this long of a reminder or a post.
const SMART_COOLDOWN_DAYS = 3;
/// ... nor when a scheduled slot is this close.
const SMART_SLOT_GAP_DAYS = 2;
/// An animal not shared for this long counts as waiting again.
const STALE_SHARE_DAYS = 30;
/// An animal listed this long with no open application is waiting.
const WAITING_LISTED_DAYS = 14;
/// How many waiting animals (when none is new) are worth a nudge.
const SMART_MIN_WAITING = 2;

/// Applications that still hold an adopter's interest.
const OPEN_APPLICATION_STATUSES = ['pending', 'interview', 'approved'];

function ms(v) {
  if (v == null) return null;
  if (typeof v === 'number') return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === 'function') return v.toMillis();
  if (typeof v._seconds === 'number') return v._seconds * 1000;
  return null;
}

/// Checks a schedule an Admin sends and returns {error} or {schedule} with
/// only the stored fields.
function validateSchedule(input) {
  const s = input || {};
  if (typeof s.enabled !== 'boolean') return {error: 'enabled must be true or false.'};
  if (typeof s.smartSuggestions !== 'boolean') return {error: 'smartSuggestions must be true or false.'};
  if (!INTERVAL_WEEKS.includes(s.intervalWeeks)) return {error: 'Choose every 1, 2 or 4 weeks.'};
  if (!Number.isInteger(s.dayOfWeek) || s.dayOfWeek < 1 || s.dayOfWeek > 7) {
    return {error: 'dayOfWeek must be 1 (Monday) to 7 (Sunday).'};
  }
  if (!Number.isInteger(s.hour) || s.hour < 0 || s.hour > 23) return {error: 'hour must be 0 to 23.'};
  if (!Number.isInteger(s.animalsPerPost) ||
      s.animalsPerPost < MIN_ANIMALS_PER_POST || s.animalsPerPost > MAX_ANIMALS_PER_POST) {
    return {error: `animalsPerPost must be ${MIN_ANIMALS_PER_POST} to ${MAX_ANIMALS_PER_POST}.`};
  }
  return {
    schedule: {
      enabled: s.enabled,
      smartSuggestions: s.smartSuggestions,
      intervalWeeks: s.intervalWeeks,
      dayOfWeek: s.dayOfWeek,
      hour: s.hour,
      animalsPerPost: s.animalsPerPost,
    },
  };
}

/// Manila wall-clock parts of [nowMs]: dayOfWeek 1 (Mon) .. 7 (Sun), hour.
function manilaParts(nowMs) {
  const d = new Date(nowMs + MANILA_OFFSET_MS);
  const js = d.getUTCDay(); // 0 = Sunday
  return {dayOfWeek: js === 0 ? 7 : js, hour: d.getUTCHours()};
}

/// The first slot (dayOfWeek at hour:00 Manila) strictly after [fromMs].
function firstSlotAfter({dayOfWeek, hour}, fromMs) {
  const local = new Date(fromMs + MANILA_OFFSET_MS);
  const js = local.getUTCDay();
  const today = js === 0 ? 7 : js;
  const midnightLocal = Date.UTC(local.getUTCFullYear(), local.getUTCMonth(), local.getUTCDate());
  let slotLocal = midnightLocal + ((dayOfWeek - today + 7) % 7) * DAY_MS + hour * HOUR_MS;
  if (slotLocal - MANILA_OFFSET_MS <= fromMs) slotLocal += WEEK_MS;
  return slotLocal - MANILA_OFFSET_MS;
}

/// The slot after [dueMs] that is later than [nowMs] (skips slots missed
/// while the job was down, so staff get one reminder, not a backlog).
function advanceSlot(dueMs, intervalWeeks, nowMs) {
  const step = intervalWeeks * WEEK_MS;
  let next = dueMs + step;
  if (next <= nowMs) next += Math.ceil((nowMs - next + 1) / step) * step;
  return next;
}

/// What the hourly job should do for one organization's schedule:
///   {action: 'none'}
///   {action: 'init', nextDueMs}           (no slot stored yet)
///   {action: 'skip', nextDueMs}           (slot covered by a recent post)
///   {action: 'remind', kind: 'scheduled', nextDueMs}
///   {action: 'remind', kind: 'smart', nextDueMs}  (nextDueMs unchanged)
/// [smart] is the result of smartNudgeReason (null when nothing to say).
function scheduleDecision({schedule, nowMs, smart = null}) {
  const s = schedule || {};
  const nextDueMs = ms(s.nextDueAt);
  const lastPostMs = ms(s.lastPostedAt);
  const lastReminderMs = ms(s.lastReminderAt);

  if (s.enabled) {
    if (nextDueMs == null) return {action: 'init', nextDueMs: firstSlotAfter(s, nowMs)};
    if (nowMs >= nextDueMs) {
      const following = advanceSlot(nextDueMs, s.intervalWeeks, nowMs);
      const window = s.intervalWeeks * WEEK_MS * COVERED_FRACTION;
      if (lastPostMs != null && lastPostMs >= nextDueMs - window) {
        return {action: 'skip', nextDueMs: following};
      }
      return {action: 'remind', kind: 'scheduled', nextDueMs: following};
    }
  }

  if (s.smartSuggestions && smart) {
    // Once a day at the schedule's hour, so nudges land at a time the
    // organization chose rather than in the middle of the night.
    if (manilaParts(nowMs).hour !== s.hour) return {action: 'none'};
    const cooldown = SMART_COOLDOWN_DAYS * DAY_MS;
    if (lastPostMs != null && nowMs - lastPostMs < cooldown) return {action: 'none'};
    if (lastReminderMs != null && nowMs - lastReminderMs < cooldown) return {action: 'none'};
    if (s.enabled && nextDueMs != null && nextDueMs - nowMs < SMART_SLOT_GAP_DAYS * DAY_MS) {
      return {action: 'none'};
    }
    return {action: 'remind', kind: 'smart', nextDueMs};
  }
  return {action: 'none'};
}

function photoOf(animal) {
  for (const key of ['photoUrls', 'images', 'imageUrls']) {
    const list = animal[key];
    if (Array.isArray(list) && list.find((u) => typeof u === 'string' && u)) return true;
  }
  return Boolean(animal.photoUrl || animal.imageUrl);
}

/// Animals open for adoption that can go in a post: adoptable, not
/// archived, deceased or hidden from the public, and with a photo
/// (facebookPublishAnimalRecords refuses one without).
function promotableAnimals(animals) {
  return animals.filter((a) =>
    a && a.adoptionStatus === 'adoptable' &&
    a.archived !== true &&
    a.status !== 'deceased' &&
    a.publicProfileHidden !== true &&
    photoOf(a));
}

/// Last time each animal went out in a Page post, from facebookShares docs.
function lastSharedById(shares) {
  const out = new Map();
  for (const s of shares) {
    const at = ms(s.createdAt);
    if (at == null) continue;
    for (const id of s.animalRecordIds || []) {
      if (!out.has(id) || out.get(id) < at) out.set(id, at);
    }
  }
  return out;
}

/// Animal ids with an application still in progress.
function animalsWithOpenApplications(adoptions) {
  const out = new Set();
  for (const a of adoptions) {
    const id = a && a.personal && a.personal.animalRecordId;
    if (id && OPEN_APPLICATION_STATUSES.includes(a.status)) out.add(id);
  }
  return out;
}

/// Each promotable animal with why it needs a post, most in need first:
/// never shared, then no open application, then longest since shared,
/// then longest listed.
///   animals: [{id, ...animal doc}]
function rankAnimals({animals, shares = [], adoptions = [], nowMs}) {
  const lastShared = lastSharedById(shares);
  const withApps = animalsWithOpenApplications(adoptions);
  const rows = promotableAnimals(animals).map((a) => {
    const sharedAt = lastShared.has(a.id) ? lastShared.get(a.id) : null;
    const listedAt = ms(a.createdAt);
    const hasApplicants = withApps.has(a.id);
    const neverShared = sharedAt == null;
    const staleShare = !neverShared && nowMs - sharedAt >= STALE_SHARE_DAYS * DAY_MS;
    const listedLong = listedAt != null && nowMs - listedAt >= WAITING_LISTED_DAYS * DAY_MS;
    return {
      id: a.id,
      name: (a.name || '').trim(),
      neverShared,
      hasApplicants,
      lastSharedMs: sharedAt,
      listedMs: listedAt,
      waiting: !hasApplicants && listedLong && (neverShared || staleShare),
    };
  });
  const cmpNullFirst = (x, y) => (x == null ? (y == null ? 0 : -1) : (y == null ? 1 : x - y));
  rows.sort((a, b) =>
    (Number(b.neverShared) - Number(a.neverShared)) ||
    (Number(a.hasApplicants) - Number(b.hasApplicants)) ||
    cmpNullFirst(a.lastSharedMs, b.lastSharedMs) ||
    cmpNullFirst(a.listedMs, b.listedMs) ||
    a.id.localeCompare(b.id));
  return rows;
}

/// Why a smart nudge is worth sending now, or null.
function smartNudgeReason(ranked) {
  const fresh = ranked.filter((r) => r.neverShared && !r.hasApplicants);
  const waiting = ranked.filter((r) => r.waiting && !r.neverShared);
  if (fresh.length) return {kind: 'never_shared', count: fresh.length};
  if (waiting.length >= SMART_MIN_WAITING) return {kind: 'waiting', count: waiting.length};
  return null;
}

function plural(n, one, many) {
  return `${n} ${n === 1 ? one : (many || `${one}s`)}`;
}

function nameList(names) {
  const clean = names.filter(Boolean);
  if (!clean.length) return '';
  if (clean.length === 1) return clean[0];
  return `${clean.slice(0, -1).join(', ')} and ${clean[clean.length - 1]}`;
}

/// The push for a reminder, or null when no animal can be posted.
///   kind: 'scheduled' | 'smart'; picks: ranked rows to suggest;
///   total: how many animals are open for adoption; reason: smartNudgeReason.
function reminderMessage({kind, intervalWeeks, picks, total, reason}) {
  if (!picks.length) return null;
  const names = nameList(picks.map((p) => p.name));
  const suggestion = names ? `Suggested: ${names}.` : `${plural(picks.length, 'animal')} suggested.`;
  if (kind === 'scheduled') {
    const label = intervalWeeks === 1 ? 'Weekly' : intervalWeeks === 2 ? 'Fortnightly' : 'Monthly';
    return {
      title: `${label} adoption post is due`,
      body: `${plural(total, 'animal')} open for adoption. ${suggestion} Tap to review and post to Facebook.`,
    };
  }
  const why = reason && reason.kind === 'never_shared'
    ? `${plural(reason.count, 'animal')} open for adoption ${reason.count === 1 ? 'has' : 'have'} never been shared`
    : `${plural(reason ? reason.count : picks.length, 'animal')} ${(reason ? reason.count : picks.length) === 1 ? 'has' : 'have'} waited a while without applicants`;
  return {
    title: 'Good time for an adoption post',
    body: `${why}. ${suggestion} Tap to review and post to Facebook.`,
  };
}

/// A ready-to-edit caption for a post of [names].
function defaultCaption(names) {
  const list = nameList(names.filter(Boolean));
  if (!list) return 'These animals are looking for a home. Message us to adopt!';
  const one = names.filter(Boolean).length === 1;
  return `Meet ${list}! ${one ? 'This animal is' : 'They are'} ready for a loving home. ` +
    'Message us or apply through the ResPAWnd app to adopt.';
}

module.exports = {
  INTERVAL_WEEKS,
  MIN_ANIMALS_PER_POST,
  MAX_ANIMALS_PER_POST,
  OPEN_APPLICATION_STATUSES,
  STALE_SHARE_DAYS,
  WAITING_LISTED_DAYS,
  validateSchedule,
  manilaParts,
  firstSlotAfter,
  advanceSlot,
  scheduleDecision,
  promotableAnimals,
  rankAnimals,
  smartNudgeReason,
  reminderMessage,
  defaultCaption,
};
