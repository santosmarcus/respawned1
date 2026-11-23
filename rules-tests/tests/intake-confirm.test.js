// Confirm Intake (CaseIntakeRepository.confirmIntake): one transaction that
// updates the case, logs the action and creates the intake-leg transport
// assignment for the transporter already carrying the animals. The vehicle
// capacity check is for new offers (Assign Transporter), not this leg.
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import { createEnv, seed } from './setup.js';

const { FieldValue } = firebase.firestore;
let env;
const as = (uid) => env.authenticatedContext(uid).firestore();

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await seed(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    // Three animals, discharged and ready for intake; the rider has no
    // vehicle details (registered before they were asked, or a volunteer).
    await db.doc('cases/intake3').set({
      reporterId: 'reporter', organizationId: 'orgA', status: 'in_treatment',
      animals: [{ species: 'Dog' }, { species: 'Dog' }, { species: 'Cat' }],
      riderId: 'rider', assignedVolunteerId: 'rider',
    });
  });
});

const confirmIntake = (db, caseId) => db.runTransaction(async (tx) => {
  const caseRef = db.doc(`cases/${caseId}`);
  await tx.get(caseRef);
  const assignmentRef = db.collection(`cases/${caseId}/transportAssignments`).doc();
  const now = firebase.firestore.Timestamp.now();
  tx.update(caseRef, {
    status: 'intake',
    intakeDestinationName: 'Shelter',
    intakeDestinationLat: 14.6,
    intakeDestinationLng: 121.0,
    intakeConfirmedAt: now,
    currentAssignmentId: assignmentRef.id,
    assignedVolunteerId: 'rider',
    assignedVolunteerName: 'Rider One',
    assignedVehicle: null,
    assignedPlate: null,
    statusHistory: FieldValue.arrayUnion({ status: 'Intake confirmed', timestamp: now }),
  });
  tx.set(caseRef.collection('activityLogs').doc(), {
    action: 'intake_confirmed', actorUid: 'staffA', organizationId: 'orgA', timestamp: now,
  });
  tx.set(assignmentRef, {
    caseId, riderId: 'rider', riderName: 'Rider One', riderType: 'Pet Transporter', status: 'accepted',
    offeredAt: now, respondedAt: now, acceptedAt: now, rejectedAt: null, rejectionReason: null,
    completedAt: null, isDemo: false, vehicle: null, plate: null,
  });
});

test('staff confirm intake for a multi-animal case with the transporter already on it', async () => {
  await assertSucceeds(confirmIntake(as('staffA'), 'intake3'));
});

test('a new offer still needs a vehicle that carries every animal', async () => {
  await assertFails(as('staffA').collection('cases/intake3/transportAssignments').add({
    caseId: 'intake3', riderId: 'rider', status: 'pending', organizationId: 'orgA',
  }));
});

test('outsiders still cannot confirm intake', async () => {
  await assertFails(confirmIntake(as('staffB'), 'intake3'));
});
