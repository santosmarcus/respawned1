// One-off backfill: stamps organizationId on cases, animals, and adoptions
// written before the app started recording it.
//
// Usage (from functions/, with Application Default Credentials for the
// project, e.g. `gcloud auth application-default login`):
//   node scripts/backfill_organization_ids.js --project=respawnd1-45021 --default-org=<orgId>
//   node scripts/backfill_organization_ids.js --project=respawnd1-45021 --default-org=<orgId> --apply
//
// Dry run unless --apply is passed. Never overwrites an existing
// organizationId. Resolution order, most specific first:
//   cases:     closedByOrganizationId -> a linked animal's org -> default org
//   animals:   linked case's org -> intake staff's users/{uid}.organizationId -> default org
//   adoptions: the animal record's org -> the source case's org -> default org
// Cases still waiting on an organization (pending review, rejected,
// referred, possible duplicate, merged) never get the default org, and
// adoptions with no animal record or case link are left alone.

const admin = require('firebase-admin');

const args = Object.fromEntries(
    process.argv.slice(2).map((a) => {
      const [k, v] = a.replace(/^--/, '').split('=');
      return [k, v === undefined ? true : v];
    }),
);
const APPLY = args.apply === true;
const DEFAULT_ORG = typeof args['default-org'] === 'string' ? args['default-org'] : null;

admin.initializeApp(args.project ? {projectId: args.project} : undefined);
const db = admin.firestore();

const UNOWNED_CASE_STATUSES = new Set(['pending', 'rejected', 'referred', 'possibleDuplicate', 'merged']);

const nonEmpty = (v) => (typeof v === 'string' && v.length > 0 ? v : null);

async function main() {
  if (DEFAULT_ORG) {
    const org = await db.collection('organizations').doc(DEFAULT_ORG).get();
    if (!org.exists) throw new Error(`--default-org ${DEFAULT_ORG} does not exist.`);
  }

  const [casesSnap, animalsSnap, adoptionsSnap] = await Promise.all([
    db.collection('cases').get(),
    db.collection('animals').get(),
    db.collection('adoptions').get(),
  ]);

  // Resolved org per doc id, seeded with what's already stored.
  const caseOrg = new Map();
  const animalOrg = new Map();
  for (const d of casesSnap.docs) caseOrg.set(d.id, nonEmpty(d.data().organizationId));
  for (const d of animalsSnap.docs) animalOrg.set(d.id, nonEmpty(d.data().organizationId));

  const updates = []; // {ref, organizationId, source}
  const userOrgCache = new Map();
  async function userOrg(uid) {
    if (!uid) return null;
    if (!userOrgCache.has(uid)) {
      const u = await db.collection('users').doc(uid).get();
      userOrgCache.set(uid, nonEmpty(u.exists ? u.data().organizationId : null));
    }
    return userOrgCache.get(uid);
  }

  // Pass 1: cases with direct evidence.
  for (const d of casesSnap.docs) {
    if (caseOrg.get(d.id)) continue;
    const closedBy = nonEmpty(d.data().closedByOrganizationId);
    if (closedBy) {
      caseOrg.set(d.id, closedBy);
      updates.push({ref: d.ref, organizationId: closedBy, source: 'closedByOrganizationId'});
    }
  }

  // Pass 2: animals.
  for (const d of animalsSnap.docs) {
    if (animalOrg.get(d.id)) continue;
    const data = d.data();
    let orgId = null;
    let source = null;
    const linkedCaseId = nonEmpty(data.linkedCaseId);
    if (linkedCaseId && caseOrg.get(linkedCaseId)) {
      orgId = caseOrg.get(linkedCaseId);
      source = 'linkedCase';
    }
    if (!orgId) {
      orgId = await userOrg(nonEmpty(data.intakeStaffId));
      if (orgId) source = 'intakeStaff';
    }
    if (!orgId && DEFAULT_ORG) {
      orgId = DEFAULT_ORG;
      source = 'default';
    }
    if (orgId) {
      animalOrg.set(d.id, orgId);
      updates.push({ref: d.ref, organizationId: orgId, source});
    }
  }

  // Pass 3: remaining cases, from linked animals, then the default org.
  const animalOrgByCase = new Map();
  for (const d of animalsSnap.docs) {
    const linkedCaseId = nonEmpty(d.data().linkedCaseId);
    if (linkedCaseId && animalOrg.get(d.id)) animalOrgByCase.set(linkedCaseId, animalOrg.get(d.id));
  }
  for (const d of casesSnap.docs) {
    if (caseOrg.get(d.id)) continue;
    const data = d.data();
    let orgId = animalOrgByCase.get(d.id) || animalOrg.get(nonEmpty(data.sourceAnimalRecordId)) || null;
    let source = orgId ? 'linkedAnimal' : null;
    if (!orgId && DEFAULT_ORG && !UNOWNED_CASE_STATUSES.has(data.status)) {
      orgId = DEFAULT_ORG;
      source = 'default';
    }
    if (orgId) {
      caseOrg.set(d.id, orgId);
      updates.push({ref: d.ref, organizationId: orgId, source});
    }
  }

  // Pass 4: adoptions.
  for (const d of adoptionsSnap.docs) {
    const data = d.data();
    if (nonEmpty(data.organizationId)) continue;
    const animalRecordId = nonEmpty(data.personal && data.personal.animalRecordId);
    const sourceCaseId = nonEmpty(data.sourceCaseId);
    let orgId = null;
    let source = null;
    if (animalRecordId && animalOrg.get(animalRecordId)) {
      orgId = animalOrg.get(animalRecordId);
      source = 'animalRecord';
    } else if (sourceCaseId && caseOrg.get(sourceCaseId)) {
      orgId = caseOrg.get(sourceCaseId);
      source = 'sourceCase';
    } else if ((animalRecordId || sourceCaseId) && DEFAULT_ORG) {
      orgId = DEFAULT_ORG;
      source = 'default';
    }
    if (orgId) updates.push({ref: d.ref, organizationId: orgId, source});
  }

  // Report.
  const summary = {};
  for (const u of updates) {
    const key = `${u.ref.parent.id} <- ${u.source}`;
    summary[key] = (summary[key] || 0) + 1;
  }
  const missing = {
    cases: casesSnap.docs.filter((d) => !caseOrg.get(d.id)).length,
    animals: animalsSnap.docs.filter((d) => !animalOrg.get(d.id)).length,
  };
  console.log(`Scanned ${casesSnap.size} cases, ${animalsSnap.size} animals, ${adoptionsSnap.size} adoptions.`);
  console.table(summary);
  console.log(`Left without an organizationId: ${missing.cases} cases, ${missing.animals} animals.`);
  if (!DEFAULT_ORG) console.log('No --default-org given; docs with no other evidence were skipped.');

  if (!APPLY) {
    console.log(`\nDry run: ${updates.length} docs would be updated. Re-run with --apply to write.`);
    return;
  }

  for (let i = 0; i < updates.length; i += 400) {
    const batch = db.batch();
    for (const u of updates.slice(i, i + 400)) batch.update(u.ref, {organizationId: u.organizationId});
    await batch.commit();
  }
  console.log(`\nUpdated ${updates.length} docs.`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
