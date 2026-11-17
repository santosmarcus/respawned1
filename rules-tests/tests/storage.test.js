import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { createEnv, seed } from './setup.js';

const bytes = new Uint8Array([1, 2, 3]);

let env;
const upload = (uid, path) => env.authenticatedContext(uid).storage().ref(path).put(bytes);

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

describe('storage', () => {
  test('case media: reporter, assigned transporter and staff', async () => {
    await assertSucceeds(upload('reporter', 'cases/pending1/media_0.jpg'));
    await assertSucceeds(upload('rider', 'cases/assigned/pickup_verify_0.jpg'));
    await assertSucceeds(upload('staffA', 'cases/ownedA/media_9.jpg'));
    // Expense receipts are money: people who manage it upload.
    await assertSucceeds(upload('ownerA', 'cases/ownedA/expenseReceipts/1.jpg'));
    await assertFails(upload('staffA', 'cases/ownedA/expenseReceipts/1.jpg'));
    await assertFails(upload('stranger', 'cases/pending1/media_0.jpg'));
    await assertFails(upload('stranger', 'cases/ownedA/expenseReceipts/1.jpg'));
  });

  test("verification photos: the reporter's live proof and the rider sent to check", async () => {
    await assertSucceeds(upload('reporter', 'cases/pending1/proof_1.jpg'));
    await assertSucceeds(upload('rider', 'cases/verifying1/verify_1_0.jpg'));
    await assertFails(upload('rider2', 'cases/verifying1/verify_1_0.jpg'));
    await assertSucceeds(upload('staffA', 'cases/verifying1/verify_2_0.jpg'));
  });

  test('anyone can attach a sighting photo', async () => {
    await assertSucceeds(upload('stranger', 'cases/ownedA/communityReports/r1.jpg'));
  });

  test('profile photos are the owner\'s', async () => {
    await assertSucceeds(upload('reporter', 'users/reporter/profile.jpg'));
    await assertFails(upload('stranger', 'users/reporter/profile.jpg'));
  });

  test('adoption documents: uploader before submission, then adopter and staff', async () => {
    await assertSucceeds(upload('adopter', 'adoptions/newApp/government_id.jpg'));
    await assertSucceeds(upload('adopter', 'adoptions/appA/checkins/f1/img_0.jpg'));
    await assertSucceeds(upload('staffA', 'adoptions/appA/returnRequest/img_0.jpg'));
    await assertFails(upload('stranger', 'adoptions/appA/government_id.jpg'));
  });

  test('organization verification papers: system admins read them, never upload', async () => {
    const path = 'organizations/orgD/verification/permits/p.pdf';
    await assertSucceeds(upload('draftOwner', path));
    const meta = (uid) => env.authenticatedContext(uid).storage().ref(path).getMetadata();
    await assertSucceeds(meta('sysadmin'));
    await assertFails(meta('stranger'));
    await assertFails(upload('sysadmin', path));
  });

  test('organization verification papers: that organization only', async () => {
    await assertSucceeds(upload('draftOwner', 'organizations/orgD/verification/permits/p.pdf'));
    await assertFails(upload('stranger', 'organizations/orgD/verification/permits/p.pdf'));
  });

  test('donation receipts: people who manage money; campaign images: campaign staff', async () => {
    await assertSucceeds(upload('ownerA', 'receipts/1.jpg'));
    await assertFails(upload('staffA', 'receipts/1.jpg'));
    await assertSucceeds(upload('staffA', 'campaigns/1.jpg'));
    await assertFails(upload('carerA', 'campaigns/1.jpg'));
    await assertFails(upload('stranger', 'receipts/1.jpg'));
    await assertFails(upload('stranger', 'campaigns/1.jpg'));
  });

  test('event cover images: staff of that organization only', async () => {
    await assertSucceeds(upload('staffA', 'events/orgA/cover_1.jpg'));
    await assertSucceeds(upload('ownerA', 'events/orgA/cover_2.jpg'));
    await assertSucceeds(upload('admin', 'events/orgA/cover_3.jpg'));
    await assertFails(upload('staffB', 'events/orgA/cover_1.jpg'));
    await assertFails(upload('carerA', 'events/orgA/cover_1.jpg'));
    await assertFails(upload('stranger', 'events/orgA/cover_1.jpg'));
    await assertFails(upload('draftOwner', 'events/orgD/cover_1.jpg'));
  });

  test('staff of an unapproved organization get no staff access', async () => {
    await assertFails(upload('draftOwner', 'receipts/1.jpg'));
  });

  test('removed members lose staff access', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('organizations/orgA/members/staffA').update({ status: 'removed' }));
    await assertFails(upload('staffA', 'cases/ownedA/expenseReceipts/2.jpg'));
    await assertSucceeds(upload('ownerA', 'cases/ownedA/expenseReceipts/2.jpg'));
  });

  test('carers add dose media for their org only; they are not staff', async () => {
    await assertSucceeds(upload('carerA', 'animalRecords/animalA/doseMedia/d1.mp4'));
    await assertFails(upload('stranger', 'animalRecords/animalA/doseMedia/d1.mp4'));
    await assertFails(upload('carerA', 'receipts/1.jpg'));
    await assertFails(upload('carerA', 'animalRecords/animalA/notes.jpg'));
  });

  test('a removed carer cannot add dose media', async () => {
    await env.withSecurityRulesDisabled((ctx) =>
      ctx.firestore().doc('organizations/orgA/members/carerA').update({ status: 'removed' }));
    await assertFails(upload('carerA', 'animalRecords/animalA/doseMedia/d2.mp4'));
  });

  test("animal medical files are for the animal's staff and carers; profile photos stay readable", async () => {
    const files = ['images/p.jpg', 'medicalDocs/m.pdf', 'careUpdates/c.jpg', 'doseMedia/d.mp4'];
    await env.withSecurityRulesDisabled(async (ctx) => {
      for (const f of files) await ctx.storage().ref(`animalRecords/animalA/${f}`).put(bytes);
    });
    const read = (uid, f) => env.authenticatedContext(uid).storage().ref(`animalRecords/animalA/${f}`).getMetadata();
    await assertSucceeds(read('stranger', 'images/p.jpg'));
    for (const f of files.slice(1)) {
      await assertFails(read('stranger', f));
      await assertFails(read('staffB', f));
      await assertSucceeds(read('staffA', f));
      await assertSucceeds(read('carerA', f));
      await assertSucceeds(read('admin', f));
    }
    // Another organization's staff can't add medical files either.
    await assertFails(upload('staffB', 'animalRecords/animalA/medicalDocs/x.pdf'));
    await assertSucceeds(upload('staffA', 'animalRecords/animalA/medicalDocs/x.pdf'));
  });

  test('unlisted paths are denied', async () => {
    await assertFails(upload('admin', 'anything/else.jpg'));
  });
});
