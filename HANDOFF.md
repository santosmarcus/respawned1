# Handoff: build fixed, analyzer clean

_Branch: `marcus` (base `a899293`, merged from `dev`) · 2026-11-04_

## Status

- **The app builds.** `flutter analyze` reports **no issues** (down from 301), and `flutter test` passes **87/87**. `assembleDebug` succeeds.
- **Nothing is committed.** All changes are in the working tree, about 115 files.
- **Not yet checked on a device.** See [Manual test checklist](#manual-test-checklist).

## What was done

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
- **Access-control pass (not deployed yet, needs the same coordinated release):**
  - Animal medical subcollections (`medications`, `medicationDoses`, `vaccinations`, `careRecords`, `careUpdates`, `medicalEpisodes`) are readable only by the owning org's staff, its carers and platform staff. The animal doc itself stays readable.
  - `donations` is readable only by the donor and staff. The public donor count now reads `campaigns/{id}.numdonors`, and the organization profile's Donations tab now lists the org's campaigns (it was listing raw donation records).
  - Case `expenses` are written only by financial admins of the owning org (or a platform `admin`). Other staff see them read-only; transporters and reporters can't read them.
  - Audit Rescue/Records tabs query by `organizationId`. The new `stampCaseLogOrganization` / `stampAnimalLogOrganization` functions (`functions/audit_logs.js`) stamp each new log from its parent.
  - Release order: deploy functions and `firestore:indexes`, run `node scripts/backfill_log_organization_ids.js --project=respawnd1-45021` (dry run, then `--apply`), ship the app build, then deploy `firestore:rules`. Older app builds lose the public donor count, the org profile Donations tab and the two Audit tabs once the rules are live.
  - Still open: dashboard collection-group reads (`vaccinations`, `careRecords`, `medications`, `medicationDoses`, `expenses`) are staff-wide across organizations, and medical photos in Storage (`animalRecords/{id}/careUpdates`, `doseMedia`) are still readable by any signed-in user who knows or lists the path.
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
