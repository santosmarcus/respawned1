// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {scorePair, matchStrength, distanceKm, colorTokens, MIN_SCORE, STRONG_SCORE} = require('./pet_match_rules');

const DAY = 24 * 60 * 60 * 1000;
const t0 = Date.UTC(2026, 10, 1, 8, 0);

// Manila-ish coordinates; 0.009° latitude ≈ 1 km.
function lost(over = {}) {
  return {
    species: 'Dog', breed: 'Shih Tzu', sex: 'Male', colorMarkings: 'White with brown patches',
    lat: 14.5649, lng: 120.9932, lastSeenDate: t0, createdAt: t0, ...over,
  };
}
function found(over = {}) {
  return {
    species: 'Dog', breed: 'Shih Tzu', sex: 'Male', colorMarkings: 'white, brown patches on back',
    lat: 14.5649 + 0.005, lng: 120.9932, createdAt: t0 + DAY, ...over,
  };
}

test('a near-identical pair scores as strong', () => {
  const r = scorePair(lost(), found());
  assert.ok(r);
  assert.ok(r.score >= STRONG_SCORE, `score ${r.score}`);
  assert.strictEqual(matchStrength(r.score), 'strong');
  assert.strictEqual(r.breakdown.distance, 35);
  assert.strictEqual(r.breakdown.breed, 20);
  assert.strictEqual(r.breakdown.sex, 10);
});

test('different species is ruled out', () => {
  assert.strictEqual(scorePair(lost(), found({species: 'Cat'})), null);
});

test('species compare ignores case and spaces', () => {
  assert.ok(scorePair(lost({species: ' dog '}), found({species: 'DOG'})));
});

test('farther than 25 km is ruled out', () => {
  assert.strictEqual(scorePair(lost(), found({lat: 14.5649 + 0.3})), null); // ~33 km
});

test('found well before last seen is ruled out', () => {
  assert.strictEqual(scorePair(lost(), found({createdAt: t0 - 3 * DAY})), null);
});

test('found up to a day before last seen is allowed (date slop)', () => {
  assert.ok(scorePair(lost(), found({createdAt: t0 - 12 * 60 * 60 * 1000})));
});

test('found more than 60 days later is ruled out', () => {
  assert.strictEqual(scorePair(lost(), found({createdAt: t0 + 61 * DAY})), null);
});

test('conflicting sex is ruled out, unknown sex is not', () => {
  assert.strictEqual(scorePair(lost(), found({sex: 'Female'})), null);
  const r = scorePair(lost(), found({sex: 'Unknown'}));
  assert.ok(r);
  assert.strictEqual(r.breakdown.sex, 5);
});

test('missing location is ruled out', () => {
  assert.strictEqual(scorePair(lost({lat: null}), found()), null);
});

test('lost report without lastSeenDate falls back to createdAt', () => {
  const r = scorePair(lost({lastSeenDate: null}), found());
  assert.ok(r);
  assert.strictEqual(r.breakdown.dayGap, 1);
});

test('accepts Firestore-like timestamps', () => {
  const ts = (ms) => ({toMillis: () => ms});
  const r = scorePair(lost({lastSeenDate: ts(t0), createdAt: ts(t0)}), found({createdAt: ts(t0 + DAY)}));
  assert.ok(r);
});

test('blank fields get half points', () => {
  const r = scorePair(lost({breed: '', colorMarkings: ''}), found());
  assert.strictEqual(r.breakdown.breed, 10);
  assert.strictEqual(r.breakdown.color, 10);
});

test('mixed breed gets partial breed points, a different breed none', () => {
  assert.strictEqual(scorePair(lost({breed: 'Aspin'}), found()).breakdown.breed, 8);
  assert.strictEqual(scorePair(lost(), found({breed: 'Poodle'})).breakdown.breed, 0);
});

test('distance points fall off with distance', () => {
  const near = scorePair(lost(), found()).breakdown.distance;
  const far = scorePair(lost(), found({lat: 14.5649 + 0.12})).breakdown.distance; // ~13 km
  assert.ok(far < near && far > 0, `near ${near}, far ${far}`);
});

test('a weak pair lands below the save threshold', () => {
  const r = scorePair(
    lost({breed: 'Shih Tzu', colorMarkings: 'all black'}),
    found({breed: 'Poodle', colorMarkings: 'white curly', lat: 14.5649 + 0.18, createdAt: t0 + 50 * DAY}),
  );
  assert.ok(r);
  assert.ok(r.score < MIN_SCORE, `score ${r.score}`);
  assert.strictEqual(matchStrength(r.score), null);
});

test('color tokens drop filler words and short tokens', () => {
  assert.deepStrictEqual([...colorTokens('White fur with a brown spot on the ear')].sort(),
    ['brown', 'ear', 'spot', 'white']);
});

test('distanceKm is roughly right', () => {
  const d = distanceKm({lat: 14.5649, lng: 120.9932}, {lat: 14.5649 + 0.009, lng: 120.9932});
  assert.ok(d > 0.95 && d < 1.05, `d ${d}`);
});
