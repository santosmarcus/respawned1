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
    dateText: formatManilaDate(new Date()),
    issuedAt: FieldValue.serverTimestamp(),
  });
  tx.set(userRef.collection('notifications').doc(`certificate_${cert.id}`), {
    title: 'Certificate of Donation',
    message: `Thank you for supporting ${cert.benefit}! Your certificate is in Profile → Certificates.`,
    timestamp: FieldValue.serverTimestamp(),
    isRead: false,
    type: 'certificate',
    certificateId: cert.id,
  });
}

module.exports = {formatManilaDate, formatPeso, completedCampaignFields, certificateBenefit, issueCertificate};
