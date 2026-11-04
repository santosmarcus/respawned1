// Shared emulator environment and seed data for the rules tests.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';

const root = fileURLToPath(new URL('../../', import.meta.url));

export async function createEnv() {
  return initializeTestEnvironment({
    projectId: 'demo-respawnd',
    firestore: { rules: readFileSync(`${root}firestore.rules`, 'utf8') },
    storage: { rules: readFileSync(`${root}storage.rules`, 'utf8') },
  });
}

// Personas (uid -> users doc):
//   admin       platform staff (console-assigned role)
//   ownerA      owner of approved orgA          staffA  member of orgA
//   staffB      member of approved orgB         draftOwner  owner of draft orgD
//   reporter / stranger / adopter  general users
//   rider / rider2  pet transporters
export const users = {
  admin: { role: 'admin' },
  ownerA: { role: 'organization', organizationId: 'orgA' },
  staffA: { role: 'organization_member', organizationId: 'orgA' },
  staffB: { role: 'organization_member', organizationId: 'orgB' },
  carerA: { role: 'organization_member', organizationId: 'orgA' },
  draftOwner: { role: 'organization', organizationId: 'orgD' },
  reporter: { role: 'general' },
  stranger: { role: 'general' },
  adopter: { role: 'general' },
  rider: { role: 'pet_transporter' },
  rider2: { role: 'pet_transporter' },
};

export async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const [uid, data] of Object.entries(users)) {
      await db.doc(`users/${uid}`).set(data);
    }

    await db.doc('organizations/orgA').set({ ownerId: 'ownerA', name: 'Org A', verificationStatus: 'approved' });
    await db.doc('organizations/orgA/members/ownerA').set({ role: 'admin', status: 'active' });
    await db.doc('organizations/orgA/members/staffA').set({ role: 'staff', status: 'active' });
    await db.doc('organizations/orgA/members/carerA').set({ role: 'carer', status: 'active' });
    await db.doc('organizations/orgB').set({ ownerId: 'someoneElse', name: 'Org B', verificationStatus: 'approved' });
    await db.doc('organizations/orgB/members/staffB').set({ role: 'staff', status: 'active' });
    await db.doc('organizations/orgD').set({ ownerId: 'draftOwner', name: 'Org D', verificationStatus: 'draft' });
    await db.doc('organizations/orgD/members/draftOwner').set({ role: 'admin', status: 'active' });

    await db.doc('organizationInvitations/inv1').set({
      organizationId: 'orgA', normalizedEmail: 'newbie@example.com', email: 'newbie@example.com',
      status: 'pending', role: 'staff',
    });

    await db.doc('cases/pending1').set({ reporterId: 'reporter', status: 'pending' });
    await db.doc('cases/ownedA').set({ reporterId: 'reporter', status: 'accepted_pending_clinic', organizationId: 'orgA' });
    await db.doc('cases/ownedA/expenses/e1').set({ amount: 500 });
    await db.doc('cases/offered').set({
      reporterId: 'reporter', status: 'awaiting_assignment', organizationId: 'orgA', currentAssignmentId: 'as1',
    });
    await db.doc('cases/offered/transportAssignments/as1').set({ riderId: 'rider', status: 'pending', caseId: 'offered' });
    await db.doc('cases/assigned').set({
      reporterId: 'reporter', status: 'assigned', organizationId: 'orgA', riderId: 'rider', assignedVolunteerId: 'rider',
    });

    await db.doc('animals/animalA').set({ name: 'Mochi', organizationId: 'orgA', adoptionStatus: 'adoptable' });
    await db.doc('adoptions/appA').set({
      organizationId: 'orgA', status: 'pending',
      personal: { adopterId: 'adopter', animalRecordId: 'animalA' },
    });
  });
}
