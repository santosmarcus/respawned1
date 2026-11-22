// Pure scoring for lost/found pet matches (scorePetAlertMatches in
// functions/pet_matching.js). No Firebase here, so `node --test` can check
// it directly.
//
// A lost report and a found report are first checked against hard rules
// (same species, close enough, plausible timing, no sex conflict). Pairs
// that pass get a 0–100 score:
//
//   distance  35  full within 1 km, linear to 0 at MAX_KM
//   time      15  full if found within 3 days of last seen, linear to 0 at MAX_DAYS
//   breed     20  same breed 20, either side mixed/aspin/puspin 8, different 0
//   color     20  word overlap of the two color/markings descriptions
//   sex       10  same sex
//
// A field one side left blank gets half its points, so missing details
// neither sink nor boost a match.

const MAX_KM = 25;
const MAX_DAYS = 60;
const MIN_SCORE = 40; // below this, no match is saved
const STRONG_SCORE = 70; // at or above this, the owner is notified

const FULL_DISTANCE_KM = 1;
const FULL_TIME_DAYS = 3;
const EARLY_FOUND_GRACE_DAYS = 1; // found up to a day "before" last seen (clock/date slop)

const DAY_MS = 24 * 60 * 60 * 1000;

const MIXED_BREEDS = new Set([
  'mixed', 'mixed breed', 'mix', 'aspin', 'puspin', 'mongrel', 'unknown', 'not sure', 'other',
]);
const UNKNOWN_SEX = new Set(['', 'unknown', 'not sure']);
const COLOR_STOPWORDS = new Set([
  'and', 'with', 'the', 'has', 'have', 'some', 'color', 'colour', 'colored', 'coloured',
  'fur', 'coat', 'hair', 'body', 'very', 'little', 'bit', 'like', 'its', 'his', 'her',
]);

function norm(s) {
  return (s === null || s === undefined ? '' : String(s)).trim().toLowerCase();
}

// Accepts a Firestore Timestamp, a Date, or epoch milliseconds.
function toMillis(t) {
  if (t === null || t === undefined) return null;
  if (typeof t === 'number') return Number.isFinite(t) ? t : null;
  if (t instanceof Date) return t.getTime();
  if (typeof t.toMillis === 'function') return t.toMillis();
  return null;
}

function distanceKm(a, b) {
  const R = 6371;
  const rad = (d) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function colorTokens(s) {
  return new Set(
    norm(s).split(/[^a-z]+/).filter((t) => t.length > 2 && !COLOR_STOPWORDS.has(t)),
  );
}

// Linear falloff: 1 up to `full`, 0 at `zero`.
function falloff(value, full, zero) {
  if (value <= full) return 1;
  return Math.max(0, 1 - (value - full) / (zero - full));
}

/// Scores one lost/found pair.
/// Returns null if the pair is impossible, else {score, breakdown}.
/// [lost] and [found] are petAlerts documents' data (lat, lng, species,
/// breed, sex, colorMarkings, createdAt, and lastSeenDate on the lost one).
function scorePair(lost, found) {
  if (!lost || !found) return null;

  const species = norm(lost.species);
  if (!species || species !== norm(found.species)) return null;

  if (![lost.lat, lost.lng, found.lat, found.lng].every((v) => typeof v === 'number')) return null;
  const km = distanceKm(lost, found);
  if (km > MAX_KM) return null;

  const lastSeenMs = toMillis(lost.lastSeenDate) ?? toMillis(lost.createdAt);
  const foundMs = toMillis(found.createdAt);
  if (lastSeenMs === null || foundMs === null) return null;
  const gapDays = (foundMs - lastSeenMs) / DAY_MS;
  if (gapDays < -EARLY_FOUND_GRACE_DAYS || gapDays > MAX_DAYS) return null;

  const lostSex = norm(lost.sex);
  const foundSex = norm(found.sex);
  const sexKnown = !UNKNOWN_SEX.has(lostSex) && !UNKNOWN_SEX.has(foundSex);
  if (sexKnown && lostSex !== foundSex) return null;

  const points = {};
  points.distance = 35 * falloff(km, FULL_DISTANCE_KM, MAX_KM);
  points.time = 15 * falloff(Math.max(0, gapDays), FULL_TIME_DAYS, MAX_DAYS);
  points.sex = sexKnown ? 10 : 5;

  const lostBreed = norm(lost.breed);
  const foundBreed = norm(found.breed);
  if (!lostBreed || !foundBreed) points.breed = 10;
  else if (lostBreed === foundBreed) points.breed = 20;
  else if (MIXED_BREEDS.has(lostBreed) || MIXED_BREEDS.has(foundBreed)) points.breed = 8;
  else points.breed = 0;

  const lostColors = colorTokens(lost.colorMarkings);
  const foundColors = colorTokens(found.colorMarkings);
  if (!lostColors.size || !foundColors.size) {
    points.color = 10;
  } else {
    const shared = [...lostColors].filter((t) => foundColors.has(t)).length;
    const union = new Set([...lostColors, ...foundColors]).size;
    points.color = 20 * (shared / union);
  }

  for (const k of Object.keys(points)) points[k] = Math.round(points[k]);
  const score = Math.min(100, Object.values(points).reduce((s, v) => s + v, 0));

  return {
    score,
    breakdown: {
      ...points,
      distanceKm: Math.round(km * 10) / 10,
      dayGap: Math.round(gapDays),
    },
  };
}

function matchStrength(score) {
  if (score >= STRONG_SCORE) return 'strong';
  if (score >= MIN_SCORE) return 'possible';
  return null;
}

module.exports = {
  scorePair,
  matchStrength,
  distanceKm,
  colorTokens,
  MAX_KM,
  MAX_DAYS,
  MIN_SCORE,
  STRONG_SCORE,
};
