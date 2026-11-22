const test = require('node:test');
const assert = require('node:assert');
const {collarTagOf, tagIdFor} = require('./animal_collar_tags');

test('tag id is derived from the animal id', () => {
  assert.strictEqual(tagIdFor('abc'), 'animal-abc');
});

test('copies the animal and organization onto the collar tag', () => {
  const tag = collarTagOf(
    'a1',
    {
      name: 'Mochi', age: '2 years', sex: 'Female', breed: '', species: 'Cat',
      size: 'Small', coatLength: 'Short', spayedNeutered: true, vaccinated: false,
      photoUrls: ['not-a-url', 'https://x/y.jpg'], chronicConditions: 'Asthma',
      specialNeedsTypes: ['Blind'], organizationId: 'org1', qrTagId: 'ABCD2345',
    },
    {name: 'Paws Org', contactNumber: '0917', email: 'a@b.c'},
  );
  assert.strictEqual(tag.animalId, 'a1');
  assert.strictEqual(tag.name, 'Mochi');
  assert.strictEqual(tag.birthday, '2 years');
  assert.strictEqual(tag.breed, 'Cat');
  assert.strictEqual(tag.colorMarkings, 'Cat · Small · Short coat');
  assert.strictEqual(tag.petImageUrl, 'https://x/y.jpg');
  assert.strictEqual(tag.medicalCondition, 'Asthma, Blind');
  assert.strictEqual(tag.isSpayedNeutered, true);
  assert.strictEqual(tag.ownerName, 'Paws Org');
  assert.strictEqual(tag.ownerMobile, '0917');
  assert.strictEqual(tag.qrEnabled, true);
  assert.strictEqual(tag.animalQrCode, 'ABCD2345');
  assert.strictEqual(tag.animalNfcCode, '');
  assert.strictEqual(tag.archived, false);
});
