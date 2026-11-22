import 'package:intl/intl.dart';

import 'package:respawnd1/core/models/rescue/rescue_case.dart';
import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/utils/species_summary.dart';
import 'package:respawnd1/core/utils/currency.dart';
import 'package:respawnd1/features/donation/models.dart';

/// Suggested Facebook post text for a donation or sponsorship campaign.
/// Staff edit it in FacebookRecordPostPage before posting.
String composeCampaignPost(DonationListing c, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final isSponsorship = c.type == 'sponsorship';
  final animal = (c.animalName ?? '').trim();
  final lines = <String>[
    isSponsorship && animal.isNotEmpty ? '💛 Sponsor $animal — ${c.title.trim()}' : '💛 ${c.title.trim()}',
  ];

  final description = c.description.trim();
  if (description.isNotEmpty) lines.add(description);

  final facts = <String>[];
  if (isSponsorship) {
    if (c.monthlyAmount != null && c.monthlyAmount! > 0) facts.add('🐾 ${formatPeso(c.monthlyAmount!)} a month');
  } else if (c.target > 0) {
    facts.add('📊 ${formatPeso(c.collected)} raised of ${formatPeso(c.target)} (${c.percentage}%)');
  }
  if (c.status == 'goal_met') {
    facts.add('🎉 Goal reached — thank you to everyone who gave!');
  } else if (c.endDate != null && c.endDate!.isAfter(today)) {
    facts.add('⏳ Until ${DateFormat('MMMM d, y').format(c.endDate!)}');
  }
  if (c.acceptInKind && c.inKindItems.isNotEmpty) {
    final needs = {for (final i in c.inKindItems) i.category.trim()}.where((s) => s.isNotEmpty).toList();
    if (needs.isNotEmpty) facts.add('📦 We also accept in-kind donations: ${needs.join(', ')}');
  }
  if (c.organizer.trim().isNotEmpty) facts.add('🏠 Organized by ${c.organizer.trim()}');
  if (facts.isNotEmpty) lines.add(facts.join('\n'));

  lines.add(
    c.status == 'goal_met' || c.status == 'closed'
        ? 'See where the funds went on the ResPAWnd app.'
        : isSponsorship
        ? 'Become a sponsor on the ResPAWnd app. 🙏'
        : 'Donate or share this post to help. You can give through the ResPAWnd app. 🙏',
  );
  return lines.join('\n\n');
}

/// Suggested Facebook post text for a volunteer event.
String composeEventPost(VolunteerEvent e) {
  final lines = <String>['📣 ${e.title.trim()}'];

  final details = <String>[
    '🗓 ${e.date}',
    '🕒 ${e.time}',
    if (e.location.trim().isNotEmpty || e.addressFull.trim().isNotEmpty)
      '📍 ${e.addressFull.trim().isNotEmpty ? e.addressFull.trim() : e.location.trim()}',
    if (e.capacity != null)
      e.isFull
          ? '👥 All ${e.capacity} spots are taken'
          : '👥 ${e.capacity! - e.goingCount} of ${e.capacity} spots left',
    if (e.organizerName.trim().isNotEmpty) '🏠 Organized by ${e.organizerName.trim()}',
  ];
  lines.add(details.join('\n'));

  final description = e.description.trim();
  if (description.isNotEmpty) lines.add(description);

  lines.add(
    e.isPast
        ? 'Thank you to everyone who came! 💛'
        : 'Sign up on the ResPAWnd app (Home → Events) to get your e-ticket. See you there! 🐾',
  );
  return lines.join('\n\n');
}

/// Suggested Facebook post text for a case referred by shared link: what
/// the animal is, how urgent, where, and the link to take it. Never the
/// reporter. Staff edit it in FacebookRecordPostPage before posting.
String composeReferralPost(RescueCase c, String url) {
  final species = summarizeSpecies(
    animals: c.raw['animals'] as List?,
    legacyAnimalType: c.raw['animalType'] as String?,
  );
  final lines = <String>['🆘 Rescue help needed: $species'];
  final facts = <String>[
    if ((c.urgency ?? '').trim().isNotEmpty) '⚠️ Urgency: ${c.urgency!.trim()}',
    if ((c.address ?? '').trim().isNotEmpty) '📍 ${c.address!.trim()}',
  ];
  if (facts.isNotEmpty) lines.add(facts.join('\n'));
  final condition = (c.condition ?? '').trim();
  if (condition.isNotEmpty) lines.add(condition);
  lines.add('Can you help? See the report and reply here: $url');
  return lines.join('\n\n');
}
