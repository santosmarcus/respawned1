// Pure decisions for pet transporter pushes about their rescues
// (functions/index.js notifyTransporterCaseMessage and
// notifyPendingTransporterLocation). No Firebase here, so `node --test`
// checks them.
//
// The transporter on a trip (riderId / assignedVolunteerId) hears about new
// messages on the case thread from anyone else, and a location the reporter
// shares there. Location changes on the case itself already reach that
// transporter (notifyTransporterCaseChanges); a transporter holding a
// pending offer, or sent to check the location, hears about them too.

const MAX_BODY = 140;

function preview(text) {
  const s = String(text || '').replace(/\s+/g, ' ').trim();
  return s.length > MAX_BODY ? `${s.slice(0, MAX_BODY - 1)}…` : s;
}

function riderOf(c) {
  return (c && (c.riderId || c.assignedVolunteerId)) || null;
}

/// The push for a new case message, or null. Questions meant for the
/// reporter (confirm / location requests) aren't sent to the transporter.
function messagePush({caseData, message, activeStatuses}) {
  const rider = riderOf(caseData);
  if (!rider || !message || !message.senderId || message.senderId === rider) return null;
  if (!activeStatuses.includes(String(caseData.status || '').toLowerCase())) return null;
  const kind = message.kind || 'text';
  const name = String(message.senderName || '').trim();
  if (kind === 'location') {
    return {
      uid: rider,
      title: 'New location shared',
      body: message.address ? `The animal is at ${message.address}.` : 'A new location for the animal was shared.',
      type: 'transporter_location_shared',
    };
  }
  if (kind !== 'text') return null;
  const body = preview(message.text);
  if (!body) return null;
  return {uid: rider, title: name ? `Message from ${name}` : 'New message about your rescue', body, type: 'transporter_message'};
}

function locationChanged(before, after) {
  return before.lat !== after.lat || before.lng !== after.lng || (before.address || '') !== (after.address || '');
}

/// Who else hears about a case location change, and what a tap opens: the
/// transporter with a pending offer ([offer] = the case's current
/// assignment) opens the offer; the one sent to check the location while it
/// is being verified opens that check. The assigned transporter is left to
/// notifyTransporterCaseChanges.
function pendingLocationRecipients({before, after, offer, offerId, activeStatuses}) {
  if (!before || !after || !locationChanged(before, after) || after.lat == null || after.lng == null) return [];
  const rider = riderOf(after);
  if (rider && activeStatuses.includes(String(after.status || '').toLowerCase())) return [];
  const out = [];
  if (offer && offer.status === 'pending' && offer.isDemo !== true && offer.riderId) {
    out.push({uid: offer.riderId, data: {type: 'transporter_assignment', ...(offerId ? {assignmentId: offerId} : {})}});
  }
  const v = after.verification;
  if (String(after.status || '') === 'verifying' && v && v.riderId && !out.some((o) => o.uid === v.riderId)) {
    out.push({uid: v.riderId, data: {type: 'verification_visit'}});
  }
  return out;
}

module.exports = {messagePush, pendingLocationRecipients, locationChanged, preview};
