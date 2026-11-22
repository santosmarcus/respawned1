// Public web page for one animal, served at /animal/<id> through the
// Hosting rewrite in firebase.json. This is the "view full details" link
// staff put on Facebook posts and shared links; it works without the app or
// signing in and offers to open the animal in the app.
//
// Reads publicAnimals/{id} only (functions/public_animals.js keeps it to the
// fields meant for the public, and deletes it when the animal is archived,
// hidden or deceased, so the page then says the profile isn't available).
// HTML is built in functions/public_animal_page_rules.js.

const {onRequest} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {isValidAnimalId, buildAnimalPageHtml, buildNotFoundHtml} = require('./public_animal_page_rules');

const BASE_URL = (process.env.SHARE_BASE_URL || process.env.PAYMENT_RETURN_BASE_URL ||
  'https://respawnd1-45021.web.app').replace(/\/+$/, '');

const animalPageUrl = (animalId) => `${BASE_URL}/animal/${animalId}`;

exports.animalPageUrl = animalPageUrl;

exports.publicAnimalPage = onRequest({cors: false, maxInstances: 10}, async (req, res) => {
  if (req.method !== 'GET' && req.method !== 'HEAD') {
    res.status(405).set('Allow', 'GET, HEAD').send('Method not allowed');
    return;
  }
  // /animal/<id> (Hosting keeps the original path).
  const segments = req.path.split('/').filter(Boolean);
  const animalId = segments[0] === 'animal' ? segments[1] : segments[0];

  res.set('Content-Type', 'text/html; charset=utf-8');
  res.set('X-Content-Type-Options', 'nosniff');
  res.set('Referrer-Policy', 'strict-origin-when-cross-origin');

  if (!isValidAnimalId(animalId)) {
    res.status(404).set('Cache-Control', 'public, max-age=60').send(buildNotFoundHtml());
    return;
  }

  try {
    const db = admin.firestore();
    const snap = await db.collection('publicAnimals').doc(animalId).get();
    if (!snap.exists) {
      res.status(404).set('Cache-Control', 'public, max-age=60').send(buildNotFoundHtml());
      return;
    }
    const animal = snap.data();
    let org = null;
    if (typeof animal.organizationId === 'string' && animal.organizationId) {
      const orgSnap = await db.collection('organizations').doc(animal.organizationId).get();
      if (orgSnap.exists) {
        const o = orgSnap.data();
        // Public profile fields only.
        org = {name: o.name, location: o.location, phone: o.phone, email: o.email, facebookUrl: o.facebookUrl};
      }
    }
    // Short CDN cache: a status change (reserved, adopted) shows within minutes.
    res.status(200)
        .set('Cache-Control', 'public, max-age=120, s-maxage=300')
        .send(buildAnimalPageHtml({animalId, animal, org, pageUrl: animalPageUrl(animalId)}));
  } catch (e) {
    console.error('[publicAnimalPage] failed', animalId, e);
    res.status(500).set('Cache-Control', 'no-store').send(buildNotFoundHtml());
  }
});
