import 'package:respawnd1/features/donation/models.dart';

/// Lifecycle statuses still "being tracked" (drafts included so admins can
/// find and publish them).
const currentListingStatuses = {'draft', 'active', 'paused'};

/// Finished listings that stay on the home screen until every peso is
/// allocated and an admin archives them.
const completedListingStatuses = {'goal_met', 'goal_not_met', 'closed'};

/// What View All / search shows by default: everything but archived
/// (archived listings are fully allocated; the filter sheet can add them).
const defaultSearchStatuses = {...currentListingStatuses, ...completedListingStatuses};

/// Ongoing listing. Ended-by-date listings the hourly job hasn't processed
/// yet still read as "active"; isEnded keeps them out of the current list.
bool isCurrentListing(DonationListing l) =>
    currentListingStatuses.contains(l.status) && (l.isDraft || l.status == 'paused' || !l.isEnded);

/// Current listings of one type, in provider order (newest first).
List<DonationListing> currentListings(Iterable<DonationListing> all, String type) =>
    all.where((l) => l.type == type && isCurrentListing(l)).toList();

/// Finished, not yet archived listings of one type; the most unallocated
/// money first. Ones still waiting for an extend/close decision are listed
/// separately under "Needs your decision".
List<DonationListing> completedListings(Iterable<DonationListing> all, String type) => all
    .where((l) => l.type == type && completedListingStatuses.contains(l.status) && !l.needsExtensionDecision)
    .toList()
  ..sort((a, b) => b.availableBalance.compareTo(a.availableBalance));

/// Search / View All filter. [type] null means both types; [query] must
/// already be trimmed and lower-cased.
bool matchesListingSearch(DonationListing l, {String? type, required Set<String> statuses, String query = ''}) {
  if (type != null && l.type != type) return false;
  if (!statuses.contains(l.status)) return false;
  if (query.isEmpty) return true;
  return l.title.toLowerCase().contains(query) ||
      (l.animalName ?? '').toLowerCase().contains(query) ||
      l.organizer.toLowerCase().contains(query);
}
