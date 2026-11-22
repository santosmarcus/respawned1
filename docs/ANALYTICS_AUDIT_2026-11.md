# Analytics audit (Phase 0 of RESPAWND_ANALYTICS_PLAN.md)

Prepared 22 Nov 2026 from branch `dev` at `ddb477c` (one local commit on top of `origin/dev` `70cfd3e`; that commit doesn't touch analytics). Read-only: no code was changed for this audit.

---

## 0. Plan assumptions that don't match the code

Read these first. Several plan steps are written around them.

| Plan says | The code has |
|---|---|
| Four analytics tabs (Rescue, Adoption, Donation, Shelter) [MEM] | The admin home has **two tabs**, `Today` and `Analytics` (`lib/features/adminhome/dashboard/adminhome_screen.dart:28`). **Today** (`today_view.dart`) has sections *Priority actions* (:116), *Rescue* (:324), *Shelter care* (:503), *Adoption* (:598) and *Donations & funds* (:845). **Analytics** (`analytics_view.dart:180`) is one scrolling column of question cards, listed below. |
| Executive Overview with hard-coded placeholders [MEM] | There is no "Executive Overview" anywhere in `lib/`. Grepping for literal numbers in the dashboard found none apart from menu labels. `lib/features/adminhome/admin_dashboard_home_widgets.dart` (`TopMetricsRow` :509, `CurrentOperationsSection` :576, `ActionRequiredSection` :186) is not used by any screen; only `staleTransportOffersProvider` from it is imported. This is probably the old overview. It is dead code, not placeholders on screen. |
| Build a period filter (2.1) | It already exists. `AnalyticsRange` (`analytics_range.dart:21`) offers last 30/90/365 days, a calendar month, a quarter or a custom range. It has a previous-period comparison (`Period.previous`) and the `AnalyticsPeriodButton` (`analytics_view.dart:230`). |
| Build CSV export (3E) | It already exists. `analytics_export.dart` exports CSV through `share_plus` (`_shareCsv` :267), a PDF (`_buildPdf` :143) and a monthly report (:319). There is also `financial_report_export.dart`. |
| Add daily snapshots (2.4) | A **monthly** snapshot already exists. `writeAnalyticsSummaries` runs on the 1st at 02:00 Manila (`functions/dashboard_ops.js:142`) and writes `organizations/{orgId}/analyticsSummaries/{yyyy-MM}` (`functions/analytics_summary_rules.js`, version 1). The "Month by month" card reads it (`analytics_view.dart:1399`). There is no daily snapshot. |
| Add `shelterCapacity` to the org | `maxCapacity` and `isolationCapacity` already exist in the shelter settings (`shelter_settings.dart:72-73, 110, 158`). Occupancy is calculated in one place (`lib/core/utils/shelter_occupancy.dart`). There is no treatment or clinic capacity. |
| Rules already in place: "no data" is not 0, small groups, medians | Already the house rule. The `analytics_view.dart:44-47` header says "missing data is excluded and counted, never treated as zero; every rate states its population; groups under kMinGroupSize are flagged". `kMinGroupSize = 10` (`dashboard_data.dart:427`), not the plan's 5. |
| `groupId` dedup for multi-animal cases | Multi-animal cases keep their animals in `animals[]` on one case document. `groupId` is only read for older linked cases (`lib/features/admin/rescue/widgets/case_animals_card.dart:57`), and nothing writes it today. |
| `claude/RESPAWND_FEATURE_PLAN.md` (F4–F7) | That file is not in this repository. Neither is `docs/` (this audit creates it). |

**Existing Analytics cards** (`analytics_view.dart`), each built on `computeOutcomes` (:104) over animal records and cases:

| Card | Line |
|---|---|
| Are we saving more lives? | 365 |
| Where did animals go? | 606 |
| How fast do animals find homes? (medians: stabilise, ready, adopted) | 737 |
| Who waits longest? | 939 |
| Could animals stay home or outside? | 1058 |
| Are animals protected from illness? | 1176 |
| End-of-care decisions (restricted) | 1316 |
| What we're improving | 1679 |
| Month by month | 1415 |
| Area reports (`area_reports.dart`; the only `fl_chart` user) | — |

The header (:31-42) maps these cards to the 12 Lifesaving Ingredients. Several plan metrics are already partly covered:

| Plan metric | Covered by |
|---|---|
| A1 (time to adoption) | *How fast* |
| A2 (long stays) | *Who waits longest* |
| A8 (live release rate) | *Are we saving more lives* |

**What this means:** most of Phase 2 (period, export, rendering rules) already exists. The work is adding cards to the existing Analytics column, or to Today's sections, and filling the data gaps below.

---

## 1. Case statuses and timestamps

**Statuses:** `RescueStatus` (`lib/core/models/rescue/rescue_status.dart`) has these values:

| Group | Statuses |
|---|---|
| Review | `pendingReview`, `accepted`, `awaitingAssignment`, `rejected`, `referred`, `possibleDuplicate`, `merged` |
| Under way | `ongoing` (covers `assigned`, `searching_clinic`, `arrived`, `in_transit_shelter`, `dropoff`), `treatment`, `intake`, `verifying` |
| Finished | `completed`, `cancelled` (used as the closed state, with `closureReason`) |
| Transporter end-reason holds | `unableToLocate`, `awaitingReporterResponse`, `pickupUnsuccessful`, `needsSpecializedAssistance`, `transitEnded` |
| Pet Surrender (new in ddb477c) | `communityAdoption`, `withdrawn` |

**Timestamps written on the case document:**

| Event | Field | Written at |
|---|---|---|
| Reported | `createdAt` | report submit (`rescue_report_service.dart`) |
| Accepted by org | **none on the case**; only an `activityLogs` entry `accepted` with a timestamp | `case_status_repository.dart:36-79` |
| Rejected | **none on the case**; `rejectionReason` plus activityLogs `rejected` | `case_status_repository.dart:88-112` |
| Transporter accepted | `transportAssignments/{id}.acceptedAt` | `transport_assignment_repository.dart:428` |
| Admitted to clinic | `dateAdmitted` | `transport_assignment_repository.dart:780`, `admin_track_case_page.dart:275` |
| Transporter handover to clinic | `treatmentAcceptedAt` (when the step completes transit) | `transit_case_service.dart:149` |
| Transit completed | `transitCompletedAt` | `transit_case_service.dart:347` |
| Vet clinic chosen | `vetClinicSelectedAt` | — |
| Per-animal discharge / death | `animals[i].dischargedAt` / `deceasedAt` (+ `outcome`) | `treatment_log_repository.dart:190, 200, 227` |
| Per-animal intake done | `animals[i].intakeCompletedAt` | `case_intake_repository.dart:650` |
| Intake confirmed / received | `intakeConfirmedAt`, `intakeReceivedAt` | `case_intake_repository.dart:688+` |
| Referred | `referral.referredAt` | `case_referral_repository.dart:90` |
| Closed | `closedAt` + `closureReason` | `case_status_repository.dart:565-589` |
| Quarantine | `quarantineStartedAt`, `quarantineScheduledEndAt`, `quarantineEndedAt` | — |

**History:** there are two, and both are already written by every case action through `RescueCaseStore.recordAction` / `recordActionIn` (`rescue_case_store.dart:74-143`):

- `statusHistory`: an **array on the case**, `{status: <reporter-facing sentence>, timestamp}`. It is free text, not a from/to status, so it isn't usable for analytics.
- `cases/{id}/activityLogs`: a subcollection, `{action, actorUid, actorName, actorRole, details, timestamp}` (`activity_log_entry.dart`). The `action` values are stable machine names, for example:

  | Area | Actions |
  |---|---|
  | Review | `accepted`, `rejected`, `merged`, `referred_to_organization`, `referred_to_volunteer`, `referral_withdrawn` |
  | Transport | `transporter_accepted`, `transporter_declined`, `transporter_claimed`, `organization_transport_started`, `organization_delivered_to_shelter` |
  | Clinic and treatment | `assigned_clinic`, `treatment_started`, `treatment_update` |
  | Intake and release | `intake_confirmed`, `intake_completed`, `released_to_adopter`, `released_to_reporter` |
  | Closing | `closed_deceased`, `case_closed` |

  The full list is in `grep -rhoE "action: '[^']+'" lib`.

**Gap:** `activityLogs` is effectively the plan's proposed `statusHistory` subcollection already (it has an actor, a time and an action), just keyed by action instead of from/to status. The missing pieces are typed timestamps on the case for **accepted** and **rejected** (`acceptedAt`, `rejectedAt`), which response-time metrics need without reading every log. Recommendation: add those two fields in `acceptCase` / `rejectCase`, and get earlier dates from `activityLogs` where present instead of guessing.

## 2. Referral and end reasons

| Path | How it's stored |
|---|---|
| Another organization | status `referred`, `referral{targetOrgId, referredAt, previousStatus, …}`, `cases/{id}/referrals/{id}` with `ReferralType.anotherOrganization`; outcome accepted / declined / withdrawn / expired (`referral_type.dart`, `case_referral_repository.dart:60-100, 140-200`) |
| Rescue volunteer | `ReferralType.rescueVolunteer`, action `referred_to_volunteer` |
| Barangay / LGU (non-rescue) | `ReferralType.localGovernmentUnit`, status `notified`, reason from `LguReferralReason` (`outsideServiceArea`, **`shelterAtCapacity`**, `nonRescueConcern`, `animalControlRequired`, `publicSafetyConcern`, `ownerDispute`, `other`) (`referral_type.dart:35-42`; created by link at `case_referral_repository.dart:331`) |
| Declined, at capacity | rejection reason **`noShelterSpace`** (`rejection_reason.dart:7`); also `noAvailableRiders` (:5) |
| Community adoption | rejection reason `healthyAnimalLowUrgency` (the case goes to Community Adoption); Pet Surrender is now status `community_adoption` from the start |
| Closed | `closureReason` from `ClosureReason` (`closure_reason.dart`): `requiresTransport`, `died`, `aggressive`, `reunited`, `rescuedOutsideWorkflow`, … |
| Transporter end reason | `endReason` on the case from the transit flow (`functions/dashboard_ops.js` around :95 reads `after.endReason`) |

**Gap:** a referral to an organization or volunteer stores **no reason**; only LGU referrals do. So "referred because of capacity" is split between rejection `noShelterSpace`, LGU `shelterAtCapacity`, and org referrals (no reason at all). R1 can be calculated today from these fields. R2 (capacity share) needs a reason on organization and volunteer referrals too. Recommendation: reuse the `LguReferralReason` choices.

## 3. Who did the rescue

- **Pet transporter or rescue volunteer:** `cases/{id}/transportAssignments/{id}` (`transport_assignment.dart:53-70`) holds:
  - `riderId`, `riderName`, `riderType` (transporter or volunteer)
  - `status`: `pending`, `accepted`, `rejected`, `cancelled`, `completed` or `expired` (:9-15)
  - timestamps: `offeredAt`, `expiresAt`, `respondedAt`, `acceptedAt`, `rejectedAt` (+ `rejectionReason`), `completedAt`, `cancelledAt`
  - `isDemo`, `vehicle`, `plate`

  Expired offers are set by `expireTransportOffers` (`functions/index.js:864`). The case keeps `riderId` / `assignedVolunteerId` and `currentAssignmentId`. Older direct claims have `riderId` and no assignment (action `transporter_claimed`).
- **Organization staff:** `organizationTransport{byUid, byName, startedAt}` on the case, plus actions `organization_transport_started` / `organization_delivered_to_shelter` (`transport_assignment_repository.dart:705-720`).

R3 and R4 can be calculated from existing data. For R5, a case where every offer was declined or expired can be derived. "Nobody in range" is **not stored**: the Assign Transporter list is computed on screen (`assign_rider_page.dart`). The closest stored signal is rejection reason `noAvailableRiders`.

## 4. Treatment

- **In treatment** = case status `treatment` (raw values in `RescueStatus` aliases), with `dateAdmitted` / `treatmentAcceptedAt` as the start.
- **Leaving treatment** is recorded per animal: `animals[i].dischargedAt` or `deceasedAt` + `outcome` (`treatment_log_repository.dart:146-227`). `postTreatmentStartedAt` marks the next step.
- **After treatment**, the animal goes on to one of these:
  - intake to the shelter (`intake_assigned`, `intakeCompletedAt`)
  - adopter pickup (`ready_for_adopter_pickup`, `adopterPickupConfirmedAt`)
  - back to the reporter (`released_to_reporter`)
  - another org (`transferred_animal`, `transferredAt`)

All of R6–R8 can be calculated per animal from these fields. A treatment-load trend needs snapshots (see 2.4).

## 5. Capacity

`organizations/{orgId}` shelter settings (`shelter_settings.dart:110`):

- `maxCapacity`, `isolationCapacity`, `monthlyBudget`, `foodPerDayKg`, `ridersNeeded`
- `acceptingCases` (with `acceptingCasesChangedAt`)

**There is no treatment or clinic capacity field** (Decision 1).

## 6. Animal records

`animals/{id}` (`animal_record.dart`):

- **Intake time** is `createdAt`. Older records used `intakeDate`, which is still read (:383-425).
- Lifecycle fields:
  - `status`, `adoptionStatus` (`not_ready` / `adoptable` / `reserved` / `adopted`), `careStatus` (`in_shelter` / `isolation` / `recovering`, :67)
  - `readyForAdoptionAt` (`create_animal_record_page.dart:1106`), `reservedAt`, `adoptedAt`, `returnedAt`, `deceasedAt` + `deceasedCause`, `archived`
  - `linkedCaseId`, `sourceAnimalIndex`
- **Occupancy** is classified by `isCurrentlyHoused` (`shelter_occupancy.dart`).
- Status changes are logged in `animals/{id}/managementLogs`.

## 7. Adoption

`adoptions/{id}` (`adoption_application.dart`):

- **Statuses:** `pending`, `interview`, `approved`, `adopted`, `rejected`, `withdrawn` (:18-23)
- **Timestamps:** `createdAt` (submitted), `appointmentDate`, `interviewCompletedAt`, `noShowAt`, `fitAssessedAt`, `approvedAt`, `rejectedAt`, `reservedAt`, `adoptedAt`, `scheduledReleaseDate`, `releasedAt` (handover), `postAdoptionCompletedAt`, `withdrawnAt` (:116-168)
- **"Listed"** = the animal's `readyForAdoptionAt`. It is only stamped when readiness is set from the record page; older animals may lack it, and the *How fast* card already falls back to other dates.
- **Community adoption** (not shelter animals): `communityAdoptionRequests`, `communityAdoptionCheckIns`.

## 8. Post-adoption check-ins

- **Storage:** `adoptions/{id}/followUps/{id}` (`follow_up_record.dart`) holds `sequenceNumber`, `scheduledDate`, `status` (`scheduled`, `reminderSent`, `submitted`, `confirmed`, `completed`, `cancelled`), `reminderSentAt`, `submittedAt`, `confirmedAt`, `completedAt` (+ `manualCompletionReason`), and rescheduling fields. The adopter's answers are in `adoptions/{id}/checkins/{same id}`.
- **The schedule** comes from `FollowUpScheduleRule` set at release (`follow_up_schedule.dart:74`), so intervals are org-configurable rather than fixed.
- **"Overdue"** is never stored. It is computed as a past `scheduledDate` with status `scheduled` or `reminderSent` (`follow_up_record.dart:91-100`).
- **Reminders:** `sendFollowUpReminders` runs daily at 08:00 Manila (`functions/index.js:1247`).

A3 can be calculated from existing data with a `followUps` collection-group query.

## 9. Returns

- **Storage:** a `returnRequest` **map on the adoption document**, not a separate collection (`return_request.dart:3-7`).
- **Fields:** `reason` (**fixed choices**), `reasonOther`, `urgency`, `explanation`, `requestedAt`, `status` (`pendingReview` … `retrieved`, `intake`, `declined`, `cancelled`), `retrievedAt`, `proceededToIntakeAt`, `intakeCaseId`. The animal gets `returnedAt`.
- **Current reason choices** (`post_adoption_page.dart:1797`):
  - Financial Difficulties
  - Housing Restrictions
  - Allergies or Health Concerns
  - Conflict with Existing Pets
  - Behavioral Challenges
  - Change in Personal Circumstances
  - Other (+ text)

These already map closely to the plan's eight categories. The differences:

- The plan splits "Animal's health" from allergies.
- The plan has "Not enough time", where the code has "Change in personal circumstances".

Decision 3 is whether to keep these seven choices (no form change, stored answers stay comparable) or change them.

## 10. Interaction signals

| Signal | Status |
|---|---|
| Profile views | **Not stored anywhere.** |
| Favourites | Persisted per user, at `users/{uid}/favorites` (`adoption_page.dart:327-334`, `favorite_screen.dart:48`). Only that user can read them under the rules, so the org can't count saves without a new counter. |
| Shares | `share_plus` is used for staff sharing (Facebook share pages, referral links, exports). There is no public "share this animal" counter. Facebook shares are logged in `facebookShares`. |
| Application source | **No `source` field** on adoption applications. |

A6 and A7 need new data (Decision 4).

## 11. Finance

| Area | What exists |
|---|---|
| Donations | `donations/{id}` (`donation_model.dart:56-98`): `type` (`donation` / `sponsorship` / `inkind`), `status`, `source` (**`paymongo` / `manual`**: the manual flag D8 needs), `method`, `paymentId`, `campaignId`, `generalFund`, `quantityReceived`, refund and reversal fields. PayMongo payments: `donationPayments`. |
| Case expenses | `cases/{id}/expenses` (`expense.dart:167-230`): `category` (`ExpenseCategory`: consultation, medication, procedure, laboratory, vaccination, confinement, transport, foodAndSupplies, utilities, rent, staffCompensation, administrative, other), `fundings[]` with `FundingSource`, `animalIndexes` (per animal on the case), `incurredAt`, `approvalStatus`. |
| Org-wide expenses | `organizations/{orgId}/orgExpenses` (`general_expenses_page.dart`). |
| Running vs paid | **No paid/unpaid or running-bill field** on expenses. The only "paid" is a PayMongo payment status. |
| Cash-outs, allocations, transfers | `organizations/{orgId}/cashOuts` (`cash_out.dart:45-55`), `campaigns/{id}/allocations` (spending records), `fundTransfers`. |
| In-kind | Donations with `type: inkind` feed `organizations/{orgId}/stock`. Every change is logged in `stockMovements` with `kind`: `opening` / `received` / `purchased` / **`used`** / `correction` (`stock_service.dart:1-30, 135-145`). **Usage is already logged**, so D5 can be calculated (Decision 5 is mostly answered). |
| Campaigns | `targetAmount`, `collectedAmount` (`lib/features/donation/models.dart:330-371`). |
| Sponsorships | `sponsorship.dart`, plus the funded/open status added in 70cfd3e. |

## Other checks

- **`isDemo`:** only on transport assignments, transporter profiles and the transporter's acceptance into a case (`case_intake_repository.dart:763`). Cases, animals, adoptions and donations have no demo flag.
- **Indexes:** `firestore.indexes.json` has 39 composite indexes. Existing analytics loads org-scoped lists and filters on the client (`analyticsCasesProvider` :165 merges the dashboard snapshot with closed cases; the functions load by `organizationId` only, `dashboard_ops.js:117-130`). This fits the plan's "one range query plus client filtering" rule.
- **Aggregates:** neither `.count()` nor `AggregateQuery` is used.

---

## What each metric needs (summary)

| Metric | Can be calculated now? | Missing |
|---|---|---|
| R1 referral rate | Yes (referral, rejection reason, LGU reason, closure) | — |
| R2 capacity share | Partly | Reason on organization and volunteer referrals |
| R3 transport rate | Yes | — |
| R4 transporter acceptance | Yes | — |
| R5 no transporter | Partly (all offers declined or expired; `noAvailableRiders`) | "Nobody in range" event |
| R6 treatment load | Live yes; trend no | Decision 1; daily snapshot |
| R7 / R8 treatment exits and duration | Yes, per animal | — |
| R9 response time | Partly | `acceptedAt` on the case (logs for older cases) |
| R10 intake and resolution | Yes | — |
| A1 intake to adoption | Yes (partly shown already) | — |
| A2 length of stay | Yes (partly shown already) | — |
| A3 check-in response | Yes | — |
| A4 / A5 success and returns | Yes | Decisions 2 and 3 |
| A6 / A7 engagement and source | No | View, save and share counters; `source` field (Decision 4) |
| A8 live release, adoption to intake | Yes (live release shown already) | — |
| D1, D6, D8 | Yes | — |
| D2 running vs paid | No | A paid/unpaid field on expenses |
| D3 funds flow | Yes (donations, cashOuts, allocations, expenses) | — |
| D4 / D5 in-kind | Yes (`stockMovements`) | — |
| D7 cost per animal | Yes, for case expenses (`animalIndexes`); org expenses aren't per animal | — |
| Shelter occupancy | Live yes (`maxCapacity`); trend no | Daily snapshot |

## Decisions, updated with what the code shows

1. **Treatment denominator:** there is no treatment capacity field. Option (a) uses the existing `maxCapacity`. Option (b) needs a new `treatmentCapacity` setting next to it in `shelter_settings.dart`.
2. **Success window:** check-in schedules are org-defined rules, not fixed. Use a day window (default 90), or "after the last scheduled follow-up".
3. **Return reasons:** keep the seven existing choices (`post_adoption_page.dart:1797`) and only add the retention-support mapping in analytics, or replace them with the plan's eight. Replacing them makes older answers need a mapping.
4. **View tracking:** nothing exists. Approve the per-animal daily counters, or start the funnel at Applied.
5. **In-kind usage:** already logged (`stockMovements.kind == 'used'`). No new stock log is needed; confirm D5 should use it.
6. **Public KPI summary:** unchanged from the plan.
7. **New: where the new cards go.** There are no module tabs. Add the cards to the existing Analytics column (grouped by module), or turn Analytics into module tabs. The second is a visual change the ground rules forbid without approval.
8. **New: the unused `admin_dashboard_home_widgets.dart` widgets.** Delete them, or leave them alone.
9. **New: small-group threshold.** The app already uses `kMinGroupSize = 10`; the plan says 5. Keep 10 for consistency, or change it everywhere.
