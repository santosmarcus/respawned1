// Independent rescuers (organizations/{id}.kind == 'independent').
//
// - Keeps the counts firestore.rules and the capacity checks read:
//   memberCount (active members), activeCaseCount (open cases it owns) and
//   animalsInCareCount (animal records still in its care), plus
//   lastActiveAt. Clients can't write any of them.
// - setIndependentLimits: a system admin (or platform staff) turns modules on
//   or off and changes the caps.
// - openCasesToIndependents: once a report's shelter head start ends and no
//   one has accepted it, tells the nearby independents it opened to.
// - Weekly "animals in your care" check-in and the 30-day auto-pause.
//
// The pure rules live in independent_rescuer_rules.js.

const {onDocumentWritten} = require('firebase-functions/v2/firestore');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const {onCall, HttpsError} = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const {isIndependent, isActiveStatus} = require('./org_access');
const rules = require('./independent_rescuer_rules');

// index.js calls admin.initializeApp() before requiring this module.
const db = admin.firestore();
const {FieldValue, Timestamp} = admin.firestore;

const AUTO_PAUSE_DAYS = 30;

module.exports = ({notifyStaff, orgStaffUids}) => {
  async function independentOrg(orgId) {
    if (typeof orgId !== 'string' || !orgId) return null;
    const snap = await db.collection('organizations').doc(orgId).get();
    return snap.exists && isIndependent(snap.data()) ? snap : null;
  }

  async function recountCases(orgRef) {
    const snap = await db.collection('cases').where('organizationId', '==', orgRef.id).get();
    const open = snap.docs.filter((d) => rules.isOpenCaseStatus(d.get('status'))).length;
    await orgRef.update({activeCaseCount: open, lastActiveAt: FieldValue.serverTimestamp()});
  }

  async function recountAnimals(orgRef) {
    const snap = await db.collection('animals').where('organizationId', '==', orgRef.id).get();
    const inCare = snap.docs.filter((d) => rules.isAnimalInCare(d.data())).length;
    await orgRef.update({animalsInCareCount: inCare, lastActiveAt: FieldValue.serverTimestamp()});
  }

  const syncIndependentMemberCount = onDocumentWritten('organizations/{orgId}/members/{uid}', async (event) => {
    const org = await independentOrg(event.params.orgId);
    if (!org) return;
    const members = await org.ref.collection('members').get();
    const active = members.docs.filter((m) => isActiveStatus(m.get('status'))).length;
    await org.ref.update({memberCount: Math.max(active, 1)});
  });

  const syncIndependentCaseCount = onDocumentWritten('cases/{caseId}', async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : {};
    const after = event.data.after.exists ? event.data.after.data() : {};
    const orgChanged = (before.organizationId || '') !== (after.organizationId || '');
    const statusChanged = before.status !== after.status;
    if (!orgChanged && !statusChanged) return;
    const ids = new Set([before.organizationId, after.organizationId].filter((x) => typeof x === 'string' && x));
    for (const id of ids) {
      const org = await independentOrg(id);
      if (org) await recountCases(org.ref);
    }
  });

  const syncIndependentAnimalCount = onDocumentWritten('animals/{animalId}', async (event) => {
    const before = event.data.before.exists ? event.data.before.data() : {};
    const after = event.data.after.exists ? event.data.after.data() : {};
    const relevant = ['organizationId', 'adoptionStatus', 'status', 'transferStatus'];
    if (event.data.before.exists && event.data.after.exists && relevant.every((k) => before[k] === after[k])) return;
    const ids = new Set([before.organizationId, after.organizationId].filter((x) => typeof x === 'string' && x));
    for (const id of ids) {
      const org = await independentOrg(id);
      if (org) await recountAnimals(org.ref);
    }
  });

  const setIndependentLimits = onCall(async (request) => {
    const uid = request.auth && request.auth.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Sign in required.');
    const me = await db.collection('users').doc(uid).get();
    const role = me.exists ? me.get('role') : '';
    if (!['system_admin', 'admin', 'ngo_staff'].includes(role)) {
      throw new HttpsError('permission-denied', 'Only a system admin can change a rescue volunteer\'s limits.');
    }
    const d = request.data || {};
    const organizationId = typeof d.organizationId === 'string' ? d.organizationId.trim() : '';
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(organizationId)) {
      throw new HttpsError('invalid-argument', 'organizationId is required.');
    }
    const plan = rules.planLimitsChange(d);
    if (plan.error) throw new HttpsError('invalid-argument', plan.error);
    const orgRef = db.collection('organizations').doc(organizationId);
    const before = await db.runTransaction(async (tx) => {
      const snap = await tx.get(orgRef);
      if (!snap.exists || !isIndependent(snap.data())) {
        throw new HttpsError('failed-precondition', 'That is not a rescue volunteer.');
      }
      tx.update(orgRef, {...plan.update, updatedAt: FieldValue.serverTimestamp()});
      return snap.data();
    });
    const old = {};
    for (const k of Object.keys(plan.update)) old[k] = before[k] === undefined ? null : before[k];
    try {
      await db.collection('auditLogs').add({
        category: 'organizationVerification',
        action: 'independent_limits_changed',
        actorId: uid,
        actorName: me.get('name') || me.get('email') || 'System admin',
        organizationId,
        targetType: 'Organization',
        targetId: organizationId,
        previousValues: old,
        newValues: plan.update,
        createdAt: FieldValue.serverTimestamp(),
      });
    } catch (e) {
      console.error('[setIndependentLimits] audit log write failed', e);
    }
    return plan.update;
  });

  // Reports whose head start just ended and that no one has taken yet.
  // notifyNewCaseReported writes independentsOpenAt and
  // independentsNotified: false when a report has nearby independents.
  const openCasesToIndependents = onSchedule('every 1 minutes', async () => {
    const due = await db.collection('cases')
        .where('independentsNotified', '==', false)
        .where('independentsOpenAt', '<=', Timestamp.now())
        .limit(50)
        .get();
    for (const doc of due.docs) {
      const c = doc.data();
      await doc.ref.update({independentsNotified: true});
      if ((c.organizationId || '') !== '' || (c.referredToOrgId || '') !== '' || c.status !== 'pending') continue;
      const ids = Array.isArray(c.nearbyIndependentIds) ? c.nearbyIndependentIds : [];
      for (const orgId of ids) {
        const org = await independentOrg(orgId);
        if (!org || rules.independentCaseRefusal(org.data())) continue;
        const uids = await orgStaffUids(orgId, {anyOf: ['rescue']});
        const urgency = c.urgency ? `${c.urgency} · ` : '';
        await notifyStaff(uids, {
          title: 'New case near you',
          body: `${urgency}${c.rescueType || 'Rescue report'}${c.address ? ` near ${c.address}` : ''}. No organization has taken it yet.`,
          data: {type: 'independent_case_open', caseId: doc.id},
        });
      }
    }
  });

  // Monday 9:00 Manila: independents with animals in care confirm how they
  // are doing; anyone inactive for AUTO_PAUSE_DAYS stops getting new cases
  // until they turn themselves back on.
  const weeklyIndependentCheckIn = onSchedule({schedule: '0 9 * * 1', timeZone: 'Asia/Manila'}, async () => {
    const snap = await db.collection('organizations').where('kind', '==', 'independent').get();
    const cutoff = Date.now() - AUTO_PAUSE_DAYS * 24 * 60 * 60 * 1000;
    for (const org of snap.docs) {
      const o = org.data();
      if ((o.verificationStatus || 'approved') !== 'approved') continue;
      const admins = await orgStaffUids(org.id, {adminsOnly: true});
      const last = o.lastActiveAt && o.lastActiveAt.toMillis ? o.lastActiveAt.toMillis() : null;
      if (o.acceptingCases !== false && last !== null && last < cutoff && !(o.activeCaseCount > 0)) {
        await org.ref.update({acceptingCases: false, autoPausedAt: FieldValue.serverTimestamp()});
        await notifyStaff(admins, {
          title: 'You\'re paused',
          body: `No activity for ${AUTO_PAUSE_DAYS} days, so new cases have stopped. Turn Available back on when you're ready.`,
          data: {type: 'independent_auto_paused'},
        });
        continue;
      }
      if ((o.animalsInCareCount || 0) > 0) {
        await notifyStaff(admins, {
          title: 'Animals in your care',
          body: `You have ${o.animalsInCareCount} animal(s) in care. Add a care update for each so their records stay current.`,
          data: {type: 'independent_weekly_check_in'},
        });
      }
    }
  });

  return {
    syncIndependentMemberCount,
    syncIndependentCaseCount,
    syncIndependentAnimalCount,
    setIndependentLimits,
    openCasesToIndependents,
    weeklyIndependentCheckIn,
  };
};
