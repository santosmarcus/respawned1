// Run with: cd functions && npm test   (node --test, no Firebase needed)

const test = require('node:test');
const assert = require('node:assert');
const {normalizePublishItems, MAX_PHOTOS} = require('./facebook_share_rules');
const {
  isValidAnimalId,
  captionsByUrl,
  statusLabel,
  healthSummary,
  appLinks,
  buildAnimalPageHtml,
  buildNotFoundHtml,
} = require('./public_animal_page_rules');
const {publicAnimalOf} = require('./public_animals');

const A = 'https://firebasestorage.googleapis.com/a.jpg';
const B = 'https://firebasestorage.googleapis.com/b.jpg';

test('publish items keep picked photos and trimmed captions', () => {
  const items = normalizePublishItems({
    items: [{animalId: 'cat1', photos: [{url: A, caption: '  Sunbathing  '}, {url: B}]}],
  });
  assert.deepStrictEqual(items, [{animalId: 'cat1', legacy: false, photos: [{url: A, caption: 'Sunbathing'}, {url: B, caption: ''}]}]);
});

test('older builds sending animalRecordIds still publish', () => {
  const items = normalizePublishItems({animalRecordIds: ['a', 'b']});
  assert.deepStrictEqual(items.map((i) => [i.animalId, i.legacy]), [['a', true], ['b', true]]);
});

test('publish input is refused when malformed', () => {
  assert.throws(() => normalizePublishItems({}), /at least one/);
  assert.throws(() => normalizePublishItems({items: [{animalId: '../x', photos: []}]}), /Invalid animal/);
  assert.throws(() => normalizePublishItems({items: [{animalId: 'a', photos: [{url: 'http://x/a.jpg'}]}]}), /Invalid photo/);
  assert.throws(() => normalizePublishItems({items: [{animalId: 'a', photos: []}, {animalId: 'a', photos: []}]}), /twice/);
  assert.throws(() => normalizePublishItems({items: [{animalId: 'a', photos: [{url: A, caption: 'x'.repeat(301)}]}]}), /descriptions/);
  assert.throws(() => normalizePublishItems({link: 'javascript:alert(1)', items: [{animalId: 'a', photos: []}]}), /https/);
  const tooMany = Array.from({length: MAX_PHOTOS + 1}, (_, i) => ({url: `${A}?${i}`}));
  assert.throws(() => normalizePublishItems({items: [{animalId: 'a', photos: tooMany}]}), /up to/);
});

test('public copy keeps captions for public photos only', () => {
  const copy = publicAnimalOf({
    name: 'Mochi',
    photoUrls: [A, B],
    photoCaptions: [{url: A, caption: ' First day '}, {url: 'https://elsewhere/x.jpg', caption: 'stale'}, {url: B, caption: ' '}],
    medicalNotes: 'private',
  });
  assert.deepStrictEqual(copy.photoCaptions, [{url: A, caption: 'First day'}]);
  assert.strictEqual(copy.medicalNotes, undefined);
});

test('animal page helpers', () => {
  assert.strictEqual(isValidAnimalId('AbC_12-x'), true);
  assert.strictEqual(isValidAnimalId('a/b'), false);
  assert.deepStrictEqual(captionsByUrl([{url: A, caption: 'hi'}, {url: 'nope', caption: 'x'}, null]), {[A]: 'hi'});
  assert.strictEqual(statusLabel({adoptionStatus: 'adoptable'}), 'Available for adoption');
  assert.strictEqual(statusLabel({adoptionStatus: 'not_ready'}), 'Not yet available');
  assert.deepStrictEqual(healthSummary({vaccinated: true, specialNeeds: true, specialNeedsTypes: ['Blind']}),
      ['Vaccinated', 'Special needs: Blind']);
  const links = appLinks('abc', 'https://site/animal/abc');
  assert.strictEqual(links.scheme, 'respawnd://open/animal/abc');
  assert.match(links.androidIntent, /^intent:\/\/open\/animal\/abc#Intent;scheme=respawnd;package=com\.dlsu\.cap2507\.respawnd1;/);
});

test('animal page escapes record text and carries og tags', () => {
  const html = buildAnimalPageHtml({
    animalId: 'abc',
    animal: {
      name: 'Mochi<script>alert(1)</script>',
      species: 'Cat',
      adoptionStatus: 'adoptable',
      description: 'Sweet & calm',
      photoUrls: [A, B],
      photoCaptions: [{url: A, caption: 'Loves "sun"'}],
    },
    org: {name: 'Paws </script> Co', phone: '+63 912 345 6789'},
    pageUrl: 'https://respawnd1-45021.web.app/animal/abc',
  });
  assert.ok(!html.includes('<script>alert(1)'));
  assert.ok(!html.includes('Paws </script>'));
  assert.ok(html.includes('Mochi&lt;script&gt;'));
  assert.ok(html.includes(`<meta property="og:image" content="${A}">`));
  assert.ok(html.includes('<figcaption>Loves &quot;sun&quot;</figcaption>'));
  assert.ok(html.includes('href="tel:+639123456789"'));
  // Exactly one closing script tag: the page's own.
  assert.strictEqual(html.split('</script>').length, 2);
});

test('not-found page has no record details', () => {
  assert.match(buildNotFoundHtml(), /Profile not available/);
});
