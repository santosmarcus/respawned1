import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/models/adoption/adoption_application.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/services/adoption_fit_assessment_service.dart';
import 'package:respawnd1/core/utils/animal_tag_codes.dart';
import 'package:respawnd1/features/admin/donation/sponsorable_animals.dart';
import 'package:respawnd1/features/adoption/adoption_form_controller.dart';
import 'package:respawnd1/features/donation/models.dart';

AnimalRecord animal(Map<String, dynamic> data) => AnimalRecord.fromMap('a1', {'name': 'Kiko', ...data});

DonationListing sponsorship({
  double collected = 0,
  double allocated = 0,
  double? monthly = 1500,
  String status = 'active',
  String? fundingStatus,
}) =>
    DonationListing(
      id: 's1',
      title: 'Kiko',
      target: 0,
      collected: collected,
      organizer: 'Shelter',
      time: '',
      description: '',
      numdonated: 0,
      address: '',
      type: 'sponsorship',
      status: status,
      monthlyAmount: monthly,
      allocatedAmount: allocated,
      fundingStatus: fundingStatus,
    );

void main() {
  group('collar tag codes (QR and NFC share them)', () {
    test('generated codes are non-empty, well-formed and unique', () {
      final rng = math.Random(7);
      final codes = {for (var i = 0; i < 2000; i++) newAnimalTagCode(rng)};
      expect(codes.length, 2000);
      for (final c in codes) {
        expect(c, hasLength(kAnimalTagLength));
        expect(isGeneratedAnimalTagCode(c), isTrue, reason: c);
      }
    });

    test('the payload is machine-readable and round-trips through a scan', () {
      final code = newAnimalTagCode();
      final payload = animalTagPayload(code);
      expect(payload, '$kAnimalTagPrefix$code');
      expect(animalTagFromScan(payload), code);
      expect(animalTagFromScan('  ${payload.toLowerCase()}  '), code, reason: 'NFC text may vary in case/spacing');
    });

    test('an empty or malformed code never becomes a tag', () {
      expect(() => animalTagPayload(''), throwsArgumentError);
      expect(() => animalTagPayload('  '), throwsArgumentError);
      expect(() => animalTagPayload('AB'), throwsArgumentError);
      expect(animalTagFromScan(kAnimalTagPrefix), isNull);
      expect(animalTagFromScan('https://respawnd1-45021.web.app/tag/abc'), isNull, reason: 'owner collar tag link');
    });

    test('codes printed before the registry still scan', () {
      expect(animalTagFromScan('${kAnimalTagPrefix}OLD123'), 'OLD123');
    });

    test('both types share one structure', () {
      expect(AnimalTagType.qr.animalField, 'qrTagId');
      expect(AnimalTagType.nfc.animalField, 'nfcTagId');
      expect(AnimalTagType.fromName('nfc'), AnimalTagType.nfc);
      expect(AnimalTagType.fromName('x'), isNull);
    });
  });

  group('collar tag status on the animal record', () {
    test('no tag, QR only, NFC only, both', () {
      expect(animal({}).hasCollarTag, isFalse);
      expect(animal({}).collarTagSummary, 'None');
      expect(animal({'qrTagId': 'ABCD2345'}).collarTagSummary, 'QR');
      expect(animal({'nfcTagId': 'WXYZ6789'}).hasCollarTag, isTrue);
      expect(animal({'nfcTagId': 'WXYZ6789'}).collarTagSummary, 'NFC');
      expect(animal({'qrTagId': 'A2345678', 'nfcTagId': 'B2345678'}).collarTagSummary, 'QR · NFC');
    });
  });

  group('adoption application without proof of address', () {
    test('only Government ID and Home Photos are required uploads', () {
      final form = AdoptionFormController();
      addTearDown(form.dispose);
      expect(form.missingUploads(), ['Government ID', 'Home Photos']);
      form.governmentIdUrl = 'https://example.com/id.jpg';
      form.existingHomePhotoUrls = ['https://example.com/home.jpg'];
      expect(form.missingUploads(), isEmpty, reason: 'submittable with no proof of address');
    });

    test('the fit score no longer marks missing proof of address as a concern', () {
      AdoptionApplication app(Map<String, dynamic> uploads) => AdoptionApplication(
            id: 'x',
            raw: {'uploads': uploads},
            adopterId: 'u',
            adopterName: 'A',
            adopterEmail: '',
            adopterPhone: '',
            animalId: 'a1',
            animalName: 'Kiko',
            status: AdoptionStatus.pending,
          );
      final fit = calculateFitAssessment(
        application: app({'governmentId': 'https://x/id.jpg', 'homePhotos': ['https://x/h.jpg']}),
        animal: animal({}),
      );
      final docs = fit.categoryScores.firstWhere((c) => c.label == 'Documents and completeness');
      expect(docs.score, docs.maxScore, reason: 'full marks without proof of address');
      expect(fit.concerns.any((c) => c.toLowerCase().contains('proof of address')), isFalse);
    });
  });

  group('sponsorship eligibility: every admitted animal in care', () {
    test('adoption status and collar tags never matter', () {
      for (final data in <Map<String, dynamic>>[
        {'adoptionStatus': 'adoptable', 'qrTagId': 'ABCD2345'},
        {'adoptionStatus': 'not_ready'},
        {'adoptionStatus': 'reserved'},
        {'status': 'in_treatment', 'adoptionStatus': 'not_ready'},
        {'status': 'intake'},
      ]) {
        expect(sponsorshipReadiness(animal(data)), isNull, reason: '$data');
      }
    });

    test('animals that left care or archived records are excluded', () {
      expect(sponsorshipReadiness(animal({'adoptionStatus': 'adopted'})), isNotNull);
      expect(sponsorshipReadiness(animal({'adoptionStatus': 'deceased'})), isNotNull);
      expect(sponsorshipReadiness(animal({'archived': true})), isNotNull);
    });
  });

  group('sponsorship funding (same rule as sponsorship_funding_rules.js)', () {
    test('insufficient donations keep it open', () {
      final s = sponsorship(collected: 1000);
      expect(s.isFullyFunded, isFalse);
      expect(s.isOpenForSponsorship, isTrue);
    });

    test('sufficient donations close it to new sponsors', () {
      final s = sponsorship(collected: 1500);
      expect(s.isFullyFunded, isTrue);
      expect(s.isOpenForSponsorship, isFalse);
    });

    test('spending that brings the balance under the amount reopens it', () {
      expect(sponsorship(collected: 2000, allocated: 600).isFullyFunded, isFalse);
    });

    test('the server status wins once it is set', () {
      expect(sponsorship(collected: 0, fundingStatus: 'fully_funded').isFullyFunded, isTrue);
      expect(sponsorship(collected: 5000, fundingStatus: 'open').isFullyFunded, isFalse);
    });

    test('no monthly amount, or not a sponsorship: never fully funded', () {
      expect(sponsorship(collected: 5000, monthly: null).isFullyFunded, isFalse);
      expect(sponsorship(collected: 5000, monthly: 0).isFullyFunded, isFalse);
    });
  });
}
