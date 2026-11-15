// One-off backfill: writes `users/{uid}.volunteerStats` (attended count and
// badges) for volunteers whose attendance was marked before the
// syncVolunteerStats function (functions/volunteer_stats.js) was deployed.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. `gcloud auth application-default login`):
//   node scripts/backfill_volunteer_stats.js --project=respawnd1-45021
//   node scripts/backfill_volunteer_stats.js --project=respawnd1-45021 --apply
//
// Dry run unless --apply is passed. Safe to run again: it writes the same
// stats the trigger would.

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
const {computeVolunteerStats} = require('../volunteer_stats');

async function main() {
  // Everyone with at least one sign-up, from the staff-side registrations.
  const regs = await db.collectionGroup('registrations').get();
  const uids = new Set();
  for (const d of regs.docs) {
    // Only events/{id}/registrations.
    if (d.ref.parent.parent && d.ref.parent.parent.parent.id === 'events') uids.add(d.id);
  }
  console.log(`${regs.size} registrations from ${uids.size} volunteers.`);
  let withBadges = 0;
  for (const uid of uids) {
    const user = db.collection('users').doc(uid);
    if (!(await user.get()).exists) continue;
    const eventIds = regs.docs.filter((d) => d.id === uid).map((d) => d.ref.parent.parent.id);
    const stats = await computeVolunteerStats(db, uid, eventIds);
    if (stats.badges.length > 0) withBadges++;
    if (APPLY) await user.set({volunteerStats: stats}, {merge: true});
  }
  console.log(`${withBadges} volunteers have at least one badge.`);
  console.log(APPLY ? 'Done.' : 'Dry run. Pass --apply to write.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
