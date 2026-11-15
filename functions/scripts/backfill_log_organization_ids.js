// One-off backfill: stamps organizationId on case `activityLogs` and animal
// `managementLogs`, and on animal vaccinations / careRecords / medications /
// medicationDoses and case expenses, written before the stampCaseLogOrganization /
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

// Donations take their campaign's organizationId.
async function collectDonations() {
  const campaigns = await db.collection('campaigns').get();
  const orgByCampaign = new Map(campaigns.docs.map((d) => [d.id, nonEmpty(d.data().organizationId)]));
  const donations = await db.collection('donations').get();
  const updates = [];
  let skipped = 0;
  for (const d of donations.docs) {
    const orgId = orgByCampaign.get(d.data().campaignId) || null;
    if (!orgId) {
      skipped++;
      continue;
    }
    if (d.data().organizationId === orgId) continue;
    updates.push({ref: d.ref, organizationId: orgId});
  }
  console.log(`donations: ${donations.size} scanned, ${updates.length} to stamp, ${skipped} with no campaign organization.`);
  return updates;
}

// Cases with no organizationId at all get '' (not owned yet), so staff can
// query the shared review pool.
async function collectUnstampedCases() {
  const cases = await db.collection('cases').get();
  const updates = cases.docs
      .filter((d) => d.data().organizationId === undefined)
      .map((d) => ({ref: d.ref, organizationId: ''}));
  console.log(`cases: ${cases.size} scanned, ${updates.length} with no organizationId field to set to ''.`);
  return updates;
}

async function main() {
  const updates = [
    ...(await collectUnstampedCases()),
    ...(await collect('cases', 'activityLogs')),
    ...(await collect('animals', 'managementLogs')),
    // Records the dashboard reads across animals and cases (stamped by the
    // stamp*Organization triggers in audit_logs.js from now on).
    ...(await collect('animals', 'vaccinations')),
    ...(await collect('animals', 'careRecords')),
    ...(await collect('animals', 'medications')),
    ...(await collect('animals', 'medicationDoses')),
    ...(await collect('cases', 'expenses')),
    ...(await collect('cases', 'transportAssignments')),
    ...(await collect('adoptions', 'followUps')),
    ...(await collectDonations()),
    // Campaign allocations (analytics spending by category).
    ...(await collect('campaigns', 'allocations')),
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
