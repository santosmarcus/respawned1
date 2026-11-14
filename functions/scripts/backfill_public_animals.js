// One-off backfill: writes `publicAnimals/{id}` for every animal that
// existed before the syncPublicAnimal function (functions/public_animals.js)
// was deployed, and removes public copies that shouldn't exist. Until this
// runs, the adoption list, public animal pages and QR scans show nothing
// for older animals.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. `gcloud auth application-default login`):
//   node scripts/backfill_public_animals.js --project=respawnd1-45021
//   node scripts/backfill_public_animals.js --project=respawnd1-45021 --apply
//
// Dry run unless --apply is passed. Safe to run again: it writes the same
// copy the trigger would.

const admin = require('firebase-admin');

const args = Object.fromEntries(
    process.argv.slice(2).map((a) => {
      const [k, v] = a.replace(/^--/, '').split('=');
      return [k, v === undefined ? true : v];
    }),
);
const APPLY = args.apply === true;

admin.initializeApp(args.project ? {projectId: args.project} : undefined);
const db = admin.firestore();

// Required after initializeApp, the same order as index.js.
const {publicAnimalOf} = require('../public_animals');

async function main() {
  const animals = await db.collection('animals').get();
  const existing = await db.collection('publicAnimals').get();
  const writes = [];
  const deletes = [];
  for (const d of animals.docs) {
    const copy = publicAnimalOf(d.data());
    if (copy) writes.push({ref: db.collection('publicAnimals').doc(d.id), copy});
  }
  const publicIds = new Set(writes.map((w) => w.ref.id));
  for (const d of existing.docs) {
    if (!publicIds.has(d.id)) deletes.push(d.ref);
  }
  console.log(`${animals.size} animals: ${writes.length} public copies to write, ${deletes.length} to remove.`);
  if (!APPLY) {
    console.log('Dry run. Pass --apply to write.');
    return;
  }
  let batch = db.batch();
  let n = 0;
  const flush = async () => {
    if (n === 0) return;
    await batch.commit();
    batch = db.batch();
    n = 0;
  };
  for (const w of writes) {
    batch.set(w.ref, w.copy);
    if (++n === 400) await flush();
  }
  for (const ref of deletes) {
    batch.delete(ref);
    if (++n === 400) await flush();
  }
  await flush();
  console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
