// One-off migration: copies the platform-wide shelter settings document
// (settings/shelter: maxCapacity, isolationCapacity, monthlyBudget,
// foodPerDayKg, ridersNeeded and who/when last updated) to the
// organization's own document at organizations/{orgId}/settings/shelter,
// which the app now reads first (lib/features/adminhome/dashboard/
// shelter_settings.dart). Until an organization has its own document the
// app keeps reading settings/shelter, so this can run before or after the
// new app build. The old document is left as it is.
//
// The old document had one set of numbers for the whole platform, so name
// the organization(s) they belong to:
//   --org=ID[,ID...]   copy to these organizations
//   --all              copy to every approved organization
// With neither, the dry run lists the organizations to choose from. An
// organization that already has its own settings is skipped unless
// --overwrite is passed.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key):
//   node scripts/migrate_shelter_settings.js --project=respawnd1-45021 --org=ORG_ID
//   node scripts/migrate_shelter_settings.js --project=respawnd1-45021 --org=ORG_ID --apply
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
const OVERWRITE = args.overwrite === true;

admin.initializeApp(args.project ? {projectId: args.project} : undefined);
const db = admin.firestore();

const FIELDS = [
  'maxCapacity', 'isolationCapacity', 'monthlyBudget', 'foodPerDayKg', 'ridersNeeded',
  'updatedAt', 'updatedBy', 'updatedByName',
];

async function main() {
  const legacy = await db.collection('settings').doc('shelter').get();
  if (!legacy.exists) {
    console.log('settings/shelter does not exist. Nothing to migrate.');
    return;
  }
  const data = legacy.data();
  const values = Object.fromEntries(FIELDS.filter((k) => k in data).map((k) => [k, data[k]]));
  console.log('settings/shelter:', JSON.stringify(values));

  const orgs = await db.collection('organizations').get();
  let targets;
  if (typeof args.org === 'string' && args.org) {
    targets = args.org.split(',').map((s) => s.trim()).filter(Boolean);
  } else if (args.all === true) {
    targets = orgs.docs
        .filter((o) => (o.get('verificationStatus') || 'approved') === 'approved')
        .map((o) => o.id);
  } else {
    console.log('Organizations (pass --org=ID or --all):');
    for (const o of orgs.docs) {
      console.log(`  ${o.id}  ${o.get('name') || '(no name)'}  [${o.get('verificationStatus') || 'approved'}]`);
    }
    return;
  }

  for (const orgId of targets) {
    const org = orgs.docs.find((o) => o.id === orgId);
    if (!org) {
      console.log(`${orgId}: no such organization, skipped.`);
      continue;
    }
    const ref = db.collection('organizations').doc(orgId).collection('settings').doc('shelter');
    const existing = await ref.get();
    if (existing.exists && !OVERWRITE) {
      console.log(`${orgId} (${org.get('name') || ''}): already has its own settings, skipped (--overwrite to replace).`);
      continue;
    }
    console.log(`${orgId} (${org.get('name') || ''}): ${APPLY ? 'writing' : 'would write'} the values above.`);
    if (APPLY) {
      await ref.set({
        ...values,
        migratedFrom: 'settings/shelter',
        migratedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    }
  }
  if (!APPLY) console.log('Dry run. Pass --apply to write.');
  else console.log('Done.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
