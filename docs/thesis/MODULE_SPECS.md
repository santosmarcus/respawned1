# ResPAWnd: module specifications (as built)

Prepared 23 Nov 2026 from branch `dev` at `74ea496`. It was then updated for `origin/dev` @ `e9ec5e8`, which isn't pulled locally yet; that commit changed analytics, donation campaigns for animals in treatment, and case expenses. It describes what the code does, not what the proposal planned. Use it as the source for Chapter 5 ("The Proposed Solution") and for any chapter that explains how a module works. `CHAPTER5_REVIEW.md` compares this file with the current Chapter 5 draft.

## How to read the rule tags

Every business rule below has one tag. Nothing here was invented: each rule points to a chapter section or a source file.

| Tag | Meaning | Where it comes from |
|---|---|---|
| **[Existing]** | The partner organization's current practice, before the app | Chapter 4 (§4.2) and the interview |
| **[Built]** | A rule the app enforces now | The code. No written sign-off from the organization was found in the repository, so call these "implemented by the system", not "approved by the organization". |
| **[Built, needs approval]** | The app enforces it, but the code says the number or policy is *"pending the organization's confirmation"* | Code comments, listed in §12 |
| **[Not built]** | Planned in Chapter 1 or Chapter 5, or listed as a gap, but not in the app | Chapters 1/5 and `docs/defense/resPAWnd_Defense_Scenarios.txt` Part 4 |

**Deployment status.** `HANDOFF.md` marks most work from 20–22 Nov 2026 as "not deployed, not checked on a device". The paper can say these features are implemented and covered by automated tests. It should not say they were validated on a device or in the field. See §13 for code issues that affect what can be claimed.

---

## 1. User Management and Authentication

### 1.1 Purpose
- Create accounts.
- Confirm identity: email link and mobile SMS.
- Give each person a role.
- Send each role to its own home screen.

### 1.2 Sign-up and sign-in
1. **Ways to sign in:**
   - Email and password (`lib/core/repos/auth_service.dart:109-152`)
   - Google (`:209-229`)
   - Mobile number with an SMS one-time code (`:232-283`)
2. **Email is confirmed by a link, not a code.** The Verify Email screen checks every 5 seconds and tells the user to open the link (`lib/features/userauth/verify_email_screen.dart:35,55`). Google accounts skip this step (`auth_service.dart:157`).
3. **Every account must confirm a mobile number by SMS** on "Your Details" (`details_screen.dart:124-136`). People who sign up by phone must also add an email and password (`:139-185`).
4. **One mobile number and one email per account.** Firebase Authentication allows a phone number on only one account. The `checkSignUpPhone` callable adds a check at sign-up, but see §13.1. [Built]
5. **Password recovery** is by a reset email (`forgotpass_screen.dart:51`).
6. **Account deletion:** Profile → Delete account calls `deleteMyAccount` (`delete_account.dart:32`).
   - Reports are de-identified, and finance records are kept.
   - An org owner or an org's only Admin cannot delete their account.

   The design is in `functions/account_deletion.js`, but the module is not currently loaded (§13.1).

### 1.3 Roles
The role is chosen in onboarding (`lib/features/userauth/onboard_screen.dart:40-77`).

| Shown as | Stored `users.role` | Goes to |
|---|---|---|
| General User | `general` | User home |
| Pet Transporter | `pet_transporter` | Transporter verification, then the transporter shell |
| Rescue Volunteer | `organization` + `signupKind: 'independent'` | Volunteer application (a small organization, see §1.6) |
| Organization Admin | `organization` | Organization registration and verification |
| Organization Member | `organization_member` | Joins an organization by invitation |

These roles are not offered in onboarding:
- `system_admin` is set in the Firebase console (`main.dart:323-326`).
- `admin` / `ngo_staff` are platform staff (`firestore.rules:87-89`).
- The old `rescue_volunteer` role is still routed into the transporter flow (`main.dart:330-343`).

Routing is done by `AuthWrapper` (`lib/main.dart:140-371`):
1. It checks the role.
2. It checks the organization's verification status.
3. It checks the member's permissions.

### 1.4 General user home
- **Bottom navigation:** Home, Notifications, My Profile (`lib/features/generalhome/home_screen.dart:72-85`).
- **Home:**
  - Explore map of nearby public reports (`:114`)
  - Quick actions: Report a Rescue, Adopt a Rescue, Donations & Sponsorships, Events (`:133-170`)
  - Activity feed: own reports, adoptions, lost and found alerts (`activity_feed.dart`)
  - Post Adoption
  - Sponsored Animals
  - A community adoption check-in prompt
- **Profile** (`user_profile.dart:148-239`):
  - Favorites, History
  - Certificates (donation certificates only)
  - Create Pet Collar Tag
  - Account, Edit account
  - Privacy → Location Sharing
  - Communications, Log out, Delete account

### 1.5 Pet transporter
1. **Verification form** (`lib/features/pettransporter/transporter_verification_screen.dart`):
   - Full name and mobile number
   - Driver's license front and back photos, and a portrait photo
   - Vehicle type: Motorcycle, Sedan, SUV, or Cargo Van/L300
   - License plate
   - How many animals the vehicle can carry safely (1–20, `maxAnimals`)
   - For motorcycles, whether it has an animal carrier
   - An optional anti-rabies record
2. **Saved** to `transporterApplications` with status `pending`. The user's `transporterVerificationStatus` is also `pending`.
3. **Who reviews** (`firestore.rules:1727-1745`): platform staff, a system admin, or organization staff with the `volunteers` permission. Approval sets `users.isVerified`. [Built]
4. **Service screen** (`service_screen.dart`):
   - **Online/Offline switch.** It saves `online`, `lastSeenAt` and the transporter's location.
   - **Service range** in km (default 10). It must be set before going online.
   - **Offers:** Start Now or Decline (with a reason).
5. **"Online"** means the switch is on and the transporter was seen in the last **10 minutes** (`lib/core/models/rescue/pet_transporter.dart:22`). [Built]
6. **Vehicle rules** (`lib/core/utils/transport_suitability.dart`): [Built]
   - Any registered vehicle can carry one animal.
   - Two or more animals need a declared capacity that covers all of them.
   - A motorcycle never carries more than one animal.
   - A motorcycle never carries an animal that needs an enclosed vehicle: Critical, large, cannot walk, unresponsive, serious injury, high bite or escape risk, or a mother with a litter.

The trip itself is described in §2.5.

### 1.6 Organizations, staff and rescue volunteers
1. **Organization registration:**
   - About screen: name, official contact number, address (`organization_about_screen.dart`)
   - Documents: SEC/DTI registration or business permit, permit or accreditation, shelter photos (`organization_verification_screen.dart:83-87`)
2. **Review** by the `reviewOrganization` callable. Only platform staff or a system admin can run it (`functions/index.js:2029-2036`).
   - Outcomes: approved, rejected, or requires changes.
   - Each decision is written to the audit log and sent to the organization as a notification. [Built]
3. **Organization roles:** `admin` and `staff` only (`lib/core/models/rescue/org_role.dart`). The old `carer` role is read as staff.
4. **Ten per-module permissions** (`functions/org_permissions.json`): `rescue`, `animals`, `care`, `adoptions`, `campaigns`, `financeView`, `financeManage`, `volunteers`, `insights`, `facebookPublish`.
   - The default Staff set is rescue, animals, care, adoptions, volunteers and insights.
   - Money permissions and Facebook posting are given by hand.
   - Only an organization Admin can change a member's permissions (`setMemberAccess`, `functions/org_members.js`). [Built]
5. **Staff join by invitation**, by email or phone (`organizationInvitations`; `organization_invitation_repository.dart`). Members are stored in `organizations/{id}/members/{uid}`.
6. **Rescue volunteers (independent rescuers).** In the code they are organizations with `kind: 'independent'`. The UI calls them "Rescue volunteer". [Built] The limits come from `functions/org_permissions.json`:
   - **Documents:** valid ID, proof of address, rescue history.
   - **Limits:** up to 5 members, 3 active cases and 5 animals in care. Their area is 1–5 km (default 3).
   - **Modules:** they may have rescue, animals, care, adoptions and insights. Rescue, animals and care are on by default. They get no donations or campaigns.
   - **Access to new reports:**
     - Shelters get a **15-minute head start** on non-critical reports. Critical reports open to independents right away.
     - The first to accept wins (`case_claim_rules.dart`).
     - Currently not working: see §13.1.
   - **Who reviews them:** system admins, or org staff with the Volunteers permission.

### 1.7 System admin console
`lib/features/systemadmin/system_admin_home_screen.dart` has four tabs, each with a pending count:

| Tab | What it does |
|---|---|
| Organizations | Approve, reject, or request changes |
| Volunteers | Approve independents, and set their modules and limits |
| Transporters | Review transporter applications |
| Users | Directory, with disable and delete |

The system admin cannot read cases, animals, medical records or finances (`firestore.rules:91-98`). [Built]

### 1.8 Not built
- A privacy notice or terms consent at sign-up. The only Terms and Conditions are in the adoption flow. [Not built]
- An automatic ban for abusive users. A system admin can disable an account by hand. [Not built]

---

## 2. Animal Reporting and Case Management

### 2.1 Purpose
- Take reports from the public.
- Check whether they are genuine.
- Let one organization (or rescue volunteer) take the case.
- Move the animal by transporter or staff to a clinic or the shelter.
- Track the case until intake or closure.

### 2.2 Existing practice [Existing] (Ch4 §4.2.1)
1. Reports arrive through Facebook and Messenger.
2. Staff ask the reporter for contact details, location and condition.
3. Staff message partner pet transporters near the location.
4. Urgent animals go to the nearest vet. Others go to the partner clinic.
5. Updates depend on the transporter sending messages.

### 2.3 Filing a report (reporter)
1. **Location.** The pin can be set three ways (`lib/features/rescue/rescue_page.dart:204-271`):
   - from the phone's GPS
   - by tapping the map
   - by searching an address

   The pin cannot be dragged. How the pin was set is saved as `pinSource` (gps / map / search).
2. **Rescue type** (`rescue_form_options.dart:310-338`): Pet Surrender, Lost Pet, Illness, Injury, Neglect or Abuse, Aggressive Animal. Each type adds its own questions:
   - visible signs
   - environment
   - neglect or abuse details
   - surrender details
3. **Media.** A rescue report needs at least 2 photos or videos (`rescue_page.dart:948-951`). A Lost Pet report needs 1 photo.
   - The app reads the time and GPS stored in gallery photos (EXIF; `lib/core/utils/photo_metadata.dart`).
   - It also saves how many items came from the camera and how many from the gallery, plus the phone's own position.
4. **Several animals per report.** Each animal has its own card, and collapsing a card keeps its answers (`rescue_form_controller.dart:195-198`). Each card asks for:
   - species, breed, sex, size, color
   - health and behavior answers, and injury
   - environment, bite and escape risk, visible signs
   - for females: litter or suspected pregnancy
   - for female dogs with a litter: puppy count, where the puppies are, how they look, how many need attention, and up to 3 photos

   A Lost Pet report covers one pet only.
5. **Urgency** is rated per animal by fixed rules (`lib/core/utils/urgency_assessment.dart`, version `rules-v1`). [Built]
   - **Critical** needs evidence of an emergency:
     - a red flag that isn't contradicted,
     - two severe signs,
     - or a severe sign backed by a functional sign from another answer.

     One severe answer alone is never Critical.
   - **Medium:** any severe or moderate sign, or not enough information.
   - **Low:** only minor signs and a complete assessment.
   - **Contradictory answers** count one level lower. Contradictions and missing answers set `needsStaffVerification`.
   - Photos are not analyzed.
   - The case gets the highest urgency among its animals.
   - Pet Surrender and Lost Pet get no urgency.
6. **Willing to help.** The form asks "Would you be willing to coordinate with the shelter to assist in the rescue?" Answering No requires a witness name and phone. This question is not asked for Lost Pet or Neglect or Abuse.
7. **Declaration of accuracy**, then submit.
8. **Where it is saved:**
   - Rescue and surrender reports go to `cases`.
   - Lost Pet reports go to `petAlerts` (`rescue_report_service.dart:353-370`).

### 2.4 Paths by type
| Type | What happens | Tag |
|---|---|---|
| Illness, Injury, Aggressive Animal | Organization review (§2.5) | [Built] |
| Neglect or Abuse | It goes to organizations like any other report. The reporter is also shown a guide and told to report to the barangay or police. A "report it yourself" path exists in the code but is never selected (`rescue_form_controller.dart:517-521`). | [Built] |
| Pet Surrender | It goes straight to `community_adoption` status, skipping organization queues and transporters. A reason is required. The pet stays with the owner. The owner can withdraw with a reason; the case becomes `withdrawn`, nothing is deleted, and open inquiries are declined. | [Built] |
| Lost Pet | Shared with the community in `petAlerts`. Lost and found alerts are matched by `functions/pet_matching.js` (not loaded now, §13.1). Collar tags are not part of the matching, but anyone who scans the owner's tag can message the owner (§7). Not handled by organizations. | [Built] |
| Nuisance or non-rescue concern | There is no separate intake category. "Non-rescue concern" is one of the reasons for an LGU referral (`referral_type.dart:58-76`). | [Built] |

### 2.5 Organization review (admin or staff with `rescue`)
1. **Who is notified.** The case is tagged to every approved organization whose service area covers the pin (default radius 10 km, `organization_repository.dart:123`), and their staff are notified. Nearby responders and users are alerted too (default 5 km, `geofence_config.dart:28`).
2. **Tabs:** Review, Assign, Ongoing, In Treatment, Intake, Rejected, Closed (`lib/features/admin/rescue/state/rescue_reports_providers.dart:317-381`).
   - Filters: search, urgency, species, date range, location, involvement.
   - Status filter: duplicate, merged, community adoption, withdrawn.
3. **Report Verification panel** (`report_verification.dart`):
   - It flags gallery photos, photos older than 2 days, photos taken away from the pin, and a phone far from the pin.
   - It shows the reporter's track record. Two or more false reports show a concern.
   - Staff record the result: confirmed remotely, ask for live proof (a new photo or video taken in the app, stamped with time and place), or needs a rider (a nearby rider checks the spot).
4. **Duplicates.** Check for Duplicates finds the same species within 1 km (`case_duplicate_repository.dart:19-37`).
   - Merge keeps the second report as `merged` and copies its details into the first. Nothing is deleted.
   - Merging needs the `rescue` permission, and is blocked if the other report belongs to another organization.
5. **Accept.** The report already is the case. Accepting sets the organization and the status `accepted_pending_clinic` in a transaction, and the first organization to accept wins (`case_status_repository.dart:36-88`). Rescue Readiness asks 7 factors: space, transport, care coverage, vet access, food & medicine, funds, continuing care. They are saved with the case but never block accepting. [Built]
6. **Reject.** A reason from a fixed list is required (`lib/core/models/rescue/rejection_reason.dart`): no available riders, healthy animal / low urgency, no shelter space, invalid or false report, animal already rescued, duplicate report, outside service area, insufficient information, other. [Built]
   - A stray rejected as healthy / low urgency becomes eligible for community adoption (§4.6).
7. **Refer:** to another organization, a rescue volunteer, or the LGU or barangay (`referral_type.dart`). A reason is required.
   - The receiving organization is reminded at **24 h**.
   - The case returns to the referring organization at **48 h**. [Built, needs approval]
   - An LGU gets a share link that stays open **30 days**. The LGU can answer "Will handle", "Can't take it" or "Needs more information". [Built, needs approval]
8. **Critical escalation.** If a Critical report is still unreviewed after **30 minutes**, every org admin covering it is alerted. Each organization can change this number (`functions/critical_escalation_rules.js`). [Built, needs approval]
9. **Destination.** Staff pick a vet clinic through a map or Places search, saved as `vetClinic*` fields (`clinic_assignment_repository.dart`). The status becomes Awaiting Assignment.
   - "Straight to shelter" uses the organization's saved shelter pin.
   - The app warns if the chosen clinic is closed.

### 2.6 Transport
1. **Assign Transporter** (`lib/features/admin/rescue/assign_rider_page.dart`). Each verified transporter is listed as Available, Pending or Busy, with their vehicle, capacity and suitability. Unsuitable transporters can't be picked. [Built]
2. **Offer timeout:** 5 minutes for Critical cases, 20 minutes otherwise (`lib/core/models/rescue/transport_assignment.dart:30-33`). `expireTransportOffers` runs every minute. [Built]
3. **Offer statuses:** pending, accepted, rejected, cancelled, completed, expired. A decline records a reason.
4. **After repeated failures**, staff choose:
   - Refer Case
   - Organization Will Transport, where staff drive the animal themselves (`startOrganizationTransport`)
   - Keep Waiting

   Reassigning cancels the previous offer.
5. **The trip** (`lib/features/pettransporter/transit_progress_page.dart`, `transit_rules.dart`):
   1. On the way to the pickup.
   2. Arrival is only accepted within **20 m** by road, or in a straight line if directions fail (`transit_rules.dart:26`).
   3. Verification photos, then the trip to the clinic, then arrival at the clinic.
   4. Treatment Accepted or Treatment Rejected (with a reason).

   The reporter and staff follow the trip on Track Case.
6. **When a clinic refuses**, the app searches for the next clinic at 5, 10, 20 and then 40 km, skipping clinics that refused. If none is found, the trip goes to the shelter. The shelter leg needs the organization's saved shelter pin.
7. **End Reasons at pickup** (`transit_rules.dart:154-359`):

   | End Reason | Case becomes |
   |---|---|
   | Animal not found | Unable to Locate Animal |
   | Reporter unreachable | Pickup Attempt Unsuccessful |
   | Too aggressive, or needs specialized transport | Needs Specialized Assistance |
   | Vehicle breakdown | Back to Awaiting Assignment |
   | Animal deceased, or Other | Transit Stopped — Needs Decision |

   If the reporter doesn't respond within 48 h, the case is cancelled automatically.

### 2.7 Case statuses
These are `RescueStatus` values in `lib/core/models/rescue/rescue_status.dart:16-64`:

| Group | Statuses (label) |
|---|---|
| Review | Pending Review, Verifying Location, Accepted, Awaiting Assignment, Rejected, Referred, Possible Duplicate, Merged |
| Under way | Ongoing, In Treatment, Intake |
| Transport holds | Unable to Locate Animal, Awaiting Reporter Response, Pickup Attempt Unsuccessful, Needs Specialized Assistance, Transit Stopped — Needs Decision |
| Pet Surrender | Community Adoption, Withdrawn |
| Finished | Completed, Cancelled (with `closureReason`) |

"Ongoing" covers the transport sub-statuses:
- `assigned`
- `ongoing`
- `arrived`
- `treatment` (picked up)
- `dropoff`
- `searching_clinic`
- `in_transit_shelter`
- `awaiting_adopter_pickup`

### 2.8 Treatment and the end of a case
1. **Proceed to Treatment.** Staff add **treatment log** entries to the case (`cases/{id}/treatmentLogs`; `lib/core/models/rescue/treatment_log_entry.dart`).
   - Types: Assessment, Medication, Procedure, Vaccination, Follow-up Check, Discharge, Death Report.
   - Fields include: date, notes, condition, medication and dose, procedure, vaccine and dose, next schedule, discharge or final condition, date and cause of death, media, and which animals the entry applies to.
   - The log is designed to be append-only (`treatment_log_repository.dart:16`). Firestore rules cover it only through the general case-subcollection rule, so verify this claim before putting it in the paper.
   - An entry has no cost or clinic field.
2. **Costs** are separate **case expenses** (`cases/{id}/expenses`). Each has a category and a funding source. (`74ea496` added a paid / unpaid running-bill status. `origin/dev` @ `e9ec5e8` removed it.)
3. **What happens to each animal** (`postTreatmentAction`): Intake to the shelter, Transfer, or Release. Other closure reasons are listed in `closure_reason.dart`, e.g. Died, Reunite with owner.
4. **Multi-animal cases** close only when every animal is discharged or deceased.
5. **Case chat** (`cases/{id}/messages`) is open to staff, the reporter, the willing adopter, and the assigned transporter.
6. **Track Case** shows the reporter a timeline, the transporter card, the route, animal details and the chat.

### 2.9 Public map
- **Explore Map** (`lib/features/generalhome/explore_reports_map.dart`) reads `publicCases`. This is a reduced copy kept by `functions/public_cases.js`, with surrender addresses removed and locations rounded. [Built]
- **Map filters:** All, Community Adoption, My Reports, and the rescue-type categories. Urgency is shown on each pin's ring.
- **Feed filters:** All / Nearby / Farther.

### 2.10 Not built
These are listed as gaps in the defense document (Part 4):
- A transporter can't cancel after accepting or after pickup. Staff reassign.
- The reporter gets no push for reject, merge or referral. These appear only on the timeline.
- No rule for who pays treatment costs after a referral.
- No foster or TNR (trap-neuter-return) outcome.

---

## 3. Animal Records

### 3.1 Existing practice [Existing] (Ch4 §4.2.2)
- Animals are tracked in Google Sheets: name, condition, vaccines, spay/neuter.
- Attachments are kept separately.
- Records are often incomplete.

### 3.2 Intake
1. **Confirm received.** Staff confirm each animal was received (`lib/core/repos/rescue_case/case_intake_repository.dart:789-831`).
2. **Quarantine/isolation is required. It has no skip** (`:861`, and the UI marks it "(required)"). [Built]
   - It is set for the whole case by duration.
   - It ends automatically when due (`completeDueQuarantines` / `completeDueIntakes`, every 30 min).
3. **Create the record.** It is blocked until the animal is marked received (`lib/features/admin/animals/create_animal_record_page.dart:954-985`). [Built]
   - The form is prefilled from the case: species, breed, sex, size, case photos, background "Rescued".
   - Each animal gets one record, matched by `linkedCaseId` + `sourceAnimalIndex`.

### 3.3 Record contents
These are in `animals/{id}`; see `lib/core/models/rescue/animal_record.dart`.
- **Identity:**
  - name, age, species, breed, sex, size, coat length
  - description, special needs
  - key characteristics: temperament, compatibility, training
  - rescue background, tags
  - photos with captions
  - litter at intake

  There are no color or markings fields.
- **Status fields:**

  | Field | Values |
  |---|---|
  | `adoptionStatus` | not_ready, adoptable, reserved, adopted, deceased |
  | `careStatus` | in_shelter, isolation, recovering |
  | `transferStatus` | (transfer state) |
  | `currentStatus` | returned |
  | `currentCaseId` | shown as In Treatment |
- **Medical tab** (`animal_medical_tab.dart`):
  - Medical profile: allergies, chronic conditions, medications, weight, body condition
  - Vaccinations: Up to date / Due soon / Overdue
  - Past health records
  - Care records: deworming, flea & tick, vet checkups

  Medications and doses are in subcollections.
- **Management log** for each animal (`animals/{id}/managementLogs`).

### 3.4 Rules
- **Becoming adoptable needs a registered QR or NFC tag** (`firestore.rules`, the `animalTags` registry). [Built]
  - Removing an adoptable animal's last tag sets it back to `not_ready`.
  - New records are never created as adoptable.
- **Shelter capacity** and **isolation capacity** are set in Shelter settings (`maxCapacity`, `isolationCapacity`). The Today view and analytics use them. [Built]
- **Euthanasia** is recorded as a death, and it needs a second review (`animal_record_repository.dart:812-821`). [Built]
- **Transfer out** only ever reaches `transferStatus: pending`.

### 3.5 Admin list
`animal_record_page.dart`:
- **Status chips:** In Shelter, Isolation, Recovering, In Treatment, Adoptable, Returned, Adopted, Deceased
- **Sort options:** 8
- **Filters:** adoptable, in treatment, vaccinated, rescue background, special needs, age group, and Active/Archived/All

### 3.6 Public view
- **What's listed:** users read `publicAnimals`, a reduced copy kept by `functions/public_animals.js`. Only adoptable and reserved animals are listed (`adoption_page.dart:104-105`).
- **Profile** (`animal_page.dart`):
  - a photo gallery you can swipe
  - Animal Information, Description and characteristic groups
  - a health summary, special needs, and sponsors

---

## 4. Adoption Management

### 4.1 Existing practice [Existing] (Ch4 §4.2.3)
1. The organization posts animals on Facebook.
2. Interested people message the organization on Messenger.
3. Staff interview the applicant.
4. Staff deliver the animal to the adopter's home, where an agreement is signed.
5. Follow-ups depend on the adopter replying.

### 4.2 Applying (user)
1. **Browse.** The Adopt page has two tabs, Shelter Animals and Community Adoption (`lib/features/adoption/adoption_page.dart:498`). Status labels are Available, Reserved, Adopted and Not Available.
2. **Form sections** (`steps/adoption_intro_step.dart`):
   - Personal Information
   - Household & Living Information
   - Pet Experience
   - Lifestyle & Care (including why they want to adopt and which costs they can afford)
   - Required Uploads: a Government ID and home photos. Proof of address is no longer required.
   - Agreements: five checkboxes, one of which is "approval not guaranteed"
3. **Tracker steps** (`adoption_step.dart:16-22`): Fill out adoption form → Book appointment → Application review → Time to meet! → Adoption Day.
   - Adoption Day shows only once the release date arrives.
   - Other end screens: rejected, withdrawn.
4. **Booking.** The applicant books the interview: On-site Visit or Online, from weekday time slots (`interview_scheduling.dart`). An Online interview gets a Zoom link automatically.
5. **No fee.** Adoption is free, as stated in the agreement PDF (`adoption_agreement_service.dart:163`). [Built]

### 4.3 Rules
| Rule | Tag |
|---|---|
| Several people may apply for the same animal. The reservation is the lock: once staff reserve or release the animal to one applicant, the others are closed as "Animal no longer available" (`functions/adoptions.js:9-13, 104-160`). | [Built, needs approval] |
| A pending application with no interview booked is reminded after **3 days** and withdrawn after **14 days** (`functions/adoption_stall_rules.js`). | [Built, needs approval] |
| After the first missed interview the applicant may book once more. The second closes the application (`adoption_no_show_rules.dart`). | [Built, needs approval] |
| The applicant may withdraw during Review or Time to meet!. After release, withdrawing becomes a return request. | [Built] |
| A person may apply for several animals. There is no blacklist. | [Built] (no limit) |

### 4.4 Staff side (permission `adoptions`)
1. **Status values** (`lib/core/models/adoption/adoption_application.dart:17-23`): pending, interview, approved, adopted, rejected, withdrawn.
2. **Admin tabs** (`adoption_application_review_page.dart:53-76`): Pending, Interview, Release (approved), Adopted, Complete, Returns, Rejected, Withdrawn.
   - "Reserved" is a timestamp on the application plus the animal's `adoptionStatus`. It is not a stage.
   - Complete and Returns come from `postAdoptionStatus` and `returnRequest`.
3. **Application detail:**
   - Fit Assessment
   - Responses, Application History (the applicant's own earlier applications) and Required Documents, as collapsible sections
   - Appointment Details
4. **Interview:** staff confirm, reschedule, complete it, or mark a no-show.
5. **Decision:**
   - Approve, or reject with one or more of 9 reasons plus notes (`adoption_rejection_sheet.dart`).
   - Reserve and unreserve run as transactions.
6. **Release** (`releaseWithFollowUps`). It needs an approved application and at least one follow-up date. The application becomes adopted, and so does the animal.
   - Staff print the Adoption Agreement PDF.
   - After it is signed by hand, they upload a photo of it (`signed_agreement_tile.dart`).
7. **Post-adoption schedule** (`follow_up_schedule.dart`, `schedule_rule_editor.dart`):
   - Each rule has an interval (days, weeks or months) and a duration (weeks, months or a year). Rules can be chained.
   - Dates are previewed before they are confirmed.
8. **Follow-ups:**
   - The adopter submits a form with photos.
   - Staff confirm receipt, send reminders, complete or reschedule, and can give warnings.
   - Reminders go out on the day a follow-up is due and again 3 days after. Staff are alerted at 7 days overdue (`follow_up_reminder_rules.js`). [Built, needs approval]
   - **Completing is manual.** The Complete button is blocked until every follow-up is done or cancelled.
9. **Returns:**
   - The adopter gives a reason from a fixed list.
   - Return stages: pending review → approved or declined → retrieval scheduled (date, address, notes) → retrieved → intake, through a return case (`createReturnIntakeCase`).
   - Staff can also start a return themselves.

### 4.5 Reporter adopts the rescued animal
- **Interest:** a reporter or user can mark interest on a case (`willingAdopterId`). This does not reserve the animal.
- **After approval:** if the organization approves the adoption request, the animal can go from the clinic to the adopter.
- **Pickup window:** the adopter has **72 h** to collect, with a reminder **24 h** before the deadline. After that the animal goes to the shelter, or is flagged for referral if the shelter is full (`rescue_adoption_rules.js`). [Built, needs approval]

### 4.6 Community Adoption
- **What can be listed** (`lib/core/utils/community_adoption_eligibility.dart`):
  - Pet Surrenders, as soon as they are filed.
  - Stray reports an organization rejected as healthy / low urgency.

  Lost Pet reports are excluded. There is **no** rule based on "not rescued within a time period". [Built]
- **Who decides:** the reporter manages the listing and chooses an adopter.
- **Agreement:** both sides type their names to sign it (`community_adoption_terms.dart`).
- **No organization steps:** no interview, review or reservation.
- **Check-in:** one, **14 days** after the adoption (`community_checkin_rules.js`). [Built, needs approval]
- **Not built:**
  - Other requests are not closed when one is chosen.
  - There is no return flow.
  - There is no check-in reminder.

### 4.7 Facebook
- **Connecting a Page:** an organization connects its Facebook Page (permission `facebookPublish`).
- **Posting:** adoptable animal records are posted in a batch to the Page (`facebookPublishAnimalRecords`, Graph API v21).
- **Promotion schedules** (every 1, 2 or 4 weeks) send reminders only. Nothing posts automatically (`adoption_promotion.js`).
- **Not live:**
  - Single posts for a campaign or event (`facebookPublishRecordPost`).
  - The public animal web page.

  Both are written but not exported (§13.2).
- **Not found:** retrieving Page Insights metrics. [Not built]

---

## 5. Donation and Sponsorship

### 5.1 Existing practice [Existing] (Ch4 §4.2.5)
- Fundraising for each case accepts GCash, Maya, bank transfer and in-kind goods.
- Each donation is typed into a public Google Sheet each month.
- Receipts are withheld from public view.

### 5.2 Campaigns (permission `campaigns`)
- **Fields** (saved by `saveCampaign`, `functions/campaigns.js:402`):
  - type, title, description, image
  - linked animal, linked case
  - `fundKind`: campaign, animal, medical, shelter_resource or general
  - purpose tags, restricted flag
  - target, deadline
  - in-kind items needed, monthly amount, intended use

  There is no "beneficiary" field.
- **Campaigns for an animal in treatment** (`origin/dev` @ `e9ec5e8`; `functions/campaign_needs_rules.js`, `lib/features/admin/donation/campaign_animal_needs.dart`): [Built]
  - The admin picks an animal that is in treatment, at intake, or has a record made from a rescue case.
  - The server builds a public summary from the case: the rescue type, the medical condition (as reported, plus the latest from the treatment log), the treatment log, and the treatment expenses.
  - Each animal gets its own expenses plus an equal share of expenses shared by animals rescued together.
  - The **target is the total of those expenses** and can't be typed in.
  - Launching needs intake complete and at least one expense. After launch, the animal, the summary and the target are fixed.
  - Donors read only this summary. Cases, expenses and treatment logs stay staff-only.
- **Lifecycle:** draft → active → paused → goal_met / goal_not_met → closed → archived. [Built]
  - A campaign can be archived only when its available balance is 0.
  - **Goal Not Met** options: extend, close, convert to the general fund, or relaunch. Restricted funds can't be converted (`campaigns.js:566-648`).
- **Updates:** campaign posts go in `campaigns/{id}/updates`.

### 5.3 Donating (user)
1. **Browse:** donation and sponsorship lists, filtered by `type` (`lib/features/donation/donation_page.dart`).
   - Each card shows image, title, progress bar, amount raised of target, percentage, and days left.
   - A campaign linked to an animal shows that animal's public profile.
   - A campaign for an **animal in treatment** shows "About the Donation" with four parts: Rescue Reason, Medical Condition, Treatment Log, and Treatment Expenses, with their total as the target (`campaign_needs_view.dart`; `origin/dev`).
   - **Fund Tracking** shows the spending records.
2. **PayMongo** hosted checkout (`functions/paymongo.js`): Card, GCash and Maya. A webhook confirms each payment.
   - Test or live mode is decided by the secret key (`sk_live_`, `paymongo.js:70`). The key is in Secret Manager, so the mode can't be told from the repository.
3. **Options:** donors can give anonymously.
4. **Certificates** go to `users/{uid}/certificates`. PayMongo email receipts are off.
5. **Refunds:** a donor may ask within **7 days**, or **60 days** for unauthorized payments (`functions/refund_rules.js`). [Built]

### 5.4 Sponsorship
- **What it is:** a **one-time payment covering 30 days**. It does not renew automatically. [Built]
  - Staff get renewal reminders (`remindSponsorshipRenewals`).
  - Lapsed sponsorships are marked inactive (`lapseExpiredSponsorships`).
  - The UI wording conflicts with this (§13.3).
- **Which animals:** any animal with a record that is in care. Each animal has one open sponsorship.
- **Funding status:** Fully Funded while the available balance covers one month, Open otherwise (`sponsorship_funding_rules.js`).
- **Not built:** a sponsorship is not closed automatically when the animal is adopted or dies.

### 5.5 Records and money (permissions `financeView` / `financeManage`)
- **Records tabs:** All, Monetary, Sponsorship, In-Kind, and Payments for finance users (`donation_admin_records.dart`).
- **Offline donations** (`recordOfflineDonation`): bank transfer, cash, check or other, with a reference number, donor, date, receipt and notes. Saved with `source: 'manual'`.
- **In-kind:**
  - The donor pledges a category, free-text items, an address, and whether to stay anonymous.
  - Staff mark the pledge received (with quantity) or cancelled.
  - Received goods go into stock (`organizations/{id}/stock`, `stockMovements`).
  - No photos are taken.
- **Allocations, voids and reallocation** (`campaigns.js:783-890`), cash-outs (`:1668-1783`), and transfers between campaigns.
- **Who can do what:**
  - Money actions need `financeManage`. Viewing needs `financeView`.
  - Neither is in the default Staff set.
  - Rescue volunteers (independents) get no money features. [Built]

---

## 6. Volunteer and Events Management

Chapters 3 and 5 say this module is deferred to CAPIT2, but it is built.

1. **Events** (staff with `volunteers`; `lib/features/admin/events/`, `lib/core/repos/volunteer_event_repository.dart`):
   - Create, edit and cancel. Cancelled is final.
   - Each event has a cover image and a capacity.
   - Events can be shared to Facebook, but that export is not live (§13.2).
2. **Users** (`lib/features/volunteerevent/`):
   - Open Events, view details, add to favorites, sign up, and get an **e-ticket**.
   - Sign-up runs in a transaction, so capacity can't be exceeded.
   - Sign-ups after the event or repeat sign-ups are refused.
3. **Attendance:** staff mark it (`setAttendance`).
4. **Badges** (`functions/volunteer_stats.js`):

   | Badge | Earned at |
   |---|---|
   | first_event | 1 event attended |
   | helping_paw | 5 events |
   | regular | 10 events |
   | champion | 25 events |
   | community_helper | 3 different organizations |

   [Built]
5. **Not built:**
   - Event certificates (only donation certificates exist)
   - Unregistering
   - A waitlist
   - A cancellation notice

Pet transporters (§1.5) and rescue volunteers (§1.6) have their own sign-up and review flows.

---

## 7. Collar Tags and Lost & Found

1. **Owner collar tags** (`lib/features/collartag/`, `collarTags`):
   - The owner creates a tag for their pet.
   - The tag can be a QR image (`tag_qr_image.dart`) or written to an NFC chip (`nfc_service.dart`).
   - The status is active or lost.
2. **Lost and found:**
   - The owner can mark a pet Lost or Found. Marking it lost creates a linked `petAlerts` report (`collar_tag_data_model.dart`).
   - When someone scans a **lost** pet's tag, a rescue session opens (`getOrCreateRescueSession`) and the owner is alerted (`notifyTagScan`).
   - The finder chats with the owner (`pet_found_chat.dart`).
3. **Shelter animal tags:**
   - One registry, `animalTags/{code}`, is shared by QR and NFC (`lib/core/utils/animal_tag_codes.dart`).
   - Staff can Add QR, Add NFC, Show, New Code and Remove.
   - Scanning a shelter animal alerts that organization's staff.
   - A registered tag is required before an animal can be adoptable (§3.4).
4. **Not built:**
   - Proof-of-ownership upload
   - An expiry for lost or found reports

---

## 8. Notifications and Geofencing

Chapter 5 says these are CAPIT2 work, but they are built.

- **Push (FCM):**
  - The device token is saved to `users.fcmToken` (`push_token_service.dart`).
  - The server sends through `notifyUser` / multicast (`functions/index.js:203-216`).
  - Each push is also saved to `users/{uid}/notifications`, which the Notifications screen shows.
- **Foreground pushes** are shown again with `flutter_local_notifications` (`notification_service.dart`).
- **Geofencing** (`native_geofence`; `lib/core/geofence/geofence_config.dart`, `lib/core/services/geofence_service.dart`):
  - Users get **300 m** fences around active cases within 10 km, up to 30 fences. Entering one shows "near an active rescue report".
  - A **1 km** fence around the user's own location refreshes `lastLat`/`lastLng` when they leave it.
  - Server-side alerts reach users within 5 km by default (10 km at most).
- **Scheduled jobs** (Cloud Scheduler; timers listed in each module):

  | Every | Jobs |
  |---|---|
  | 1 min | expireTransportOffers |
  | 5 min | notifyUnconfirmedReports, escalateCriticalReports |
  | 30 min | completeDueQuarantines, completeDueIntakes, followUpAdopterPickups |
  | 60 min | sendFollowUpReminders, followUpCaseReferrals, expireStaleReporterResponses, remindAdoptionPromotions, followUpStalledApplications, evaluateCampaignDeadlines |
  | 24 h | remindSponsorshipRenewals, lapseExpiredSponsorships |
  | Daily | sendCommunityAdoptionCheckIns (09:30 Manila), sendDashboardDigest |
  | Monthly | writeAnalyticsSummaries (1st, 02:00) |
  | Not stated | expireStaleDonationCheckouts |

---

## 9. Analytics and Audit (permission `insights`; finance cards need `financeView`)

This section follows `origin/dev` @ `e9ec5e8`. That commit replaced the analytics described in `74ea496`.

1. **Admin home tabs** (`lib/features/adminhome/dashboard/adminhome_screen.dart`):
   - **Today** has Priority actions, Rescue, Shelter care, Adoption, and Donations & funds.
   - **Analytics** opens with **Reports by area** (`area_reports.dart`; definitions in `dashboard/reports/*.dart`), five tabs that serve as the organization's KPIs:

     | Tab | Example measures |
     |---|---|
     | Rescue | reports received; referral rate; successful rescue rate; treatment rate; average response time (report → accepted) and completion time (report → clinic or shelter); transport completion; transporter utilization; shelter and treatment capacity utilization |
     | Adoptions | intake → adoption time; adoption rate; adoptions that last 90 days; post-adoption response and follow-up completion; a promotion funnel (profile views and saves are now counted per animal per day); listings that need attention |
     | Donations | finance staff only. Money received by channel and fund; donor retention; progress toward targets; expenses by group; remaining funds; in-kind received, used and on hand; sponsorship progress |
     | Shelter | capacity, occupancy, available spaces, admissions and readmissions, discharges, length of stay, animals turned away for lack of space |
     | Volunteers & transporters | registered and active volunteers, events, attendance; verified and available transporters, offer response rate and time, cases no transporter took, decline reasons |

     The question cards come next: "Are we saving more lives?", "Where did animals go?", "How fast do animals find homes?", "Who waits longest?", "Are animals protected from illness?", "End-of-care decisions", "Month by month", "What we're improving".
2. **Measures and rules:**
   - **Live release rate** = live outcomes ÷ finalized outcomes, shown against a 90% benchmark.
   - Each rate states what it was measured on.
   - Missing data is excluded and never shown as 0.
   - Small groups show the fraction only.
   - Data that isn't available is labelled as such: Facebook reach (Insights is not connected), adoption inquiries, and in-kind items in use.
3. **Filters:** the time period only (a day, a week, last N days, a month, a quarter, a year, or a custom range), compared with the previous period. Reports update live. There are no filters by module, status or animal type.
4. **Export** (`analytics_export.dart`): a summary PDF, CSV files, and a monthly accomplishment report. The financial report is separate.
5. **Snapshots:** monthly only, at `organizations/{id}/analyticsSummaries/{yyyy-MM}`. The daily snapshot function was removed in `e9ec5e8`.
6. **Audit log** (`auditLogs`; `lib/core/models/audit/audit_log_entry.dart`):
   - **Tabs:** Rescue, Adoptions, Donations, Expenses, Records, Logins, Organization and Staff.
   - **Fields:** category, action, actor (id, email, name, role), organization, target type and id, old and new values, metadata, time.
   - **Role** is optional, and adoption entries don't set it.
   - **Where entries come from:** the app writes them on a best-effort basis, and Cloud Functions write them too. The Rescue and Records tabs read the case and animal activity logs instead.
   - Entries are append-only (`firestore.rules:1864-1879`).
   - The viewer (`admin/audit/audit_page.dart`) shows the latest 30 entries per tab, with search.

---

## 10. Architecture (as built)

| Layer | What is used |
|---|---|
| **Presentation** | Flutter (Dart), Material 3, theme in `lib/app_theme.dart` (Tilt Warp and Zain fonts via Google Fonts). Navigation is **Navigator 1.0** (`MaterialPageRoute`, `onGenerateRoute` for deep links). `go_router` is in `pubspec.yaml` but never imported. `AuthWrapper` routes by role. State uses Riverpod (`ProviderScope` at `main.dart:61`, mostly admin screens) together with `StreamBuilder`/`setState`. |
| **Application** | Repository classes in `lib/core/repos/`. Business rules run in Cloud Functions (Node.js; triggers, callables, scheduled jobs). Firestore and Storage security rules (`firestore.rules`, `storage.rules`) enforce roles and permissions. |
| **Data** | Cloud Firestore and Firebase Storage (see §11). |
| **External** | Google Maps (maps, Places clinic search, Directions), PayMongo, Facebook Graph API v21, Zoom (online interviews), native geofencing, FCM. |
| **Tests** (per `HANDOFF.md`, 22 Nov) | Flutter 410, Cloud Functions 159, Firestore rules emulator 232. |

## 11. Data layer (Firestore)

**Top-level collections:**
- **People and organizations:** `users`, `organizations`, `organizationInvitations`
- **Rescue:** `cases`, `publicCases`, `communityReports`, `rescueSessions`, `referralShares`, `possibleMatches`
- **Animals and tags:** `animals`, `publicAnimals`, `animalTags`, `collarTags`, `petAlerts`, `petAlertChats`
- **Adoption:** `adoptions`, `communityAdoptionRequests`, `communityAdoptions`, `communityAdoptionCheckIns`
- **Money:** `campaigns`, `donations`, `donationPayments`, `fundTransfers`, `manualDonationRefs`, `paymongoWebhookEvents`, `orgExpenses`
- **Audit and Facebook:** `auditLogs`, `facebookShares`, `facebookConnectRequests`
- **Volunteers and transporters:** `events`, `registrations`, `volunteerRegistrations`, `volunteerApplications`, `transporterApplications`
- **Other:** `clinic_profiles`, `zoomMeetingHostInfo`

**Main subcollections:**

| Parent | Subcollections |
|---|---|
| `organizations/{id}` | members, settings, integrations, stock, stockMovements, cashOuts, analyticsSummaries, analyticsSnapshots, alertClaims, careRounds |
| `cases/{id}` | activityLogs, messages, tracking, transportAssignments, expenses, referrals, treatmentLogs, communityReports |
| `animals/{id}` | managementLogs, medications, medicationDoses, vaccinations, illnesses, medicalEpisodes, careRecords, careUpdates |
| `adoptions/{id}` | followUps, checkins, notesLog, warnings |
| `campaigns/{id}` | allocations, updates, history |
| `users/{uid}` | notifications, history, donated, certificates, favorites, donationFavorites, cards |

## 12. Rules waiting for the organization's approval

The code itself marks these numbers or policies as *"pending the organization's confirmation"*. Present them in the paper as **proposed rules that need approval**, not as agreed policy.

| Rule | Value | Source |
|---|---|---|
| Critical report escalation | 30 min (each org can change it) | `functions/critical_escalation_rules.js:4` |
| Referral reminder / return | 24 h / 48 h | `functions/referral_rules.js:5`, `referral_type.dart:83` |
| LGU share link stays open | 30 days | `functions/referral_share_rules.js:13` |
| Several applicants; reservation is the lock | policy | `functions/adoptions.js:9` |
| Booking reminder / auto-withdraw | 3 / 14 days | `functions/adoption_stall_rules.js:6` |
| Interview no-shows before closing | 2 | `adoption_no_show_rules.dart:1` |
| Post-adoption reminders | adopter on the due day and 3 days after; staff alert at 7 days | `functions/follow_up_reminder_rules.js:5` |
| Reporter-adopter pickup window / reminder | 72 h / 24 h | `functions/rescue_adoption_rules.js:8`, `rescue_adoption.dart:30` |
| Community adoption check-in | 14 days | `functions/community_checkin_rules.js:7` |
| Care rounds starting list | default list | `lib/features/care/care_rounds.dart:114` |

## 13. Code issues that affect what the paper can claim

1. **Six Cloud Function modules were dropped from `functions/index.js`** in commit `7c10528` (21 Nov 2026). They are `account_deletion`, `phone_accounts`, `independent_rescuers`, `pet_matching`, `pet_alerts` and `public_animal_page`. They were loaded in the commit before it.
   - **In the current source these don't run:** account deletion, the sign-up phone check, rescue volunteer limits and opening cases to them, lost-and-found matching, and the public animal page.
   - **Risk:** the next full functions deploy would remove the copies that are live now.
   - **For the paper:** until this is fixed, describe these features as "implemented in source, not currently deployed".
2. **Two functions are not exported:** `facebookPublishRecordPost` and `publicAnimalPage`. `firebase.json:41` still routes `/animal/**` to `publicAnimalPage`.
3. **Sponsorship screen problems:**
   - It shows hard-coded placeholder text: "Rescue Pet • Young • Short Coat" and Health/Weight/Activity values (`lib/features/donation/sponsorship_detail.dart:167, 229-231`).
   - It says "Recurring Sponsorship - Every 30 days" (`:633`), and the summaries say "Recurring monthly support". The payment is one-time.
4. **Out-of-date figures in `docs/defense/resPAWnd_Defense_Scenarios.txt`:**

   | Topic | Defense doc says | Code |
   |---|---|---|
   | Arrival check | 150 m | 20 m (`transit_rules.dart:26`) |
   | "Online" transporter | seen in the last 5 min | 10 min (`pet_transporter.dart:22`) |
   | Quarantine | optional | required (`case_intake_repository.dart:861`) |
   | Urgency | set by rescue type | rated from the answers (`urgency_assessment.dart`) |

   Correct these before the defense.
5. **Analytics changed after this spec was first written.** `origin/dev` @ `e9ec5e8` deleted `docs/ANALYTICS_AUDIT_2026-11.md` and the `snapshotDailyAnalytics` function. If that function was deployed, `HANDOFF.md` says to remove it (`firebase functions:delete snapshotDailyAnalytics`).
6. **Rechecked 23 Nov 2026** on local `dev` (`74ea496`), `origin/dev` (`e9ec5e8`) and `origin/main`. Issue 1 is still present on all three: none of them loads the six modules. `functions/package.json` uses `index.js` as its only entry point, and no other file requires these modules.
