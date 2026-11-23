# Chapter 5 review: draft vs. the app

**What was compared.** The Chapter 5 draft (`cap1 outline.md`, §5.1–5.7) was checked against the code on `dev` at `74ea496` (23 Nov 2026). The other chapters were read for consistency.

**Ground rule.** Where the draft and the app disagree, the **code is taken as correct**. Every change below is labelled ➕ **Added** (built but not in the draft), ➖ **Removed** (in the draft but not built), or ✏️ **Corrected** (in both, but the draft describes it wrongly).

**Evidence.** All file references and rule tags come from `MODULE_SPECS.md` in this folder; the evidence is there.

---

## 1. Verdict by section

| § | Section | Verdict | Main problem |
|---|---|---|---|
| 5.1 | Solution description | Matches | Lists "volunteers" as a user type. The app has transporters and rescue volunteers (small organizations), plus event volunteers, who are ordinary users. |
| 5.2.1 | General objective | Matches | — |
| 5.2.2 | Specific objectives | Partial | Obj. 2: Lost Pet is not part of the case flow. Obj. 3: there is no "adoption or return history" section on the record. Obj. 5: rescue volunteers register as small organizations, not as individuals. Obj. 6: sponsorship is one-time per 30 days. Objectives 6–7 contradict §5.6.4 in the same chapter. |
| 5.3 | Technical requirements | Matches | Heading typo "5.3.1." |
| 5.4.1 | Data security | Matches | — |
| 5.4.2 | Performance | Not verified | The try-catch parsing and client-side sorting claims were not checked line by line. Keep the wording general or check it. |
| 5.4.3 | UI and usability | Partial | Theme and fonts match (`app_theme.dart`). "Adheres closely to the approved mockups" can't be checked from code. |
| 5.4.4 | Privacy | **Wrong** in one sentence | Location is also collected in the background by geofencing, and while a transporter is online. It is not only collected on submission. The consent gap is stated honestly. Not formatted as a heading. |
| 5.4.5 | Organizational | Matches | — |
| 5.5.1 | UMA – General user | Partial | Email is verified by a **link**. A mobile number is **required** for every account. |
| 5.5.2 | UMA – Pet transporter | Partial | The organization is not the only reviewer. License and portrait photos are missing. About 12 empty headings follow. |
| 5.5.3 | UMA – Admin | **Unfinished** | Stops mid-sentence. Staff roles, permissions, invitations, rescue volunteers and the system admin are missing. |
| 5.5.4 | Rescue – User | Partial | Marker dragging, map filters, Lost Pet storage and matching, and "live proof questions" are described wrongly. |
| 5.5.5 | Rescue – Admin | **Wrong** in places | Accepting does not create a case. The tab names are wrong. Verification, duplicates, referral, escalation and transporter rules are missing. |
| 5.5.6 | Animal Records – Admin | **Wrong** in places | Quarantine is required. The treatment types are wrong. Logs have no cost or clinic field. There are no color or markings fields. |
| 5.5.7 | Animal Records – User | Partial | Returned and unavailable animals are not listed publicly. |
| 5.5.8 | Adoption – User | Partial / **Unfinished** | There is no disclaimer page. The lock is the reservation, not the approval. The community adoption paragraph stops mid-sentence. |
| 5.5.9 | Adoption – Admin | **Wrong** in places | The 10 stages are not the status list. The interview has no location or instructions fields. Completion is manual. |
| 5.5.10 | Donation – User | Partial | There is no beneficiary field. Sponsorship is a one-time payment for 30 days. PayMongo is not mentioned. Showing the animal's condition, treatment and expenses **now matches** on `origin/dev` (campaigns for animals in treatment). |
| 5.5.11 | Donation – Admin | Partial | In-kind donations have no photos. Lifecycle, offline donations, allocations, cash-out, refunds and finance permissions are missing. |
| 5.5.12 | Analytics & Audit | Partial | There is only a time-period filter. The audit role is optional. Today/Analytics, live release rate and exports are missing. |
| 5.6.1 | Presentation | **Wrong** | go_router is not used. |
| 5.6.2 | Application | Partial | Typo: "business login" should be "logic". "Managing rescue sessions" refers to collar-tag sessions. |
| 5.6.3 | Data | Partial | `transportAssignments` and `expenses` are **subcollections** of `cases`. Many collections are missing (see `MODULE_SPECS.md` §11). |
| 5.6.4 | External services | **Wrong** | FCM and PayMongo are already built. Facebook, Zoom and geofencing are missing. |
| 5.7 | Deployment plan | Partial | The heading appears twice. §5.7.8 lists Volunteer & Events and FCM as CAPIT2 work, but they are built. |
| — | Missing subsections | **Missing** | Pet transporter trip, Volunteer & Events, Collar Tags / Lost & Found, Notifications & Geofencing, System Admin. |

---

## 2. What changes

### ➕ Added: built, but not in the draft
1. **Volunteer & Events module:** events with a capacity, sign-up with an e-ticket, attendance, and badges at 1, 5, 10 and 25 events, plus Community Helper at 3 organizations. The draft calls this CAPIT2 work.
2. **Push notifications (FCM), local notifications and geofencing:** 300 m alerts near a case, and a 1 km fence around the user's own area. The draft calls this CAPIT2 work.
3. **PayMongo checkout** (Card, GCash, Maya) with webhook confirmation. The draft says "may be used".
4. **Organization staff model:**
   - roles: admin and staff
   - 10 module permissions
   - invitations
   - restricted finance permissions (`financeView` / `financeManage`)
5. **Rescue volunteers as small organizations:**
   - limits: 5 members, 3 active cases, 5 animals
   - a 1–5 km area
   - shelters get a 15-minute head start
   - no access to money features
6. **System admin console:** Organizations, Volunteers, Transporters, Users. It has no access to case or finance data.
7. **Report verification:**
   - photo checks using EXIF data
   - the phone's distance from the pin
   - the reporter's track record
   - live proof
   - a rider location check
8. **Rule-based urgency** (Critical, Medium or Low from the answers, with contradiction handling).
9. **Litter details** for female dogs, and linked puppy reports.
10. **Duplicate check and merge**, critical escalation after 30 minutes, and referral to another org, a rescue volunteer, or the LGU (with timers).
11. **Rescue Readiness** (7 factors, advisory only).
12. **Transport rules:**
    - vehicle suitability
    - offer expiry after 5 or 20 minutes
    - Organization Will Transport
    - End Reasons
    - re-routing when a clinic refuses
13. **Case expenses** with a payment status; post-treatment Transfer or Release.
14. **Animal tag registry** (QR and NFC). A tag is required before an animal can be adoptable.
15. **Euthanasia** needs a second review.
16. **Adoption details:**
    - the applicant books the interview (On-site or Online with Zoom)
    - two no-shows close the application
    - auto-reminder and auto-withdraw when no interview is booked
    - an agreement PDF plus an upload of the signed copy
    - the reporter can adopt the animal they reported, with a 72-hour pickup window
17. **Community Adoption rules:** the reporter chooses the adopter, both sign by typing their names, and there is one check-in after 14 days.
18. **Facebook Page connection and batch posting** of adoptable animals; promotion reminders.
19. **Donations:**
    - campaign lifecycle and Goal Not Met options
    - offline donations
    - allocations, cash-outs and transfers
    - refunds within 7 days (60 days if unauthorized)
    - in-kind stock
    - donation certificates
20. **Analytics** (`origin/dev`):
    - the Today tab
    - Reports by area, with five KPI tabs: Rescue, Adoptions, Donations, Shelter, Volunteers & transporters
    - live release rate
    - the "missing data is not zero" rule
    - monthly summaries
    - CSV and PDF exports, and the monthly accomplishment report
21. **Account deletion**, with de-identification.
22. **Campaigns for animals in treatment** (`origin/dev`): the target is the total of the animal's treatment expenses and is fixed at launch.

### ➖ Removed: in the draft, not in the app
1. Navigation with go_router. (✏️ The app uses Navigator 1.0 with `AuthWrapper`.)
2. Dragging the map marker. (✏️ The pin is set by GPS, tapping the map, or searching.)
3. Explore Map filters by status, urgency, condition and temperament.
4. Matching lost pets against **scanned collar tags**.
5. Treatment types Surgery, Weight update and Observation, and a cost and clinic on each treatment entry.
6. Color and markings fields on the animal record.
7. Optional quarantine. (✏️ It is required.)
8. A separate adoption disclaimer page before the form.
9. Interview location and instructions.
10. The ten adoption "stages" as a status list.
11. Automatic move to Completed after the last follow-up.
12. A "beneficiary" field on campaigns. (Case treatment expenses do now appear on campaigns for animals in treatment on `origin/dev`, so keep that part of the draft.)
13. Photos for in-kind donations.
14. Analytics filters by module, status and animal type; a separate sponsorship total.
15. "Community adoption for healthy strays not rescued within a time period". (✏️ It covers rejected healthy strays and Pet Surrender.)

---

## 3. Replacement text

These are written in the draft's own voice. Each says only what the app does. Rules marked † are numbers the code still lists as *pending the organization's confirmation* (`MODULE_SPECS.md` §12). Either get the organization's approval before the defense, or keep the word "proposed".

### 5.2.2 Specific objectives (changes only)
- **Obj. 2:** replace "…shelter intake, and case completion" with:
  > …shelter intake, and case completion, with Lost Pet reports shared with the community and Pet Surrender reports listed for community adoption.
- **Obj. 3:** replace with:
  > To maintain a structured digital record for each animal containing its identity and characteristics, photographs, vaccination and medical profile, care records, and current shelter, care and adoption status, linked to the rescue case and treatment log it came from.
- **Obj. 5:** replace with:
  > To allow pet transporters to register and be verified, and to allow rescue volunteers to register as small independent organizations that may accept rescue cases within set limits.
- **Obj. 6:** replace "secure payment processing using PayMongo" with:
  > secure online payment through PayMongo (card, GCash and Maya), with offline donations recorded manually by authorized staff.

### 5.4.4 Privacy (replace the location sentence)
> Location data is attached to a report when it is submitted and to a rescue while it is being transported. With the user's permission, the application also uses the device's geofencing service to alert users who come within 300 meters of an active rescue report and to keep the user's approximate area current for nearby alerts. A pet transporter's location is shared only while the transporter is online.

### 5.5.1 User Management and Authentication — General User (replace paragraph 1)
> A user may register with an email address and password, sign in with a Google account, or sign in with a mobile number verified through a one-time SMS code. Accounts created with an email address are confirmed through a verification link sent to that address. Every account must also verify a mobile number by SMS, and each email address and mobile number may belong to only one account. Forgotten passwords are reset through an email link. After verification the user chooses one of five roles: General User, Pet Transporter, Rescue Volunteer, Organization Admin, or Organization Member.

Keep paragraph 2. Change "certificates" to "donation certificates", and add "Delete account" to the list of account settings.

### 5.5.2 Pet Transporter (replace)
> An account that selects Pet Transporter is routed to the transporter verification screen. The applicant submits their full name and mobile number, photographs of the front and back of their driver's license and a portrait photograph, the vehicle type (motorcycle, sedan, SUV, or cargo van), the license plate, the number of animals the vehicle can carry safely, whether a motorcycle has an animal carrier, and an optional anti-rabies vaccination record. The application is saved to the transporterApplications collection with a pending status. It is reviewed by platform administrators or by organization staff who hold the Volunteers permission. Once approved, the user is routed to the Service screen, where they set their service range, switch between online and offline, and accept or decline transport offers with a reason. A transporter is treated as online only when the switch is on and the app has reported in within the last ten minutes. The system matches transporters to cases by vehicle: a motorcycle carries only one animal and never one that needs an enclosed vehicle, and trips with several animals require a declared capacity that covers all of them.

Delete the empty headings that follow this section.

### 5.5.3 Organization Admin, Staff, Rescue Volunteers and System Admin (replace the unfinished paragraph)
> An account that registers as an organization first enters its name, official contact number and address, then uploads its SEC or DTI registration or business permit, its permit or accreditation, and photographs of its shelter. Platform administrators approve or reject the application, or ask for changes, and each decision is recorded in the audit log. An approved organization has two roles, Admin and Staff. The Admin invites staff by email or mobile number and grants each staff member module permissions: rescue, animals, care, adoptions, campaigns, finance viewing, finance management, volunteers, insights, and Facebook publishing. Finance permissions are not part of the default staff set and are granted separately.
>
> A person who registers as a Rescue Volunteer is set up as a small independent organization. They submit a valid ID, proof of address and their rescue history. Once approved, they may have up to five members, three active cases and five animals in care, within a service area of one to five kilometers. Shelters receive non-critical reports fifteen minutes before rescue volunteers do. Critical reports open to them immediately, and the first responder to accept a case receives it. Rescue volunteers do not have access to donation features.
>
> A system administrator reviews organizations, rescue volunteers and pet transporters, and can disable or delete user accounts. The system administrator cannot view rescue cases, animal records or financial records.

### 5.5.4 Animal Reporting — User (corrections, in order)
- **Sentence 2:** replace with:
  > The report location is taken from the device's GPS, or set by tapping the map or searching an address.
- **Rescue types:** "Aggressive" → "Aggressive Animal".
- **Photos:** replace the photo sentence with:
  > The reporter must attach at least two photos or videos (one photo for a Lost Pet). The application records whether each item was taken with the camera or chosen from the gallery, and reads the capture time and location stored in gallery photos, so that staff can see when a photo is old or was taken away from the reported location.
- **Animal cards:** add after "…suspected pregnancy":
  > For a female dog with a litter, the reporter also gives the number of puppies, where they are, how they look, and up to three photos.
- **Urgency:** replace with:
  > The system rates each animal as Low, Medium or Critical using fixed rules applied to the reporter's answers. A Critical rating requires evidence of an emergency, and missing information keeps the rating at Medium or higher. Contradictory or missing answers flag the report for staff verification, and the case takes the highest rating among its animals. Photos are not analyzed by the system.
- **Neglect or Abuse:** add:
  > The report is still sent to the covering organizations, and the reporter is shown a guide for reporting the case to the barangay or police.
- **Lost Pet:** replace with:
  > Lost Pet reports are not handled by organizations. They are shared with the community as pet alerts, and lost and found alerts are matched by the system. If the pet wears a registered collar tag, anyone who scans it can message the owner.
- **Storage:** "stored in the cases collection" → "stored in the cases collection (Lost Pet reports in petAlerts)".
- **Track Case:** replace "where the reporter can answer live proof questions" with:
  > where staff may also ask the reporter for a new photo or video taken in the app as live proof.
- **Explore Map:** replace the filter sentence with:
  > Filters allow the user to show all reports, community adoption listings, their own reports, or a rescue type. The map reads a public copy of each case in which locations are rounded and surrender addresses are removed.

### 5.5.5 Animal Reporting — Admin (replace)
> Each new report is assigned to every approved organization whose service area covers its location, and their staff are notified. The administrator's Rescue Reports page is organized into Review, Assign, Ongoing, In Treatment, Intake, Rejected and Closed tabs. It can be filtered by urgency, species, date, location and involvement.
>
> When opening a report, the administrator sees a verification panel. It flags gallery or old photos, photos taken away from the pin, a reporter whose device was far from the pin, and the reporter's history of false reports. The administrator may confirm the report remotely, request live proof from the reporter, or ask a nearby rider to check the location. Possible duplicates (the same species within one kilometer) can be compared and merged, and nothing is deleted.
>
> Accepting a report assigns it to the organization. The report itself becomes the rescue case, and the first organization to accept it receives it. Before accepting, the administrator reviews a Rescue Readiness checklist of seven factors: space, transport, care coverage, vet access, food and medicine, funds, and continuing care. The checklist does not block acceptance. A report may be rejected with a reason from a fixed list, or referred with a reason to another organization, a rescue volunteer, or the barangay or LGU. A referral that receives no answer is followed up after 24 hours and returned after 48 hours.† Critical reports that remain unreviewed for 30 minutes are escalated to every covering organization's administrators.†
>
> The administrator then selects a veterinary clinic through a map search, or sends the animal directly to the organization's shelter, and assigns a pet transporter. Transporters are shown as available, pending or busy, together with their vehicle's suitability. An offer expires after five minutes for Critical cases and twenty minutes otherwise. If no transporter accepts, the organization may refer the case, wait, or transport the animal itself. During the trip, arrival is confirmed only when the transporter is within twenty meters of the stop. If a clinic refuses the animal, the system searches for the next clinic in widening radii of up to forty kilometers. Transport problems are recorded with an end reason, such as the animal not being found, the reporter being unreachable, or a vehicle breakdown, and each reason moves the case to a matching status.
>
> At the clinic, staff record treatment log entries for the case: assessment, medication, procedure, vaccination, follow-up check, discharge, and death report. Treatment costs are recorded separately as case expenses. After discharge, each animal proceeds to shelter intake, transfer, or release. A case with several animals closes only when every animal has been discharged or has died.

### 5.5.6 Animal Records — Admin (replace the intake, quarantine and treatment sentences)
> Individual animal records can be created only after each animal from the case has been confirmed as received. The record is prefilled with the species, breed, sex, size and photographs from the report. The administrator records the animal's name, age, breed, sex, size, coat length, description, special needs, temperament, compatibility, training, rescue background and captioned photographs. Every intake includes a required isolation (quarantine) period, set for the case by duration, which ends automatically when due.
>
> The Medical tab holds the animal's medical profile (allergies, chronic conditions, medications, weight and body condition), its vaccinations marked as up to date, due soon or overdue, and its care records such as deworming, flea and tick treatment, and vet checkups. Treatment entries from the rescue remain in the case's treatment log. An animal becomes adoptable only when a QR or NFC tag is registered to it. Recording a euthanasia requires a second review.

Keep the search and filter paragraph, but make it match the code:
- **Status chips:** In Shelter, Isolation, Recovering, In Treatment, Adoptable, Returned, Adopted, Deceased.
- **Filters:** remove "reservation status". Add age group and archived records.

### 5.5.7 Animal Records — User (replace the last sentence)
> Only animals that are adoptable or reserved are listed to users, and each is labeled Available or Reserved.

### 5.5.8 Adoption — User (replace paragraphs 2–4 and finish community adoption)
> The application form collects personal information, household and living information, pet experience, lifestyle and care arrangements, and two required uploads: a government-issued ID and photographs of the home. The form ends with five agreements, including an acknowledgment that approval is not guaranteed. Adoption is free of charge.
>
> The adopter follows five steps: Fill out adoption form, Book appointment, Application review, Time to meet!, and Adoption Day. The applicant books the interview, either an on-site visit or an online meeting with an automatically created Zoom link. Several people may apply for the same animal. Once staff reserve the animal for one applicant, the other open applications are closed.† An applicant who does not book an interview is reminded after three days, and the application is withdrawn after fourteen days.† An applicant may withdraw during review. After release, the adopter submits post-adoption check-ins on the schedule set by the organization and receives reminders when one is due. A returned animal is requested with a reason, and the organization schedules its retrieval.
>
> Community Adoption lists two kinds of animals that are not in a shelter's care: pets surrendered by their owners, and healthy strays whose reports were declined by an organization as low urgency. The person who reported the animal manages the listing and chooses the adopter, and both parties accept the community adoption agreement by typing their names. The adopter is asked for one check-in fourteen days after the adoption.† Lost pets cannot be listed for community adoption.

### 5.5.9 Adoption — Admin (replace the stage, interview and completion sentences)
> Applications have six statuses: pending, interview, approved, adopted, rejected and withdrawn. The administrator's page groups them into the Pending, Interview, Release, Adopted, Complete, Returns, Rejected and Withdrawn tabs. Reservation is recorded on the application and on the animal; it is not a separate status. The administrator reviews a fit assessment and collapsible sections containing the applicant's responses, application history and documents.
>
> The administrator may confirm, reschedule or complete an interview, or record a no-show. A second no-show closes the application.† Applications may be rejected with one or more reasons from a list, plus notes. Release is separate from approval. It requires an approved application and at least one follow-up date, and the signed adoption agreement is uploaded afterwards. Follow-up schedules are built from rules that set an interval of days, weeks or months for a set duration, and the generated dates are previewed before saving. The administrator confirms each submission, sends reminders, reschedules or issues warnings, and marks the adoption complete once every follow-up is completed or cancelled. Returns go through review, retrieval scheduling and retrieval, and then into intake through a return case.

### 5.5.10 Donation — User (corrections)
- **Campaign card:** replace the card sentence with:
  > Each campaign card shows its image, title, a progress bar, the amount raised against the target, the percentage reached and the days left.
- **Linked animal:** on `origin/dev` the draft's sentence is close to correct. Replace it with:
  > Campaigns for an animal in treatment show the rescue reason, the animal's medical condition, its treatment log and its treatment expenses, and the total of those expenses is the campaign's target. The target and summary cannot be changed after the campaign is launched. Other campaigns linked to an animal show its public profile, and the Fund Tracking section lists how the funds were spent.
- **Sponsorship:** replace the sponsorship sentence with:
  > A sponsorship is a single payment that supports an animal for thirty days. It does not renew automatically, and staff are reminded when it is due for renewal.
- **Payment:** add:
  > Payments are made through PayMongo's hosted checkout using a card, GCash or Maya. Donors may choose to remain anonymous, receive a donation certificate in their profile, and may request a refund within seven days.

### 5.5.11 Donation — Admin (add, and fix in-kind)
- **Add:**
  > Campaigns move from draft to active, may be paused, and end as goal met or goal not met before being closed and archived. A campaign can be archived only after all of its funds have been allocated or transferred. When a goal is not met, the organization may extend, close or relaunch the campaign, or convert it to the general fund unless the funds are restricted. Donations received outside the application, such as bank transfers, cash or checks, are recorded with a reference number and receipt. Funds may be allocated to expenses, cashed out, or transferred between campaigns. These actions require the Finance Management permission, while viewing requires the Finance View permission.
- **In-kind:** replace the in-kind sentence with:
  > In-kind donations are pledged by the donor with a category, list of items and address, and staff mark them as received, with the quantity, into the organization's stock.

### 5.5.12 Analytics and Audit (replace the filter and audit sentences)
> The administrator home has a Today tab, with priority actions and the current state of rescue, shelter care, adoption and donations, and an Analytics tab. The Analytics tab opens with Reports by area, which serve as the organization's key performance indicators across five areas:
> - Rescue: referral rate, successful rescue rate, response and completion times, transport completion, and capacity utilization.
> - Adoptions: intake-to-adoption time, adoption rate, adoptions lasting ninety days, follow-up completion, and a promotion funnel based on profile views and saves.
> - Donations, shown only to finance staff: money received by channel and fund, donor retention, target completion, and expenses.
> - Shelter: occupancy, admissions, discharges, and length of stay.
> - Volunteers and transporters: participation, attendance, and transport offer response.
>
> Question-based cards follow, including the live release rate compared against a 90% benchmark. Results are filtered by period, from a single day to a year or a custom range, and compared with the previous period. Missing data is excluded rather than counted as zero. Results can be exported as CSV, as a summary PDF, or as a monthly accomplishment report, and a monthly summary is saved automatically.
>
> The audit log records actions in seven categories: rescue, adoptions, donations, expenses, records, logins, and organization and staff. Each entry records the action, the responsible account, the affected record, the old and new values, and the time. Entries cannot be edited or deleted.

### New subsections to add
These are taken from `MODULE_SPECS.md`. Use the matching section there for each.
- **5.5.x Volunteer and Events Management:** §6.
- **5.5.x Collar Tags and Lost & Found:** §7.
- **5.5.x Notifications and Geofencing:** §8.
- **5.5.x Pet Transporter Rescue Workflow:** §2.6. This could also stay inside 5.5.5.

### 5.6 Infrastructure (corrections)
- **5.6.1:** replace the go_router sentence with:
  > Navigation uses Flutter's Navigator, and an AuthWrapper widget directs each user to the correct home screen based on their role, their organization's verification status and their permissions.
- **5.6.2:** "business login" → "business logic". "managing rescue sessions" → "opening collar-tag rescue sessions".
- **5.6.3:** describe `transportAssignments` and `expenses` as subcollections of `cases`. Use the collection list in `MODULE_SPECS.md` §11.
- **5.6.4:** replace paragraph 2 with:
  > Firebase Cloud Messaging delivers push notifications, and the device's native geofencing service triggers nearby-case alerts. PayMongo processes online donations. The Facebook Graph API publishes adoption listings to the organization's Facebook Page, and Zoom provides links for online adoption interviews.

### 5.7 Deployment
- Delete the duplicate "5.7" heading.
- **§5.7.8:** CAPIT2 work is now:
  - fixing the issues in `MODULE_SPECS.md` §13
  - event certificates, waitlists and cancellation notices
  - the gaps listed in the defense document, Part 4
  - getting the organization's approval of the † rules
  - wider user acceptance testing and field testing

  Volunteer & Events and FCM should not be listed there as unbuilt.

---

## 4. Advice for the other chapters

### Chapter 1 (proposal)
- **§1.4.1 / 1.6.3:** rescue volunteers are now small independent organizations, and are verified by the system admin or by organization staff with the Volunteers permission.
- **§1.4.2 / 1.4.12.1:** "only a verified user can create a report" and "each report starts by asking about a QR tag" were not confirmed in the report form. Tag scanning is a separate entry point.
  - Status labels in §1.4.12.1: "Ongoing" and "In Treatment" exist. "Arrived at the location", "Rescued" and "Animal in shelter" are not case statuses. Use the `RescueStatus` labels (`MODULE_SPECS.md` §2.7).
- **§1.4.2:** non-rescue concerns are not a separate category; they are an LGU referral reason. "Rescued by a volunteer is not moved to Animal Records" was not verified; check it before keeping it.
- **§1.4.5 / 1.6.5:** the community adoption trigger is a rejected healthy stray or a Pet Surrender. There is no time limit.
- **§1.4.7 / 1.6.5:** monthly sponsorship is not a subscription that can be cancelled. PayPal is not offered; the methods are card, GCash and Maya. "Recognition of contributions" means donation certificates.
- **§1.5.4 / 1.6.4.3:** Facebook Page Insights retrieval was not found. Remove it, or mark it as planned.
- **§1.6.1:** "direct messaging" and "pet registration" are listed as excluded, but case chat, community adoption chat and the collar-tag registry exist. Reword this.
- **§1.6.5 item 5 (Volunteering):** now a full events module.
- **§1.3.2:** the objective of testing with 30 participants is not reported anywhere yet. Chapter 6 needs it.

### Chapter 2
- Fix the heading typo: "Systhesis" → "Synthesis" (§2.4).
- Re-check the feature comparison table in §2.4.3 against `MODULE_SPECS.md`. Mark features that are planned but not built (e.g. Page Insights, event certificates).

### Chapter 3
- **Coverage:** §3.2.3, §3.2.5, §3.3.2 and §3.3.3 say Volunteer & Events and notifications were left for CAPIT2. Both are built. Choose one:
  - (a) Update the coverage table and say they were pulled forward.
  - (b) Keep the 80/20 split and describe CAPIT2 as refinement and validation of these modules.

  Either way, Chapters 3 and 5 must agree.
- **Interview partner:** §3.2.1 names Loved by the Gapz, but §3.2.1.2 says Animal Rescue Manila was interviewed through Messenger. Make them the same, or explain both.
- **Testing tools:** in §3.2.4.1 the "Flutter" paragraph is a copy of the Emulator paragraph. Replace it with the automated tests:
  - Flutter unit and widget tests (410)
  - Cloud Functions tests (159)
  - Firestore security-rules tests on the Firebase emulator (232)
- **Device testing:** don't call features "validated" if `HANDOFF.md` marks them "not checked on a device". Say "verified by automated tests" until device and field tests are done.
- **§3.2.3.4:** the problems listed match the code's history. You could add the 21 Nov regression (`MODULE_SPECS.md` §13.1) as a real integration problem, once it is fixed.

### Chapter 4
- **§4.2:** the introduction repeats §4.2.2 word for word. Shorten it to a two-line overview.
- **§4.2.6:** fix the empty citation "()".
- **§4.4.1:** "rescue volunteers and pet transporters… formally registered, screened" matches the app. Keep it.

---

## 5. Before the defense: code issues to fix or disclose
Details are in `MODULE_SPECS.md` §13.
1. Put the six dropped modules back into `functions/index.js`. Rechecked 23 Nov: still missing on local `dev`, `origin/dev` and `origin/main`. Until then, account deletion, the phone check, rescue volunteer case access, lost-pet matching and the public animal page are not deployed.
2. Export `facebookPublishRecordPost` and `publicAnimalPage`, or remove the hosting rewrite.
3. Remove the placeholder text on the sponsorship screen, and the "Recurring" wording.
4. Fix the defense document's figures: 20 m arrival, 10-minute online window, required quarantine, and urgency rated from the answers.
