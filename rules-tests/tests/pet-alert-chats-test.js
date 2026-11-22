// Private lost/found chats (petAlertChats): only the two people in a chat
// can read it, only the person who filed the report decides the match, and
// the reunion can only be recorded once the match is confirmed.
import { after, before, beforeEach, describe, test } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { createEnv, seed } from './setup.js';

let env;
const as = (uid) => env.authenticatedContext(uid).firestore();

const chat = (over = {}) => ({
  alertId: 'lost1',
  alertType: 'lost',
  reporterId: 'reporter',
  inquirerId: 'stranger',
  matchStatus: 'pending',
  ...over,
});

before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await seed(env);
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('petAlerts/lost1').set({ type: 'lost', reporterId: 'reporter', status: 'open' });
    await db.doc('petAlertChats/lost1_adopter').set(chat({ inquirerId: 'adopter' }));
    await db.doc('petAlertChats/lost1_adopter/messages/m1').set({ senderId: 'adopter', text: 'Hi' });
  });
});

describe('petAlertChats', () => {
  test('anyone can start a chat about a report, as themselves', async () => {
    await assertSucceeds(as('stranger').doc('petAlertChats/lost1_stranger').set(chat()));
  });

  test('cannot start a chat for someone else, with the wrong id, or with themselves', async () => {
    await assertFails(as('stranger').doc('petAlertChats/lost1_rider').set(chat({ inquirerId: 'rider' })));
    await assertFails(as('stranger').doc('petAlertChats/other_stranger').set(chat()));
    await assertFails(as('reporter').doc('petAlertChats/lost1_reporter').set(chat({ inquirerId: 'reporter' })));
  });

  test('cannot fake the report owner or start already matched', async () => {
    await assertFails(as('stranger').doc('petAlertChats/lost1_stranger').set(chat({ reporterId: 'rider' })));
    await assertFails(as('stranger').doc('petAlertChats/lost1_stranger').set(chat({ matchStatus: 'confirmed' })));
  });

  test('only the two people in a chat can read it and its messages', async () => {
    await assertSucceeds(as('reporter').doc('petAlertChats/lost1_adopter').get());
    await assertSucceeds(as('adopter').doc('petAlertChats/lost1_adopter').get());
    await assertFails(as('stranger').doc('petAlertChats/lost1_adopter').get());
    await assertSucceeds(as('adopter').doc('petAlertChats/lost1_adopter/messages/m1').get());
    await assertFails(as('stranger').doc('petAlertChats/lost1_adopter/messages/m1').get());
  });

  test('anyone signed in can check whether their chat exists yet', async () => {
    await assertSucceeds(as('stranger').doc('petAlertChats/lost1_stranger').get());
  });

  test("the report owner can list their report's chats", async () => {
    await assertSucceeds(as('reporter').collection('petAlertChats')
      .where('alertId', '==', 'lost1').where('reporterId', '==', 'reporter').get());
    await assertFails(as('stranger').collection('petAlertChats')
      .where('alertId', '==', 'lost1').get());
  });

  test('both can message as themselves; outsiders and system notes cannot', async () => {
    const msgs = (uid) => as(uid).collection('petAlertChats/lost1_adopter/messages');
    await assertSucceeds(msgs('adopter').add({ senderId: 'adopter', text: 'Is this your dog?' }));
    await assertSucceeds(msgs('reporter').add({ senderId: 'reporter', text: 'Yes!' }));
    await assertFails(msgs('adopter').add({ senderId: 'reporter', text: 'spoof' }));
    await assertFails(msgs('stranger').add({ senderId: 'stranger', text: 'hi' }));
    await assertFails(msgs('adopter').add({ senderId: 'adopter', text: 'note', kind: 'system' }));
    await assertFails(msgs('adopter').add({ senderId: 'adopter', text: '' }));
  });

  test('only the report owner decides the match', async () => {
    await assertFails(as('adopter').doc('petAlertChats/lost1_adopter').update({ matchStatus: 'confirmed' }));
    await assertSucceeds(as('reporter').doc('petAlertChats/lost1_adopter').update({ matchStatus: 'confirmed', matchDecidedBy: 'reporter' }));
    await assertSucceeds(as('reporter').doc('petAlertChats/lost1_adopter').update({ matchStatus: 'rejected' }));
  });

  test('the reunion is recorded only after the match is confirmed, by either of them', async () => {
    await assertFails(as('adopter').doc('petAlertChats/lost1_adopter').update({ reunitedAt: new Date(), reunitedBy: 'adopter' }));
    await env.withSecurityRulesDisabled((ctx) => ctx.firestore().doc('petAlertChats/lost1_adopter').update({ matchStatus: 'confirmed' }));
    await assertSucceeds(as('adopter').doc('petAlertChats/lost1_adopter').update({ reunitedAt: new Date(), reunitedBy: 'adopter' }));
  });

  test('chat fields other than the decision and reunion are locked', async () => {
    await assertFails(as('reporter').doc('petAlertChats/lost1_adopter').update({ inquirerId: 'stranger' }));
    await assertFails(as('adopter').doc('petAlertChats/lost1_adopter').update({ lastMessage: 'x' }));
    await assertFails(as('reporter').doc('petAlertChats/lost1_adopter').delete());
  });
});