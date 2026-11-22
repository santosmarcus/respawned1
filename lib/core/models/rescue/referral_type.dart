/// Who a rescue case is being referred to.
enum ReferralType {
  anotherOrganization,
  rescueVolunteer,
  localGovernmentUnit;

  String get label => switch (this) {
        ReferralType.anotherOrganization => 'Another Organization',
        ReferralType.rescueVolunteer => 'Rescue Volunteer',
        ReferralType.localGovernmentUnit => 'Shared link',
      };

  static ReferralType fromName(String? value) => ReferralType.values
      .firstWhere((e) => e.name == value, orElse: () => ReferralType.anotherOrganization);
}

/// Current lifecycle of a referral document.
enum ReferralStatus {
  referredPending,
  accepted,
  declined,
  // The receiving organization didn't answer in time; the case went back
  // to the referring organization (functions/index.js followUpCaseReferrals).
  expired,
  // The referring organization took the case back before it was answered
  // (CaseReferralRepository.withdraw).
  withdrawn,
  notified; // used for LGU referrals, which are one-way notifications

  static ReferralStatus fromName(String? value) => ReferralStatus.values
      .firstWhere((e) => e.name == value, orElse: () => ReferralStatus.referredPending);
}

/// Why a case is referred to another organization or a rescue volunteer
/// (`referralReason` on the referral and the case's `referral` summary).
/// Analytics counts [shelterAtCapacity] as a capacity referral, together
/// with LGU [LguReferralReason.shelterAtCapacity] and the rejection reason
/// noShelterSpace.
enum OrgReferralReason {
  shelterAtCapacity('Shelter at capacity'),
  outsideServiceArea('Outside our service area'),
  specializedCare('Needs care we can\'t provide'),
  closerResponder('Another responder is closer'),
  other('Other');

  const OrgReferralReason(this.label);
  final String label;

  static OrgReferralReason? fromName(Object? value) {
    for (final r in values) {
      if (r.name == value) return r;
    }
    return null;
  }
}

/// Reason dropdown for LGU/barangay referrals.
enum LguReferralReason {
  outsideServiceArea,
  shelterAtCapacity,
  nonRescueConcern,
  animalControlRequired,
  publicSafetyConcern,
  ownerDispute,
  other;

  String get label => switch (this) {
        LguReferralReason.outsideServiceArea => 'Outside service area',
        LguReferralReason.shelterAtCapacity => 'Shelter at capacity',
        LguReferralReason.nonRescueConcern => 'Non-rescue concern',
        LguReferralReason.animalControlRequired => 'Animal control required',
        LguReferralReason.publicSafetyConcern => 'Public safety concern',
        LguReferralReason.ownerDispute => 'Owner dispute',
        LguReferralReason.other => 'Other',
      };

  static LguReferralReason fromName(String? value) => LguReferralReason.values
      .firstWhere((e) => e.name == value, orElse: () => LguReferralReason.other);
}

/// Hours a receiving organization has to answer a referral before it is
/// reminded, and before the case goes back to the referring organization.
/// Pending the organization's confirmation; keep equal to
/// REFERRAL_REMINDER_HOURS / REFERRAL_RETURN_HOURS in
/// functions/referral_rules.js.
const kReferralReminderHours = 24;
const kReferralReturnHours = 48;
