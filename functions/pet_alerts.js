// Lost/found pet report (petAlerts) messaging and reunions.
//
// Messaging works like a marketplace: anyone who messages the person who
// filed a report gets a private chat with them, petAlertChats/{alertId}_{uid},
// linked to the report (and to the sender's own report, if they have one).
// The person who filed the report decides whether the sender is the right
// match; once they are, either of them can mark the pet reunited.
//
//  - notifyPetAlertChatMessage: a chat message notifies the other person
//    and keeps the chat's last-message preview up to date.
//  - onPetAlertChatDecision: "Right match" / "Not a match" posts a note in
//    the chat, tells the sender, and marks the possible match between the
//    two reports verified or rejected.
//  - onPetAlertReunited: when a report is marked reunited, its possible
//    matches are resolved and everyone who messaged about it is told.
//  - notifyPetAlertMessage: the older public thread on a report
//    (petAlerts/{alertId}/messages), still notified for app versions that
//    post there.
//
// Each notification is an in-app item (users/{uid}/notifications) plus a
// push, both with {type, alertId[, chatId]} so a tap opens the chat or the
// report (NotificationService._pageFor and NotificationsScreen._openItem).
//
// index.js passes in its helpers: db and safeNotifyUser.

const {onDocumentCreated, onDocumentUpdated} = require('firebase-functions/v2/firestore');
const admin = require('firebase-admin');

const MESSAGE_PREVIEW_CHARS = 120;
const MAX_THREAD_MESSAGES_SCANNED = 300;

function preview(text) {
  const t = (text || '').toString().replace(/\s+/g, ' ').trim();
  return t.length > MESSAGE_PREVIEW_CHARS ? `${t.slice(0, MESSAGE_PREVIEW_CHARS - 1)}…` : t;
}

// "Bantay (lost dog)" / "a found cat" — how a report is named in a notification.
function reportName(alert) {
  const species = (alert.species || 'pet').toString().toLowerCase();
  const kind = alert.type === 'found' ? 'found' : 'lost';
  const name = (alert.petName || '').toString().trim();
  return name ? `${name} (${kind} ${species})` : `a ${kind} ${species}`;
}

// Who someone is in a chat: on a lost report the person who filed it is
// the Owner and whoever messages is a Finder; on a found report it's the
// other way round.
function roleIn(chat, uid) {
  const isReporter = uid === chat.reporterId;
  if (chat.alertType === 'found') return isReporter ? 'Finder' : 'Owner';
  return isReporter ? 'Owner' : 'Finder';
}

module.exports = ({db, safeNotifyUser}) => {
  // The report's owner, everyone who posted on its old public thread, and
  // everyone with a chat about it.
  async function threadParticipants(alertId, alert) {
    const uids = new Set();
    if (alert.reporterId) uids.add(alert.reporterId);
    const [msgs, chats] = await Promise.all([
      db.collection('petAlerts').doc(alertId).collection('messages')
        .orderBy('timestamp', 'desc')
        .limit(MAX_THREAD_MESSAGES_SCANNED)
        .get(),
      db.collection('petAlertChats').where('alertId', '==', alertId).get(),
    ]);
    msgs.forEach((m) => {
      const s = m.get('senderId');
      if (s) uids.add(s);
    });
    chats.forEach((c) => {
      const s = c.get('inquirerId');
      if (s) uids.add(s);
    });
    return uids;
  }

  async function notify(uid, {title, body, type, alertId, chatId}) {
    try {
      await db.collection('users').doc(uid).collection('notifications').add({
        title,
        message: body,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false,
        type,
        alertId,
        ...(chatId ? {chatId} : {}),
      });
    } catch (e) {
      console.warn('[petAlerts] in-app notification failed', uid, e.message);
    }
    await safeNotifyUser({uid, title, body, data: {type, alertId, chatId}});
  }

  const notifyPetAlertChatMessage = onDocumentCreated(
    'petAlertChats/{chatId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const msg = snap.data();
      const {chatId} = event.params;
      if (msg.kind === 'system' || !msg.senderId) return;

      const chatRef = db.collection('petAlertChats').doc(chatId);
      const chatSnap = await chatRef.get();
      if (!chatSnap.exists) return;
      const chat = chatSnap.data();

      await chatRef.update({
        lastMessage: preview(msg.text),
        lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
        lastSenderId: msg.senderId,
      });

      const to = msg.senderId === chat.reporterId ? chat.inquirerId : chat.reporterId;
      if (!to || to === msg.senderId) return;
      const name = (msg.senderName || '').toString().trim();
      const role = roleIn(chat, msg.senderId);
      await notify(to, {
        title: name ? `${name} (${role})` : `Message from the ${role.toLowerCase()}`,
        body: preview(msg.text) || 'Sent you a message.',
        type: 'pet_alert_chat',
        alertId: chat.alertId,
        chatId,
      });
    },
  );

  const onPetAlertChatDecision = onDocumentUpdated('petAlertChats/{chatId}', async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;
    const decision = after.matchStatus;
    if (decision === before.matchStatus) return;
    if (decision !== 'confirmed' && decision !== 'rejected') return;
    const {chatId} = event.params;
    const chatRef = db.collection('petAlertChats').doc(chatId);

    const reporterRole = roleIn(after, after.reporterId).toLowerCase();
    // Confirmed, then after meeting it turned out to be a different animal.
    const undone = before.matchStatus === 'confirmed' && decision === 'rejected';
    const note = decision === 'confirmed'
      ? `The ${reporterRole} confirmed this is the right match. Arrange a time and place to meet, then tap Reunited with Owner once the pet is back home.`
      : undone
        ? `The ${reporterRole} found this isn't the right pet after all and marked it as not a match. The report stays open.`
        : `The ${reporterRole} marked this as not a match.`;
    await chatRef.collection('messages').add({
      kind: 'system',
      text: note,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    // The possible match between the report and the sender's own report.
    if (after.linkedAlertId) {
      const lostId = after.alertType === 'found' ? after.linkedAlertId : after.alertId;
      const foundId = after.alertType === 'found' ? after.alertId : after.linkedAlertId;
      try {
        await db.collection('possibleMatches').doc(`${lostId}_${foundId}`).set({
          lostAlertId: lostId,
          foundAlertId: foundId,
          lostReporterId: after.alertType === 'found' ? after.inquirerId : after.reporterId,
          foundReporterId: after.alertType === 'found' ? after.reporterId : after.inquirerId,
          status: decision === 'confirmed' ? 'verified' : 'rejected',
          reviewedBy: after.reporterId,
          reviewedAt: admin.firestore.FieldValue.serverTimestamp(),
          chatId,
        }, {merge: true});
      } catch (e) {
        console.warn('[onPetAlertChatDecision] match update failed', chatId, e.message);
      }
    }

    await notify(after.inquirerId, {
      title: decision === 'confirmed' ? "It's a match!" : 'Not a match',
      body: decision === 'confirmed'
        ? `The ${reporterRole} confirmed you're the right match. Open the chat to arrange the handover.`
        : undone
          ? `The ${reporterRole} found this isn't the right pet after all. Thank you for meeting up and helping.`
          : `The ${reporterRole} doesn't think this is the right match. Thank you for reaching out.`,
      type: 'pet_alert_chat',
      alertId: after.alertId,
      chatId,
    });
  });

  const notifyPetAlertMessage = onDocumentCreated(
    'petAlerts/{alertId}/messages/{messageId}',
    async (event) => {
      const snap = event.data;
      if (!snap) return;
      const msg = snap.data();
      const {alertId} = event.params;
      const senderId = msg.senderId;
      if (!senderId) return;

      const alertSnap = await db.collection('petAlerts').doc(alertId).get();
      if (!alertSnap.exists) return;
      const alert = alertSnap.data();

      const recipients = await threadParticipants(alertId, alert);
      recipients.delete(senderId);
      if (recipients.size === 0) return;

      const sender = (msg.senderName || 'Someone').toString().trim() || 'Someone';
      const body = preview(msg.text) || 'Sent you a message.';

      await Promise.all([...recipients].map((uid) => notify(uid, {
        title: uid === alert.reporterId
          ? `${sender} messaged about your report`
          : `${sender} replied about ${reportName(alert)}`,
        body,
        type: 'pet_alert_message',
        alertId,
      })));
    },
  );

  const onPetAlertReunited = onDocumentUpdated('petAlerts/{alertId}', async (event) => {
    const before = event.data && event.data.before.data();
    const after = event.data && event.data.after.data();
    if (!before || !after) return;
    if (before.status === 'reunited' || after.status !== 'reunited') return;

    // A found report with several animals is one doc per animal; the app
    // marks them all, so act once, on the group's first doc (the id the
    // report page, messages and matches use).
    const {alertId} = event.params;
    if (after.groupId && after.groupId !== alertId) return;

    const field = after.type === 'found' ? 'foundAlertId' : 'lostAlertId';
    const matches = await db.collection('possibleMatches').where(field, '==', alertId).get();
    if (!matches.empty) {
      const batch = db.batch();
      matches.forEach((m) => {
        if (m.get('status') === 'rejected') return;
        batch.update(m.ref, {
          status: 'resolved',
          resolvedAt: admin.firestore.FieldValue.serverTimestamp(),
          resolvedReason: 'reunited',
        });
      });
      await batch.commit();
    }

    const chats = await db.collection('petAlertChats').where('alertId', '==', alertId).get();
    if (!chats.empty) {
      const batch = db.batch();
      chats.forEach((c) => {
        if (c.get('reunitedAt')) return;
        batch.update(c.ref, {reunitedAt: admin.firestore.FieldValue.serverTimestamp()});
      });
      await batch.commit();
    }

    const recipients = await threadParticipants(alertId, after);
    if (after.reunitedBy) recipients.delete(after.reunitedBy);
    if (recipients.size === 0) return;

    await Promise.all([...recipients].map((uid) => notify(uid, {
      title: 'Reunited with owner',
      body: `${reportName(after).replace(/^a /, 'A ')} has been reunited with its owner. Thank you for helping!`,
      type: 'pet_alert_reunited',
      alertId,
    })));
  });

  return {notifyPetAlertMessage, notifyPetAlertChatMessage, onPetAlertChatDecision, onPetAlertReunited};
};
