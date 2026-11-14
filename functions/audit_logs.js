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
