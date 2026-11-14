import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/rescue/report_verification.dart';

void main() {
  // Manila; one hundredth of a degree of latitude is about 1.1 km.
  const pinLat = 14.5995, pinLng = 120.9842;

  group('evidenceFlags', () {
    test('an old report with no evidence says so instead of guessing', () {
      final flags = evidenceFlags(null, pinLat: pinLat, pinLng: pinLng);
      expect(flags, hasLength(1));
      expect(flags.single.level, EvidenceLevel.unknown);
    });

    test('phone at the pin with camera photos supports the report', () {
      final flags = evidenceFlags(
        const ReportEvidence(cameraMediaCount: 2, deviceLat: pinLat + 0.001, deviceLng: pinLng),
        pinLat: pinLat,
        pinLng: pinLng,
      );
      expect(flags.map((f) => f.level), [EvidenceLevel.supports, EvidenceLevel.supports]);
      expect(flags.first.label, 'Reporter was at the location');
    });

    test('phone a little way off is a caution, far away is a concern', () {
      EvidenceLevel levelAt(double latOffset) => evidenceFlags(
            ReportEvidence(deviceLat: pinLat + latOffset, deviceLng: pinLng, pinSource: PinSource.map),
            pinLat: pinLat,
            pinLng: pinLng,
          ).first.level;
      expect(levelAt(0.01), EvidenceLevel.caution); // about 1.1 km
      expect(levelAt(0.05), EvidenceLevel.concern); // about 5.5 km
    });

    test('no phone location is unknown, not a concern', () {
      final flags = evidenceFlags(const ReportEvidence(cameraMediaCount: 1), pinLat: pinLat, pinLng: pinLng);
      expect(flags.first.level, EvidenceLevel.unknown);
      expect(flags.first.label, 'Phone location not shared');
    });

    test('gallery photos are a caution and say how many', () {
      final mixed = evidenceFlags(const ReportEvidence(cameraMediaCount: 1, galleryMediaCount: 2));
      expect(mixed.last.level, EvidenceLevel.caution);
      expect(mixed.last.label, '2 of 3 photos or videos came from the gallery');

      final all = evidenceFlags(const ReportEvidence(galleryMediaCount: 2));
      expect(all.last.label, 'All 2 photos or videos came from the gallery');
    });
  });

  group('ReportEvidence', () {
    test('round-trips through its stored map', () {
      final fixAt = DateTime(2026, 11, 15, 9, 30);
      final stored = ReportEvidence(
        cameraMediaCount: 2,
        galleryMediaCount: 1,
        pinSource: PinSource.search,
        deviceLat: pinLat,
        deviceLng: pinLng,
        deviceAccuracyM: 12.5,
        deviceFixAt: fixAt,
      ).toMap();
      final read = ReportEvidence.fromMap(stored)!;
      expect(read.mediaCount, 3);
      expect(read.pinSource, PinSource.search);
      expect(read.deviceAccuracyM, 12.5);
      expect(read.deviceFixAt, fixAt);
    });

    test('leaves out what the phone did not provide', () {
      expect(const ReportEvidence(cameraMediaCount: 1).toMap().keys, ['cameraMediaCount', 'galleryMediaCount']);
    });
  });

  group('ReporterTrackRecord', () {
    test('counts false reports apart from other rejections', () {
      final record = ReporterTrackRecord.fromCases([
        {'status': 'rejected', 'rejectionReason': 'invalidOrFalseReport'},
        {'status': 'rejected', 'rejectionReason': 'outsideServiceArea'},
        {'status': 'completed'},
        {'status': 'in_treatment'},
        {'status': 'pending'},
      ]);
      expect(record.total, 5);
      expect(record.falseReports, 1);
      expect(record.otherRejected, 1);
      expect(record.actedOn, 2);
      expect(record.flag.level, EvidenceLevel.caution);
    });

    test('a first-time reporter is unknown, a reliable one supports', () {
      expect(const ReporterTrackRecord().flag.level, EvidenceLevel.unknown);
      expect(const ReporterTrackRecord(total: 3, actedOn: 3).flag.level, EvidenceLevel.supports);
    });

    test('repeated false reports, or only false reports, are a concern', () {
      expect(const ReporterTrackRecord(total: 5, falseReports: 2, actedOn: 3).flag.level, EvidenceLevel.concern);
      expect(const ReporterTrackRecord(total: 1, falseReports: 1).flag.level, EvidenceLevel.concern);
    });
  });

  group('corroborationFlag', () {
    test('other reports or sightings support the report', () {
      final flag = corroborationFlag(otherReports: 1, sightings: 2, notThere: 0);
      expect(flag.level, EvidenceLevel.supports);
      expect(flag.label, 'Backed up by 3 people besides the reporter');
    });

    test('only "no animal there" updates are a concern', () {
      expect(corroborationFlag(otherReports: 0, sightings: 0, notThere: 1).level, EvidenceLevel.concern);
    });

    test('disagreement is a caution; silence is unknown', () {
      expect(corroborationFlag(otherReports: 1, sightings: 0, notThere: 1).level, EvidenceLevel.caution);
      expect(corroborationFlag(otherReports: 0, sightings: 0, notThere: 0).level, EvidenceLevel.unknown);
    });
  });

  group('live proof', () {
    final asked = DateTime(2026, 11, 15, 10);

    test('is pending until proof newer than the request arrives', () {
      final request = LiveProofRequest(requestedAt: asked);
      expect(isLiveProofPending(null, null), isFalse);
      expect(isLiveProofPending(request, null), isTrue);
      expect(
        isLiveProofPending(request, LiveProof(submittedAt: asked.subtract(const Duration(hours: 1)))),
        isTrue,
        reason: 'proof from before a second request does not answer it',
      );
      expect(isLiveProofPending(request, LiveProof(submittedAt: asked.add(const Duration(minutes: 5)))), isFalse);
    });

    test('is judged by how far from the pin it was taken', () {
      expect(
        const LiveProof(lat: pinLat, lng: pinLng).flagAgainst(pinLat: pinLat, pinLng: pinLng).level,
        EvidenceLevel.supports,
      );
      expect(
        const LiveProof(lat: pinLat + 0.05, lng: pinLng).flagAgainst(pinLat: pinLat, pinLng: pinLng).level,
        EvidenceLevel.concern,
      );
      expect(const LiveProof().flagAgainst(pinLat: pinLat, pinLng: pinLng).level, EvidenceLevel.caution);
    });

    test('reads the stored media and location', () {
      final proof = LiveProof.fromMap({
        'mediaUrls': ['a', 'b'],
        'mediaTypes': ['image', 'video'],
        'submittedAt': Timestamp.fromDate(asked),
        'lat': 14,
        'lng': 121.5,
      })!;
      expect(proof.media.map((m) => m.isVideo), [false, true]);
      expect(proof.submittedAt, asked);
      expect(proof.lat, 14.0);
    });
  });

  group('CaseVerification', () {
    test('a rider sent with no result yet is awaiting the rider', () {
      final v = CaseVerification.fromMap({'deskOutcome': 'needsRider', 'riderId': 'r1', 'riderName': 'Ana'})!;
      expect(v.awaitingRider, isTrue);
      expect(v.isConfirmed, isFalse);
      expect(v.summary, 'Rider sent: Ana');
    });

    test('the rider\'s finding decides whether the report is confirmed', () {
      final found = CaseVerification.fromMap({'deskOutcome': 'needsRider', 'riderName': 'Ana', 'riderOutcome': 'found'})!;
      expect(found.awaitingRider, isFalse);
      expect(found.isConfirmed, isTrue);

      final notFound =
          CaseVerification.fromMap({'deskOutcome': 'needsRider', 'riderName': 'Ana', 'riderOutcome': 'notFound'})!;
      expect(notFound.isConfirmed, isFalse);
      expect(notFound.summary, 'Rider: animal not found');
    });

    test('a desk confirmation counts on its own', () {
      final v = CaseVerification.fromMap({'deskOutcome': 'confirmedRemotely', 'deskByName': 'Staff'})!;
      expect(v.isConfirmed, isTrue);
      expect(v.hasRider, isFalse);
      expect(v.summary, 'Confirmed remotely');
    });

    test('unknown or missing values read as nothing recorded', () {
      expect(CaseVerification.fromMap(null), isNull);
      expect(CaseVerification.fromMap({'deskOutcome': 'somethingNew'})!.deskOutcome, isNull);
      expect(const CaseVerificationState().hasRecord, isFalse);
    });
  });

  test('formatDistance switches to kilometres at 1 km', () {
    expect(formatDistance(120.4), '120 m');
    expect(formatDistance(3400), '3.4 km');
  });
}
