// One-off backfill: writes `publicCases/{id}` for every rescue report that
// existed before the syncPublicCase function (functions/public_cases.js)
// was deployed, and removes public copies whose case is gone. Until this
// runs, the Explore map and feed, nearby reports, geofences and the
// transporter job board show nothing for older reports.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. `gcloud auth application-default login`):
//   node scripts/backfill_public_cases.js --project=respawnd1-45021
//   node scripts/backfill_public_cases.js --project=respawnd1-45021 --apply
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
const {publicCaseOf} = require('../public_cases');

async function main() {
  const cases = await db.collection('cases').get();
  const existing = await db.collection('publicCases').get();
  const writes = [];
  const deletes = [];
  for (const d of cases.docs) {
    const copy = publicCaseOf(d.data());
    if (copy) writes.push({ref: db.collection('publicCases').doc(d.id), copy});
  }
  const publicIds = new Set(writes.map((w) => w.ref.id));
  for (const d of existing.docs) {
    if (!publicIds.has(d.id)) deletes.push(d.ref);
  }
  console.log(`${cases.size} cases: ${writes.length} public copies to write, ${deletes.length} to remove.`);
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
