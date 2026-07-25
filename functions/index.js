const {onCall, onRequest} = require("firebase-functions/v2/https");
const {HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const axios = require("axios");

admin.initializeApp();

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
              description: "App Donation",
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
  const event = req.body.data;

  if (event.attributes.type === "payment.paid") {
    const payment = event.attributes.data;
    const amount = payment.attributes.amount / 100;

    console.log(`Payment successful: ₱${amount}`);
  }

  res.status(200).send("Webhook received");
});
