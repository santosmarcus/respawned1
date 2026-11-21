// Scheduled adoption posts to the organization's Facebook Page.
//
//  - facebookSaveAdoptionPromotion (callable, Admin): the schedule (every
//    1, 2 or 4 weeks, weekday, hour Manila time, animals per post, smart
//    suggestions on/off). Stored at organizations/{orgId}/integrations/
//    facebookPromotion, which members can read and only the backend writes.
//  - facebookAdoptionPromotionSuggestions (callable, facebookPublish): the
//    animals open for adoption, most in need of a post first, with a draft
//    caption. The app's Promote Adoptions screen preselects the top ones.
//  - remindAdoptionPromotions (hourly): when a slot comes due, or (smart
//    suggestions) when animals have never been shared or have waited
//    without applicants, every active member of the organization gets a
//    push and an in-app notification (type adoption_promotion_due).
//    Nothing is posted on its own: a member with facebookPublish reviews
//    the animals and caption and posts; others see who can.
//
// facebookPublishAnimalRecords (functions/facebook.js) stamps lastPostedAt
// on the same doc, so a post made shortly before a slot counts for it.
// Pure decisions: functions/adoption_promotion_rules.js.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {onSchedule} = require('firebase-functions/v2/scheduler');
const admin = require('firebase-admin');

const rules = require('./adoption_promotion_rules');
const {requireOrgPermission, writeOrgAuditLog} = require('./org_access');

module.exports = function adoptionPromotion({db, orgStaffUids, notifyStaff}) {
  const FieldValue = admin.firestore.FieldValue;
  const Timestamp = admin.firestore.Timestamp;

  function promotionRef(orgId) {
    return db.collection('organizations').doc(orgId).collection('integrations').doc('facebookPromotion');
  }

  function integrationRef(orgId) {
    return db.collection('organizations').doc(orgId).collection('integrations').doc('facebook');
  }

  async function rankedFor(orgId, nowMs) {
    const [animals, shares, adoptions] = await Promise.all([
      db.collection('animals')
        .where('organizationId', '==', orgId)
        .where('adoptionStatus', '==', 'adoptable')
        .get(),
      db.collection('facebookShares').where('organizationId', '==', orgId).get(),
      db.collection('adoptions')
        .where('organizationId', '==', orgId)
        .where('status', 'in', rules.OPEN_APPLICATION_STATUSES)
        .get(),
    ]);
    return rules.rankAnimals({
      animals: animals.docs.map((d) => ({id: d.id, ...d.data()})),
      shares: shares.docs.map((d) => d.data()),
      adoptions: adoptions.docs.map((d) => d.data()),
      nowMs,
    });
  }

  const facebookSaveAdoptionPromotion = onCall(async (request) => {
    const {organizationId, schedule} = request.data || {};
    if (!organizationId) throw new HttpsError('invalid-argument', 'organizationId is required.');
    const caller = await requireOrgPermission(db, request, {
      organizationId,
      adminOnly: true,
      message: 'Only an organization Admin can change the adoption post schedule.',
    });
    const checked = rules.validateSchedule(schedule);
    if (checked.error) throw new HttpsError('invalid-argument', checked.error);
    const s = checked.schedule;

    const ref = promotionRef(organizationId);
    const before = (await ref.get()).data() || {};
    const nowMs = Date.now();
    await ref.set({
      ...s,
      organizationId,
      nextDueAt: s.enabled ? Timestamp.fromMillis(rules.firstSlotAfter(s, nowMs)) : null,
      updatedBy: caller.uid,
      updatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});

    await writeOrgAuditLog(db, FieldValue, {
      action: 'Adoption post schedule updated',
      actorId: caller.uid,
      actorName: caller.name,
      actorEmail: request.auth.token.email,
      organizationId,
      targetType: 'FacebookIntegration',
      targetId: organizationId,
      oldValues: {
        enabled: before.enabled ?? null,
        smartSuggestions: before.smartSuggestions ?? null,
        intervalWeeks: before.intervalWeeks ?? null,
        dayOfWeek: before.dayOfWeek ?? null,
        hour: before.hour ?? null,
        animalsPerPost: before.animalsPerPost ?? null,
      },
      newValues: s,
    });
    return {ok: true};
  });

  const facebookAdoptionPromotionSuggestions = onCall(async (request) => {
    const {organizationId} = request.data || {};
    if (!organizationId) throw new HttpsError('invalid-argument', 'organizationId is required.');
    await requireOrgPermission(db, request, {
      organizationId,
      anyOf: ['facebookPublish'],
      message: 'Only members allowed to share to Facebook can prepare an adoption post.',
    });
    const nowMs = Date.now();
    const [ranked, promo] = await Promise.all([rankedFor(organizationId, nowMs), promotionRef(organizationId).get()]);
    const perPost = (promo.exists && promo.get('animalsPerPost')) || 3;
    const picks = ranked.slice(0, perPost);
    return {
      animalsPerPost: perPost,
      animals: ranked.map((r) => ({
        id: r.id,
        name: r.name,
        neverShared: r.neverShared,
        hasApplicants: r.hasApplicants,
        waiting: r.waiting,
        lastSharedMs: r.lastSharedMs,
      })),
      suggestedIds: picks.map((r) => r.id),
      caption: rules.defaultCaption(picks.map((r) => r.name)),
    };
  });

  async function remindOrg(orgId, promoSnap, nowMs) {
    const schedule = promoSnap.data() || {};
    if (!schedule.enabled && !schedule.smartSuggestions) return;

    const integration = await integrationRef(orgId).get();
    const connected = integration.exists && integration.get('connectionStatus') === 'connected';

    // Ranking needs three queries, so only when it can matter: a slot is
    // due, or it is the hour smart nudges may go out.
    const dueMs = schedule.nextDueAt && schedule.nextDueAt.toMillis ? schedule.nextDueAt.toMillis() : null;
    const slotDue = schedule.enabled && (dueMs == null || nowMs >= dueMs);
    const smartHour = schedule.smartSuggestions && rules.manilaParts(nowMs).hour === schedule.hour;
    if (!slotDue && !smartHour) return;

    let ranked = [];
    let smart = null;
    if (connected) {
      ranked = await rankedFor(orgId, nowMs);
      smart = rules.smartNudgeReason(ranked);
    }
    const decision = rules.scheduleDecision({schedule, nowMs, smart});
    if (decision.action === 'none') return;

    const update = {};
    if (decision.nextDueMs != null && decision.nextDueMs !== dueMs) {
      update.nextDueAt = Timestamp.fromMillis(decision.nextDueMs);
    }

    if (decision.action === 'remind') {
      const perPost = schedule.animalsPerPost || 3;
      const picks = ranked.slice(0, perPost);
      const message = connected
        ? rules.reminderMessage({
          kind: decision.kind,
          intervalWeeks: schedule.intervalWeeks,
          picks,
          total: ranked.length,
          reason: smart,
        })
        : null;
      if (message) {
        // Every active member (owner, Admins, all Staff): the Admin's
        // schedule is a reminder for the whole team. Only members with
        // facebookPublish can post from the screen it opens.
        const uids = await orgStaffUids(orgId);
        await notifyStaff(uids, {
          ...message,
          data: {
            type: 'adoption_promotion_due',
            organizationId: orgId,
            reminderKind: decision.kind,
            animalIds: picks.map((p) => p.id).join(','),
          },
        });
        update.lastReminderAt = Timestamp.fromMillis(nowMs);
        update.lastReminderKind = decision.kind;
        update.lastSuggestedIds = picks.map((p) => p.id);
      }
    }
    if (Object.keys(update).length) await promoSnap.ref.set(update, {merge: true});
  }

  const remindAdoptionPromotions = onSchedule(
      {schedule: '5 * * * *', timeZone: 'Asia/Manila'},
      async () => {
        const nowMs = Date.now();
        const orgs = await db.collection('organizations').get();
        for (const org of orgs.docs) {
          if ((org.get('verificationStatus') || 'approved') !== 'approved') continue;
          const orgId = org.id;
          try {
            const promo = await promotionRef(orgId).get();
            if (!promo.exists) continue;
            await remindOrg(orgId, promo, nowMs);
          } catch (e) {
            console.error('[remindAdoptionPromotions] failed for org', orgId, e);
          }
        }
      },
  );

  return {
    facebookSaveAdoptionPromotion,
    facebookAdoptionPromotionSuggestions,
    remindAdoptionPromotions,
  };
};
