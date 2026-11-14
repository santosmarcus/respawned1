// One-off backfill: stamps organizationId on case `activityLogs` and animal
// `managementLogs` written before the stampCaseLogOrganization /
// stampAnimalLogOrganization functions (functions/audit_logs.js) existed.
// The admin Audit page's Rescue and Records tabs filter on it, so older logs
// stay hidden from organization staff until this runs.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. `gcloud auth application-default login`):
//   node scripts/backfill_log_organization_ids.js --project=respawnd1-45021
//   node scripts/backfill_log_organization_ids.js --project=respawnd1-45021 --apply
//
// Dry run unless --apply is passed. Each log gets its parent case/animal's
// current organizationId; logs that already have one are left alone, and
// logs whose parent has no organization are skipped. Run
// backfill_organization_ids.js first if cases/animals are still missing
// theirs.

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

const nonEmpty = (v) => (typeof v === 'string' && v.length > 0 ? v : null);

async function collect(parentCollection, logCollection) {
  const parents = await db.collection(parentCollection).get();
  const orgByParent = new Map(parents.docs.map((d) => [d.id, nonEmpty(d.data().organizationId)]));
  const logs = await db.collectionGroup(logCollection).get();
  const updates = [];
  let skipped = 0;
  for (const d of logs.docs) {
    const parent = d.ref.parent.parent;
    // collectionGroup('activityLogs') also matches organizations/{id}/activityLogs.
    if (!parent || parent.parent.id !== parentCollection) continue;
    if (nonEmpty(d.data().organizationId)) continue;
    const orgId = orgByParent.get(parent.id) || null;
    if (!orgId) {
      skipped++;
      continue;
    }
    updates.push({ref: d.ref, organizationId: orgId});
  }
  console.log(`${parentCollection}/*/${logCollection}: ${logs.size} scanned, ${updates.length} to stamp, ${skipped} with no parent organization.`);
  return updates;
}

async function main() {
  const updates = [
    ...(await collect('cases', 'activityLogs')),
    ...(await collect('animals', 'managementLogs')),
  ];
  if (!APPLY) {
    console.log(`\nDry run: ${updates.length} logs would be updated. Re-run with --apply to write.`);
    return;
  }
  for (let i = 0; i < updates.length; i += 400) {
    const batch = db.batch();
    for (const u of updates.slice(i, i + 400)) batch.update(u.ref, {organizationId: u.organizationId});
    await batch.commit();
  }
  console.log(`\nUpdated ${updates.length} logs.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
