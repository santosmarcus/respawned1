import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:respawnd1/core/widgets/animal_record_card.dart';
import 'package:respawnd1/features/adoption/community_profile.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  test('age comes from the birthday, else the estimate', () {
    final now = DateTime.now();
    expect(
      CommunityAnimalProfile(birthday: DateTime(now.year - 2, now.month, 1)).ageText,
      '2 years old',
    );
    expect(const CommunityAnimalProfile(ageEstimate: 'about 1 year').ageText, 'about 1 year');
  });

  test('profile round-trips and falls back to the report', () {
    final saved = const CommunityAnimalProfile(
      name: 'Bantay',
      ageEstimate: '1 year',
      about: 'Friendly',
      vaccinated: true,
      dewormed: true,
      temperament: ['Calm'],
    ).toMap();
    final caseData = {
      'animals': [
        {'species': 'Dog', 'sex': 'Male', 'size': 'Large'},
      ],
      'communityListing': {
        'animals': {'0': saved},
      },
    };
    final p = communityProfileOf(caseData, 0);
    expect(p.name, 'Bantay');
    expect(p.sex, 'Male');
    expect(p.size, 'Large');
    expect(p.healthTags, ['Vaccinated', 'Dewormed']);
    expect(p.isComplete, isTrue);
    expect(communityProfileOf({'animalType': 'Cat'}, 0).isComplete, isFalse);
    expect(
      CommunityAnimalProfile.fromMap({'birthday': Timestamp.fromDate(DateTime(2024, 5, 2))}).birthdayText,
      '5/2/2024',
    );
  });

  test('an unsaved profile starts from the surrender answers', () {
    final p = communityProfileOf({
      'animals': [
        {
          'species': 'Cat',
          'age': '2 years old',
          'vaccination': 'Fully vaccinated (up to date)',
          'spayNeuter': 'Yes',
          'compatibility': ['Good with children', 'Not sure / Not yet tested'],
        },
      ],
    }, 0);
    expect(p.ageText, '2 years old');
    expect(p.healthTags, ['Vaccinated', 'Spayed/Neutered']);
    expect(p.goodWith, ['Good with children']);
  });

  testWidgets('the card is the shelter adoption card, without In Shelter', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CommunityAnimalCard(
          profile: const CommunityAnimalProfile(sex: 'Female', ageEstimate: '1 year old', vaccinated: true),
          label: 'Dog 1',
          species: 'Dog',
          breed: 'Aspin',
          statusLabel: 'Available',
          fallbackDescription: 'Found near the market',
        ),
      ),
    ));
    expect(find.byType(AnimalRecordCard), findsOneWidget);
    expect(find.text('Dog 1'), findsOneWidget);
    expect(find.text('Dog · Aspin'), findsOneWidget);
    expect(find.text('1 year old'), findsOneWidget);
    expect(find.text('Found near the market'), findsOneWidget);
    expect(find.text('Vaccinated'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('In Shelter'), findsNothing);
    // Let the font loader's late system-font notice land before teardown.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
  });

  testWidgets('the profile editor opens and saves', (tester) async {
    final errors = <String>[];
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (!m.contains('overflowed')) errors.add(m);
    };
    tester.view.physicalSize = const Size(1200, 6000);
    tester.view.devicePixelRatio = 1;
    CommunityAnimalProfile? saved;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CommunityProfileEditPage(
                  caseId: 'c1',
                  index: 0,
                  label: 'Dog 1',
                  initial: const CommunityAnimalProfile(),
                  onSave: (p) async => saved = p,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Basic Information'), findsOneWidget);
    expect(errors, isEmpty, reason: errors.join('\n'));

    // Missing required fields: stays open with a message.
    await tester.tap(find.text('Save Profile'));
    await tester.pump();
    expect(find.textContaining('Please add a name'), findsOneWidget);
    expect(saved, isNull);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Bantay');
    await tester.enterText(fields.at(1), 'about 1 year old');
    await tester.enterText(fields.at(2), 'Gentle and loves walks.');
    await tester.tap(find.text('Vaccinated'));
    await tester.tap(find.text('Calm'));
    await tester.pump();
    await tester.tap(find.text('Save Profile'));
    await tester.pumpAndSettle();
    expect(saved?.name, 'Bantay');
    expect(saved?.vaccinated, isTrue);
    expect(saved?.temperament, ['Calm']);
    expect(find.text('Basic Information'), findsNothing); // closed after saving
    expect(errors, isEmpty, reason: errors.join('\n'));
  });
}
