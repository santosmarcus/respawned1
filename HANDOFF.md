# Handoff

_Latest: money taken out / "Where did this money go?" (2026-11-22, not deployed, not checked on a device). Before that, scheduled adoption posts to Facebook (2026-11-21, fixed up 2026-11-22; not deployed, not checked on a device). Before that, independent rescuers (2026-11-20, indexes, functions and rules deployed; app build pending, not checked on a device). Before that, animal QR tags fixed, with New Code and Remove (2026-11-20, app only, not checked on a device). Before that, one mobile number and one email per account (2026-11-20, not deployed, not checked on a device). Before that, one default Staff permission set, carers merged into Staff, volunteer naming (2026-11-20, functions and rules deployed; app build pending). Before that, user Events page and Facebook sharing for campaigns and events (2026-11-20, function deployed; app build pending). Before that, Facebook sharing and photo descriptions (2026-11-20, deployed). Before that, feedback round (2026-11-18, Firestore rules deployed; app build pending). Before that, Admin + Staff permissions (2026-11-18, committed and deployed; app build pending). Then the system admin console, one-organization scope and referral links (2026-11-17, committed and deployed). The build-fix sections further down are from branch `marcus` (base `a899293`), 2026-11-04._

## Money taken out: "Where did this money go?" (2026-11-22, not deployed, not checked on a device)

When money leaves the organization (a **PayMongo payout** to the bank, or someone **taking money out** of the bank, GCash or the cash box), the app asks the people who manage money which fund it came from and what it was for, and tells the rest of the finance team.

**What people see** (Donations, admin):
- **Pop-up** the first time someone with *Manage money* opens Donations while a cash-out has no fund: "₱5,000 was paid out from PayMongo on Nov 20. Choose which fund it came from…" → *Choose fund* / *Later*.
- **Yellow banner** above the Donations tabs until every cash-out is sorted out. Everyone who can see money sees it; those who can't manage money see "Someone who manages money needs to choose".
- **Where did this money go?** sheet: the amount, then one or more parts, each with *Which fund did it come from?* (General fund first, each with its available balance), *What was it for?* (the allocation categories), a short description and an amount. *Split into another fund* adds a part; a live "Left without a fund / All of it has a fund ✓" line. Saving part of it is allowed (the rest stays on the banner). *It was already recorded somewhere else* closes it with a note, for spending already entered as a general expense or allocation, so nothing is counted twice.
- Menu → **Record money taken out** (Manage money): amount, taken from (PayMongo payout / Bank / GCash / Cash on hand / Other), date, note, and the same fund parts, or *I'll decide later*.
- Menu → **Money taken out** (View or Manage money): the history with status (Needs a fund, Partly assigned, Assigned, Already recorded) and who assigned what.

**What it records.** Each part becomes an ordinary spending record on that fund (`campaigns/{id}/allocations`, kind `expense`, with `cashOutId`), so fund balances, Fund Tracking, reports and analytics include it. A fund can't go below zero; a cash-out can't be assigned more than its amount.

**Notifications** (`notifyCashOut`, push + in-app, type `cash_out_needs_assignment` / `cash_out_assigned`): everyone with *View money* or *Manage money* (Admins included) when a cash-out needs a fund and when someone assigns it or marks it recorded, except the person who just did it. Tapping opens Money taken out with that cash-out's sheet.

**Access** (same as the rest of the money): reading needs `financeView` or `financeManage`; recording, assigning and settling need `financeManage` (checked in the functions; the app hides the buttons). `organizations/{orgId}/cashOuts` has no client writes.

**Backend**
- `functions/campaigns.js`: `recordCashOut`, `assignCashOut`, `settleCashOut` (transactions; idempotent by request id; audit log entries, category `expenses`).
- `functions/paymongo.js`: the webhook now handles **`payout.paid`** and records a cash-out (doc id = payout id, so repeats are ignored). Fields are read defensively (`net_amount` or `amount` in centavos, `paid_at`/`created_at`, destination bank if present) because PayMongo's payout docs couldn't be checked from here; check one real payout event against `cash_out_rules.js payoutFromPaymongo`. The payout is assigned to the only approved organization; with more than one, it's only logged and staff record it by hand.
- `functions/cash_out_rules.js` (+ `cash_out_rules_test.js`): validation, the split plan, payout parsing, notification text.
- `functions/index.js`: `notifyCashOut` trigger; `notifyStaff` also keeps `cashOutId`.
- `firestore.rules`: `organizations/{orgId}/cashOuts` read for `financeView`/`financeManage`, no writes; added to the subcollection catch-all's exclusions.

**App:** `lib/core/models/donation/cash_out.dart`, `lib/features/admin/donation/cash_out_sheets.dart`, providers `cashOutsProvider`/`openCashOutsProvider`, service calls, Donations home (banner, pop-up, menu), notification routing.

### Deploy, in this order

1. Rules: `firebase deploy --only firestore:rules` (adds read access only).
2. Functions, by name: `FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions:recordCashOut,functions:assignCashOut,functions:settleCashOut,functions:notifyCashOut,functions:paymongoWebhook`.
3. PayMongo dashboard → Developers → Webhooks: add **`payout.paid`** to the existing webhook's events (same URL and secret).
4. App build.

### Checks run

- `functions/`: `npm test` 139 pass (6 new). `rules-tests`: 210 pass, including the new cash-out test (run with `firebase emulators:exec … "node --test --test-concurrency=1 tests/*.test.js"`; the package script's `tests/` folder argument fails on Node 22).
- App (Flutter 3.50.1): `flutter analyze` 0 errors. `flutter test`: 309 pass; the same 4 Google Fonts widget-test failures as before. New: `test/core/models/cash_out_test.dart` (5 pass).
- Not run: a real PayMongo payout event; the sheets on a device.

### Check on a device

As a Treasurer, Record money taken out ₱1,000 from Cash on hand, split ₱600 General fund (Food) + ₱400 a campaign (Transport): both funds' Fund Tracking show the spending, and an Admin gets "₱1,000 taken out and assigned". Record another with *I'll decide later*: the Admin gets "Where did this money go?", opening Donations shows the pop-up and banner, and assigning it clears both. A Full staff member (view only) sees the banner and history but no buttons; a Rescue-only member sees nothing.

## Scheduled adoption posts to Facebook (2026-11-21, fixed up 2026-11-22; not deployed, not checked on a device)

Adoption listings get shared to the organization's Facebook Page on a schedule the organization sets. **The Admin sets the schedule; the whole organization is reminded.** Nothing posts automatically: when a post is due, every active member (owner, Admins, all Staff) gets a reminder with suggested animals, and a member with the Share to Facebook permission reviews and posts it.

**Schedule (Admin).** Organization Profile → Facebook Page Integration → *Set/Edit Post Schedule*, or *Edit* on the Promote Adoptions screen:
- Scheduled reminders: every 1, 2 or 4 weeks, on a weekday, at an hour (Philippine time), N animals per post (1–6).
- Smart suggestions (separate switch): a nudge between reminders when an animal open for adoption has **never been shared**, or **2+ animals** listed 14+ days with no open application haven't been shared in 30+ days. Sent at the schedule's hour, at most every 3 days, not within 3 days of a post, nor within 2 days of the next scheduled reminder.
- A post made in the half-interval before a slot (3.5 days for weekly) counts for that slot: no reminder.
- Missed slots (job down) collapse into one reminder.

**Reminder.** Push + in-app notification `adoption_promotion_due` to every active member (`orgStaffUids(orgId)`: owner, Admins, all Staff, linked accounts). Tapping opens **Promote Adoptions**: members with `facebookPublish` get the suggested animals ticked; others see the schedule and a note that posting needs that permission. If the Page isn't connected, the slot passes silently.

**Promote Adoptions screen** (`lib/features/admin/animals/promote_adoptions_page.dart`; admin drawer → Promote Adoptions for every active member; also from the Facebook section): the schedule (everyone; only Admins can edit), then, for members with Share to Facebook, every animal open for adoption (adoptable, not archived/deceased/hidden, with a photo), most in need first (never shared → no applicants → longest since shared → longest listed), with the reason. Tick up to 10, edit the caption (draft follows the selection until edited), **Post** → the existing `facebookPublishAnimalRecords`.

**Backend** (`functions/adoption_promotion.js`, rules in `functions/adoption_promotion_rules.js` + tests):
- `facebookSaveAdoptionPromotion` (callable, Admin only): validates and stores the schedule at `organizations/{orgId}/integrations/facebookPromotion` with the next slot (`nextDueAt`); audit log entry with old and new values. The existing rules already cover the doc (members read, no client writes), so **no rules change**.
- `facebookAdoptionPromotionSuggestions` (callable, `facebookPublish`): ranked animals, suggested ids, draft caption. Callable because `facebookShares` is closed to clients.
- `remindAdoptionPromotions` (scheduled, minute 5 of every hour, Asia/Manila): per approved organization with a schedule doc.
- `facebookPublishAnimalRecords` now also stamps `lastPostedAt`/`lastPostUrl`/`lastPostAnimalIds` on the schedule doc (best effort).
- `notifyStaff` (index.js) now also keeps `organizationId` and `animalIds` on the in-app notification when given.

**Posting** uses the current `facebookPublishAnimalRecords` items API: one photo per animal (its first) plus the caption. Facebook campaign/event posts (`facebookPublishRecordPost`) don't count as adoption posts.

**Merge fix (2026-11-22):** commit `0c9cacb` brought these files in by hand. It overwrote `lib/core/repos/facebook_integration_repository.dart` with a copy of `functions/index.js` (1,600+ analyzer errors), replaced the newer `functions/facebook.js` (per-photo captions, link posts, Secret Manager errors) with an older copy, added a second unused copy of the schedule sheet, and left out the drawer entry, provider, push routing and Facebook section. All fixed in the following commit; `functions/facebook.js` is the team's version plus the `lastPostedAt` stamp.

### Deploy

1. Functions, by name (a plain `--only functions` would delete the two functions that aren't in the repo; see below): `FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions:facebookSaveAdoptionPromotion,functions:facebookAdoptionPromotionSuggestions,functions:remindAdoptionPromotions,functions:facebookPublishAnimalRecords`. Safe for older builds (they never call the new callables). Other functions pick up the `notifyStaff` change at their next deploy; nothing depends on it.
2. App build.

### Checks run

- `functions/`: `npm test` 133 pass (9 new in `adoption_promotion_rules_test.js`); `index.js` loads and exports the new functions.
- App (Flutter 3.50.1): `flutter analyze` 0 errors (1 warning, unused `_FundTrackingPanel` in donation_detail.dart, not from this work). `flutter test`: 304 pass, 4 fail (`admin_shared_widgets_test.dart` x2, `rescue_closed_tab_test.dart`, `member_access_editor_test.dart`) with "An animation is still running even after the widget tree was disposed" from Google Fonts' system-font relayout; the same 4 fail on `0c9cacb^`, so they're unrelated. New: `test/core/models/adoption_promotion_schedule_test.dart` (6 pass).

### Check on a device

As an Admin, set a weekly schedule for the next hour with smart suggestions on; at that hour, every member gets the reminder. A Staff member with Share to Facebook taps it, sees the suggested animals ticked, posts; the schedule shows the last post, and the next reminder moves a week ahead. A Staff member without the permission also gets the reminder; Promote Adoptions shows them the schedule and that posting needs the permission, and they can't edit the schedule.

## Independent rescuers (2026-11-20, indexes, functions and rules deployed; app build pending, not checked on a device)

One person or a small team who rescues like a small organization. They are an `organizations/{id}` doc with `kind: 'independent'`, so cases, animal records, members and rules work as they do for shelters, with these limits. Picks up the volunteer work that was deferred.

- **Sign-up:** **Independent Rescuer** on Select User Type. It saves `role: organization` + `signupKind: independent` and runs the same About → documents → review steps, worded for a person:
  - **Name and area:** a name, plus a general area (barangay, city) that is shown on the profile.
  - **Home pin (private):** saved in `organizations/{id}/settings/home`, readable by the team only. The public coverage circle is centred on the pin rounded to about 1 km, 3 km by default.
  - **Documents:** valid ID, proof of address, rescue history or references, and an optional barangay clearance.
  - **Review:** system admins approve or reject it in Approvals, where the card shows "Type: Independent rescuer".
- **Modules:** `functions/org_permissions.json` `independent`, mirrored in `IndependentRescuer` (`org_permission.dart`) and in `independentPerms()`/`independentDefaultPerms()` in firestore.rules.
  - **Defaults:** rescue, animals, care.
  - **Optional:** adoptions and insights, which a system admin turns on in Approvals → Approved → **Modules & limits** (`setIndependentLimits`).
  - **Never:** campaigns, donations/finance, volunteers/events and Facebook posting.
  - **Owner included:** nobody in the org gets more than what it has (`orgEnabledPermissions` in the app and `org_access.js`, `orgPermsOf` in rules).
  - **Member editor:** shows only the org's modules.
- **Limits:** team of 5, 3 active cases, 5 animals in care (a system admin can change each).
  - **Counters:** `memberCount`, `activeCaseCount`, `animalsInCareCount` and `lastActiveAt` are kept by `functions/independent_rescuers.js`. Clients can't write them, nor `kind`, `enabledPermissions` or the caps.
  - **Team cap:** rules refuse invitations and joins once the team is full.
  - **Available/Paused:** the existing `acceptingCases` switch.
- **Getting cases:**
  - **Head start:** `assignCaseToServiceAreas` now tags shelters only (`areaOrgIds`). It also writes `nearbyIndependentIds` (approved, available, under-capacity independents covering the point, radius clamped to 1–5 km) and `independentsOpenAt`, which is 15 minutes after the report, or at once for Critical.
  - **Notifications:** independents get no instant "nearby responder" push. `openCasesToIndependents` (every minute) tells them when a case opens and nobody has taken it.
  - **Their list:** only their own cases, cases referred to them, and unowned cases opened to them (`watchScopedCaseDocs`).
  - **Shelters:** their view is unchanged.
- **First accept wins:**
  - **App:** `acceptCase` is now a transaction. It throws `CaseClaimException` ("An organization already accepted this case", head start, outside area, at capacity, paused), and Rescue Details shows it and leaves.
  - **Rules:** `claimOk()` stops anyone re-stamping a case another org owns. This also fixes the last-write-wins race between two shelters.
  - **Independents:** rules let them work an unowned case only once it opened to them (`poolCaseOpenToMe`).
- **Referrals:** Refer → **Rescue Volunteer** is live. It lists independents covering the case with their room left; paused or full ones are shown but greyed out. It goes through `referToOrganization` with type `rescueVolunteer`, so accept/decline and the 24 h/48 h follow-ups are unchanged. Accepting checks capacity in the transaction. Independents can refer a case on to a **Shelter or Rescue Group** even while `multiOrganizationEnabled` is off. New flag: `FeatureFlags.independentRescuersEnabled` (on).
- **Transport:**
  - **I'll Bring It Myself:** shown on Assign Transport as soon as the clinic is saved (`startOrganizationTransport(byChoice: true)`).
  - **Switch to a Transporter:** Rescue Details offers it mid-trip (`stopOrganizationTransport`), which sends the case back to Awaiting Assignment.
  - **Transporter trips end at the clinic:** accepting stamps `ownerKind: 'independent'`, and `statusAfterTreatmentAccepted` then ends the trip there, because the rescuer collects the animal.
- **Adoption:** the shelter flow, made lighter:
  - **Interview optional:** a pending application has **Accept Without Interview**.
  - **No stall withdrawals:** `followUpStalledApplications` skips independents' applications.
  - **Returns:** approving one while at the animal limit warns the rescuer to transfer an animal on.
  - **Public label:** the public animal page reads "Independent rescuer · name" (`syncPublicAnimal` adds `ownerKind`/`ownerName`).
  - **Track Case:** shows "Handled by an independent rescuer".
- **Dashboard:** `IndependentAreaCard` on Today, a new widget rather than one extracted from `explore_reports_map.dart`:
  - **Map:** the coverage circle, open cases in it, their own cases, nearby shelters and the home pin.
  - **Controls:** a radius slider (1–5 km), the Available switch, and room left.
  - **Left out:** other orgs' cases and reporter details.
  - **Profile:** for independents it hides the shelter pin, city service areas and Facebook.
- **Accountability:**
  - **Weekly check-in:** "Animals in your care" push (`weeklyIndependentCheckIn`, Monday 9:00).
  - **Auto-pause:** after 30 days with no activity and no open cases.
  - **Deletion:** account deletion is refused while the rescuer holds cases or animals.
  - **Users directory:** shows "Independent rescuer · 1/3 cases · 2/5 animals".
- **Rescue Volunteer accounts** stay transporters (no case ownership) and now verify with the same ID/vehicle documents as pet transporters. `isVerifiedResponder()`, `transitBlockReason` and `staffTransporterReview` accept `isVerified` for them, and an older approved volunteer application still counts. This closes the "nothing creates one now" gap noted below.
- **Not done:**
  - **Rules don't enforce the head start on reads.** They check the case lists the rescuer, but the 15 minutes is checked on accept, not on read: a listed independent could open a case early with a direct link, though not take it.
  - **Storage not capped:** storage.rules doesn't cap independents' modules. Photos only; Firestore refuses the records.
  - **No expense log:** independents have none (finance is off for them).
  - **No partner clinics on the map:** there's no saved list of partner clinics.

### Deploy, in this order
1. `firebase deploy --only firestore:indexes` (three new `cases` indexes: the head-start job and the independents' pool queries).
2. Functions:
   - **New:** `setIndependentLimits`, `syncIndependentMemberCount`, `syncIndependentCaseCount`, `syncIndependentAnimalCount`, `openCasesToIndependents`, `weeklyIndependentCheckIn`.
   - **Changed:** `notifyNewCaseReported`, `setMemberAccess` (and every callable using `org_access.js`), `followUpStalledApplications`, `syncPublicAnimal`, `deleteMyAccount`, `adminDeleteUser`.
   - `FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions`.
3. App build.
4. `firebase deploy --only firestore:rules`. This only adds access for existing builds, apart from `claimOk`, which older builds never trip, because they accept unowned cases only.

**Deployed 2026-11-20 (commit `335b3b5`, rebased on `0873df0` pet matching):** `firestore:indexes`, all 102 functions (8 created: the six above, `scorePetAlertMatches` from the pet-matching commits, and `checkSignUpPhone`; some updates hit the per-minute quota and went through on the CLI's retry), then `firestore:rules`.
- **Side effect:** these rules include the phone rule from "One mobile number, one email per account" below, which was meant to wait for the new app build: older builds that save a typed number at onboarding are now refused. Ship the app build soon, or relax that rule until then.

### Checks run
- `flutter analyze lib`: the 17 issues already there, none in changed files.
- `flutter test`: 287 pass (new: `test/core/models/rescue/case_claim_rules_test.dart`, more in `org_permission_test.dart` and `transit_rules_test.dart`).
- `functions`: `npm test` 104 pass (new: `independent_rescuer_rules.test.js`; independent lists added to `org_permissions_sync.test.js`).
- `rules-tests`: 198 pass with JDK 21 (new: `tests/independent-rescuers.test.js`, 10 tests). Run on ports 8188/9299 because emulators from an interrupted run still held 8080/9199 on this machine.

### Check on a device
- **Sign-up:** Independent Rescuer → name, area, home pin, documents → Submit. As a system admin, approve it, then Modules & limits → turn on Adoptions.
- **Head start:** a non-critical report inside the rescuer's circle. The shelter sees it at once; the rescuer sees it after 15 minutes with a "New case near you" push. A Critical report shows to both at once.
- **Race:** shelter and rescuer tap Accept together. One gets it, and the other sees "already accepted" and is sent back.
- **Self-transport:** rescuer accepts → saves a clinic → I'll Bring It Myself → Arrived — Start Treatment. On another case, Switch to a Transporter mid-trip.
- **Referral:** a shelter refers a case to a full rescuer (3 active cases): the rescuer is greyed out. Refer to one with room, who accepts.
- **Dashboard:** the map shows the circle and pins; the radius slider saves; Paused hides new cases.

## Animal QR tags: Show/Add fixed, New Code and Remove (2026-11-20, app only, not checked on a device)

- **Cause:** Animal record → Management → **Show QR Tag** / **Add QR Tag** stayed on a dimmed screen on every build. The QR was shown in an `AlertDialog`, which sizes itself from its content's intrinsic width, and `QrImageView` (qr_flutter 4.1.0) is a `LayoutBuilder`, which can't report one. Layout threw "LayoutBuilder does not support returning intrinsic dimensions", and in release builds only the dialog's barrier was painted. Add QR's write was saved; only the dialog failed. Firestore rules, the scanner and the CameraX/ML Kit bump in `android/app/build.gradle.kts` weren't involved.
- **Fix** (`lib/features/admin/animals/widgets/animal_management_tab.dart`): the QR sits in a fixed 220×220 box inside a new `_QrTagDialog`. Saving shows "Saving QR tag…" on the tile, with a 20 s timeout and clear messages for no connection, permission denied and other errors, instead of a silent wait.
- **New Code / Remove** (in the QR dialog, each behind a confirmation): `AnimalRecordRepository.regenerateQrTag` writes a new random code and `removeQrTag` deletes `qrTagId`. Both log the old code in View Logs (`qrRegenerated` / `qrRemoved`, `previousValues.qrTagId`). Scans resolve by `qrTagId` (`animal_tag_scan.dart`) and `syncPublicAnimal` replaces the public copy, so tags already printed with the old code show "No animal record uses this QR tag". The confirmations say so and tell staff to reprint. Same people as Add QR (records staff of the owning organization); no rules change. Collar tags (`users/{uid}/collarTags`) are separate and unchanged.

### Deploy
- App build only.

### Checks run
- `flutter analyze` on the changed files: no issues.
- A throwaway widget test (not kept) reproduced the LayoutBuilder exception with the old layout; the sized version rendered.
- `rules-tests`: 188/188 with JDK 21 (1 new: "the owning organization's records staff add, replace and remove QR tags").

### Check on a device
- Animal without a tag → Add QR Tag: the QR and code show at once; the tile then reads Show QR Tag.
- Show QR Tag → New Code → Replace Code: a new code shows; scanning the old printout says "No animal record uses this QR tag"; the new one opens the animal.
- Show QR Tag → Remove → Remove Code: "QR tag removed." and the tile reads Add QR Tag. View Logs lists all three events.
- Airplane mode → Add QR Tag: after 20 s, the connection message shows instead of a dimmed screen.

## One mobile number, one email per account (2026-11-20, not deployed, not checked on a device)

- **Email:** Firebase Auth already keeps an email on one account (sign-up fails with "email already in use"; Google sign-in with the same email joins the same account while Authentication → Settings → *User account linking* stays on "Link accounts that use the same email").
- **Phone sign-ups add an email:** Your Details also asks phone sign-ups for an email and password and adds them to the account (`AuthService.addEmailSignIn` → `linkWithCredential`), then shows the confirm-email screen until the link is opened. An email another account uses is refused ("This email already has a ResPAWnd account…"). Every new account can then sign in with either its email or its number.
- **Existing phone accounts:** Profile → Email Address → Update opens **Add Email Address** (email + password, same check), and the row shows "(not confirmed)" until the link is opened. The app-wide confirm-email gate (`AuthService.needsEmailVerification`) no longer holds accounts that also sign in with a verified number, so a mistyped address can be corrected there instead of locking the person out; Your Details still waits for new phone sign-ups to confirm.
- **Mobile number:** the number typed in **Your Details** used to be saved without checking, so the same person could sign up by email and later sign in with that number and get a second account. Now:
  - Your Details sends an SMS code and adds the verified number to the account (`AuthService.addVerifiedPhone` → `updatePhoneNumber`). Signing in with that number later opens the same account. A number another account already has is refused: "This number already has a ResPAWnd account. Log out and sign in with your number instead…". After phone sign-in the number is filled in and locked.
  - Profile → Update Mobile Number uses the same code check (`lib/core/widgets/phone_verification_sheet.dart`); phone sign-in accounts change the number they sign in with.
  - Older profiles list numbers nobody verified. `checkSignUpPhone` (`functions/phone_accounts.js`) runs after a new sign-up verifies a number: if a finished account already lists it, a phone-only sign-up is removed (it has no data yet) and an email/Google sign-up loses the number; the message names that account's masked email (e.g. `ma***@gmail.com`) so the person signs in there. Existing accounts keep a number they verify.
  - firestore.rules: a profile's `phone` can only be set to the number verified on the account (`request.auth.token.phone_number`) or emptied. Existing values stay until changed.

### Deploy, in this order
1. `firebase deploy --only functions:checkSignUpPhone`
2. Ship the app build.
3. `firebase deploy --only firestore:rules`, only once people have the new build: older builds save the typed number at onboarding, which the new rule refuses.

### Checks run
- `functions`: `npm test` 94/94 (6 new in `phone_account_rules.test.js`).
- `rules-tests`: 187/187 with JDK 21 (3 new under "one mobile number, one account").
- `flutter analyze` on the changed files: no issues.

### Check on a device
- Email sign-up → Your Details → number → code → finish. Log out, sign in with that number: the same account opens.
- Second email sign-up with the same number: refused at the code step.
- Phone sign-up → Your Details asks email and password → confirm the link → finish. Log out, sign in with that email and password: the same account opens. An email already in use is refused.
- Existing phone-only account → Profile → Email Address → Update → add email and password: the row shows "(not confirmed)" until the link is opened; then email sign-in opens the same account.
- Phone sign-in with a number an older account lists (unverified): told to sign in with `xx***@…`, and no new account is left behind.
- Profile → Update Mobile Number with a number another account has: refused; with a new number: saved.

## One default Staff set, carers merged into Staff, volunteer naming (2026-11-20, functions and rules deployed, not checked on a device)

- **Presets removed.** `functions/org_permissions.json` has one set, `staff`: rescue, animals, care, adoptions, volunteers, insights. Campaigns, View donations & funds, Manage money and Post to Facebook are never in it; an Admin ticks them per person. The member editor (`member_access_editor.dart`) shows "Default staff permissions" / "Custom permissions" with **Reset to default** instead of the preset dropdown. Titles read "Staff" or "Staff · Custom access" (`staffTitle`).
- **Carers merged into Staff.** Legacy `role: 'carer'` and legacy Staff without a `permissions` list both get the default set (app, `functions/org_access.js`, `firestore.rules`/`storage.rules` `defaultStaffPerms()` + `permsOf`). Any member with daily care (the default) gets **Care Tasks** in the admin drawer, which opens the care-tasks screen (`CarerHomeScreen(fromAdminShell: true)`, back button instead of Log out). Staff whose *only* box is daily care still land on that screen as their home.
- **Volunteers.** Home screen's **Volunteer** card is gone; **Events** stays (no application banner). Signing up for an event = event volunteer (admin event detail: "Event volunteers"; dashboard report "Event volunteers"). Admin **Volunteers** is now **Rescue Volunteers** (external `rescue_volunteer` accounts; applications page "Rescue Volunteer Applications"; system admin directory group "Rescue volunteers"). The general volunteer application form and its banner (`volunteer_application_screen.dart`) were **removed**; rescue volunteers sign up as their own account type. The admin review page (`volunteer_applications_page.dart`) and the model/repository stay for existing applications. **Open:** rescue volunteers still need an approved `volunteerApplications/{uid}` to take transits and read full reports (`transitBlockReason`, `isVerifiedResponder()` in firestore.rules), and nothing creates one now (nothing did for them before either, since they never saw the form). `rescue_volunteer` is self-selectable at sign-up, so the gate should stay until staff have another way to approve them.
- **Access change for existing members:** members without an explicit list (the `--step=permissions` migration hasn't run) lose campaigns and View donations once the rules are live; former carers gain the default set. Members with an explicit list keep it. Before deploying the rules, an Admin should open each person who handles money in Staff Members and tick their money permissions (that writes an explicit list through `setMemberAccess`).
- **To deploy, in order:** `firebase deploy --only functions` (org_access is shared by every callable that checks access), the app build, money boxes ticked for the people who need them, then `firebase deploy --only firestore:rules,storage`. `functions/scripts/migrate_member_permissions.js --step=permissions` now writes the default set for both staff and carers.

**Deployed 2026-11-20 (commit `cd5c0df`):** all 91 live functions by name (88 on the first run; `completeDueQuarantines`, `evaluateCampaignDeadlines`, `followUpStalledApplications` hit the per-minute quota and went through on a retry), then `firestore:rules` and `storage`. The members check before the rules was skipped: there are no local Google credentials for `migrate_member_permissions.js`, so which non-Admin Staff lost money access wasn't listed; an Admin ticks it back in Staff Members. App build not installed anywhere yet.
- `syncActiveSponsorCount` and `recountActiveSponsors` (the unlisted functions noted below) are no longer on the project. `deleteMyAccount`, `adminDeleteUser`, `adminSetUserDisabled` (in `functions/index.js` since `f157dff`) had never been deployed, so Delete account and the system admin's disable/remove buttons failed; **created 2026-11-20** by name (not tried from the app yet).

**Checks:** `flutter analyze` (pre-existing issues only), `flutter test` 280 pass, functions `npm test` 88 pass, `rules-tests` 184 pass (fixtures: `staffA`/`staffB` now have money ticked, `carerA` is care-only Staff, new `legacyStaffA`/`legacyCarerA` for the fallback).

## User Events page, campaign and event Facebook sharing (2026-11-20, function deployed, not checked on a device)

- **Events (Home → Events):** the event detail page now follows the live event (spots left, cancellation, removed) and checks the viewer's own sign-up when opened from anywhere (organization profile, Favorites), so it shows **View E-Ticket** instead of offering a second sign-up. The sign-up form fills name, email and mobile from the profile (`UserAutofill`), validates email and PH mobile, and names the event. The list's filter button works (Saved only, Hide full), has pull-to-refresh, a "You're going" label and a **Past events you joined** section. Favorites → Volunteer lists saved events (`VolunteerEventRepository.loadMyFavoriteEvents`).
- **Share to Facebook for campaigns and events:** admin campaign detail → **Share to Facebook** chip (not drafts or archived); admin event detail → Facebook icon in the app bar (not cancelled). Both open `lib/features/admin/facebook/facebook_record_post_page.dart`: editable suggested text (`record_post_text.dart`), optional cover photo, **Post to <Page>** or **Share…** (share sheet, text copied).
- **New callable `facebookPublishRecordPost`** (`functions/facebook.js`, checks in `facebook_share_rules.js`): `{organizationId, kind: 'campaign'|'event', recordId, message, includePhoto}`. Same publisher check as animals; the record must belong to the organization; refuses draft/archived campaigns and cancelled events; the photo is the record's own `imageUrl`. Logged to `facebookShares` (`recordKind`, `recordId`) and `auditLogs`. No rules change.
- **Deployed 2026-11-20:** `firebase deploy --only functions:facebookPublishRecordPost` (the first try returned 409 while the function was still being created; the second updated it). App build not installed anywhere yet.

**Checks:** `flutter analyze` (pre-existing issues only), new `test/features/admin/record_post_text_test.dart` (5 pass), functions `facebook_share.test.js` 10 pass.

## Facebook sharing and photo descriptions (2026-11-20, functions + hosting deployed, not checked on a device)

- **Facebook re-enabled:** `flutter_facebook_auth` 7.3.3 is back in pubspec; Organization Profile → Facebook Page Integration → Connect works again (classic login, `pages_*` permissions; Limited Login on iOS can't post to Pages). App ID `1764224901694464` (same as the `FB_APP_ID` secret) is in `lib/core/constants/facebook_config.dart`, `strings.xml` and `Info.plist`. **The client token is still a placeholder** in `android/app/src/main/res/values/strings.xml` and `ios/Runner/Info.plist` (Meta dashboard → App settings → Advanced → Client token).
- **Share to Facebook** (`lib/features/admin/animals/facebook_share_page.dart`): Animal Records → long-press to select (up to 10) → Facebook icon, or Management tab → Share to Facebook. Pick which details go in the text (`ShareField`, `lib/core/utils/facebook_post_composer.dart`), which photos to attach (up to 20) and each photo's description, opening/closing lines, and whether to add each animal's profile link. **Post to <Page>** (owner/Admin or `facebookPublish`; confirm dialog) or **Share…** (system share sheet; the text is copied because Facebook drops pre-filled text).
- `facebookPublishAnimalRecords` now takes `items: [{animalId, photos: [{url, caption}]}]` and `link`; each photo must be one of that record's own photos, captions go on the Facebook photos. Older builds sending `animalRecordIds` still post each record's first photo. Checks in `functions/facebook_share_rules.js`.
- **Public animal page** `/animal/<id>` (`functions/public_animal_page.js`, HTML in `public_animal_page_rules.js`, Hosting rewrite in firebase.json): server-rendered from `publicAnimals` only, with og: tags for the Facebook preview, photo captions, facts, health summary, organization contacts, and **Open in the ResPAWnd app** (`respawnd://open/animal/<id>`; Android intent URL falls back to the page). Archived/hidden/deceased animals show "Profile not available".
- **In the app:** the `respawnd://open/...` scheme is registered (AndroidManifest, Info.plist); `MaterialApp.onGenerateRoute` → `AnimalLinkPage` (staff of the owning org get the full record, others the public profile, signed-out users a sign-in prompt).
- **Photo descriptions:** `animals.photoCaptions: [{url, caption}]` (`lib/core/models/photo_captions.dart`), edited by tapping a photo in Create/Edit Animal Record, copied to `publicAnimals` for public photos, shown in the photo gallery (inline and fullscreen), on the web page and on Facebook photos. No rules change needed.

**Deployed 2026-11-20:** the three functions below (by name) and Hosting; `/animal/<made-up id>` returns the not-found page (a real animal's page not checked: no local credentials to look one up). App build not installed anywhere yet.

**How it was deployed:** `firebase deploy --only functions:publicAnimalPage,functions:facebookPublishAnimalRecords,functions:syncPublicAnimal` (by name, see the note on unlisted functions below), then `firebase deploy --only hosting`. Existing `publicAnimals` copies gain captions the next time each animal is saved (or rerun `functions/scripts/backfill_public_animals.js`). Posting to a Page needs the Meta app live with `pages_manage_posts` approved, or the posting account added as a tester/developer while it's in development mode.

**Checks:** `flutter analyze` (pre-existing issues only), `flutter test` 275 pass (new `facebook_post_composer_test.dart`), functions `npm test` 85 pass (new `facebook_share.test.js`).

## Feedback round: view-only modules, account page, transport flow (2026-11-18, rules deployed, not checked on a device)

- **Access:** every module shows for every Staff member outside the care-tasks screen; without the permission it is **view only** (drawer tag, banner, no action bar/menus/create buttons). `firestore.rules` `readKeys()` (= `opsKeys()`) now gates reads of cases, animals and medical records, adoptions, events, volunteer/transporter applications, transport assignments, logs, audit log and analytics; writes keep their own permission. Money (donor records, payments, expenses, transfers, general expenses) is unchanged. Carers still can't read the unowned pool. Storage rules unchanged (transporter IDs and adoption documents stay with `volunteers`/`adoptions`).
- **Presets:** Rescue coordinator + Adoptions officer are now one preset, **Rescue & adoptions** (`rescueAdoptions`: rescue, animals, care, adoptions, insights). Members saved with the old names match by permissions, so they show as Custom. Picking **Custom** clears every box.
- **Dashboard loading for Staff:** Riverpod 3 retried refused queries and reported them as loading; `appProviderRetry` (main.dart) no longer retries `permission-denied`, and the dashboard treats errors as settled.
- **Drawer:** Members section (Team for Admins, Volunteers, Transporters); **Account** next to Log out: details, Switch account (accounts used on this device, `known_accounts.dart`, `shared_preferences`), Delete account. Carers get Account and a labelled Log out.
- **Rescue pages:** the bottom-left "more" button moved to the app bar (top right) on Rescue Details, Track Case, Treatment and Intake. Intake: transporter card has its own menu (Reassign Transporter) and Transport Tracking under Call; the bar keeps only Confirm Animal Received. Transporter card is full width everywhere.
- **Assign Transport:** no popup. One inline panel: live timer, Send to Another Transporter, Cancel Offer; a declined/expired offer offers Retry <name> or Choose Another; acceptance opens tracking.
- **Track Case:** the map follows the sheet (no empty band when it slides down); the animal's photo is its map pin and sits on the status card.
- **Create Animal Record from a case:** description starts empty; every case photo is prefilled (removable).

**Deployed 2026-11-18:** `firebase deploy --only firestore:rules` to respawnd1-45021 (only widens reads; safe for older builds; the four compiler warnings are pre-existing). **Not done:** the app build. Checks: `flutter analyze` (pre-existing issues only), `flutter test` 242 pass, functions 78 pass, rules-tests 181 pass.

## Admin + Staff permissions (2026-11-18, deployed, not checked on a device)

**Deployed 2026-11-18:** migration `--step=admins --apply` (Marcus Gabriel Santos, test123@gmail.com and Gabrielle are now Admin members of Respawnd Test Org; the orphaned `PsncBNL0…` profile was skipped), all 88 functions (`setMemberAccess` new, 87 updated), Firestore and Storage rules. **Not done:** the app build is not installed anywhere, and `--step=permissions` waits until it is (deploy step 5 below).

Functions were deployed **by name** (`firebase deploy --only functions:<each export>`): the project has two functions that are in no branch on GitHub, `syncActiveSponsorCount` (asia-southeast1) and `recountActiveSponsors`, deployed by someone from local code; a plain `--only functions` deploy stops because it would delete them. Commit their source, or delete them on purpose, before the next full deploy. The first by-name attempt failed with a one-off upload error; the retry went through.

Until the new build is installed, the team accounts' **Donations** screens in the old build fail to load: as platform `admin` accounts the old build lists donations without the organization filter, which the new rules refuse.

Fixes the money-access gap: money was tied to the org Admin role, and a platform account (`users.role 'admin'`) counted as a financial admin of every organization (interview finding #8).

**Model.** Members are **Admin** (everything, including members, org profile, shelter and care settings, Facebook connection, analytics rebuild) or **Staff** with permissions an Admin picks from a preset and can then tick or untick ("Custom").

| Permission | Covers |
|---|---|
| `rescue` | cases, referrals, transport, collar tags |
| `animals` | animal records, medical, medication plans |
| `care` | doses, care updates, care rounds, stock |
| `adoptions` | applications through returns |
| `campaigns` | fundraising listings, updates, in-kind |
| `financeView` | donor records, campaign history, transfers, case expenses |
| `financeManage` | record/allocate/void/refund, approve expenses, settle payments, general expenses and staff pay, resolve expired campaigns (includes `financeView`) |
| `volunteers` | events, volunteer and transporter applications |
| `insights` | analytics, audit log |
| `facebookPublish` | post to Facebook (replaces `members.facebookPublisher`) |

Presets: Full staff (everything but `financeManage` and `facebookPublish`, = old Staff), Rescue coordinator, Animal care (= old Carer), Adoptions officer, Treasurer. One source: `functions/org_permissions.json`, mirrored in `lib/core/models/organization/org_permission.dart` and the lists in `firestore.rules`/`storage.rules`, with sync tests on both sides.

**Legacy fallback** (rules, functions and app agree): role `carer` = Animal care, other Staff without a list = Full staff (+ Facebook if `facebookPublisher`), an account linked by `users.organizationId` with no members doc = Full staff. So nothing breaks before the migration.

**Where it's enforced**
- `functions/org_access.js`: `effectiveAccess`, `requireOrgPermission`, `orgMemberUids` (notification audiences by permission), `planAccessChange`.
- `functions/org_members.js`: new `setMemberAccess` callable, the only writer of a member's `role`/`permissions`/`preset` (owner stays Admin, one active Admin must remain, audit entry with old and new values).
- Callables now check permissions: campaign listings `campaigns`; money callables, `resolveExpiredCampaign` (which also refuses converting a **restricted** campaign to a general fund) and `settleFlaggedPayment` `financeManage`; Facebook connect Admin, publish `facebookPublish`; `rebuildAnalyticsSummaries` Admin; referral links `rescue`; Zoom meetings `adoptions` (were open to any signed-in user). `LISTING_ROLES` is gone: membership decides.
- `firestore.rules`: `staffWith(orgId, keys)` replaces `isStaffOf`/`isCarerOf`/`isFinanceAdmin`/etc.; every block maps to permissions. Platform `admin`/`ngo_staff` keep non-money platform access and lose donations, payments, transfers, campaign history, case expense writes, `orgExpenses` and settings writes. Clients can no longer write `permissions`/`preset`; only Admins invite (Staff could invite an Admin before); org profile and settings writes are Admin only. Care-only Staff are kept out of the admin-shell data (profiles, unowned animals, budget settings, alert claims).
- `storage.rules`: same helpers; expense receipts need `financeManage` (any member, carers included, could read org receipts before).
- App: `OrganizationCapabilities` (permissions, `isAdmin`, `isCareOnly`, `orgHomeFor`), `canManageFinancesProvider`/`canViewFinancesProvider`/`isOrgAdminProvider` (call sites split by intent), drawer shows only usable modules, `main.dart` routes care-only Staff to the care screen and Staff with no permissions to a "No access yet" page, Staff Members uses `MemberAccessEditor` (invite and edit), invitations carry permissions and accepting copies them.

### Deploy, in this order

1. Tests (all passing, see below).
2. `node scripts/migrate_member_permissions.js --project=respawnd1-45021 --org=RdU4Oc7eUPiRX5iGL6Tu --step=admins` (dry run printed 3 team accounts to add as Admins; the orphaned `PsncBNL0…` profile has no sign-in and is skipped), then `--apply`. Do this **before** step 3, or the team accounts lose money access.
3. `FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions`, then `firebase deploy --only firestore:rules,storage`. Both accept old and new member shapes.
4. App build.
5. `--step=permissions` (dry run: the owner stays Admin, 1 pending `carer` invitation to convert), then `--apply`, **only after** everyone has the new build (older builds route by `role == 'carer'`).
6. Later cleanup: drop the legacy `carer` branches, the client role-write branch in members rules, `facebookSetPublisher`, and the "no members doc = Full staff" fallback.

### What changes for people (tell the organization)

- Staff can no longer invite members or edit the org profile or settings; extending, closing or converting an expired campaign needs Manage money.
- Platform `admin` accounts see money only as members of the organization.
- respawnd.mgmt@gmail.com (owner, now `system_admin`) opens the system admin console, so no one uses the org tools as owner until another Admin does.
- The Donations & funds dashboard card stays with Manage money (it shows general expenses and staff pay).

### Checks run

- `flutter analyze`: the same 9 issues as before. `flutter test`: 230 pass (new: `org_permission_test.dart` incl. the JSON sync, rewritten `organization_capabilities_test.dart`, `member_access_editor_test.dart`).
- `functions/`: `npm test` 72 pass (new: `org_access.test.js`, `org_permissions_sync.test.js`).
- `rules-tests`: 167 pass (new `permissions.test.js` per preset, legacy fallbacks and access writes; expression-budget scenarios for same-org Staff without `rescue`; six older tests updated for the intended changes).
- Migration: dry runs only, on the live project.

### Check on a device

One account per preset: Treasurer sees Donations and approves expenses but not Rescue; Animal care lands on the care-tasks screen; Full staff sees donations but can't record money; Staff can't invite; an Admin edits a member's access and the change shows in the audit log; a platform admin who isn't a member sees no money.

## System admin console, one-organization scope, referral links (2026-11-17, not checked on a device)

**Deployed 2026-11-17:** all 87 functions (new: the four referral-link callables; `reviewOrganization` changed), Firestore and Storage rules, Hosting (`/referral`). The full functions deploy hit Cloud Run's per-minute read quota (HTTP 429): the CLI retried every function but `evaluateCampaignDeadlines`, which was redeployed on its own. `createReferralShare` and `revokeReferralShare` were then redeployed to check sign-in before looking up the case (a signed-out caller could tell whether a case existed). Smoke test on the live site: a made-up link shows "Link not found"; signed-out create is refused. **Not done:** the app build with these screens.

**System admin account (2026-11-17):** respawnd.mgmt@gmail.com (uid `2vAxdRFvtmVIutiXywz03F8tiAa2`) now has `role: system_admin`, at the project owner's request, with an `auditLogs` entry. It is also the owner and only Admin member of Respawnd Test Org; that ownership and membership were kept, so firestore.rules still grant it the organization's staff and finance access (they check membership, not the role). Only the app changes: the new build opens the console for it, and **nobody is left using the org admin tools** until another account is added as an Admin member. Older builds have no `system_admin` route and open the general home screen. To undo: set `role` back to `admin`. A second profile, `users/PsncBNL0TRfA6Yfji05F`, also lists that email but has no sign-in account; it was left as it is.

### System admin console

- New account role `system_admin` (`users/{uid}.role`), **set in the Firebase console only** (`selfRoles` in firestore.rules never lets a client pick it). `main.dart` routes it to `SystemAdminHomeScreen` (`lib/features/systemadmin/`), two tabs:
  - **Approvals:** the existing `OrganizationReviewPage` (organization sign-ups under review; approve, ask for changes, not approve through `reviewOrganization`). Badge shows the pending count.
  - **Users:** read-only directory. Organization tab lists each organization with its people and their role there (owner, Admin, Staff, Carer, linked account, inactive), plus organization accounts not on one yet. Transporters (with verification state), Volunteers, General, Admins. Search; tap for details (type, organization and role, transporter state, email, phone, joined, copy ID).
- **Transporters are still verified by organization staff** (admin drawer → Transporters); the console only shows their state.
- Access is narrow on purpose: `isSystemAdmin()` in firestore.rules adds `users` reads; organizations and members were already readable by signed-in users; storage.rules lets it read `organizations/{id}/verification/**` (not upload); `reviewOrganization` accepts it. It is **not** platform staff: no cases, animals, medical records, adoptions or money (rules tests check this).
- The six existing `role: 'admin'` accounts are unchanged and keep the organization tools. To make a system admin, set `role` to `system_admin` on an account in the console (not one of those six, or it loses the org tools).

### One organization for now

`FeatureFlags.multiOrganizationEnabled = false` (`lib/core/constants/feature_flags.dart`) hides: Refer → Another organization, Transfer Animal → Organization (Treatment Details), Transfer Animal Record → Another Organization (the sheet goes straight to a named volunteer), the "Open for transfer" switch on Accept Case, and Organization approvals in the admin drawer (now in the system admin console). Code, data, rules and functions are untouched; flip the flag to bring them back.

### Referral links (shareable web page)

- After an LGU/barangay referral is saved, staff are offered **Share link**; every referral in Referral History (Rescue Details) also has Share link / Share again / Stop sharing. Staff choose whether to include the reporter's name and phone (never for an anonymous report). The share sheet sends a link like `https://respawnd1-45021.web.app/referral/<token>`.
- The page (`public/referral/index.html`, Hosting rewrite `/referral/**`) works without the app or sign-in: report copy (animals, condition, risks, photos and videos staff attached, address + Open in Google Maps, why it was referred, the organization's call/email/Facebook), the case's status in plain words, and a form: Will handle it / Can't take it / Needs more information, with name, contact and note. `noindex`.
- Backend `functions/referral_shares.js`: `createReferralShare`, `revokeReferralShare` (staff of the owning organization, or platform staff), `getReferralShare`, `respondToReferralShare` (no sign-in; the token is the key). Stored at `referralShares/{token}` (rules: no client access). The page never reads Firestore. The copy is built by `buildReferralSnapshot` (`functions/referral_share_rules.js`): no notes, verification evidence, status history or rider location. Links expire after 30 days (`SHARE_TTL_DAYS`, pending the organization's confirmation), take at most 20 answers, and a new choice about the reporter's contact replaces the old link.
- An answer is kept with the link, shown in Referral History ("Answer from …"), added to the case's status history and activity log, and pushed to the organization's staff (`referral_response`, opens the case). On an LGU referral, Will handle it marks it Accepted and Can't take it marks it Declined with the note.

### Deploy, in this order (steps 1–3 done)

1. **Functions:** new `createReferralShare`, `revokeReferralShare`, `getReferralShare`, `respondToReferralShare`; changed `reviewOrganization`. `FUNCTIONS_DISCOVERY_TIMEOUT=60 firebase deploy --only functions`.
2. **Rules:** `firebase deploy --only firestore:rules,storage` (`system_admin` reads, `referralShares` locked). Safe for current builds: only adds access.
3. **Hosting:** `firebase deploy --only hosting` (the `/referral` page and rewrite).
4. **App build.**
5. Set `role: system_admin` on the account(s) that should approve sign-ups.

### Checks run

- `flutter analyze`: the same 9 issues as before. `flutter test`: 212 pass (new: `test/features/systemadmin/user_directory_test.dart`, `test/core/models/referral_share_test.dart`). `functions/`: `npm test` 59 pass (7 new in `referral_share_rules.test.js`). `rules-tests`: 146 pass (system admin reads and limits, storage verification reads, `referralShares` locked).
- The referral page was checked at phone width with sample data in a local preview: layout, answer choice, validation and the thank-you message. Not checked against the deployed functions.

### Check on a device

- Sign in as a `system_admin` account: only Approvals and Users show; Users lists the test organization's members with roles, and the transporters with Pending. Opening an organization's documents in Approvals works.
- Refer a case to a barangay, choose Share link, open the link on another phone without the app, answer Can't take it with a note: the referral shows Declined with the note, staff get a push, and the case history shows the answer. Stop sharing: the link shows "This link is closed".

## Deploy status (2026-11-17)

- **Functions:** all 83 deployed from `dev`'s working tree (14 created: `pledgeInKindDonation`, `recordDonationReversal`, `mirrorCampaignHistoryToAudit`, `stampAnimalsIllnessesOrganization`, `syncRescueAdoptionRequest`, `onRescueAdoptionCaseUpdate`, `followUpAdopterPickups`, `escalateCriticalReports`, `scheduleCommunityAdoptionCheckIn`, `sendCommunityAdoptionCheckIns`, `sendDashboardDigest`, `notifyStaffOfSpecializedAssistance`, `writeAnalyticsSummaries`, `rebuildAnalyticsSummaries`; 69 updated). Needed `FUNCTIONS_DISCOVERY_TIMEOUT=60`: the default 10 s load timeout failed once while another deploy was running.
- **Indexes:** deployed.
- **Scripts: run 2026-11-17** with a service-account key (`GOOGLE_APPLICATION_CREDENTIALS`), each dry run then `--apply`, in this order: `backfill_organization_ids` (22 docs from evidence; no `--default-org`, so 71 cases stay in the review pool and 4 animals have no organization), `backfill_log_organization_ids` (88), `backfill_public_animals` (11), `backfill_public_cases` (77), `backfill_rider_status` (6 riders), `backfill_volunteer_stats` (none), `backfill_referral_targets` (1), `migrate_shelter_settings --org=RdU4Oc7eUPiRX5iGL6Tu` (Respawnd Test Org, the project's only organization; Loved by the Gapz isn't in this project).
- **Campaigns have no `organizationId`** (all 7; created by a general user, a platform admin, or nobody). Their 22 donations, 8 payments and 5 allocations stay unstamped, so once the rules are live only platform admins and the donors themselves see them. Assign the campaigns to an organization, then rerun `backfill_log_organization_ids.js`.
- **Rules (`firestore`, `storage`): deployed 2026-11-17**, before the new app build was out. Phones on older builds lose their staff case lists, Explore map, job board, payment lists, public donor counts and the other screens listed in the release-order notes below until they install the new build.
- **Hosting:** deployed 2026-11-17 (payment return pages and `/tag`; the previous deploy was 2026-10-15). The first try failed with a one-off Hosting API error; the retry released fine.
- **App build:** release APK built 2026-11-17 from the uncommitted `dev` working tree (`build/app/outputs/flutter-apk/app-release.apk`, 101 MB). Signed with the debug key (`android/app/build.gradle.kts` has no release signing config), so it installs by sideloading, not through the Play Store. Not installed on a device yet.

## Release open issues (2026-11-17, not checked on a device, not deployed)

The three "Still open" items under Defense gap fixes, now closed.

| Issue | Fix |
|---|---|
| `donationPayments` readable by every organization's financial admins | Rule now uses `isFinanceAdminOf(resource.data.organizationId)`: the donor, a platform `admin`, or an Admin member of the owning organization. `paymentAttemptsProvider` queries by `organizationId` (platform admins: everything); Payments to Verify drops its client-side campaign filter. New index `donationPayments (organizationId, createdAt desc)`. `scripts/backfill_log_organization_ids.js` now also stamps older payments from their campaign; until it runs, older payments are hidden from organization admins. |
| Adopter notifications for no-show, booking reminder and withdrawal opened nothing | Push taps (`notification_service.dart`) and the in-app list (`notifications_screen.dart`, now labelled "Adoption", not "Donation") open the application through the new `adopterPageForAdoption` (`lib/features/adoption/adopter_adoption_route.dart`), which the list's other adoption items now use too. |
| Multi-animal intakes on separate post-treatment paths needed staff to open the page | `completeDueIntakes` now also runs `completeDueAnimalIntakes`: cases with `activeAnimalStages` containing `intake`; each animal sent to Intake, received and with its record gets `intakeCompletedAt`, with the stage counts and case status recomputed the way `completeIntakeForAnimals` does. Rules in `functions/rescue_timer_rules.js` (`animalsDueForIntakeCompletion`, `stageSummary`, `derivedCaseStatus`) with tests. |

### Deploy, in this order

1. **Functions:** `completeDueIntakes` changed (a full `firebase deploy --only functions` covers it).
2. **Indexes:** `firebase deploy --only firestore:indexes` (the new `donationPayments` index).
3. **Script:** `node scripts/backfill_log_organization_ids.js --project=respawnd1-45021`, dry run, then `--apply`.
4. **App build.**
5. **Rules:** `firebase deploy --only firestore:rules`. Older builds list payments without the organization filter, which the new rule refuses, so their Payments to Verify and payment-attempt lists go empty.

### Checks run

- `flutter analyze`: the same 9 issues as before. `flutter test`: 201 pass.
- `functions/`: `npm test` 52 pass (2 new for per-animal intake).
- `rules-tests`: all pass, including 3 new for payment attempts.

### Check on a device

- As an org Admin, Payments to Verify and the payment-attempt list show only your organization's payments; as a platform admin, all of them.
- As an applicant, tap a no-show, booking-reminder and withdrawal notification (push and in-app): each opens the application.
- A two-animal case: send one animal to Intake, receive it and create its record, leave the other in Treatment. Within 30 minutes the first animal's Intake completes without opening the page, and the case stays in Treatment.

## Dashboard and Analytics gaps (2026-11-17, not checked on a device, not deployed)

| Gap | What |
|---|---|
| Dashboard 2, care rounds | `lib/features/care/`. Areas × round tasks (default: Main shelter; morning feed, water, cleaning, evening feed) ticked once a day at `organizations/{orgId}/careRounds/{yyyy-MM-dd}`, with who and when. On the carer's Care tasks screen (full list) and the Shelter care card (progress, what is still open, link to the full list). |
| Dashboard 3, care coverage | Weekly roster (weekday × shift → members) in `organizations/{orgId}/settings/care`, edited by admins on **Roster & tasks**. The readiness factor reads Constrained when any shift in the next 7 days has no one, "not set" with no roster. The accept-case snapshot uses the same factor. |
| Dashboard 6, pushes | `functions/dashboard_ops.js`: `sendDashboardDigest` (07:00 Manila) pushes each approved org's admins the Priority actions counts by area, and deletes lapsed claims. `notifyStaffOfSpecializedAssistance` pushes staff at once when a rescue needs specialized assistance (the other critical alerts already pushed). |
| Dashboard 7, alert ownership | Every alert has a stable `key`. The row's ⋮ menu: I'm on it / Release / Take over. Claims at `organizations/{orgId}/alertClaims/{key}`, shown as "Ana is on it · 2h ago", lapse after 24 h (`kAlertClaimTtl`). Alerts still clear only when the record changes. |
| Analytics 1, export | Export menu next to the period: summary PDF for the period vs. the comparison period, CSVs (cases, animals, adoptions, donations for financial admins), and a monthly accomplishment report for last month with up to five earlier months from the stored summaries. |
| Analytics 2, periods | `analytics_range.dart`: last 30/90/365 days, this/last/any month, this/last quarter, custom range. Calendar ranges compare with the previous month or quarter. |
| Analytics 3, timestamps | `readyForAdoptionAt` is stamped when an animal is confirmed ready (older records fall back to the checklist's `confirmedAt`). "Discharge (or intake) to ready" and "Ready to adopted" now show medians. |
| Analytics 4, location | Rescue report: "By city", "By barangay" (parsed from the saved Google address, `case_location.dart`) and a heat map of report pins. |
| Analytics 5, untracked events | Community cat: a switch on the stray report form when a cat is reported, and a staff switch on Rescue Details (`communityCat`). Illness log: a section on the Medical tab (`animals/{id}/illnesses`). Euthanasia second review: on the End-of-care card, a different admin records alternatives considered and agrees or has concerns (`euthanasiaReview`; `markDeceased` now stores `deceasedByUid`). **Help requests are still not tracked: ask the organization whether they should become a report type.** |
| Analytics 6, summaries | `writeAnalyticsSummaries` (1st of the month, 02:00 Manila) stores `organizations/{orgId}/analyticsSummaries/{yyyy-MM}` for the month just ended and fills in any of the last 12 that are missing. `rebuildAnalyticsSummaries` (callable, org admins) rebuilds all 12. A new **Month by month** card reads them; the current month is live. The existing cards still compute on the phone. |

Pending the organization's confirmation: the default round tasks and shifts, the 24 h claim lapse, the 07:00 digest time.

### Deploy, in this order

1. **Functions:** new `sendDashboardDigest`, `notifyStaffOfSpecializedAssistance`, `writeAnalyticsSummaries`, `rebuildAnalyticsSummaries`, `stampAnimalsIllnessesOrganization`. A full `firebase deploy --only functions` covers them.
2. **Indexes:** `firebase deploy --only firestore:indexes` (new `illnesses.organizationId` field override).
3. Optional: an org admin presses **Rebuild the last 12 months** on Analytics → Month by month, so the card isn't empty until 1 December.
4. **App build.**
5. **Rules:** `firebase deploy --only firestore:rules` (care settings readable by carers; `careRounds`, `alertClaims`, `analyticsSummaries`; `illnesses` collection-group read).

### Checks run

- `flutter analyze`: the same 9 issues as before, none in new code. `flutter test`: 201 pass (12 new in `test/features/adminhome/dashboard_analytics_gaps_test.dart`).
- `functions/`: `npm test` 50 pass (digest and summary rules are new). `rules-tests`: 137 pass (6 new).

### Check on a device

- Care rounds: as a carer, tick and untick a task; the dashboard card updates. As an admin, edit the roster, leave a shift empty, and see Care coverage turn Constrained.
- Claims: as two admins, claim an alert on one phone and see "… is on it" on the other; release as a non-admin fails for someone else's claim.
- Export: each of the three exports opens the share sheet; PDFs show peso amounts as "PHP".
- Heat map: needs the Maps SDK key that the other maps use; check it draws on Android.
- Digest: run `sendDashboardDigest` from the Cloud Scheduler console once and check the push.

## Defense gap fixes (2026-11-17, not checked on a device)

Two rounds of fixes from a code-reading gap review of `dev`. Numbers marked "pending the organization's confirmation" are named constants, easy to change.

### Round 1 (`703981a..862d754`, on `dev`)

Six functions and two indexes from this round were deployed on 2026-11-16 from the unmerged branch: `expireTransportOffers`, `notifyStaffOfOfferOutcome`, `hasBlockingAdoption` (changed), `closeOtherAdoptionApplications`, `notifyStaffOfTransitEnd`, `sendFollowUpReminders`, plus the `transportAssignments (status, expiresAt)` and `followUps (status, scheduledDate)` indexes. Local `dev` was fast-forwarded to `862d754` and not pushed. The app changes need a new build.

| Commit | What |
|---|---|
| `703981a` | Transport offers wait 5 min for a Critical case, 20 min otherwise (`kTransportOfferTtlCritical` / `kTransportOfferTtlStandard`). Staff screens show the offer's own deadline and an "Offer Expired" state. |
| `607c6dd` | `expireTransportOffers` (every minute) expires stale offers on the server. `notifyStaffOfOfferOutcome` pushes to the sender and staff when an offer is declined or expires. New `offeredBy` on offers. |
| `f331e5d` | "No transporter available" prompt on Assign Transporter after the radius is exhausted or 3 failed offers: Refer, Organization Will Transport (`organizationTransport`, case goes to Ongoing), Keep Waiting. Critical case at the limit: URGENT push to org admins. |
| `e933a43` | **Policy commit (revert alone if the organization says no):** several applicants per animal; the reservation is the lock. `hasBlockingAdoption` blocks only reserved-for-someone-else / adopted / closed. `closeOtherAdoptionApplications` closes the other open applications on reserve or adopt. |
| `d4a6502` | Transporter end reasons: Vehicle breakdown returns the case to Awaiting Assignment; Deceased / Other become `transit_ended` with a staff decision panel and `notifyStaffOfTransitEnd`. Shelter drop-off goes to Intake instead of Completed. |
| `862d754` | `sendFollowUpReminders` (daily 08:00 Manila): adopter reminded on the due date and 3 days later, staff alerted at 7 days overdue. Rules in `functions/follow_up_reminder_rules.js` with node tests. |

### Round 2 (branch `claude/remaining-gap-fixes-481458`, cut from `dev`)

| Commit | What |
|---|---|
| `1fc9c75` | **Missing donation backend.** The app called `voidAllocation` and sent `generalFund: true` to `recordOfflineDonation`, but neither existed in `functions/`. Added both in `functions/campaigns.js`: `voidAllocation` (financial admins of the campaign's org, transaction, allocation marked `voided`, amount back to the campaign's balance, history + `auditLogs`), and the General fund at `campaigns/general_{orgId}`, created on first use (`ensureGeneralFund`), not editable, closable, deactivatable or archivable, same duplicate-reference check. Offline donations now write `auditLogs` too. `recordAllocation` and excess transfers now stamp `organizationId` on the allocation (the analytics queries filter on it; only the backfill set it before). **Kept in its own commit in case the original code turns up elsewhere.** |
| `dd27fb6` | **Referral follow-through.** The target is stored on the case (`referredToOrgId` + `referral`); only that organization's staff (and platform staff) see it in Referred and can answer it. Accept: their org becomes owner, case to their Rescue Review. Decline: reason required, case back to the referring org's Review with a "Referral returned" card. Referral record gets Accepted / Declined / Expired. `notifyCaseReferralCreated`, `notifyCaseReferralOutcome`, and `followUpCaseReferrals` (hourly: remind the target at 24 h, return the case at 48 h; `functions/referral_rules.js`). An unowned case is stamped with the referring org when referred. LGU referral unchanged. `scripts/backfill_referral_targets.js` for cases referred before this. |
| `d289bd0` | **Fit score saved at decision.** Accept and Reject save `fitAtDecision`: score, band, breakdown, strengths/concerns, rubric version, the staff's manual fit value and their notes. Adoption Details shows "Fit Assessment at decision time" from the saved copy; the review list chip says "(at decision)". The audit entries carry the score. Adopters can't edit `fitAtDecision` (rules). |
| `0b6ea49` | **Shelter pin and per-org shelter settings.** (a) No more hard-coded Rodriguez coordinates. Without a saved shelter pin the shelter leg doesn't start: the transporter is told, the case is stamped `shelterLocationMissing`, `notifyStaffOfMissingShelterPin` alerts staff and admins, and a "Shelter location not set" prompt with a Set button appears on the dashboard readiness card, Rescue Details and Organization Profile edit. (b) Dashboard shelter settings and Organization Profile's capacity move to `organizations/{orgId}/settings/shelter` (staff read, admins write; the old open org-subcollection rule now excludes `settings`). The old `settings/shelter` is still read as a fallback until migrated: `scripts/migrate_shelter_settings.js`. |
| `a76c84d` | **Settle "needs review" payments.** New `settleFlaggedPayment` callable (`functions/paymongo.js`), financial admins of the owning org only: `check` (fetch the paid amount from PayMongo), `accept` (credit the amount actually paid through the same `finalizePaidDonation` path: donation, history, campaign total, certificate, plus campaign history and `auditLogs`), `void` (reason required, `auditLogs`; a voided payment is never credited by a later webhook). New "Payments to Verify" screen from the dashboard alert and tile. New flags store the paid amount; new payments store `organizationId`. |
| `3c383e0` | **No-shows and stalled applications.** "Mark No-show" on Adoption Details (it existed in the repository but nothing called it). First no-show: back to Pending, appointment cleared, the applicant can book once more. Second: closed as rejected, "Did not attend the interview twice". `notifyAdopterOfNoShow` tells the applicant. `followUpStalledApplications` (daily 09:00 Manila): pending with no interview booked → reminder after 3 days, withdrawn after 14 (from submission or the last no-show), with duplicate guards. Rules in `functions/adoption_stall_rules.js` and `adoption_no_show_rules.dart` with tests. |
| `64c5773` | **Rescue timers.** `completeDueQuarantines` and `completeDueIntakes` (every 30 min) make the same writes the app makes when staff open the case, and staff are told when a quarantine ends. Intakes where animals follow separate post-treatment paths are still completed per animal by the app. The app checks stay as the fallback. |

### Deploy, in this order

From `functions/` (with `functions/.env` and the secrets in place). Merge this branch into `dev` first, so a later `deploy --only functions` from `dev` doesn't offer to delete these.

1. **Functions.**
   - New: `voidAllocation`, `settleFlaggedPayment`, `notifyCaseReferralCreated`, `notifyCaseReferralOutcome`, `followUpCaseReferrals`, `notifyStaffOfMissingShelterPin`, `notifyAdopterOfNoShow`, `followUpStalledApplications`, `completeDueQuarantines`, `completeDueIntakes`.
   - Changed: `recordOfflineDonation`, `recordAllocation`, `reallocateExcess`, `saveCampaign`, `setCampaignStatus` (campaigns.js); `createDonationCheckout`, `syncDonationPayment`, `cancelDonationCheckout`, `paymongoWebhook`, `expireStaleDonationCheckouts` (they share `finalizePaidDonation`).
   - A full `firebase deploy --only functions` covers all of them.
2. **Indexes:** `firebase deploy --only firestore:indexes` (new: `cases (quarantineStatus, quarantineScheduledEndAt)`). `completeDueQuarantines` logs errors until it finishes building.
3. **Scripts**, each as a dry run, then `--apply`:
   - `node scripts/migrate_shelter_settings.js --project=respawnd1-45021`. With no flags it lists the organizations. Then run `--org=<Loved by the Gapz id>`, then add `--apply`.
   - `node scripts/backfill_referral_targets.js --project=respawnd1-45021`.
4. **App build.**
5. **Rules:** `firebase deploy --only firestore:rules`, only once the new build is what people use. Older builds query referred cases by status, which the new rules refuse, and that query error can empty their whole Referred list.

### Checks run

- `flutter analyze`: 8 issues, the same 8 as before round 1, all in lines this branch doesn't change (initializing formals in `transit_case_service.dart` and `adoption_application_service.dart`, a duplicate import in `donation_admin_create.dart`, an unused `_FundTrackingPanel` in `donation_detail.dart`).
- `flutter test`: 181 pass (175 before this round, plus the new `fit_at_decision_test.dart` and `adoption_no_show_rules_test.dart`).
- `functions/`: `npm test` 24 pass (referral, stalled-application and timer rules are new), and `node --check` passes for every file.
- `rules-tests`: 121 pass, including the new referral, shelter-settings, fit-score and no-show cases and the expression budget.
- Nothing was deployed and nothing was run on a device or the emulator suite beyond the rules tests.

### Check on a device

- **General fund.** Donations admin → Record donation with no campaign creates "General Fund" and credits it. Recording the same reference twice is refused. Close or Edit on the General fund is refused.
- **Voiding spending.** Pay an expense from a campaign, then delete the expense or remove that funding line. The campaign's balance goes back up, and Fund Tracking hides the voided line.
- **Referrals (two organizations).** Refer from org A to org B: only B sees it in Referred. As B, Accept: it lands in B's Rescue Review. Refer again and Decline with a reason: it returns to A with the reason, and A gets a push. The 24 h reminder and 48 h return need waiting or a test case with an old `referral.referredAt`.
- **Fit score.** Accept one applicant and reject another for the same animal. Reopen both: "Fit Assessment at decision time" shows the saved score, staff fit and notes.
- **Shelter pin.** With an org that has no pin, run a transporter through Accept Treatment: the trip to the shelter is blocked and staff get the alert. Set the pin from the prompt, retry, and arrival at the shelter should work within 150 m.
- **Shelter settings.** Set up the shelter from the dashboard, as an org admin and as a non-admin. Check the capacity in Organization Profile matches.
- **Payments to Verify.** Needs a PayMongo test payment whose amount differs from the priced amount, or a `donationPayments` doc set to `needs_review` in the test project. Check, then Accept: the campaign total, donor history and certificate show the paid amount. Void another with a reason.
- **No-shows.** Book an interview, then Mark No-show: the applicant's app shows Book Appointment again, and they get a push. Book again and mark a second no-show: the application closes with the reason.
- **Stalled applications.** A pending application with no booking gets the 3-day reminder and the 14-day withdrawal (needs an old `createdAt` in the test project).
- **Timers.** A quarantine with a short duration ends on its own, and staff get "Quarantine ended" without anyone opening the case. A single-animal intake completes on its own once its record exists.

### Still open (not done here)

All three items that were listed here are closed: see Release open issues at the top.

## Build fix status (2026-11-04)

- **The app builds.** `flutter analyze` reports **no issues** (down from 301), and `flutter test` passes **87/87**. `assembleDebug` succeeds.
- **Nothing is committed.** All changes are in the working tree, about 115 files.
- **Not yet checked on a device.** See [Manual test checklist](#manual-test-checklist).

## What was done (build fix)

### 1. Fixed the build
- **Upgraded Flutter.** The old version was 3.41.2 with Dart 3.11, but `native_geofence ^1.5.1` (from commit `39ff2f5`) needs Dart 3.12 or newer, so `pub get` failed and nothing resolved. **Everyone on the team needs to upgrade Flutter**, or they'll hit the same failure.
- **Removed a stray `git` line** in `signOut()`, at `lib/core/repos/auth_service.dart:238`. It came in with commit `a88bd06`.

### 2. Automatic cleanup (`dart fix --apply`, 234 fixes)
These were cosmetic: `(_, __)` → `(_, _)`, `'k': ?x` null-aware entries, braces, `final` fields, `SizedBox`, unused imports, and dropdown `value:` → `initialValue:`.

### 3. Changes that affect behavior (please review)
- **Dropdowns (15 sites).** `initialValue` stops a dropdown from following its parent's state. Without a fix, that would crash the breed dropdown when species changes and show stale values after deleting a care-record row. Each migrated dropdown got `key: ValueKey(<value>)` so it behaves the way it did before.
- **`BuildContext` across `await` (7 sites).** Added `mounted` / `context.mounted` checks in:
  - `post_adoption_details_page`
  - `adoption_process`
  - `staff_members_page` (2 sites)
  - `transit_progress_page`
  - `login_screen`
  - `event_detail_page`
- **`Radio` → `RadioGroup` (13 groups):**
  - List-tile groups are wrapped as a whole.
  - Custom row radios (payment methods, adoption forms, collar tag) each wrap their own `Radio`, so card layout is unchanged.
- **Sharing.** `Share.shareXFiles` → `SharePlus.instance.share(ShareParams(...))` in:
  - `animal_record_export_service`
  - `transfer_export_service`
  - `admin_qr`
  - `collar_id_tag_screen`
- **Reorder.** `release_details_page` now uses `onReorderItem`. I also removed the manual `newIndex -= 1`, because the new callback already adjusts the index.
- **Map markers.** `BitmapDescriptor.fromBytes` → `.bytes(..., bitmapScaling: MapBitmapScaling.none)` in `explore_reports_map`, which keeps the old marker size.
- **Dead code removed in `donation_page.dart`.** `_toggleSponsorFavorite`, `_petFavoriteIds` and the Firestore read of `users/{uid}/favorites` that fed them. Sponsor cards now use campaign favourites (`_toggleFavorite`). The old code is in git history if pet-level favourites come back.
- **Other removals.** The unused `_animalLoading` (`donation_detail`), the unused `_selectedPayment` (`SponsorshipDetail` state), and an unused `closure_reason` import (`analytics_view`).

### 4. Small lint fixes
- `sum`/`count` closure parameters renamed to `acc`/`n`.
- `<…>` in doc comments wrapped in backticks.
- `_DonationListItem` → `_donationListItem` and `_FieldLabel` → `_fieldLabel` (both are methods).
- `print` → `debugPrint` in `history_provider`.

## Manual test checklist

**Radio buttons:** tap through the options and check that "Other" shows its text field.
- Admin, close rescue case (closure reason and service type)
- Transporter: end transit, reject treatment, decline rescue request
- Staff members: Edit Role (member) and Change Role (invite)
- Volunteers: sort sheet
- Donation detail and sponsorship detail: pick a payment method
- Adoption application form, post-adoption form, collar tag form

**Dropdowns:**
- Rescue report: pick a species and a breed, then **change the species**. The breed should reset with no crash.
- Add care record: add 3 rows, **delete the middle one**, and check the remaining values.
- Lost pet, surrender and found animal: selections should stick when moving between steps.
- Editing an existing animal record, expense, treatment or transporter verification should show its saved values.

**Other:**
- Release details: drag rules up and down. Each should land where you drop it.
- Explore reports map: markers are the same size as before.
- Share a collar QR, a collar ID card, an animal record export and a transfer packet. The file should be attached.
- Donations tab: list loads, campaign hearts toggle, bottom nav works.
- Sign out fully logs you out.

## Still to do

1. **Run through the checklist**, then commit. A suggested split:
   - the build fix (`auth_service.dart`, `pubspec.lock`)
   - the lint and deprecation cleanup
2. **Upgrade the Android toolchain** (warnings for now, future Flutter versions will make them errors). Do this as its own task, since AGP 9 has breaking changes:

   | Tool | Current | Required soon | File |
   |---|---|---|---|
   | Gradle | 8.14 | ≥ 9.1.0 | `android/gradle/wrapper/gradle-wrapper.properties` |
   | AGP | 8.11.1 | ≥ 9.0.1 | `android/settings.gradle.kts` |
   | Kotlin | 2.2.20 | ≥ 2.3.20 | `android/settings.gradle.kts` |

   While doing it, also migrate to Flutter's built-in Kotlin, which removes the repeated "KGP was not found on the classpath" messages. See <https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin>.
3. **Optional:** raise `environment.sdk` in `pubspec.yaml` to `>=3.12.0`, so anyone on an old Flutter gets a clear error.

## Earlier work on `marcus` (committed, from the interview-based plan)

These commits landed before the `dev` merge and are in this branch's history. They're tracked against the redesign plan for Loved by the Gapz (P0 security, P1 critical gaps, P2 supporting work, P3 cleanup).

| Commit | What |
|---|---|
| `e79b579` | **P3 cleanup.** Dead buttons wired up (alerts bell, transporters list, rider call button, Share/Maps, View Donations). Real `lastLat`/`lastLng` instead of demo coordinates, with a "location not shared" state. Removed `volhome_screen.dart`, the Payment methods tile and `flutter_stripe`. |
| `ac7ece1` | **P0 security.** `firestore.rules`: users can't set their own `role`/`organizationId`, org verification, cases/animals/adoptions scoped by org, collection-group rules. New `storage.rules`. Emulator tests in `rules-tests/` (including a 1,000-expression budget test). |
| `4bb6cde` | **P2.** Email verification at sign-up with a gate in `main.dart`, and email change via `verifyBeforeUpdateEmail`. Partial expense funding (one expense from several funds). Case fundraisers prefilled from a treatment. Generated adoption agreement PDF. |
| `026c87e` | Analytics closure-reason fixes so the app compiled. |
| `0c5265c` | **P1 items 10–12.** Below. |

### Items 10–12 (`0c5265c`)
- **Preventive care after intake.** Dated deworming, flea & tick and vet checkup records on the animal's Medical tab, stored at `animals/{id}/careRecords`. Each has a next-due date with due-soon/overdue badges, and a history view. Default intervals are 90 / 30 / 180 days. Deworming sets `dewormed`; a checkup moves `lastVetCheckup` forward only.
- **Past health records.** "Add Past Health Records" on the Medical tab enters many old vaccines and care doses at once. Same-day duplicates and future dates are rejected.
- **Adoption readiness gate.** New records start as **not adoptable**. Switching to adoptable opens a checklist: health (blocked during an open treatment episode), behavior, vaccines, spay/neuter, continuing care. The confirmed checklist is saved as `adoptionReadiness` on the animal.
- Tests: `test/core/models/care_record_test.dart`, `test/core/utils/adoption_readiness_test.dart`.

**Checklist for these:** add a single care record and a batch of past records, then check the badges and history. Mark an animal in active treatment as adoptable (should be blocked), then one that's discharged (should ask for confirmations).

### Known gaps
- **Known-limits pass (2026-11-15):**
  - Styling: public, adopter, transporter and organization screens now use the shared helpers. Snackbars use `appSnackBar`, the five inline error boxes use `AppErrorBanner`, meaning colours use `AppColors.error/warning/success`, standard buttons use `AppButtons`, display dates use `formatDate`/`formatDateTime`, and plain yes/no dialogs use `showConfirmActionDialog`. Still hand-styled: 24 one-off button styles (conditional or green/white colours), 15 dialogs with text fields or custom content, and greys.
  - Case timeline: every case action now writes the status line and the activity log together through `recordAction`/`recordActionIn`/`recordActionInBatch`, including transporter transit steps, claim/decline and the reporter's adoption-interest/arrival updates, which used to write no activity log at all.
  - Dashboard: "Donations & funds" shows unfunded general expenses and counts their missing receipts.
  - Attachments: medical record attachments accept PDFs (`file_picker`), stored with type `document` and opened in the device's PDF viewer.
  - Not checked on a device yet: the restyled screens, picking and opening a PDF, and a transporter run end to end.
- **Report verification (2026-11-15, not deployed, not checked on a device):**
  - Rescue Details has a "Report verification" panel while a report is in review: evidence checks (where the reporter's phone was, camera or gallery photos, the reporter's earlier reports, other reports and sightings nearby), "Ask for live proof", and "Record result" (confirmed remotely, needs a rider, could not confirm). It replaces the old "Send rider to verify" button.
  - New reports save `reportEvidence`. Reports filed before this show "No evidence details".
  - The reporter answers a live-proof request from Track Case with the camera only; the photo is saved with the time and the phone's location (`liveProof`).
  - A rider with a transporter account sees "Check a location" on their home screen and records found or not found with a photo. A rider added by name only has the result recorded by staff.
  - Everything is stored on the case (`reportEvidence`, `liveProofRequest`, `liveProof`, `verification`) and logged on the case timeline.
  - Needs deploying: `firestore.rules` and `storage.rules` (the rider's own result and photo are denied until then; the staff and reporter steps were not tried against the live rules), and the `notifyCaseVerificationEvents` function (pushes to the reporter and the rider).
  - Not done: a "verified" badge on the rescue list, and reading the capture time and place stored inside a photo file.
- **Organization approval and volunteer badges (2026-11-15, not deployed, not checked on a device):**
  - Platform staff (`role` `admin`/`ngo_staff`) see "Organization approvals" in the admin drawer, with a pending count. It shows documents and offers Approve, Not approve and Ask for changes. Decisions run in the new `reviewOrganization` callable (`functions/index.js`), which writes `verificationStatus`, the reason and reviewer fields, logs to `auditLogs`, and notifies the owner (push plus `users/{owner}/notifications`). Rules now stop every client, platform staff included, from setting those fields. Owners can resubmit after "requires changes", which used to be a dead end. After submitting, an owner now lands on the pending page instead of the admin home.
  - Volunteer badges: the new `syncVolunteerStats` trigger (`functions/volunteer_stats.js`) recounts staff-marked attendance and writes `users/{uid}.volunteerStats` (First event, Helping paw, Regular, Champion, Community helper). Shown in History, on the profile, and on the staff volunteer list. Rules block users from writing `volunteerStats` and from creating a sign-up already marked attended.
  - "Refer to volunteer" and "Open for transfer" are shown as "Coming soon".
  - Release order: deploy functions, run `node scripts/backfill_volunteer_stats.js --project=respawnd1-45021` (dry run, then `--apply`), ship the app build, then deploy `firestore:rules`. Until the rules are live, platform staff can still edit `verificationStatus` directly.
- **Access-control pass (not deployed yet, needs the same coordinated release):**
  - Animal medical subcollections (`medications`, `medicationDoses`, `vaccinations`, `careRecords`, `careUpdates`, `medicalEpisodes`) are readable only by the owning org's staff, its carers and platform staff.
  - The animal doc (`animals/{id}`) is now readable only by the owning org's staff and carers, platform staff, and the user it is reserved for or adopted by. Everyone else reads `publicAnimals/{id}`, a copy written by the new `syncPublicAnimal` function (`functions/public_animals.js`): public fields plus a yes/no health summary, and only while the animal isn't archived, hidden or deceased. The adoption list, public animal page (its Medical tab is now that summary), org profile Animals tab, sponsored animals, donation detail, QR scans and the post-adoption header read it. Staff animal lists query by `organizationId` (their org plus records with none); platform staff list everything. Records with no `organizationId` field at all are readable only by platform staff.
  - Release order for this part: deploy `syncPublicAnimal`, run `node scripts/backfill_public_animals.js --project=respawnd1-45021` (dry run, then `--apply`), ship the app build, then deploy `firestore:rules`. Until the backfill runs, public screens show no animals; older app builds lose the adoption list once the rules are live.
  - `donations` is readable only by the donor and staff. The public donor count now reads `campaigns/{id}.numdonors`, and the organization profile's Donations tab now lists the org's campaigns (it was listing raw donation records).
  - Case `expenses` are written only by financial admins of the owning org (or a platform `admin`). Other staff see them read-only; transporters and reporters can't read them.
  - Audit Rescue/Records tabs query by `organizationId`. The new `stampCaseLogOrganization` / `stampAnimalLogOrganization` functions (`functions/audit_logs.js`) stamp each new log from its parent.
  - Release order: deploy functions and `firestore:indexes`, run `node scripts/backfill_log_organization_ids.js --project=respawnd1-45021` (dry run, then `--apply`), ship the app build, then deploy `firestore:rules`. Older app builds lose the public donor count, the org profile Donations tab and the two Audit tabs once the rules are live.
  - Follow-up pass (2026-11-15, not deployed, not checked on a device):
    - Every animal subcollection, `managementLogs` included, is readable only by the owning org's staff and carers and platform staff.
    - Storage `animalRecords/{id}/…`: `images/` stays readable by signed-in users. `medicalDocs/`, `careUpdates/` and `doseMedia/` are readable only by that animal's staff and carers, and only its own org's staff can upload medical files.
    - `users/{uid}` subcollections now belong to that user. Exceptions: `notifications` (backend writes, the user marks them read), `volunteerRegistrations` (the event org's staff mark attendance) and `collarTags` (staff toggle QR).
    - The dashboard's collection-group reads (`vaccinations`, `careRecords`, `medications`, `medicationDoses`, case `expenses`) filter on `organizationId` (`OrgListScope`, `lib/core/utils/org_list_scope.dart`). New triggers in `functions/audit_logs.js` stamp it from the parent and restamp when the parent changes organization. These rules also covered direct reads, so other orgs' staff could read those records before.
    - Donor records (`donations`) are readable only by the donor and the campaign organization's staff. `stampDonationOrganization` copies the campaign's org onto each donation.
    - Each org gets a permanent General fund (`campaigns/general_{orgId}`, created on first use by `ensureGeneralFund` / `recordOfflineDonation` with `generalFund: true`). Donations admin → menu → "Record donation". It can't be closed or deactivated.
    - Analytics → Donations shows funds by campaign, spending by category and spending by animal. Allocations now carry `organizationId`.
    - Analytics has a new Volunteers tab: events held, sign-ups, attendance rate, returning volunteers, attendance by month, and most events attended.
    - Release order: deploy functions and `firestore:indexes`, run `node scripts/backfill_log_organization_ids.js --project=respawnd1-45021` (dry run, then `--apply`; it now also covers the medical records, case expenses, donations and allocations), ship the app build, then deploy `firestore:rules` and `storage`. Older builds lose the dashboard health/medication/expense alerts and donation lists once the rules are live.
  - Cases and users lock (2026-11-15, not deployed, not checked on a device):
    - `cases/{id}` is readable by approved organization staff (any org, since the review pool, referrals and transfers are shared) and platform staff, the reporter, the willing adopter, the transporter holding or offered it, the rider sent to verify it, verified transporters (`isVerified`) and approved rescue volunteers (`volunteerApplications/{uid}.status == 'approved'`), and anyone for a report open to Community Adoption (rejected as `healthyAnimalLowUrgency`, not a lost pet).
    - Everyone else reads `publicCases/{id}`, written by the new `syncPublicCase` function (`functions/public_cases.js`). It has no reporter name or phone, no rider location, no notes, no verification evidence and no status history. Surrender reports leave out the address and round the location to about 100 m. The Explore map and feed, Nearby Reports, nearby notifications, geofences, the transporter job board list, sighting submission and the group-sibling lists read it. Track Case and push routing fall back to it for people not working the case (`lib/core/utils/case_access.dart`).
    - A case's `activityLogs` are readable only by the people working the case. The community-claim update now only works on a report open to Community Adoption; before, any signed-in user could close any case that way.
    - `users/{uid}` is readable by its owner, approved organization staff, platform staff, and members of the same organization.
    - Release order: deploy functions and `firestore:indexes` (new `publicCases` status + createdAt index), run `node scripts/backfill_public_cases.js --project=respawnd1-45021` (dry run, then `--apply`), ship the app build, then deploy `firestore:rules`. Older builds lose the Explore map and feed, Nearby Reports and the job board once the rules are live.
  - Staff scoped to their own organization (2026-11-15, not deployed, not checked on a device):
    - Cases: staff read their own organization's cases, the unowned review pool (`organizationId == ''`) and every `referred` case (the referral target wasn't recorded on the case; since `dd27fb6` only the target organization sees it, see Defense gap fixes). Every case now carries `organizationId`: new reports write `''`, `stampCaseOrganizationDefault` (functions/audit_logs.js) covers older builds, and the backfill sets `''` on existing ones. Staff lists merge those three queries (`RescueCaseQueryRepository.watchScopedCaseDocs`).
    - Lookups that span organizations read `publicCases`: duplicate detection, the reporter's track record, old grouped submissions, and a transporter's trip counts. Merging a duplicate that belongs to another organization now fails with a message.
    - Transport offers and adoption follow-ups carry their parent's `organizationId` (stamp/restamp triggers); staff queries filter on it. Assign Transporter's Available/Pending/Busy and the dashboard transport counts read `users/{uid}.transportStatus`, kept by the new `syncRiderTransportStatus` function (functions/rider_status.js). Users can't write it.
    - Release order: deploy functions and `firestore:indexes` (new cases, transportAssignments, followUps and publicCases indexes), run `node scripts/backfill_log_organization_ids.js --project=respawnd1-45021` (now also sets `''` on unowned cases and stamps offers and follow-ups), `node scripts/backfill_public_cases.js` (adds trip-completion fields) and `node scripts/backfill_rider_status.js`, each as a dry run then `--apply`, ship the app build, then deploy `firestore:rules`. Older builds lose every staff case list, the stale-offer and follow-up alerts and the transporter chips once the rules are live.
- **Rules not deployed yet (needs a coordinated release):** the adoptions read lock and readiness gate in `firestore.rules`. The `hasBlockingAdoption` callable (`functions/adoptions.js`) is deployed. App builds from before this change query adoptions without an organization filter and check availability client-side, so they break once the lock is live. Next: ship the new app build, then `firebase deploy --only firestore:rules`.
- Adoption applications with no `organizationId` (from animals that had none) are readable only by their adopter and platform staff after the lock.
- `users` and `cases` are still readable by any signed-in user (public case map, profiles). Admin-only case actions are enforced in the app only.
- Public animal profiles: the hide flag filters the adoption list and the organization page, but the animal document itself is still readable by any signed-in user.
- Missed medication doses show on the animal's Medical tab, not in the dashboard alerts (would need a collection-group index on dose dates).
- NFC tags for animals are not implemented. QR tags are.
- Volunteer referral is a stub ("coming soon"), kept as is.
- Rules tests: `cd rules-tests && npm test` (92 passing; needs Java 21, Android Studio's `jbr` works as `JAVA_HOME`).
- Function deploys need `functions/.env` with `PAYMENT_RETURN_BASE_URL=https://respawnd1-45021.web.app` (gitignored) and the `FB_APP_ID`/`FB_APP_SECRET` secrets (set).

### Done since the interview plan
- **P0:** reporters file unowned reports only; storage staff checks match Firestore; adoption reads locked to adopter, owning org and platform staff (not deployed yet).
- **P1:** readiness snapshot on accept; `verifying` status (records the verifying org); medication orders with carer dose logging (photo optional, confirm step); `carer` org role in rules, invite sheet and a carer-only care-tasks home screen; readiness gate enforced in rules.
- **P2:** volunteer applications (form on the Volunteer page, review from the admin Volunteers page); public-profile hide flag; restricted donations were already enforced in the backend.
- **P3:** QR tags assigned on the animal profile and opened by the app's scanner; overdue preventive care in the dashboard alerts; demo coordinates are debug-only; the home "Coming soon" tile is an intentional feature flag.

## Other notes

- **`analysis_options.yaml`.** There's an uncommitted `analyzer.exclude` block for `build/`, `android/`, `ios/` and `web/` that was already in the working tree. It's harmless, but check whether it's meant to be committed.
- **Node version.** Local Node is v20.12.2, but `functions/package.json` asks for 22. That only matters for emulators or deploying from this machine. Every file in `functions/` passes `node --check`.
- **Device logs.** The `I/flutter` lines mentioning Shorebird or MarketKit come from another Flutter app on the test phone, not from respawnd1.
- **Git warnings.** The "LF will be replaced by CRLF" messages are harmless with `core.autocrlf=true`.
