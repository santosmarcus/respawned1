// One-off backfill: cases referred to another organization before the
// target was stored on the case. For each case with status 'referred' and
// no referredToOrgId, the newest pending organization referral
// (cases/{id}/referrals, type anotherOrganization) is copied onto the case
// as referredToOrgId plus the `referral` summary the app and
// followUpCaseReferrals read. Its referredAt is set to now, so the 24-hour
// reminder and 48-hour return count from the backfill, not from the
// original referral. Until this runs, once the new rules are live those
// cases are visible only to their owning organization and platform staff.
// LGU/barangay referrals are left alone.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key):
//   node scripts/backfill_referral_targets.js --project=respawnd1-45021
//   node scripts/backfill_referral_targets.js --project=respawnd1-45021 --apply
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

async function main() {
  const cases = await db.collection('cases').where('status', '==', 'referred').get();
  let toFix = 0;
  let noTarget = 0;
  for (const doc of cases.docs) {
    const c = doc.data();
    if (typeof c.referredToOrgId === 'string' && c.referredToOrgId) continue;
    const refs = await doc.ref.collection('referrals').where('type', '==', 'anotherOrganization').get();
    const pending = refs.docs
        .filter((r) => r.get('status') === 'referredPending' && r.get('targetOrgId'))
        .sort((a, b) => (b.get('createdAt')?.toMillis?.() || 0) - (a.get('createdAt')?.toMillis?.() || 0));
    if (pending.length === 0) {
      noTarget++;
      continue;
    }
    const r = pending[0];
    const d = r.data();
    toFix++;
    const fromOrgId = d.fromOrgId || c.organizationId || '';
    let fromOrgName = d.fromOrgName || '';
    if (!fromOrgName && fromOrgId) {
      const org = await db.collection('organizations').doc(fromOrgId).get();
      fromOrgName = (org.exists && org.get('name')) || '';
    }
    console.log(`${doc.id}: referred to ${d.targetOrgName || d.targetOrgId} (referral ${r.id}) by ${fromOrgName || fromOrgId || 'unknown'}`);
    if (!APPLY) continue;
    await doc.ref.update({
      referredToOrgId: d.targetOrgId,
      referral: {
        referralId: r.id,
        targetOrgId: d.targetOrgId,
        targetOrgName: d.targetOrgName || null,
        fromOrgId,
        fromOrgName,
        referredAt: admin.firestore.FieldValue.serverTimestamp(),
        referredByUid: d.createdByUid || null,
        referredByName: d.createdByName || null,
        note: d.note || null,
        backfilled: true,
      },
    });
    await r.ref.update({fromOrgId, fromOrgName});
  }
  console.log(`${cases.size} referred cases: ${toFix} to update, ${noTarget} without a pending organization referral (LGU or answered).`);
  if (!APPLY) console.log('Dry run. Pass --apply to write.');
  else console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
