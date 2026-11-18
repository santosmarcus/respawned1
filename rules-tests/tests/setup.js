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
//   sysadmin   system admin (approvals and user directory only)
//   adminA, fullA, rescueA, careA, adoptA, treasurerA, noPermsA,
//   inactiveAdminA  orgA members by preset (see presets)
//   platformMemberA  platform 'admin' account that is also an orgA Admin
export const users = {
  admin: { role: 'admin' },
  sysadmin: { role: 'system_admin' },
  ownerA: { role: 'organization', organizationId: 'orgA' },
  staffA: { role: 'organization_member', organizationId: 'orgA' },
  staffB: { role: 'organization_member', organizationId: 'orgB' },
  carerA: { role: 'organization_member', organizationId: 'orgA' },
  draftOwner: { role: 'organization', organizationId: 'orgD' },
  reporter: { role: 'general' },
  stranger: { role: 'general' },
  adopter: { role: 'general' },
  // rider is a verified transporter; rider2 is not (still pending review).
  rider: { role: 'pet_transporter', isVerified: true, transporterVerificationStatus: 'approved' },
  rider2: { role: 'pet_transporter' },
  // orgA members with explicit permissions (Admin + Staff model).
  adminA: { role: 'organization_member', organizationId: 'orgA' },
  fullA: { role: 'organization_member', organizationId: 'orgA' },
  rescueA: { role: 'organization_member', organizationId: 'orgA' },
  careA: { role: 'organization_member', organizationId: 'orgA' },
  adoptA: { role: 'organization_member', organizationId: 'orgA' },
  treasurerA: { role: 'organization_member', organizationId: 'orgA' },
  noPermsA: { role: 'organization_member', organizationId: 'orgA' },
  inactiveAdminA: { role: 'organization_member', organizationId: 'orgA' },
  // A platform account that is also an Admin member of orgA.
  platformMemberA: { role: 'admin', organizationId: 'orgA' },
};

// Preset lists, as in functions/org_permissions.json.
export const presets = {
  fullStaff: ['rescue', 'animals', 'care', 'adoptions', 'campaigns', 'financeView', 'volunteers', 'insights'],
  rescueCoordinator: ['rescue', 'animals', 'care', 'insights'],
  animalCare: ['care'],
  adoptionsOfficer: ['adoptions', 'animals', 'care'],
  treasurer: ['campaigns', 'financeView', 'financeManage', 'insights'],
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
    const staff = (preset, permissions) => ({ role: 'staff', status: 'active', preset, permissions });
    await db.doc('organizations/orgA/members/adminA').set({ role: 'admin', status: 'active' });
    await db.doc('organizations/orgA/members/fullA').set(staff('fullStaff', presets.fullStaff));
    await db.doc('organizations/orgA/members/rescueA').set(staff('rescueCoordinator', presets.rescueCoordinator));
    await db.doc('organizations/orgA/members/careA').set(staff('animalCare', presets.animalCare));
    await db.doc('organizations/orgA/members/adoptA').set(staff('adoptionsOfficer', presets.adoptionsOfficer));
    await db.doc('organizations/orgA/members/treasurerA').set(staff('treasurer', presets.treasurer));
    await db.doc('organizations/orgA/members/noPermsA').set(staff('custom', []));
    await db.doc('organizations/orgA/members/inactiveAdminA').set({ role: 'admin', status: 'removed' });
    await db.doc('organizations/orgA/members/platformMemberA').set({ role: 'admin', status: 'active' });
    await db.doc('organizations/orgB').set({ ownerId: 'someoneElse', name: 'Org B', verificationStatus: 'approved' });
    await db.doc('organizations/orgB/members/staffB').set({ role: 'staff', status: 'active' });
    await db.doc('organizations/orgD').set({ ownerId: 'draftOwner', name: 'Org D', verificationStatus: 'draft' });
    await db.doc('organizations/orgD/members/draftOwner').set({ role: 'admin', status: 'active' });

    await db.doc('organizationInvitations/inv1').set({
      organizationId: 'orgA', normalizedEmail: 'newbie@example.com', email: 'newbie@example.com',
      status: 'pending', role: 'staff',
    });

    await db.doc('cases/pending1').set({ reporterId: 'reporter', status: 'pending', organizationId: '' });
    await db.doc('cases/ownedA').set({ reporterId: 'reporter', status: 'accepted_pending_clinic', organizationId: 'orgA' });
    await db.doc('cases/ownedA/expenses/e1').set({ amount: 500 });
    await db.doc('cases/offered').set({
      reporterId: 'reporter', status: 'awaiting_assignment', organizationId: 'orgA', currentAssignmentId: 'as1',
    });
    await db.doc('cases/offered/transportAssignments/as1').set({ riderId: 'rider', status: 'pending', caseId: 'offered' });
    await db.doc('cases/assigned').set({
      reporterId: 'reporter', status: 'assigned', organizationId: 'orgA', riderId: 'rider', assignedVolunteerId: 'rider',
    });
    // Unowned report with a rider sent to check the location.
    await db.doc('cases/verifying1').set({
      reporterId: 'reporter', status: 'verifying', organizationId: '', verifyingOrganizationId: 'orgA',
      verification: { deskOutcome: 'needsRider', deskBy: 'staffA', riderId: 'rider', riderName: 'Rider One' },
    });

    await db.doc('animals/animalA').set({ name: 'Mochi', organizationId: 'orgA', adoptionStatus: 'adoptable' });
    await db.doc('adoptions/appA').set({
      organizationId: 'orgA', status: 'pending',
      personal: { adopterId: 'adopter', animalRecordId: 'animalA' },
    });
  });
}
