import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:respawnd1/core/models/rescue/transporter_application.dart';
import 'package:respawnd1/core/utils/transporter_trip_stats.dart';

void main() {
  group('TransporterApplication.fromMap', () {
    test('reads the fields transporter_verification_screen.dart writes', () {
      final submitted = DateTime(2026, 11, 1, 9);
      final app = TransporterApplication.fromMap('rider', {
        'uid': 'rider',
        'name': ' Juan ',
        'mobileNumber': '09171234567',
        'vehicleType': 'Motorcycle',
        'licensePlate': 'ABC 123',
        'licenseFrontUrl': 'https://x/front',
        'licenseBackUrl': 'https://x/back',
        'portraitUrl': 'https://x/portrait',
        'antiRabiesUrl': null,
        'status': 'pending',
        'submittedAt': Timestamp.fromDate(submitted),
      });
      expect(app.uid, 'rider');
      expect(app.name, 'Juan');
      expect(app.status, TransporterApplicationStatus.pending);
      expect(app.submittedAt, submitted);
      expect(app.antiRabiesUrl, isNull);
      expect(app.documents.map((d) => d.label), ['Portrait', "Driver's license (front)", "Driver's license (back)"]);
    });

    test('unknown or missing status reads as pending; review fields parse', () {
      expect(TransporterApplication.fromMap('a', const {}).status, TransporterApplicationStatus.pending);
      final rejected = TransporterApplication.fromMap('a', const {'status': 'rejected', 'reviewNote': 'Blurry photo'});
      expect(rejected.status, TransporterApplicationStatus.rejected);
      expect(rejected.reviewNote, 'Blurry photo');
      expect(rejected.documents, isEmpty);
    });
  });

  group('transporter trip stats', () {
    test('finished trips count as completed even after the case moved on', () {
      expect(isCompletedTransit({'status': 'intake'}), isTrue);
      expect(isCompletedTransit({'status': 'in_treatment'}), isTrue);
      expect(isCompletedTransit({'status': 'treatment', 'transitCompletedAt': Timestamp.now()}), isTrue);
      expect(isOngoingTransit({'status': 'treatment', 'transitCompletedAt': Timestamp.now()}), isFalse);
    });

    test('in-progress statuses are ongoing; others are neither', () {
      expect(isOngoingTransit({'status': 'ongoing'}), isTrue);
      expect(isOngoingTransit({'status': 'pending'}), isFalse);
      expect(isCompletedTransit({'status': 'pending'}), isFalse);
    });
  });
}
