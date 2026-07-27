const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const axios = require("axios");
const PDFDocument = require("pdfkit");

admin.initializeApp();
const db = admin.firestore();
const storage = admin.storage();

// --- RECEIPT GENERATOR ---

exports.generateReceipt = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");

  const { donationId } = request.data;
  const donationSnap = await db.collection("donations").doc(donationId).get();
  if (!donationSnap.exists) throw new HttpsError("not-found", "Record not found.");

  const d = donationSnap.data();
  const doc = new PDFDocument({ size: "A4", margin: 50 });
  const buffers = [];

  doc.on("data", buffers.push.bind(buffers));

  return new Promise((resolve, reject) => {
    doc.on("end", async () => {
      const pdfData = Buffer.concat(buffers);
      const filename = `receipts/${donationId}.pdf`;
      const file = storage.bucket().file(filename);

      try {
        await file.save(pdfData, { contentType: "application/pdf" });
        const [url] = await file.getSignedUrl({
          action: "read",
          expires: "03-01-2500", // Far future
        });
        resolve({ url });
      } catch (e) {
        reject(new HttpsError("internal", "Failed to save receipt."));
      }
    });

    // Minimalist Template
    doc.fontSize(20).text("OFFICIAL RECEIPT", { align: "center" });
    doc.moveDown();
    doc.fontSize(12).text(`Organization: ${d.organizer || "ResPAWnd Rescue"}`);
    doc.text(`Reference No: ${d.refNumber || donationId}`);
    doc.text(`Date: ${d.date || new Date().toDateString()}`);
    doc.moveDown();
    doc.text(`Donor Name: ${d.donorName || "Anonymous"}`);
    doc.fontSize(16).text(`Amount: ₱${(d.amount || 0).toFixed(2)}`, { bold: true });
    doc.moveDown();
    doc.fontSize(10).text("Thank you for your generous contribution to animal welfare.", { align: "center", italic: true });

    doc.end();
  });
});

// --- PAYMONGO FUNCTIONS (from Austin) ---

exports.createPaymentIntent = onCall({
  secrets: ["PAYMONGO_SECRET_KEY"],
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "User must be logged in.",
    );
  }

  const data = request.data;
  const secretKey = process.env.PAYMONGO_SECRET_KEY;

  try {
    const response = await axios.post(
      "https://api.paymongo.com/v1/payment_intents",
      {
        data: {
          attributes: {
            amount: data.amount,
            payment_method_allowed: ["card", "gcash", "paymaya"],
            currency: "PHP",
            description: data.description || "App Donation",
            metadata: data.metadata || {},
          },
        },
      },
      {
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Basic ${Buffer.from(secretKey + ":")
            .toString("base64")}`,
        },
      },
    );

    return response.data.data;
  } catch (error) {
    console.error("PayMongo Error:", error.response ?
      error.response.data : error.message);
    throw new HttpsError(
      "internal",
      "Failed to create payment intent.",
    );
  }
});

exports.retrievePaymentIntent = onCall({
  secrets: ["PAYMONGO_SECRET_KEY"],
}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "User must be logged in.");
  }

  const intentId = request.data.intentId;
  const secretKey = process.env.PAYMONGO_SECRET_KEY;

  try {
    const response = await axios.get(
      `https://api.paymongo.com/v1/payment_intents/${intentId}`,
      {
        headers: {
          Authorization: `Basic ${Buffer.from(secretKey + ":")
            .toString("base64")}`,
        },
      },
    );

    return response.data.data;
  } catch (error) {
    console.error("PayMongo Status Error:", error.response ?
      error.response.data : error.message);
    throw new HttpsError("internal", "Failed to retrieve status.");
  }
});

exports.paymongoWebhook = onRequest(async (req, res) => {
  const secret = process.env.PAYMONGO_WEBHOOK_SECRET;
  // In production, verify the signature here using the secret.

  const event = req.body.data;
  const ip = req.ip || req.headers["x-forwarded-for"] || req.connection.remoteAddress;

  if (event.attributes.type === "payment.paid") {
    const payment = event.attributes.data;
    const amount = payment.attributes.amount / 100;
    const metadata = payment.attributes.metadata || {};
    const intentId = payment.attributes.payment_intent_id;

    // Use Intent ID as document ID to prevent duplicates with client-side write
    const donationRef = db.collection("donations").doc(intentId || payment.id);
    const donationSnap = await donationRef.get();

    const donationData = {
      amount,
      status: "succeeded",
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      userId: metadata.userId || "anonymous",
      campaignId: metadata.campaignId || "general",
      method: payment.attributes.payment_method_type,
      refNumber: payment.id,
      webhookVerified: true,
      donorName: metadata.donorName || "Anonymous",
      isPublic: metadata.isPublic === "true",
      type: metadata.isSponsorship === "true" ? "sponsorship" : "donation",
    };

    await donationRef.set(donationData, { merge: true });

    // If metadata exists, perform the campaign and user history updates
    if (metadata.campaignId && !donationSnap.exists) {
      const campaignRef = db.collection("campaigns").doc(metadata.campaignId);
      await db.runTransaction(async (t) => {
        const campaignSnap = await t.get(campaignRef);
        if (campaignSnap.exists) {
          const cData = campaignSnap.data();
          t.update(campaignRef, {
            collectedAmount: (cData.collectedAmount || 0) + amount,
            numdonors: admin.firestore.FieldValue.increment(1),
          });
        }

        if (metadata.userId) {
          const historyRef = db.collection("users").doc(metadata.userId).collection("history").doc(donationRef.id);
          t.set(historyRef, donationData);
        }
      });
    }

    console.log(`Payment recorded via Webhook: ₱${amount}`);
  } else if (event.attributes.type === "payment.failed") {
    // Handle Auto-Blocking (5 failures / 15 mins)
    const blockRef = db.collection("failed_attempts").doc();
    await blockRef.set({
      ip,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);
    const recentFailures = await db.collection("failed_attempts")
      .where("ip", "==", ip)
      .where("timestamp", ">=", admin.firestore.Timestamp.fromDate(fifteenMinsAgo))
      .get();

    if (recentFailures.size >= 5) {
      await db.collection("blocked_sources").doc(ip).set({
        blockedAt: admin.firestore.FieldValue.serverTimestamp(),
        reason: "Repeated payment failures",
      });
      console.log(`Source blocked: ${ip}`);
    }
  } else if (event.attributes.type === "payment.refunded") {
    const payment = event.attributes.data;
    const refNumber = payment.id;

    // Find the donation and mark as refunded
    const donationSnap = await db.collection("donations")
      .where("refNumber", "==", refNumber)
      .limit(1)
      .get();

    if (!donationSnap.empty) {
      await donationSnap.docs[0].ref.update({
        status: "refunded",
        refundStatus: "approved",
        refundedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.log(`Donation marked as refunded: ${refNumber}`);
    }
  }

  res.status(200).send("Webhook received");
});

exports.subscriptionEngine = onSchedule("every 24 hours", async () => {
  const now = admin.firestore.Timestamp.now();
  const activeSponsorships = await db.collection("donations")
    .where("type", "==", "sponsorship")
    .where("status", "==", "active")
    .where("nextChargeDate", "<=", now)
    .get();

  for (const doc of activeSponsorships.docs) {
    const s = doc.data();
    try {
      // Trigger renewal via PayMongo API (using stored Payment Method ID)
      // This is a placeholder for the actual API call
      console.log(`Processing renewal for sponsorship: ${doc.id}`);

      // Update next charge date on success
      await doc.ref.update({
        nextChargeDate: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)),
        lastRenewalAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (error) {
      console.error(`Renewal failed for ${doc.id}: ${error.message}`);
      // Anti-frustration: Sponsorship remains 'active' but flagged for grace period
      await doc.ref.update({
        renewalError: error.message,
        isOverdue: true,
      });
    }
  }
});

exports.reconciliationJob = onSchedule("every 24 hours", async () => {
  const secretKey = process.env.PAYMONGO_SECRET_KEY;
  const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  try {
    const response = await axios.get(
      `https://api.paymongo.com/v1/payments?after=${yesterday}`,
      {
        headers: {
          Authorization: `Basic ${Buffer.from(secretKey + ":").toString("base64")}`,
        },
      },
    );

    const payments = response.data.data;
    for (const p of payments) {
      const exists = await db.collection("donations").where("refNumber", "==", p.id).get();
      if (exists.empty) {
        console.warn(`Reconciliation Alert: Found unmatched payment ${p.id}. Recording now.`);
        // Record missing donation...
      }
    }
  } catch (error) {
    console.error("Reconciliation Error:", error.message);
  }
});

exports.requestRefund = onCall({
  secrets: ["PAYMONGO_SECRET_KEY"],
}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "User must be logged in.");

  const { donationId, reason } = request.data;
  const secretKey = process.env.PAYMONGO_SECRET_KEY;

  try {
    const donationSnap = await db.collection("donations").doc(donationId).get();
    if (!donationSnap.exists) throw new HttpsError("not-found", "Donation record not found.");

    const p = donationSnap.data();
    // In production, trigger PayMongo Refund API: https://developers.paymongo.com/reference/create-a-refund
    // Here we just mark as pending for Org Admin review
    await donationSnap.ref.update({
      refundStatus: "pending",
      refundReason: reason,
      refundRequestedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Log to audit log
    await db.collection("audit_logs").add({
      type: "refund_requested",
      donationId,
      userId: request.auth.uid,
      reason,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    return { success: true };
  } catch (error) {
    console.error("Refund Error:", error.message);
    throw new HttpsError("internal", "Failed to process refund request.");
  }
});

// --- RESCUE FUNCTIONS (from Merge) ---

exports.getOrCreateRescueSession = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }

  const { tagId, location } = request.data || {};
  if (!tagId) {
    throw new HttpsError("invalid-argument", "tagId is required.");
  }

  const tagRef = db.collection("collarTags").doc(tagId);
  const tagSnap = await tagRef.get();
  if (!tagSnap.exists) {
    throw new HttpsError("not-found", "This tag is not registered.");
  }
  const tagData = tagSnap.data();

  const lat = location && typeof location.lat === "number" ? location.lat : null;
  const lng = location && typeof location.lng === "number" ? location.lng : null;
  const address = location && typeof location.address === "string" ? location.address : null;

  const existingSessionId = tagData.activeRescueSessionId;
  if (existingSessionId) {
    const existingRef = db.collection("rescueSessions").doc(existingSessionId);
    const existingSnap = await existingRef.get();
    if (existingSnap.exists && existingSnap.data().status !== "resolved") {
      if (lat !== null && lng !== null) {
        await existingRef.set(
          {
            lat,
            lng,
            ...(address !== null ? { address } : {}),
            lastScannedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        const tagRescanUpdate = {
          lastSeenLat: lat,
          lastSeenLng: lng,
          ...(address !== null ? { lastSeenAddress: address } : {}),
        };
        await tagRef.set(tagRescanUpdate, { merge: true });
        const rescanOwnerId = tagData.ownerId;
        if (rescanOwnerId) {
          await db
            .collection("users")
            .doc(rescanOwnerId)
            .collection("collarTags")
            .doc(tagId)
            .set(tagRescanUpdate, { merge: true });
        }
      }

      return { sessionId: existingSessionId };
    }
  }

  const sessionRef = db.collection("rescueSessions").doc();
  await sessionRef.set({
    tagId,
    status: "active",
    chatEnabledByOwner: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(lat !== null ? { lat } : {}),
    ...(lng !== null ? { lng } : {}),
    ...(address !== null ? { address } : {}),
  });

  const tagUpdate = {
    status: "lost",
    activeRescueSessionId: sessionRef.id,
    lostAt: admin.firestore.FieldValue.serverTimestamp(),
    ...(lat !== null ? { lastSeenLat: lat } : {}),
    ...(lng !== null ? { lastSeenLng: lng } : {}),
    ...(address !== null ? { lastSeenAddress: address } : {}),
  };

  await tagRef.set(tagUpdate, { merge: true });

  const ownerId = tagData.ownerId;
  if (ownerId) {
    await db
      .collection("users")
      .doc(ownerId)
      .collection("collarTags")
      .doc(tagId)
      .set(tagUpdate, { merge: true });
  }

  return { sessionId: sessionRef.id };
});

const UNCONFIRMED_THRESHOLD_MINUTES = 15;
const NUDGE_COOLDOWN_MINUTES = 20;
const RADIUS_KM = 5;
const CASES_SCAN_LIMIT = 300;
const DISMISSED_STATUSES = ["dismissed", "cancelled", "withdrawn", "rejected"];
const PICKED_UP_STATUSES = [
  "treatment",
  "dropoff",
  "searching_clinic",
  "in_transit_shelter",
  "completed",
  "ended",
];

function haversineKm(lat1, lng1, lat2, lng2) {
  const earthRadiusKm = 6371.0;
  const deg2rad = (deg) => (deg * Math.PI) / 180.0;
  const dLat = deg2rad(lat2 - lat1);
  const dLng = deg2rad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) * Math.sin(dLng / 2) ** 2;
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return earthRadiusKm * c;
}

function isFinalStatus(status) {
  const s = (status || "").toLowerCase();
  return s === "closed" || s.includes("completed") || s.includes("ended");
}

function hasBeenPickedUp(c) {
  const s = (c.status || "").toLowerCase();
  return PICKED_UP_STATUSES.includes(s);
}

function hasReceivedResponse(c, communityReportsCount) {
  const status = (c.status || "").toLowerCase();
  if (status && status !== "pending" && status !== "open") return true;
  if (c.riderId || c.assignedVolunteerId) return true;
  if (communityReportsCount > 0) return true;
  if (hasBeenPickedUp(c)) return true;
  return false;
}

async function notifyUser({ uid, title, body, data }) {
  if (!uid) return false;
  const userDoc = await db.collection("users").doc(uid).get();
  if (!userDoc.exists) return false;
  const token = userDoc.data().fcmToken;
  if (!token) return false;

  await admin.messaging().send({
    token,
    notification: { title, body },
    data,
  });
  return true;
}

async function notifyNearbyUsers({ lat, lng, excludeUid, title, body, data }) {
  const latDeltaDeg = RADIUS_KM / 111;
  const lngDeltaDeg = RADIUS_KM / (111 * Math.cos((lat * Math.PI) / 180));

  const usersSnap = await db
    .collection("users")
    .where("lastLat", ">=", lat - latDeltaDeg)
    .where("lastLat", "<=", lat + latDeltaDeg)
    .get();

  const tokens = [];
  usersSnap.forEach((userDoc) => {
    if (userDoc.id === excludeUid) return;
    const u = userDoc.data();
    if (!u.fcmToken || u.lastLng == null) return;
    if (Math.abs(u.lastLng - lng) > lngDeltaDeg) return;
    if (haversineKm(lat, lng, u.lastLat, u.lastLng) <= RADIUS_KM) {
      tokens.push(u.fcmToken);
    }
  });

  if (tokens.length === 0) return 0;

  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data,
  });

  return tokens.length;
}

exports.notifyNewCaseReported = onDocumentCreated(
  "cases/{caseId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const c = snap.data();

    if (c.lat == null || c.lng == null) return;

    const status = (c.status || "").toLowerCase();
    if (DISMISSED_STATUSES.includes(status)) return;

    await notifyNearbyUsers({
      lat: c.lat,
      lng: c.lng,
      excludeUid: c.reporterId,
      title: "New rescue report near you",
      body: "A rescue report just came in nearby — tap to see if you can help.",
      data: {
        type: "new_case_nearby",
        caseId: event.params.caseId,
      },
    });
  },
);

exports.notifyUnconfirmedReports = onSchedule("every 5 minutes", async () => {
  const now = admin.firestore.Timestamp.now();

  const casesSnap = await db
    .collection("cases")
    .orderBy("createdAt", "desc")
    .limit(CASES_SCAN_LIMIT)
    .get();

  for (const caseDoc of casesSnap.docs) {
    const c = caseDoc.data();
    const status = (c.status || "").toLowerCase();

    if (DISMISSED_STATUSES.includes(status)) continue;
    if (isFinalStatus(status)) continue;
    if (c.lat == null || c.lng == null) continue;

    const reportsSnap = await caseDoc.ref
      .collection("communityReports")
      .orderBy("timestamp", "desc")
      .limit(1)
      .get();

    if (hasReceivedResponse(c, reportsSnap.size)) continue;

    const lastNudge = c.lastNudgeSentAt;

    if (!lastNudge) {
      const createdMs = c.createdAt ? c.createdAt.toMillis() : 0;
      const minutesSinceCreated = (now.toMillis() - createdMs) / 60000;
      if (minutesSinceCreated < UNCONFIRMED_THRESHOLD_MINUTES) continue;
    } else {
      const minutesSinceLastNudge =
        (now.toMillis() - lastNudge.toMillis()) / 60000;
      if (minutesSinceLastNudge < NUDGE_COOLDOWN_MINUTES) continue;
    }

    const notifiedCount = await notifyNearbyUsers({
      lat: c.lat,
      lng: c.lng,
      excludeUid: c.reporterId,
      title: "A nearby report still needs a responder",
      body: "This report is still awaiting a pet transporter — is the animal present or not? Tap to confirm.",
      data: {
        type: "community_nudge",
        caseId: caseDoc.id,
      },
    });

    if (notifiedCount === 0) continue;

    await caseDoc.ref.update({
      lastNudgeSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
});

exports.notifyDonationStatusUpdate = onDocumentUpdated(
  "donations/{donationId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after || before.status === after.status) return;

    const uid = after.userId;
    if (!uid) return;

    let title = "";
    let body = "";
    let type = "";

    if (after.type === "inkind" && after.status === "complete") {
      title = "In-Kind Donation Complete";
      body = `Your donation to ${after.organizer || "the shelter"} has been marked as complete. Thank you for your contribution!`;
      type = "inkind_complete";
    } else if (after.type === "sponsorship" && after.status === "inactive") {
      title = "Sponsorship Ended Early";
      body = `The pet you were sponsoring, ${after.animalName || "the pet"}, is no longer up for sponsorship. We're sorry for the inconvenience.`;
      type = "sponsorship_cancelled";
    }

    if (!title) return;

    // 1. Add to in-app notifications collection
    await db.collection("users").doc(uid).collection("notifications").add({
      title,
      message: body,
      type,
      donationId: event.params.donationId,
      campaignId: after.campaignId || null,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      isRead: false,
    });

    // 2. Send Push Notification
    await notifyUser({
      uid,
      title,
      body,
      data: {
        type,
        donationId: event.params.donationId,
        campaignId: after.campaignId || "",
      },
    });
  },
);

exports.notifyCampaignGoalReached = onDocumentUpdated(
  "campaigns/{campaignId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after) return;

    const reachedBefore = before.collectedAmount >= before.targetAmount;
    const reachedAfter = after.collectedAmount >= after.targetAmount;

    if (reachedAfter && !reachedBefore) {
      const title = "Goal Reached";
      const body = `A campaign you donated to, ${after.title}, has reached its goal. Thank you for your contribution!`;

      // Find all unique donors
      const donationsSnap = await db
        .collection("donations")
        .where("campaignId", "==", event.params.campaignId)
        .get();

      const donorIds = new Set();
      donationsSnap.forEach((doc) => {
        const d = doc.data();
        if (d.userId) donorIds.add(d.userId);
      });

      for (const uid of donorIds) {
        // 1. Add to in-app notifications
        await db.collection("users").doc(uid).collection("notifications").add({
          title,
          message: body,
          type: "goal_reached",
          campaignId: event.params.campaignId,
          timestamp: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false,
        });

        // 2. Send Push Notification
        await notifyUser({
          uid,
          title,
          body,
          data: {
            type: "goal_reached",
            campaignId: event.params.campaignId,
          },
        });
      }
    }
  },
);

const REPORTER_NOTIFY_STATUSES = {
  unable_to_locate: {
    title: "Update on your rescue report",
    body: "The transporter couldn't find the animal at the location you reported. Can you confirm or update the location?",
  },
  awaiting_reporter_response: {
    title: "Update on your rescue report",
    body: "The transporter could not find the animal and could not reach you. Please respond with an updated location if you can.",
  },
  pickup_attempt_unsuccessful: {
    title: "We tried to reach you",
    body: "A pickup attempt was made for your rescue report, but we couldn't reach you. Please respond so we can reschedule.",
  },
  needs_specialized_assistance: {
    title: "Update on your rescue report",
    body: "Pickup was postponed because the animal could not be safely handled. Our team is arranging specialized assistance.",
  },
};

exports.notifyOnEndReasonStatus = onDocumentUpdated(
  "cases/{caseId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after || before.status === after.status) return;

    const config = REPORTER_NOTIFY_STATUSES[after.status];
    if (!config) return;

    await notifyUser({
      uid: after.reporterId,
      title: config.title,
      body: config.body,
      data: {
        type: "case_status_update",
        caseId: event.params.caseId,
        status: after.status,
      },
    });

    if (after.status === "needs_specialized_assistance") {
      await db.collection("adminAlerts").add({
        type: "needs_specialized_assistance",
        caseId: event.params.caseId,
        reason: after.endReason || null,
        notes: after.endReasonNotes || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        resolved: false,
      });
    }
  },
);

const REPORTER_RESPONSE_TIMEOUT_HOURS = 48;

exports.expireStaleReporterResponses = onSchedule("every 60 minutes", async () => {
  const cutoffMs = Date.now() - REPORTER_RESPONSE_TIMEOUT_HOURS * 60 * 60 * 1000;

  const casesSnap = await db
    .collection("cases")
    .where("status", "in", [
      "unable_to_locate",
      "awaiting_reporter_response",
      "pickup_attempt_unsuccessful",
    ])
    .get();

  for (const caseDoc of casesSnap.docs) {
    const c = caseDoc.data();
    const awaitingSince = c.awaitingReporterSince;
    if (!awaitingSince) continue;
    if (awaitingSince.toMillis() > cutoffMs) continue;

    await caseDoc.ref.update({
      status: "cancelled",
      statusHistory: admin.firestore.FieldValue.arrayUnion([
        {
          status: `Case automatically closed after ${REPORTER_RESPONSE_TIMEOUT_HOURS}h with no reporter response.`,
          timestamp: admin.firestore.Timestamp.now(),
        },
      ]),
      awaitingReporterSince: admin.firestore.FieldValue.delete(),
    });
  }
});
