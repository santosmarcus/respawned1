// Facebook Page Sharing spec — Animal Records → Facebook Page publishing.
//
// Architecture: Flutter admin UI -> authenticated callable Cloud Function ->
// verify organization Owner/active-Admin -> Meta Graph API -> Google Secret
// Manager for the Page access token -> Firestore for safe connection
// metadata + per-animal management logs. The raw Page access token (and the
// short-lived/long-lived user tokens obtained during connect) NEVER reach
// Flutter and are never written to Firestore — only Secret Manager.
//
// Canonical org role schema reused as-is from the rest of this codebase
// (see lib/core/repos/org_membership_service.dart / lib/core/models/rescue/
// org_role.dart): organizations/{orgId}.ownerId identifies the owner;
// organizations/{orgId}/members/{uid}.role is 'admin' | 'staff' ('staff' ==
// "Organization Member" in the UI). Unlike the rest of the app's temporary
// equal-access phase (where a missing membership doc fails OPEN), Facebook
// connect/disconnect/test/publish deliberately fail CLOSED on anything but
// a confirmed owner or an active admin membership doc — this is the one
// narrowly-scoped stricter boundary the whole spec asks for.

const {onCall, HttpsError} = require('firebase-functions/v2/https');
const {defineSecret} = require('firebase-functions/params');
const admin = require('firebase-admin');
const {SecretManagerServiceClient} = require('@google-cloud/secret-manager');

const fbAppId = defineSecret('FB_APP_ID');
const fbAppSecret = defineSecret('FB_APP_SECRET');

// Not secret (Meta's own version string), but centralized so every Graph
// call in this file uses the same reviewed version instead of hardcoding
// it repeatedly. Bump this after checking the current Meta Graph API
// changelog — do not assume this stays correct indefinitely.
const GRAPH_API_VERSION = 'v21.0';
const GRAPH_BASE = `https://graph.facebook.com/${GRAPH_API_VERSION}`;

const PENDING_REQUEST_TTL_MS = 10 * 60 * 1000; // 10 minutes

function db() {
  return admin.firestore();
}

function secretClient() {
  return new SecretManagerServiceClient();
}

function gcpProjectId() {
  return process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT;
}

// ---- Secret Manager helpers (per-organization dynamic secrets) -----------
//
// defineSecret (used above for FB_APP_ID/FB_APP_SECRET) only supports
// secrets whose NAMES are known at deploy time — it can't address a secret
// named dynamically per organizationId. Per-org Page tokens and the
// short-lived pending-selection cache genuinely need a name chosen at
// runtime, so those go through the Secret Manager Admin client directly.
//
// Requires (documented again in the final report — cannot be granted by
// this code): Secret Manager API enabled on the GCP project, and the Cloud
// Functions runtime service account granted roles/secretmanager.admin (or
// at least create+addVersion+access+delete on this project) — a `defineSecret`-only
// deployment does NOT include this broader permission automatically.

async function writeDynamicSecret(secretId, value) {
  const client = secretClient();
  const parent = `projects/${gcpProjectId()}`;
  const secretPath = `${parent}/secrets/${secretId}`;
  try {
    await client.getSecret({name: secretPath});
  } catch (e) {
    if (e.code !== 5 /* NOT_FOUND */) throw e;
    await client.createSecret({
      parent,
      secretId,
      secret: {replication: {automatic: {}}},
    });
  }
  const [version] = await client.addSecretVersion({
    parent: secretPath,
    payload: {data: Buffer.from(value, 'utf8')},
  });

  // Disable (never delete outright here — avoids a race with an in-flight
  // read of the previous version) every older enabled version so a stale
  // Page token can't silently keep working after a reconnect.
  const [versions] = await client.listSecretVersions({parent: secretPath});
  for (const v of versions) {
    if (v.name !== version.name && v.state === 'ENABLED') {
      try {
        await client.disableSecretVersion({name: v.name});
      } catch (_) {
        // Best-effort cleanup only — never fails the primary write.
      }
    }
  }
  return version.name;
}

async function readDynamicSecret(secretId) {
  const client = secretClient();
  const name = `projects/${gcpProjectId()}/secrets/${secretId}/versions/latest`;
  try {
    const [accessResponse] = await client.accessSecretVersion({name});
    return accessResponse.payload.data.toString('utf8');
  } catch (e) {
    if (e.code === 5 /* NOT_FOUND */) return null;
    throw e;
  }
}

async function deleteDynamicSecret(secretId) {
  const client = secretClient();
  const name = `projects/${gcpProjectId()}/secrets/${secretId}`;
  try {
    await client.deleteSecret({name});
  } catch (e) {
    if (e.code !== 5 /* NOT_FOUND */) throw e;
  }
}

function pageTokenSecretId(organizationId) {
  return `fb-page-token-${organizationId}`;
}

function pendingPagesSecretId(requestId) {
  return `fb-pending-pages-${requestId}`;
}

// ---- Authorization (never trusts client-provided role/isAdmin/etc) -------

async function requireOwnerOrActiveAdmin(uid, organizationId) {
  if (!organizationId) {
    throw new HttpsError('invalid-argument', 'organizationId is required.');
  }
  const orgSnap = await db().collection('organizations').doc(organizationId).get();
  if (!orgSnap.exists) {
    throw new HttpsError('not-found', 'Organization not found.');
  }
  if (orgSnap.data().ownerId === uid) return; // legacy-owner-safe: no membership doc required

  const memberSnap = await db()
      .collection('organizations')
      .doc(organizationId)
      .collection('members')
      .doc(uid)
      .get();
  const member = memberSnap.data();
  const status = member && member.status;
  const isActive = !status || !['inactive', 'removed', 'disabled'].includes(status);
  if (memberSnap.exists && isActive && member.role === 'admin') return;

  throw new HttpsError(
      'permission-denied',
      'Only the organization owner or an active Organization Admin can manage Facebook Page publishing.',
  );
}

/// Publishing is wider than managing the connection: the owner, an active
/// admin, or an active member an admin granted `facebookPublisher` to. The
/// grant is an app-level permission only — posts go out as the Page via the
/// stored Page token, so the member needs no Facebook role on the Page.
async function requireFacebookPublisher(uid, organizationId) {
  if (!organizationId) {
    throw new HttpsError('invalid-argument', 'organizationId is required.');
  }
  const orgSnap = await db().collection('organizations').doc(organizationId).get();
  if (!orgSnap.exists) {
    throw new HttpsError('not-found', 'Organization not found.');
  }
  if (orgSnap.data().ownerId === uid) return;

  const memberSnap = await db()
      .collection('organizations')
      .doc(organizationId)
      .collection('members')
      .doc(uid)
      .get();
  const member = memberSnap.data();
  const status = member && member.status;
  const isActive = !status || !['inactive', 'removed', 'disabled'].includes(status);
  if (memberSnap.exists && isActive && (member.role === 'admin' || member.facebookPublisher === true)) return;

  throw new HttpsError(
      'permission-denied',
      'Only the organization owner, an Organization Admin, or a member allowed to share to Facebook can publish to the Page.',
  );
}

/// Animal Records viewing/managing itself stays open to any active member —
/// this only re-verifies the caller has SOME active relationship with the
/// organization (owner, admin, or active member) so a completely unrelated
/// account can't call facebookPublishAnimalRecords with someone else's
/// organizationId and have it silently no-op past the stricter check inside
/// that function. Mirrors OrganizationCapabilities' resolution, not a new
/// authorization concept.
async function requireActiveOrgRelationship(uid, organizationId) {
  const orgSnap = await db().collection('organizations').doc(organizationId).get();
  if (orgSnap.exists && orgSnap.data().ownerId === uid) return;
  const memberSnap = await db()
      .collection('organizations')
      .doc(organizationId)
      .collection('members')
      .doc(uid)
      .get();
  if (!memberSnap.exists) {
    throw new HttpsError('permission-denied', 'Not a member of this organization.');
  }
  const status = memberSnap.data().status;
  const isActive = !status || !['inactive', 'removed', 'disabled'].includes(status);
  if (!isActive) {
    throw new HttpsError('permission-denied', 'This organization membership is no longer active.');
  }
}

// ---- Graph API error classification ---------------------------------------
//
// Section 3 requirement: distinguish dev-mode/not-permitted/no-page-
// selected/permission-declined/expired-token/app-review-required instead of
// a single generic "Facebook error" for everything.
function classifyGraphError(status, body) {
  const err = (body && body.error) || {};
  const code = err.code;
  const subcode = err.error_subcode;
  const type = err.type;

  if (code === 190) {
    return {code: 'token-expired', message: 'This Facebook connection has expired or was revoked. Reconnect the Page.'};
  }
  if (code === 200 || type === 'OAuthException' && subcode === 458) {
    return {code: 'permission-declined', message: 'A required Facebook Page permission was declined or removed.'};
  }
  if (code === 10 || subcode === 33) {
    return {code: 'not-permitted', message: 'This Facebook account is not permitted to manage the selected Page.'};
  }
  if (subcode === 1349048 || subcode === 1349152) {
    return {code: 'dev-mode', message: 'This Facebook app is still in development mode and cannot act on this Page yet.'};
  }
  if (code === 100 && /permission/i.test(err.message || '')) {
    return {code: 'app-review-required', message: 'Facebook App Review is required for this action before it can be used.'};
  }
  return {code: 'facebook-error', message: 'Facebook rejected this request. Please try again or reconnect the Page.'};
}

async function graphFetch(path, {method = 'GET', params = {}, body} = {}) {
  const url = new URL(`${GRAPH_BASE}${path}`);
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== null) url.searchParams.set(k, v);
  }
  const res = await fetch(url.toString(), {
    method,
    headers: body ? {'Content-Type': 'application/json'} : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) {
    const classified = classifyGraphError(res.status, json);
    throw new HttpsError('failed-precondition', classified.message, {facebookErrorCode: classified.code});
  }
  return json;
}

async function writeOrgAuditLog({action, actorId, actorEmail, organizationId, newValues}) {
  try {
    await db().collection('auditLogs').add({
      category: 'organizationStaff',
      action,
      actorId,
      actorEmail: actorEmail || null,
      organizationId,
      targetType: 'FacebookIntegration',
      targetId: organizationId,
      newValues: newValues || {},
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    // Best-effort only — never blocks the primary Facebook operation,
    // matching AuditLogRepository.log's own existing non-blocking contract.
    console.error('[facebook] audit log write failed', e);
  }
}

// ---- 1. Connect ------------------------------------------------------------
//
// Flutter obtains a short-lived Facebook USER access token client-side via
// flutter_facebook_auth's native login (already an existing dependency in
// this app) and passes it here — this is the one token the client is
// expected to hold, exactly as Facebook's own Login SDK design intends; it
// is never the Page token, and this function never returns it or the Page
// token back to the client.
exports.facebookConnectPage = onCall(
    {secrets: [fbAppId, fbAppSecret]},
    async (request) => {
      if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
      const uid = request.auth.uid;
      const {organizationId, userAccessToken} = request.data || {};
      if (!organizationId || !userAccessToken) {
        throw new HttpsError('invalid-argument', 'organizationId and userAccessToken are required.');
      }
      await requireOwnerOrActiveAdmin(uid, organizationId);

      // Short-lived -> long-lived user token exchange (standard Meta flow).
      const exchange = await graphFetch('/oauth/access_token', {
        params: {
          grant_type: 'fb_exchange_token',
          client_id: fbAppId.value(),
          client_secret: fbAppSecret.value(),
          fb_exchange_token: userAccessToken,
        },
      });
      const longLivedUserToken = exchange.access_token;
      if (!longLivedUserToken) {
        throw new HttpsError('failed-precondition', 'Could not validate this Facebook login.');
      }

      const accounts = await graphFetch('/me/accounts', {
        params: {fields: 'id,name,username,picture,access_token', access_token: longLivedUserToken},
      });
      const pages = accounts.data || [];
      if (pages.length === 0) {
        throw new HttpsError(
            'failed-precondition',
            'This Facebook account does not manage any Pages. Ask the Page admin to grant access, or connect with an account that manages the organization\'s Page.',
            {facebookErrorCode: 'not-permitted'},
        );
      }

      const safeMeta = (p) => ({
        pageId: p.id,
        pageName: p.name,
        pageUsername: p.username || null,
        pagePictureUrl: p.picture && p.picture.data ? p.picture.data.url : null,
      });

      if (pages.length === 1) {
        await finalizeConnection({organizationId, uid, actorEmail: request.auth.token.email, page: pages[0]});
        return {status: 'connected', page: safeMeta(pages[0])};
      }

      // Multiple pages — cache per-page tokens server-side only (Secret
      // Manager, short TTL) and hand back safe metadata for selection.
      const requestId = db().collection('facebookConnectRequests').doc().id;
      await writeDynamicSecret(
          pendingPagesSecretId(requestId),
          JSON.stringify(Object.fromEntries(pages.map((p) => [p.id, p.access_token]))),
      );
      await db().collection('facebookConnectRequests').doc(requestId).set({
        uid,
        organizationId,
        status: 'pending_selection',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + PENDING_REQUEST_TTL_MS),
      });

      return {status: 'selection_required', requestId, pages: pages.map(safeMeta)};
    },
);

async function finalizeConnection({organizationId, uid, actorEmail, page}) {
  await writeDynamicSecret(pageTokenSecretId(organizationId), page.access_token);
  await db()
      .collection('organizations')
      .doc(organizationId)
      .collection('integrations')
      .doc('facebook')
      .set({
        pageId: page.id,
        pageName: page.name,
        pageUsername: page.username || null,
        pagePictureUrl: page.picture && page.picture.data ? page.picture.data.url : null,
        pageUrl: page.username ? `https://facebook.com/${page.username}` : `https://facebook.com/${page.id}`,
        connectionStatus: 'connected',
        connectedBy: uid,
        connectedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastValidatedAt: admin.firestore.FieldValue.serverTimestamp(),
        permissionsGranted: ['pages_show_list', 'pages_read_engagement', 'pages_manage_posts'],
        graphApiVersion: GRAPH_API_VERSION,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
  await writeOrgAuditLog({
    action: 'Facebook Page connected',
    actorId: uid,
    actorEmail,
    organizationId,
    newValues: {pageId: page.id, pageName: page.name},
  });
}

// ---- 2. Confirm page selection (only reached when >1 page was offered) ----
exports.facebookConfirmPageSelection = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const {organizationId, requestId, pageId} = request.data || {};
  if (!organizationId || !requestId || !pageId) {
    throw new HttpsError('invalid-argument', 'organizationId, requestId, and pageId are required.');
  }
  await requireOwnerOrActiveAdmin(uid, organizationId);

  const reqRef = db().collection('facebookConnectRequests').doc(requestId);
  const reqSnap = await reqRef.get();
  if (!reqSnap.exists) throw new HttpsError('not-found', 'This connection attempt is no longer valid.');
  const data = reqSnap.data();
  if (data.uid !== uid || data.organizationId !== organizationId) {
    throw new HttpsError('permission-denied', 'This connection attempt belongs to a different account.');
  }
  if (data.status !== 'pending_selection') {
    throw new HttpsError('failed-precondition', 'This connection attempt was already used or cancelled.');
  }
  if (data.expiresAt && data.expiresAt.toMillis() < Date.now()) {
    await reqRef.update({status: 'expired'});
    throw new HttpsError('deadline-exceeded', 'This connection attempt expired. Start connecting again.');
  }

  const cached = await readDynamicSecret(pendingPagesSecretId(requestId));
  if (!cached) throw new HttpsError('not-found', 'This connection attempt is no longer valid.');
  const tokensByPageId = JSON.parse(cached);
  const pageToken = tokensByPageId[pageId];
  if (!pageToken) {
    // Never trust a pageId the client invents — must be one of the exact
    // pages this account was actually offered.
    throw new HttpsError('permission-denied', 'That Page was not part of this connection attempt.');
  }

  const page = await graphFetch(`/${pageId}`, {params: {fields: 'id,name,username,picture', access_token: pageToken}});
  await finalizeConnection({
    organizationId,
    uid,
    actorEmail: request.auth.token.email,
    page: {...page, access_token: pageToken},
  });

  await reqRef.update({status: 'consumed'});
  await deleteDynamicSecret(pendingPagesSecretId(requestId));

  return {
    status: 'connected',
    page: {
      pageId: page.id,
      pageName: page.name,
      pageUsername: page.username || null,
      pagePictureUrl: page.picture && page.picture.data ? page.picture.data.url : null,
    },
  };
});

// ---- 3. Test connection -----------------------------------------------------
exports.facebookTestConnection = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const {organizationId} = request.data || {};
  await requireFacebookPublisher(uid, organizationId);

  const integrationRef = db().collection('organizations').doc(organizationId).collection('integrations').doc('facebook');
  const integrationSnap = await integrationRef.get();
  if (!integrationSnap.exists || integrationSnap.data().connectionStatus !== 'connected') {
    throw new HttpsError('failed-precondition', 'No Facebook Page is connected for this organization.');
  }
  const pageId = integrationSnap.data().pageId;
  const token = await readDynamicSecret(pageTokenSecretId(organizationId));
  if (!token) {
    await integrationRef.set({connectionStatus: 'error', updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    throw new HttpsError('failed-precondition', 'This Facebook connection needs attention. Reconnect the Page.');
  }

  try {
    await graphFetch(`/${pageId}`, {params: {fields: 'id,name', access_token: token}});
  } catch (e) {
    await integrationRef.set({connectionStatus: 'error', updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});
    throw e;
  }
  await integrationRef.set(
      {connectionStatus: 'connected', lastValidatedAt: admin.firestore.FieldValue.serverTimestamp()},
      {merge: true},
  );
  return {status: 'connected'};
});

// ---- 4. Disconnect -----------------------------------------------------------
//
// Chosen behavior (documented per the spec's explicit ask): disconnecting
// removes ONLY ResPAWnd's own stored copy of the Page token (Secret Manager
// secret deleted) and marks the connection disconnected in Firestore. It
// does NOT call Meta to revoke the underlying grant — Meta does not expose
// a Page-scoped token revocation endpoint usable this way; a full revoke
// requires the organization admin to remove the app via Facebook's own
// Business Settings / App Settings. This is a deliberate, narrower "stop
// ResPAWnd from being able to publish" action, not a full Meta-side revoke.
exports.facebookDisconnectPage = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const {organizationId} = request.data || {};
  await requireOwnerOrActiveAdmin(uid, organizationId);

  await deleteDynamicSecret(pageTokenSecretId(organizationId));
  await db()
      .collection('organizations')
      .doc(organizationId)
      .collection('integrations')
      .doc('facebook')
      .set({connectionStatus: 'disconnected', updatedAt: admin.firestore.FieldValue.serverTimestamp()}, {merge: true});

  await writeOrgAuditLog({
    action: 'Facebook Page disconnected',
    actorId: uid,
    actorEmail: request.auth.token.email,
    organizationId,
  });
  return {status: 'disconnected'};
});

// ---- 5. Publish Animal Records ----------------------------------------------
exports.facebookPublishAnimalRecords = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const {organizationId, animalRecordIds, message} = request.data || {};
  if (!organizationId || !Array.isArray(animalRecordIds) || animalRecordIds.length === 0) {
    throw new HttpsError('invalid-argument', 'organizationId and at least one animalRecordId are required.');
  }
  // Owner, active Admin, or a member granted facebookPublisher (Animal
  // Records viewing/managing itself stays open to every Member).
  await requireFacebookPublisher(uid, organizationId);

  const integrationSnap = await db()
      .collection('organizations').doc(organizationId).collection('integrations').doc('facebook').get();
  if (!integrationSnap.exists || integrationSnap.data().connectionStatus !== 'connected') {
    throw new HttpsError('failed-precondition', 'No Facebook Page is connected for this organization.');
  }
  const pageId = integrationSnap.data().pageId;
  const token = await readDynamicSecret(pageTokenSecretId(organizationId));
  if (!token) {
    throw new HttpsError('failed-precondition', 'This Facebook connection needs attention. Reconnect the Page.');
  }

  // Load + validate every selected Animal Record belongs to THIS
  // organization before publishing anything — never trust the client's
  // selection alone (an Admin from another organization must not be able
  // to publish this organization's animals just by knowing their IDs, and
  // this organization must not be able to publish another organization's
  // animals).
  const animalDocs = await Promise.all(
      animalRecordIds.map((id) => db().collection('animals').doc(id).get()),
  );
  const mediaFbids = [];
  const publishedAnimalIds = [];
  for (const snap of animalDocs) {
    if (!snap.exists) throw new HttpsError('not-found', `Animal record ${snap.id} not found.`);
    const animal = snap.data();
    // NOTE: `animals/{id}` documents in this codebase currently carry no
    // `organizationId` field anywhere (confirmed: no writer sets it, no
    // query filters by it) — Animal Records is effectively a single global
    // collection today, a pre-existing gap that predates and is outside
    // this Facebook publishing feature's scope to fix (it would require
    // retrofitting organizationId onto every animal record, every query,
    // and the Firestore rules — a separate, much larger migration). This
    // check only enforces isolation for records that DO carry the field
    // (forward-compatible with a future migration); it cannot reject
    // today's unscoped records without breaking publishing entirely for
    // every organization. See the final report's "Known limitation" note.
    if (animal.organizationId && animal.organizationId !== organizationId) {
      throw new HttpsError(
          'permission-denied',
          'One or more selected Animal Records do not belong to this organization.',
      );
    }
    const photoUrls = animal.photoUrls || animal.images || animal.imageUrls;
    const imageUrl = (Array.isArray(photoUrls) && photoUrls[0]) || animal.photoUrl || animal.imageUrl;
    if (!imageUrl) {
      throw new HttpsError('failed-precondition', `${animal.name || snap.id} has no image to publish.`);
    }
    const photo = await graphFetch(`/${pageId}/photos`, {
      method: 'POST',
      params: {url: imageUrl, published: 'false', access_token: token},
    });
    mediaFbids.push(photo.id);
    publishedAnimalIds.push(snap.id);
  }

  const feedPost = await graphFetch(`/${pageId}/feed`, {
    method: 'POST',
    params: {access_token: token},
    body: {
      message: message || '',
      attached_media: mediaFbids.map((id) => ({media_fbid: id})),
    },
  });

  const postId = feedPost.id;
  const postUrl = `https://www.facebook.com/${postId}`;

  const shareRef = db().collection('facebookShares').doc();
  await shareRef.set({
    organizationId,
    animalRecordIds: publishedAnimalIds,
    postId,
    postUrl,
    publishedBy: uid,
    publishedByEmail: request.auth.token.email || null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  for (const animalId of publishedAnimalIds) {
    await db().collection('animals').doc(animalId).collection('managementLogs').add({
      animalId,
      action: 'Published to Facebook Page',
      eventType: 'facebookPublished',
      actorId: uid,
      actorEmail: request.auth.token.email || null,
      organizationId,
      newValues: {postId, postUrl},
      sourceModule: 'AnimalRecords',
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  }

  return {postId, postUrl, animalRecordIds: publishedAnimalIds};
});

// ---- 6. Grant / revoke Facebook publishing to a member ----------------------
//
// Server-side so the grant stays owner/admin-only regardless of what the
// deployed Firestore rules allow on members docs. Only touches the
// facebookPublisher fields — the member's app role is left as-is.
exports.facebookSetPublisher = onCall(async (request) => {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Sign in required.');
  const uid = request.auth.uid;
  const {organizationId, memberUid, enabled} = request.data || {};
  if (!organizationId || !memberUid || typeof enabled !== 'boolean') {
    throw new HttpsError('invalid-argument', 'organizationId, memberUid, and enabled are required.');
  }
  await requireOwnerOrActiveAdmin(uid, organizationId);

  const memberRef = db().collection('organizations').doc(organizationId).collection('members').doc(memberUid);
  const memberSnap = await memberRef.get();
  if (!memberSnap.exists) {
    throw new HttpsError('not-found', 'That person is not a member of this organization.');
  }

  await memberRef.update({
    facebookPublisher: enabled,
    facebookPublisherGrantedBy: enabled ? uid : null,
    facebookPublisherGrantedAt: enabled ? admin.firestore.FieldValue.serverTimestamp() : null,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await writeOrgAuditLog({
    action: enabled ? 'Facebook sharing granted to member' : 'Facebook sharing revoked from member',
    actorId: uid,
    actorEmail: request.auth.token.email,
    organizationId,
    newValues: {memberUid, facebookPublisher: enabled},
  });
  return {facebookPublisher: enabled};
});
