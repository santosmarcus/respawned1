// Migration to the Admin + Staff permission model (functions/org_access.js).
//
// Two steps, run in this order (see HANDOFF.md for when):
//
//   --step=admins       Makes every account with users.role 'admin' and no
//                       organizationId an Admin member of --org, and links
//                       it (users.organizationId). Platform accounts no
//                       longer count as financial admins of every
//                       organization; this keeps the team's access through
//                       membership. users.role is left as it is. Also lists
//                       accounts linked to --org that have no members doc.
//
//   --step=permissions  Gives every Staff members doc an explicit
//                       `permissions` list: 'carer' → Staff with the default set;
//                       'staff' without a list → the default set (+ Facebook
//                       posting if facebookPublisher was set). Removes the
//                       old facebookPublisher fields, converts pending
//                       'carer' invitations, and writes one audit entry per
//                       changed member. Run it only once everyone has the
//                       app build that routes by permissions: older builds
//                       route by role == 'carer'.
//
// Usage (from functions/, with Application Default Credentials, e.g.
// GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key):
//   node scripts/migrate_member_permissions.js --project=respawnd1-45021 --org=ORG_ID --step=admins
//   node scripts/migrate_member_permissions.js --project=respawnd1-45021 --org=ORG_ID --step=admins --apply
//
// Dry run unless --apply is passed. Safe to run again: done records are
// skipped.

const admin = require('firebase-admin');
const {PRESETS, memberPermissions, presetFor} = require('../org_access');

const args = Object.fromEntries(
    process.argv.slice(2).map((a) => {
      const [k, v] = a.replace(/^--/, '').split('=');
      return [k, v === undefined ? true : v];
    }),
);
const APPLY = args.apply === true;
const ORG = typeof args.org === 'string' ? args.org : '';
const STEP = args.step;

if (!ORG || !['admins', 'permissions'].includes(STEP)) {
  console.error('Usage: --org=ORG_ID --step=admins|permissions [--project=ID] [--apply]');
  process.exit(1);
}

admin.initializeApp(args.project ? {projectId: args.project} : undefined);
const db = admin.firestore();
const {FieldValue} = admin.firestore;

const nameOf = (u) => `${u.firstName || ''} ${u.lastName || ''}`.trim() || u.name || u.email || '';

async function stepAdmins(orgRef) {
  const users = await db.collection('users').where('role', '==', 'admin').get();
  const unlinked = users.docs.filter((d) => !d.get('organizationId'));
  // Profiles with no sign-in account behind them (left over from deleted
  // logins) are skipped: nobody can use them.
  const todo = [];
  for (const d of unlinked) {
    try {
      await admin.auth().getUser(d.id);
      todo.push(d);
    } catch (e) {
      if (e.code !== 'auth/user-not-found') throw e;
      console.log(`  skipped ${d.id} ${d.get('email') || ''}: no sign-in account`);
    }
  }
  console.log(`users.role 'admin': ${users.size}; without an organization: ${unlinked.length}; to add: ${todo.length}`);
  const rows = [];
  for (const u of todo) {
    const memberRef = orgRef.collection('members').doc(u.id);
    const member = await memberRef.get();
    rows.push({uid: u.id, email: u.get('email') || '', name: nameOf(u.data()),
      member: member.exists ? `${member.get('role')} (kept)` : 'new Admin'});
    if (!APPLY) continue;
    const batch = db.batch();
    if (!member.exists) {
      const email = (u.get('email') || '').trim();
      batch.set(memberRef, {
        uid: u.id,
        organizationId: ORG,
        role: 'admin',
        status: 'active',
        ...(email ? {email, normalizedEmail: email.toLowerCase()} : {}),
        ...(nameOf(u.data()) ? {displayName: nameOf(u.data())} : {}),
        joinedAt: FieldValue.serverTimestamp(),
        addedBy: 'migration',
      });
    }
    batch.update(u.ref, {organizationId: ORG});
    batch.set(db.collection('auditLogs').doc(), {
      category: 'organizationStaff',
      action: 'Platform account added as Admin',
      actorId: null,
      actorName: 'Migration (migrate_member_permissions.js)',
      organizationId: ORG,
      targetType: 'Member',
      targetId: u.id,
      newValues: {role: 'admin', organizationId: ORG},
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
  console.table(rows);

  const linked = await db.collection('users').where('organizationId', '==', ORG).get();
  const members = await orgRef.collection('members').get();
  const ids = new Set(members.docs.map((m) => m.id));
  const missing = linked.docs.filter((d) => !ids.has(d.id) && !todo.some((t) => t.id === d.id));
  console.log(`Linked accounts with no members doc (treated as Full staff): ${missing.length}`);
  for (const m of missing) console.log(`  ${m.id} ${m.get('role') || ''} ${m.get('email') || ''}`);
}

async function stepPermissions(orgRef) {
  const members = await orgRef.collection('members').get();
  const rows = [];
  let changed = 0;
  for (const m of members.docs) {
    const d = m.data();
    const hasFb = ['facebookPublisher', 'facebookPublisherGrantedBy', 'facebookPublisherGrantedAt'].some((k) => k in d);
    if (d.role === 'admin') {
      const extra = 'permissions' in d || 'preset' in d || hasFb;
      rows.push({uid: m.id, before: 'admin', after: extra ? 'admin (clean up fields)' : 'admin (unchanged)'});
      if (extra && APPLY) {
        await m.ref.update({permissions: FieldValue.delete(), preset: FieldValue.delete(),
          facebookPublisher: FieldValue.delete(), facebookPublisherGrantedBy: FieldValue.delete(),
          facebookPublisherGrantedAt: FieldValue.delete()});
      }
      continue;
    }
    if (Array.isArray(d.permissions) && d.role === 'staff' && !hasFb) {
      rows.push({uid: m.id, before: `staff/${d.preset || presetFor(d.permissions)}`, after: '(already migrated)'});
      continue;
    }
    const perms = memberPermissions(d);
    const preset = presetFor(perms);
    rows.push({uid: m.id, before: `${d.role || '(none)'}${d.facebookPublisher ? ' +facebook' : ''}`,
      after: `staff/${preset}: ${perms.join(', ')}`});
    changed++;
    if (!APPLY) continue;
    const batch = db.batch();
    batch.update(m.ref, {
      role: 'staff',
      permissions: perms,
      preset,
      accessUpdatedBy: 'migration',
      accessUpdatedAt: FieldValue.serverTimestamp(),
      facebookPublisher: FieldValue.delete(),
      facebookPublisherGrantedBy: FieldValue.delete(),
      facebookPublisherGrantedAt: FieldValue.delete(),
    });
    batch.set(db.collection('auditLogs').doc(), {
      category: 'organizationStaff',
      action: 'Staff access changed',
      actorId: null,
      actorName: 'Migration (migrate_member_permissions.js)',
      organizationId: ORG,
      targetType: 'Member',
      targetId: m.id,
      oldValues: {role: d.role || null, facebookPublisher: d.facebookPublisher === true},
      newValues: {role: 'staff', preset, permissions: perms},
      createdAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }
  console.table(rows);

  const invitations = await db.collection('organizationInvitations')
      .where('organizationId', '==', ORG).where('status', '==', 'pending').get();
  const carerInvites = invitations.docs.filter((i) => i.get('role') === 'carer');
  console.log(`Pending 'carer' invitations to convert: ${carerInvites.length}`);
  if (APPLY) {
    for (const i of carerInvites) {
      await i.ref.update({role: 'staff', permissions: [...PRESETS.staff], preset: 'staff'});
    }
  }
  return changed;
}

async function main() {
  const orgRef = db.collection('organizations').doc(ORG);
  const org = await orgRef.get();
  if (!org.exists) throw new Error(`Organization ${ORG} not found.`);
  console.log(`Organization: ${org.get('name') || ORG} (owner ${org.get('ownerId') || '-'})`);
  if (STEP === 'admins') await stepAdmins(orgRef);
  else await stepPermissions(orgRef);
  console.log(APPLY ? '\nDone.' : '\nDry run. Pass --apply to write.');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
