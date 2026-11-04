import 'package:cloud_firestore/cloud_firestore.dart';

/// What a volunteer offers to help with (paper 1.4.5).
enum VolunteerCategory {
  rescue,
  event,
  carer;

  String get label => switch (this) {
        VolunteerCategory.rescue => 'Rescue operations',
        VolunteerCategory.event => 'Events and drives',
        VolunteerCategory.carer => 'Shelter care',
      };

  static VolunteerCategory? fromName(String? name) {
    for (final c in values) {
      if (c.name == name) return c;
    }
    return null;
  }
}

enum VolunteerApplicationStatus {
  pending,
  approved,
  rejected;

  String get label => switch (this) {
        VolunteerApplicationStatus.pending => 'Under review',
        VolunteerApplicationStatus.approved => 'Approved',
        VolunteerApplicationStatus.rejected => 'Not approved',
      };

  static VolunteerApplicationStatus fromName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => VolunteerApplicationStatus.pending);
}

/// `volunteerApplications/{uid}`: one application per account. Organization
/// staff review it; only physical rescue work needs an approved application.
class VolunteerApplication {
  final String uid;
  final String name;
  final String phone;
  final Set<VolunteerCategory> categories;
  final String availability;
  final String serviceArea;
  final String experience;
  final VolunteerApplicationStatus status;
  final String? reviewNote;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;

  const VolunteerApplication({
    required this.uid,
    required this.name,
    required this.phone,
    required this.categories,
    required this.availability,
    required this.serviceArea,
    required this.experience,
    this.status = VolunteerApplicationStatus.pending,
    this.reviewNote,
    this.submittedAt,
    this.reviewedAt,
  });

  factory VolunteerApplication.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    DateTime? ts(String k) => (d[k] as Timestamp?)?.toDate();
    return VolunteerApplication(
      uid: doc.id,
      name: d['name'] as String? ?? '',
      phone: d['phone'] as String? ?? '',
      categories: {
        for (final c in (d['categories'] as List? ?? const []))
          ?VolunteerCategory.fromName(c as String?),
      },
      availability: d['availability'] as String? ?? '',
      serviceArea: d['serviceArea'] as String? ?? '',
      experience: d['experience'] as String? ?? '',
      status: VolunteerApplicationStatus.fromName(d['status'] as String?),
      reviewNote: d['reviewNote'] as String?,
      submittedAt: ts('submittedAt'),
      reviewedAt: ts('reviewedAt'),
    );
  }

  /// Fields the applicant writes. Status always resets to pending, so an
  /// edited application goes back for review.
  Map<String, dynamic> toSubmission() => {
        'uid': uid,
        'name': name.trim(),
        'phone': phone.trim(),
        'categories': [for (final c in categories) c.name],
        'availability': availability.trim(),
        'serviceArea': serviceArea.trim(),
        'experience': experience.trim(),
        'status': VolunteerApplicationStatus.pending.name,
        'submittedAt': FieldValue.serverTimestamp(),
      };

  /// Problems with the form, or empty if it can be submitted.
  List<String> validate() => [
        if (name.trim().isEmpty) 'Enter your name.',
        if (phone.trim().length < 7) 'Enter a phone number.',
        if (categories.isEmpty) 'Pick at least one way to help.',
        if (availability.trim().isEmpty) 'Say when you are available.',
      ];
}
