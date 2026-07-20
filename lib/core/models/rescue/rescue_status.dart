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
  cancelled;

  /// The canonical string this module writes to Firestore for this status.
  ///
  /// [accepted] and [awaitingAssignment] intentionally share `'accepted'`:
  /// in the existing flow, accepting a report immediately routes the case
  /// into the assign-rider screen, so there is no separate persisted state
  /// between the two. Call sites that need a specific legacy string other
  /// than this canonical one (e.g. assign_rider_page.dart writing
  /// `'assigned'` so the transporter's own job board keeps working) should
  /// keep writing that literal string directly rather than going through
  /// this getter.
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
        RescueStatus.accepted => 'accepted',
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
      };

  /// Every raw Firestore string that should be treated as this status when
  /// reading, including legacy/sub-state strings written by other features.
  static const Map<RescueStatus, List<String>> _legacyAliases = {
    RescueStatus.pendingReview: ['pending'],
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
      };

  /// True once the case has left the active triage/rescue pipeline.
  bool get isTerminal =>
      this == RescueStatus.rejected ||
      this == RescueStatus.merged ||
      this == RescueStatus.completed ||
      this == RescueStatus.cancelled;
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
