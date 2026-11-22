/// Content of the independent reporting guide for suspected animal neglect
/// or abuse (NeglectAbuseGuideSheet). Kept as data, apart from the UI, so
/// it can be reviewed and replaced without touching any screen.
///
/// SOURCE STATUS — READ BEFORE EDITING
/// The request was to base this on the Philippine Animal Welfare Society
/// (PAWS) reporting guidelines. Their site could not be reached when this
/// was written, so the steps below are Respawnd's own general, safety-first
/// guidance. They deliberately contain no phone numbers, fees, deadlines,
/// legal requirements or claims about what any office must do. Until PAWS's
/// published guidance has been checked and adapted here:
///   * keep [kAbuseGuideVerifiedAgainstPaws] false, so the app says the
///     guide is general guidance and not PAWS's or the government's;
///   * do not add contact details or legal procedures from memory.
/// When verified, set [kAbuseGuideSourceNote] to cite the exact PAWS page
/// and mark which steps are PAWS recommendations and which are official
/// government procedures (see GuideStep.source).
library;

const bool kAbuseGuideVerifiedAgainstPaws = false;

const String kAbuseGuideSourceNote = kAbuseGuideVerifiedAgainstPaws
    ? ''
    : 'This is general guidance from Respawnd. It is not yet verified against '
        'the Philippine Animal Welfare Society (PAWS) guidelines, it is not '
        'legal advice, and it is not an official government procedure. Your '
        'local government and the authorities you report to decide how a '
        'complaint is handled.';

/// Where a step's content comes from, shown next to it once verified.
enum GuideSource { respawndGeneral, pawsRecommendation, officialProcedure }

class GuideStep {
  const GuideStep({
    required this.title,
    required this.summary,
    required this.points,
    this.source = GuideSource.respawndGeneral,
  });

  final String title;
  final String summary;
  final List<String> points;
  final GuideSource source;
}

const List<GuideStep> kNeglectAbuseGuideSteps = [
  GuideStep(
    title: 'Document what you see',
    summary: 'Record facts, only when it is safe to do so.',
    points: [
      'Take photos or videos from a public place or with permission. Do not '
          'enter private property to get them.',
      'Write down the exact location, the date and the time of each '
          'observation.',
      'Describe what you observed: the animal\'s condition, injuries, food, '
          'water and shelter, how it is confined, and how long it has been that '
          'way.',
      'Stick to what you saw and heard. Avoid accusations or guesses about '
          'intent.',
      'Keep the original files. Note anyone else who saw it and is willing '
          'to be contacted.',
    ],
  ),
  GuideStep(
    title: 'Keep yourself and the animal safe',
    summary: 'Do not confront anyone or take the animal yourself.',
    points: [
      'Do not confront the person you suspect.',
      'Do not trespass or put yourself, or the animal, in more danger.',
      'Do not seize or remove an animal from private property without proper '
          'authority or coordination with the authorities.',
      'Avoid posting accusations or the person\'s identity online: it can put '
          'you at risk and get in the way of a complaint.',
      'If a person is in immediate danger, contact the police right away.',
    ],
  ),
  GuideStep(
    title: 'Report it to the authorities',
    summary: 'Bring your account and evidence to a local office.',
    points: [
      'Ask your local government which office takes animal welfare '
          'complaints in your area. Depending on the place, this may be your '
          'barangay, the local police station, or the city or municipal '
          'veterinary office.',
      'Bring a written account (what, where, when), your photos and videos, '
          'and your contact details.',
      'Mention that you are reporting suspected neglect or cruelty to an '
          'animal. The Philippine Animal Welfare Act (Republic Act No. 8485, as '
          'amended by Republic Act No. 10631) covers animal welfare; the office '
          'you report to will tell you how they apply it.',
      'You may ask whether your identity can be kept confidential.',
    ],
  ),
  GuideStep(
    title: 'Work with the authorities',
    summary: 'Give accurate information and keep a record of your report.',
    points: [
      'Answer questions accurately and say when you are not sure.',
      'Ask for an acknowledgment, reference or blotter number if one is given.',
      'Write down the name of the person or office that received your report '
          'and the date.',
      'Follow the instructions of authorized personnel.',
    ],
  ),
  GuideStep(
    title: 'Help the animal while you wait, safely',
    summary: 'Support without compromising the case.',
    points: [
      'If the animal is in a public place and it is safe, you can ask a '
          'veterinarian for advice.',
      'If the animal needs urgent care and is not on private property, '
          'coordinate with a veterinarian or an authorized rescuer, or ask the '
          'organization for assistance from this app.',
      'Do not move evidence, damage property or take the animal from its '
          'owner\'s property.',
    ],
  ),
  GuideStep(
    title: 'Follow up',
    summary: 'Keep watching from a safe distance and keep your report current.',
    points: [
      'Note any change in the animal\'s situation, with the date and time.',
      'Give new evidence to the office you reported to, quoting your '
          'reference number.',
      'If nothing seems to happen, follow up with the same office first, then '
          'ask your local government which other office can act.',
      'You can add your report details or ask the organization for assistance '
          'at any time from this report\'s tracking page.',
    ],
  ),
];
