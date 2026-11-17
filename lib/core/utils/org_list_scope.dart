import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Which organization's records a staff-wide list may read.
///
/// firestore.rules only allows a query across many parents (collection
/// groups, the animal list) when it filters on organizationId, except for
/// platform staff (users/{uid}.role 'admin' or 'ngo_staff'), who see every
/// organization — except money ([money] true): donor records and payments
/// are readable only by the organization's own people, so platform staff
/// list their own organization's, or nothing.
sealed class OrgListScope {
  const OrgListScope();

  /// Platform staff: no filter.
  static const all = _AllOrganizations();

  /// Signed out, or not linked to an organization: nothing to list.
  static const none = _NoOrganization();

  /// Restricts [query] to this scope. Don't call for [none].
  Query<T> apply<T>(Query<T> query);

  bool get isNone => this is _NoOrganization;

  bool get isAll => this is _AllOrganizations;

  /// Resolves the scope for the signed-in account.
  static Future<OrgListScope> current({FirebaseFirestore? firestore, bool money = false}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return none;
    final user = (await (firestore ?? FirebaseFirestore.instance).collection('users').doc(uid).get()).data() ??
        const <String, dynamic>{};
    if (!money && const ['admin', 'ngo_staff'].contains(user['role'])) return all;
    final orgId = (user['organizationId'] as String?) ?? '';
    return orgId.isEmpty ? none : OneOrganization(orgId);
  }

  /// A stream built from the scoped [query], or [empty] when there is
  /// nothing to list.
  static Stream<R> watch<T, R>(
    Query<T> query,
    R Function(QuerySnapshot<T> snap) map, {
    required R empty,
    FirebaseFirestore? firestore,
    bool money = false,
  }) async* {
    final scope = await current(firestore: firestore, money: money);
    if (scope.isNone) {
      yield empty;
      return;
    }
    yield* scope.apply(query).snapshots().map(map);
  }
}

class _AllOrganizations extends OrgListScope {
  const _AllOrganizations();

  @override
  Query<T> apply<T>(Query<T> query) => query;
}

class _NoOrganization extends OrgListScope {
  const _NoOrganization();

  @override
  Query<T> apply<T>(Query<T> query) => throw StateError('No organization to list.');
}

class OneOrganization extends OrgListScope {
  const OneOrganization(this.organizationId);

  final String organizationId;

  @override
  Query<T> apply<T>(Query<T> query) => query.where('organizationId', isEqualTo: organizationId);
}
