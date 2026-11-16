// Helpers shared by paymongo.js and campaigns.js. Not a functions module:
// index.js never re-exports it, so nothing here is deployed on its own.

const admin = require('firebase-admin');

const {FieldValue} = admin.firestore;

// "October 15, 2026" (Philippine time) — same format paymongo.js uses.
function formatManilaDate(date) {
  return new Intl.DateTimeFormat('en-US', {
    month: 'long', day: 'numeric', year: 'numeric', timeZone: 'Asia/Manila',
  }).format(date);
}

function formatPeso(amount) {
  return `₱${Number(amount).toLocaleString('en-PH', {minimumFractionDigits: 2, maximumFractionDigits: 2})}`;
}

// Campaign fields set when verified donations first reach the target: the
// campaign stops taking donations (the general view moves it to Past
// Campaigns) but keeps its funds until admins allocate them.
function completedCampaignFields() {
  return {
    status: 'goal_met',
    isActive: false,
    needsExtensionDecision: false,
    completedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  };
}

// "For the benefit of ..." line on the certificate.
function certificateBenefit(c, fallbackTitle) {
  if (c && c.type === 'sponsorship' && c.animalName) return c.animalName;
  if (c && c.fundKind === 'general') return 'our rescues';
  return (c && c.title) || fallbackTitle || 'our rescues';
}

// Certificate of Donation at users/{uid}/certificates/{id} (id = payment or
// donation id, so a retry rewrites the same doc), announced in the donor's
// notifications. Server-written only. Must run inside a transaction `tx`.
// cert.details holds what was given, for the certificate's wording
// (certificate_view.dart): in-kind {inKindCategory, inKindItems,
// quantityReceived}; sponsorship {animalName, sponsoredUntil}.
// cert.notification ({title, message, type}) overrides the generic
// "Certificate of Donation" notification so the donor learns what happened
// (payment confirmed, items received, ...) from that one notification.
function issueCertificate(tx, cert) {
  if (typeof cert.uid !== 'string' || !cert.uid) return;
  const db = admin.firestore();
  const userRef = db.collection('users').doc(cert.uid);
  tx.set(userRef.collection('certificates').doc(cert.id), {
    type: cert.type, // 'donation' | 'sponsorship' | 'inkind'
    recipientName: cert.recipientName || 'Our Supporter',
    organizationName: cert.organizationName || 'Rescue Shelter',
    contribution: cert.contribution,
    benefit: cert.benefit,
    campaignId: cert.campaignId || null,
    campaignTitle: cert.campaignTitle || null,
    refNumber: cert.refNumber || null,
    ...(cert.details || {}),
    dateText: formatManilaDate(new Date()),
    issuedAt: FieldValue.serverTimestamp(),
  });
  const n = cert.notification || {};
  tx.set(userRef.collection('notifications').doc(`certificate_${cert.id}`), {
    title: n.title || 'Certificate of Donation',
    message: n.message || `Thank you for supporting ${cert.benefit}! Your certificate is in Profile → Certificates.`,
    timestamp: FieldValue.serverTimestamp(),
    isRead: false,
    type: n.type || 'certificate',
    certificateType: cert.type,
    certificateId: cert.id,
    campaignId: cert.campaignId || null,
  });
}

module.exports = {formatManilaDate, formatPeso, completedCampaignFields, certificateBenefit, issueCertificate};