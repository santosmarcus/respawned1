// One-off backfill: writes `users/{uid}.transportStatus` (the status of the
// rider's newest transport offer) for riders who had offers before the
// syncRiderTransportStatus function (functions/rider_status.js) was
// deployed. Until it runs, Assign Transporter shows those riders as
// Available.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key):
//   node scripts/backfill_rider_status.js --project=respawnd1-45021
//   node scripts/backfill_rider_status.js --project=respawnd1-45021 --apply
//
// Dry run unless --apply is passed. Safe to run again.

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
const {writeRiderStatus} = require('../rider_status');

async function main() {
  const offers = await db.collectionGroup('transportAssignments').get();
  const riders = new Set();
  for (const d of offers.docs) {
    const riderId = d.data().riderId;
    if (typeof riderId === 'string' && riderId) riders.add(riderId);
  }
  console.log(`${offers.size} offers from ${riders.size} riders.`);
  if (!APPLY) {
    console.log('Dry run. Pass --apply to write.');
    return;
  }
  for (const riderId of riders) await writeRiderStatus(db, riderId);
  console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
