import 'package:flutter/material.dart';
import 'package:respawnd1/app_theme.dart';

/// Case-level triage status used across the admin rescue module.
///
/// The `cases` collection predates this enum and is also written/read by
/// the reporter app and the pet-transporter app (see
/// lib/features/pettransporter/transit_progress_page.dart and
/// lib/features/pettransporter/service_screen.dart). To avoid breaking
/// those already-working flows, this enum does NOT rename any existing
/// persisted status string — it only adds the new values this module
/// needs (referred, possibleDuplicate, merged, cancelled) and maps
/// several admin-facing statuses onto the richer set of raw strings the
/// transporter flow already writes (e.g. `ongoing` covers `assigned`,
/// `searching_clinic`, `arrived`, `in_transit_shelter`, `dropoff`).
enum RescueStatus {
  pendingReview,
  accepted,
  awaitingAssignment,
  rejected,
  referred,
  possibleDuplicate,
  merged,
  ongoing,
  treatment,
  intake,
  completed,
  cancelled,
  // The four statuses below back the pet-transporter "End Reason" flow in
  // transit_progress_page.dart (_showCloseTransitDialog /
  // _resolveEndReason). Unlike [cancelled], none of these mean the rescue
  // itself failed — the case is still expected to be picked up, either by
  // the same transporter once the reporter responds, or (for
  // [needsSpecializedAssistance]) by a different handler org staff assign.
  // A scheduled Cloud Function (see functions/index.js
  // expireStaleReporterResponses) auto-closes [unableToLocate],
  // [awaitingReporterResponse], and [pickupUnsuccessful] cases after a
  // configurable no-response window; [needsSpecializedAssistance] is
  // intentionally excluded from that auto-expiry since it's waiting on
  // staff/organization action, not the reporter.
  unableToLocate,
  awaitingReporterResponse,
  pickupUnsuccessful,
  needsSpecializedAssistance;

  /// The canonical string this module writes to Firestore for this status.
  ///
  /// [accepted] and [awaitingAssignment] used to intentionally share
  /// `'accepted'` back when accepting a report immediately routed the case
  /// into the assign-rider screen with no separate persisted state between
  /// the two. That's no longer true: [acceptCase] now stops at [accepted]
  /// (case is accepted but has no saved clinic yet, stays under Rescue
  /// Review) and only advances to [awaitingAssignment] once [assignClinic]
  /// actually saves one — so the two need distinguishable Firestore
  /// strings. [accepted] was never previously written with its own
  /// canonical value (only ever read back as [awaitingAssignment] via that
  /// status's `'accepted'` legacy alias below), so giving it
  /// `'accepted_pending_clinic'` here doesn't change how any existing
  /// persisted case data is interpreted. Call sites that need a specific
  /// legacy string other than this canonical one (e.g. assign_rider_page.dart
  /// writing `'assigned'` so the transporter's own job board keeps working)
  /// should keep writing that literal string directly rather than going
  /// through this getter.
  ///
  /// ROOT CAUSE (fixed here) of "Proceed to Treatment doesn't leave
  /// Ongoing": this getter used to return the bare string `'treatment'` for
  /// [treatment] — but the pet-transporter app already writes that exact
  /// string to mean "picked up, en route to the clinic" (see
  /// transit_progress_page.dart), and `'treatment'` was (correctly, for
  /// that meaning) listed in [ongoing]'s own `_legacyAliases`. Since
  /// [fromFirestoreValue] checks [ongoing]'s aliases before [treatment]'s,
  /// a case admin-marked as "in treatment" via this getter was immediately
  /// read back as [ongoing] everywhere (Rescue Reports tabs, Rescue
  /// Details' action buttons, this enum's own `queryValues`). [treatment]
  /// already declared the non-colliding alias `'in_treatment'` below —
  /// this getter just wasn't writing it. Now it does, so the write and the
  /// read finally agree.
  String get firestoreValue => switch (this) {
    RescueStatus.pendingReview => 'pending',
    RescueStatus.accepted => 'accepted_pending_clinic',
    RescueStatus.awaitingAssignment => 'accepted',
    RescueStatus.rejected => 'rejected',
    RescueStatus.referred => 'referred',
    RescueStatus.possibleDuplicate => 'possibleDuplicate',
    RescueStatus.merged => 'merged',
    RescueStatus.ongoing => 'ongoing',
    RescueStatus.treatment => 'in_treatment',
    RescueStatus.intake => 'intake',
    RescueStatus.completed => 'completed',
    RescueStatus.cancelled => 'cancelled',
    RescueStatus.unableToLocate => 'unable_to_locate',
    RescueStatus.awaitingReporterResponse => 'awaiting_reporter_response',
    RescueStatus.pickupUnsuccessful => 'pickup_attempt_unsuccessful',
    RescueStatus.needsSpecializedAssistance => 'needs_specialized_assistance',
  };

  /// Every raw Firestore string that should be treated as this status when
  /// reading, including legacy/sub-state strings written by other features.
  static const Map<RescueStatus, List<String>> _legacyAliases = {
    RescueStatus.pendingReview: ['pending'],
    RescueStatus.accepted: ['accepted_pending_clinic'],
    RescueStatus.awaitingAssignment: ['accepted'],
    RescueStatus.rejected: ['rejected'],
    RescueStatus.referred: ['referred'],
    RescueStatus.possibleDuplicate: ['possibleDuplicate'],
    RescueStatus.merged: ['merged'],
    // Every transit sub-state the pet-transporter app writes while it's
    // actively moving the animal — including its own 'treatment' value,
    // which despite the name means "picked up, en route to the clinic",
    // NOT "receiving care". 'dropoff' is the real "arrived at the clinic"
    // signal (see transit_progress_page.dart _arriveAtClinic /
    // _submitPickupVerification). None of these represent the multi-day
    // clinical-care phase admin_track_case_page.dart / treatment_detail_page.dart
    // model — that only begins once staff explicitly click "Proceed to
    // Treatment" once the case reaches 'dropoff'.
    RescueStatus.ongoing: [
      'assigned',
      'ongoing',
      'searching_clinic',
      'arrived',
      'in_transit_shelter',
      'dropoff',
      'treatment',
    ],
    RescueStatus.treatment: ['in_treatment'],
    RescueStatus.intake: ['intake'],
    RescueStatus.completed: ['completed', 'closed'],
    RescueStatus.cancelled: ['cancelled'],
    RescueStatus.unableToLocate: ['unable_to_locate'],
    RescueStatus.awaitingReporterResponse: ['awaiting_reporter_response'],
    RescueStatus.pickupUnsuccessful: ['pickup_attempt_unsuccessful'],
    RescueStatus.needsSpecializedAssistance: ['needs_specialized_assistance'],
  };

  static RescueStatus fromFirestoreValue(String? value) {
    if (value == null || value.isEmpty) return RescueStatus.pendingReview;
    for (final entry in _legacyAliases.entries) {
      if (entry.value.contains(value)) return entry.key;
    }
    return RescueStatus.pendingReview;
  }

  /// All raw string values to include when querying Firestore for cases in
  /// this status (covers legacy aliases/sub-states in a single `whereIn`).
  List<String> get queryValues => _legacyAliases[this] ?? [firestoreValue];

  String get label => switch (this) {
    RescueStatus.pendingReview => 'Pending Review',
    RescueStatus.accepted => 'Accepted',
    RescueStatus.awaitingAssignment => 'Awaiting Assignment',
    RescueStatus.rejected => 'Rejected',
    RescueStatus.referred => 'Referred',
    RescueStatus.possibleDuplicate => 'Possible Duplicate',
    RescueStatus.merged => 'Merged',
    RescueStatus.ongoing => 'Ongoing',
    RescueStatus.treatment => 'In Treatment',
    RescueStatus.intake => 'Intake',
    RescueStatus.completed => 'Completed',
    RescueStatus.cancelled => 'Cancelled',
    RescueStatus.unableToLocate => 'Unable to Locate Animal',
    RescueStatus.awaitingReporterResponse => 'Awaiting Reporter Response',
    RescueStatus.pickupUnsuccessful => 'Pickup Attempt Unsuccessful',
    RescueStatus.needsSpecializedAssistance => 'Needs Specialized Assistance',
  };

  Color get color => switch (this) {
    RescueStatus.pendingReview => AppColors.slaterspwn,
    RescueStatus.accepted => AppColors.yellowrspwn,
    RescueStatus.awaitingAssignment => AppColors.yellowrspwn,
    RescueStatus.rejected => const Color(0xFFE05353),
    RescueStatus.referred => AppColors.lavenderrspwn,
    RescueStatus.possibleDuplicate => const Color(0xFFE0A030),
    RescueStatus.merged => AppColors.tearspwn,
    RescueStatus.ongoing => AppColors.greenrspwn,
    RescueStatus.treatment => const Color(0xFF4E8FE0),
    RescueStatus.intake => const Color(0xFF9C7A4C),
    RescueStatus.completed => const Color(0xFF4CAF6D),
    RescueStatus.cancelled => AppColors.textSecondary,
    RescueStatus.unableToLocate => const Color(0xFFE0A030),
    RescueStatus.awaitingReporterResponse => const Color(0xFFE0A030),
    RescueStatus.pickupUnsuccessful => const Color(0xFFE0A030),
    RescueStatus.needsSpecializedAssistance => const Color(0xFFE05353),
  };

  /// True once the case has left the active triage/rescue pipeline.
  bool get isTerminal =>
      this == RescueStatus.rejected ||
          this == RescueStatus.merged ||
          this == RescueStatus.completed ||
          this == RescueStatus.cancelled;

  /// True for the three reporter-facing "waiting on you" statuses that the
  /// scheduled auto-expiry function in functions/index.js
  /// (expireStaleReporterResponses) will close automatically if the
  /// reporter never responds within the configured window.
  bool get isAwaitingReporterResponse =>
      this == RescueStatus.unableToLocate ||
          this == RescueStatus.awaitingReporterResponse ||
          this == RescueStatus.pickupUnsuccessful;
}

/// Rescue urgency level. Kept as a thin typed wrapper around the existing
/// 'Critical' / 'Medium' / 'Low' strings already used throughout
/// lib/features/rescue and lib/features/admin/rescue, so existing raw-string
/// call sites keep working while new filter/chip UI gets type safety.
enum UrgencyLevel {
  critical,
  medium,
  low;

  String get firestoreValue => switch (this) {
    UrgencyLevel.critical => 'Critical',
    UrgencyLevel.medium => 'Medium',
    UrgencyLevel.low => 'Low',
  };

  static UrgencyLevel? fromFirestoreValue(String? value) => switch (value) {
    'Critical' => UrgencyLevel.critical,
    'Medium' => UrgencyLevel.medium,
    'Low' => UrgencyLevel.low,
    _ => null,
  };

  Color get color => switch (this) {
    UrgencyLevel.critical => const Color(0xFFE05353),
    UrgencyLevel.medium => AppColors.yellowrspwn,
    UrgencyLevel.low => AppColors.greenrspwn,
  };
}