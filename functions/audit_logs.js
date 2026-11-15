// Organization stamp on case and animal logs.
//
// The admin Audit page's Rescue and Records tabs read every case's
// `activityLogs` and every animal's `managementLogs` with one
// collection-group query each. firestore.rules lets staff read only their
// own organization's logs, through a query that filters on organizationId,
// so each log needs that field. Many screens write these logs (some by
// reporters and transporters, who don't know the owning organization), so
// it is stamped here from the parent case/animal instead of by every
// writer. The value the client sent, if any, is always replaced, so a log
// can't be planted in another organization's audit trail.
//
// Existing logs: scripts/backfill_log_organization_ids.js.

const {onDocumentCreated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();

function orgOf(snap) {
  const v = snap.exists ? snap.get('organizationId') : null;
  return typeof v === 'string' && v.length > 0 ? v : null;
}

async function stamp(event, parentCollection, parentId) {
  const log = event.data;
  if (!log) return;
  const parent = await db.collection(parentCollection).doc(parentId).get();
  const organizationId = orgOf(parent);
  if ((log.get('organizationId') || null) === organizationId) return;
  await log.ref.update({organizationId});
}

exports.stampCaseLogOrganization = onDocumentCreated(
    'cases/{caseId}/activityLogs/{logId}',
    (event) => stamp(event, 'cases', event.params.caseId),
);

exports.stampAnimalLogOrganization = onDocumentCreated(
    'animals/{animalId}/managementLogs/{logId}',
    (event) => stamp(event, 'animals', event.params.animalId),
);

// ---- Organization stamp on records read across animals and cases --------
//
// The dashboard reads vaccinations, care records, medication orders, doses
// and case expenses with collection-group queries. firestore.rules lets
// staff read only their own organization's, through a query that filters on
// organizationId, so each record carries its parent's. Unlike logs (which
// keep the organization they were written under), these follow the parent:
// when an animal or case moves to another organization, its records move
// with it. A client-written organizationId is always corrected.
//
// Existing records: scripts/backfill_log_organization_ids.js.

const {onDocumentWritten, onDocumentUpdated} = require('firebase-functions/v2/firestore');

// Also transport offers (dashboard stale offers, transporter report) and
// adoption follow-ups (dashboard overdue follow-ups), so staff see only
// their own organization's.
const FOLLOWING_RECORDS = {
  animals: ['vaccinations', 'careRecords', 'medications', 'medicationDoses'],
  cases: ['expenses', 'transportAssignments'],
  adoptions: ['followUps'],
};
const PARENT_PARAM = {animals: 'animalId', cases: 'caseId', adoptions: 'adoptionId'};

async function stampRecord(event, parentCollection, parentId) {
  const after = event.data && event.data.after;
  if (!after || !after.exists) return;
  const parent = await db.collection(parentCollection).doc(parentId).get();
  const organizationId = orgOf(parent);
  if ((after.get('organizationId') || null) === organizationId) return;
  await after.ref.update({organizationId});
}

async function restampChildren(event, parentCollection) {
  const before = orgOf(event.data.before);
  const after = orgOf(event.data.after);
  if (before === after) return;
  const parentRef = event.data.after.ref;
  for (const sub of FOLLOWING_RECORDS[parentCollection]) {
    const docs = (await parentRef.collection(sub).get()).docs;
    for (let i = 0; i < docs.length; i += 400) {
      const batch = db.batch();
      for (const d of docs.slice(i, i + 400)) batch.update(d.ref, {organizationId: after});
      await batch.commit();
    }
  }
}

const capitalize = (s) => s[0].toUpperCase() + s.slice(1);

for (const [parentCollection, subs] of Object.entries(FOLLOWING_RECORDS)) {
  const parentParam = PARENT_PARAM[parentCollection];
  for (const sub of subs) {
    // e.g. stampAnimalsVaccinationsOrganization
    exports[`stamp${capitalize(parentCollection)}${capitalize(sub)}Organization`] = onDocumentWritten(
        `${parentCollection}/{${parentParam}}/${sub}/{docId}`,
        (event) => stampRecord(event, parentCollection, event.params[parentParam]),
    );
  }
  exports[`restamp${capitalize(parentCollection)}RecordsOrganization`] = onDocumentUpdated(
      `${parentCollection}/{${parentParam}}`,
      (event) => restampChildren(event, parentCollection),
  );
}


// Donations carry their campaign's organizationId so firestore.rules can
// limit donor records to that organization's staff. Manual donations
// (recordOfflineDonation) already write it; PayMongo payments and in-kind
// pledges get it here. Existing records: scripts/backfill_log_organization_ids.js.
exports.stampDonationOrganization = onDocumentWritten('donations/{donationId}', async (event) => {
  const after = event.data && event.data.after;
  if (!after || !after.exists) return;
  const campaignId = after.get('campaignId');
  if (typeof campaignId !== 'string' || !campaignId) return;
  const campaign = await db.collection('campaigns').doc(campaignId).get();
  const organizationId = orgOf(campaign);
  if ((after.get('organizationId') || null) === organizationId) return;
  await after.ref.update({organizationId});
});

// Every case carries organizationId; '' means not owned yet (the shared
// review pool). New reports from current app builds write '' themselves;
// this covers older builds. firestore.rules can only let staff query the
// pool by organizationId == '', and Firestore can't match a missing field.
exports.stampCaseOrganizationDefault = onDocumentCreated('cases/{caseId}', async (event) => {
  const snap = event.data;
  if (!snap || snap.get('organizationId') !== undefined) return;
  await snap.ref.update({organizationId: ''});
});
