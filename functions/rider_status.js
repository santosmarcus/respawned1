// Rider availability for every organization's staff.
//
// Assign Transporter's Available / Pending / Busy chips and the dashboard's
// transport-supply counts need each rider's newest offer, whichever
// organization's case it is on. firestore.rules only lets staff read their
// own organization's offers, so this keeps the status of each rider's
// newest offer on their user doc instead — `users/{uid}.transportStatus =
// {status, offeredAt, updatedAt}` — with no case id or other details.
// Staff can read rider profiles; riders can't write this field.
//
// Existing riders: scripts/backfill_rider_status.js.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

/// The transportStatus map for [riderId]'s newest offer, or null if none.
async function riderTransportStatus(db, riderId) {
  const snap = await db
      .collectionGroup('transportAssignments')
      .where('riderId', '==', riderId)
      .orderBy('offeredAt', 'desc')
      .limit(1)
      .get();
  if (snap.empty) return null;
  const a = snap.docs[0].data();
  return {
    status: typeof a.status === 'string' ? a.status : 'pending',
    offeredAt: a.offeredAt || null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
}

async function writeRiderStatus(db, riderId) {
  const user = db.collection('users').doc(riderId);
  if (!(await user.get()).exists) return;
  const status = await riderTransportStatus(db, riderId);
  await user.set(
      {transportStatus: status || admin.firestore.FieldValue.delete()},
      {merge: true},
  );
}

exports.writeRiderStatus = writeRiderStatus;

exports.syncRiderTransportStatus = onDocumentWritten(
    'cases/{caseId}/transportAssignments/{assignmentId}',
    async (event) => {
      const before = event.data && event.data.before.exists ? event.data.before.data() : null;
      const after = event.data && event.data.after.exists ? event.data.after.data() : null;
      // Only the rider, status or timing matter; organizationId stamps don't.
      if (before && after && before.riderId === after.riderId && before.status === after.status &&
          String(before.offeredAt) === String(after.offeredAt)) {
        return;
      }
      const db = admin.firestore();
      const riders = new Set([before && before.riderId, after && after.riderId].filter((r) => typeof r === 'string' && r));
      for (const riderId of riders) await writeRiderStatus(db, riderId);
    },
);
