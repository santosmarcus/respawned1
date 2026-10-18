/// Who a rescue case is being referred to.
enum ReferralType {
  anotherOrganization,
  rescueVolunteer,
  localGovernmentUnit;

  String get label => switch (this) {
        ReferralType.anotherOrganization => 'Another Organization',
        ReferralType.rescueVolunteer => 'Rescue Volunteer',
        ReferralType.localGovernmentUnit => 'LGU / Barangay',
      };

  static ReferralType fromName(String? value) => ReferralType.values
      .firstWhere((e) => e.name == value, orElse: () => ReferralType.anotherOrganization);
}

/// Current lifecycle of a referral document.
enum ReferralStatus {
  referredPending,
  accepted,
  declined,
  notified; // used for LGU referrals, which are one-way notifications

  static ReferralStatus fromName(String? value) => ReferralStatus.values
      .firstWhere((e) => e.name == value, orElse: () => ReferralStatus.referredPending);
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
