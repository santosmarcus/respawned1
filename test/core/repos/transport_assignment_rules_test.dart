import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/pet_transporter.dart';
import 'package:respawnd1/core/models/rescue/transport_assignment.dart';
import 'package:respawnd1/core/repos/rescue_case/transport_assignment_rules.dart';

void main() {
  group('creating an offer', () {
    test('a pending offer always blocks a new one', () {
      expect(
        resolveOfferConflict('pending', allowReassign: false),
        OfferConflictResolution.block,
      );
      expect(
        resolveOfferConflict('pending', allowReassign: true),
        OfferConflictResolution.block,
      );
    });

    test('an accepted offer blocks unless reassigning', () {
      expect(
        resolveOfferConflict('accepted', allowReassign: false),
        OfferConflictResolution.block,
      );
      expect(
        resolveOfferConflict('accepted', allowReassign: true),
        OfferConflictResolution.supersede,
      );
    });

    test('finished or dangling pointers never block', () {
      for (final status in [
        'rejected',
        'cancelled',
        'completed',
        'expired',
        null,
      ]) {
        expect(
          resolveOfferConflict(status, allowReassign: false),
          OfferConflictResolution.none,
          reason: '$status',
        );
      }
    });

    test('only a fresh online presence counts as still online', () {
      final now = DateTime(2026, 10, 25, 12);
      expect(
        isTransporterStillOnline(
          online: true,
          lastSeenAt: now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        isTrue,
      );
      expect(
        isTransporterStillOnline(
          online: true,
          lastSeenAt: now.subtract(kTransporterPresenceThreshold),
          now: now,
        ),
        isTrue,
      );
      expect(
        isTransporterStillOnline(
          online: true,
          lastSeenAt: now.subtract(
            kTransporterPresenceThreshold + const Duration(seconds: 1),
          ),
          now: now,
        ),
        isFalse,
      );
      expect(
        isTransporterStillOnline(online: false, lastSeenAt: now, now: now),
        isFalse,
      );
      expect(
        isTransporterStillOnline(online: true, lastSeenAt: null, now: now),
        isFalse,
      );
    });
  });

  group('responding to an offer', () {
    test('accepting needs an existing, pending, current offer', () {
      expect(
        offerResponseBlockReason(
          exists: false,
          status: null,
          assignmentId: 'a1',
          requireCurrent: true,
        ),
        'assignment no longer exists',
      );
      expect(
        offerResponseBlockReason(
          exists: true,
          status: 'accepted',
          assignmentId: 'a1',
          currentAssignmentId: 'a1',
          requireCurrent: true,
        ),
        'status is accepted, not pending',
      );
      expect(
        offerResponseBlockReason(
          exists: true,
          status: 'pending',
          assignmentId: 'a1',
          currentAssignmentId: 'a2',
          requireCurrent: true,
        ),
        'a newer offer has superseded this one',
      );
      expect(
        offerResponseBlockReason(
          exists: true,
          status: 'pending',
          assignmentId: 'a1',
          currentAssignmentId: 'a1',
          requireCurrent: true,
        ),
        isNull,
      );
    });

    test('rejecting ignores which offer is current', () {
      expect(
        offerResponseBlockReason(
          exists: true,
          status: 'pending',
          assignmentId: 'a1',
          currentAssignmentId: 'a2',
        ),
        isNull,
      );
    });

    test('expiry compares against the offer\'s own expiresAt', () {
      final expires = Timestamp.fromDate(DateTime(2026, 10, 25, 12));
      expect(
        isOfferExpired(expires, Timestamp.fromDate(DateTime(2026, 10, 25, 13))),
        isTrue,
      );
      expect(
        isOfferExpired(expires, Timestamp.fromDate(DateTime(2026, 10, 25, 11))),
        isFalse,
      );
      expect(isOfferExpired(expires, expires), isFalse);
      expect(isOfferExpired(null, Timestamp.now()), isFalse);
      expect(isOfferExpired('2026-10-25', Timestamp.now()), isFalse);
    });
  });

  group('assignment model', () {
    test('unknown statuses read as pending', () {
      expect(
        TransportAssignmentStatus.fromName('accepted'),
        TransportAssignmentStatus.accepted,
      );
      expect(
        TransportAssignmentStatus.fromName('bogus'),
        TransportAssignmentStatus.pending,
      );
      expect(
        TransportAssignmentStatus.fromName(null),
        TransportAssignmentStatus.pending,
      );
    });

    TransportAssignment assignment(
      TransportAssignmentStatus status, {
      DateTime? expiresAt,
    }) => TransportAssignment(
      id: 'a1',
      caseId: 'c1',
      riderId: 'r1',
      riderName: 'Rider',
      riderType: 'Pet Transporter',
      status: status,
      expiresAt: expiresAt,
    );

    test('only pending and accepted offers are active', () {
      expect(assignment(TransportAssignmentStatus.pending).isActive, isTrue);
      expect(assignment(TransportAssignmentStatus.accepted).isActive, isTrue);
      for (final s in [
        TransportAssignmentStatus.rejected,
        TransportAssignmentStatus.cancelled,
        TransportAssignmentStatus.completed,
        TransportAssignmentStatus.expired,
      ]) {
        expect(assignment(s).isActive, isFalse, reason: s.name);
      }
    });

    test('isStalePending only flags a pending offer past expiry', () {
      final past = DateTime.now().subtract(const Duration(minutes: 1));
      final future = DateTime.now().add(kTransportOfferTtl);
      expect(
        assignment(
          TransportAssignmentStatus.pending,
          expiresAt: past,
        ).isStalePending,
        isTrue,
      );
      expect(
        assignment(
          TransportAssignmentStatus.pending,
          expiresAt: future,
        ).isStalePending,
        isFalse,
      );
      expect(
        assignment(
          TransportAssignmentStatus.accepted,
          expiresAt: past,
        ).isStalePending,
        isFalse,
      );
      expect(
        assignment(TransportAssignmentStatus.pending).isStalePending,
        isFalse,
      );
    });

    test('conflict messages name the rider when known', () {
      const pending = ActiveAssignmentConflictException(
        assignmentId: 'a1',
        status: TransportAssignmentStatus.pending,
        riderName: 'Juan',
        riderType: 'Pet Transporter',
      );
      expect(
        pending.userMessage,
        'This case already has a pending assignment for Juan.',
      );
      final accepted = ActiveAssignmentConflictException.fromMap('a2', {
        'status': 'accepted',
        'riderName': 'Ana',
      });
      expect(accepted.userMessage, 'This case is currently assigned to Ana.');
      final unknown = ActiveAssignmentConflictException.fromMap('a3', {
        'status': 'pending',
      });
      expect(unknown.hasKnownIdentity, isFalse);
      expect(
        unknown.userMessage,
        'An active transporter assignment already exists.',
      );
    });
  });
}
