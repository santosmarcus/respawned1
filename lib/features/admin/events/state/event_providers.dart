import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:respawnd1/core/models/volunteer/volunteer_event.dart';
import 'package:respawnd1/core/repos/volunteer_event_repository.dart';

final volunteerEventRepositoryProvider = Provider<VolunteerEventRepository>((ref) {
  return VolunteerEventRepository();
});

final organizationEventsProvider =
    StreamProvider.family.autoDispose<List<VolunteerEvent>, String>((ref, organizationId) {
  return ref.watch(volunteerEventRepositoryProvider).streamOrganizationEvents(organizationId);
});

final eventDetailProvider = StreamProvider.family.autoDispose<VolunteerEvent?, String>((ref, eventId) {
  return ref.watch(volunteerEventRepositoryProvider).streamEvent(eventId);
});

final eventRegistrationsProvider =
    StreamProvider.family.autoDispose<List<EventRegistration>, String>((ref, eventId) {
  return ref.watch(volunteerEventRepositoryProvider).streamRegistrations(eventId);
});
