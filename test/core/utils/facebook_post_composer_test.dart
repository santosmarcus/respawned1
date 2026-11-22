import 'package:flutter_test/flutter_test.dart';
import 'package:respawnd1/core/constants/app.links.dart';
import 'package:respawnd1/core/models/photo_captions.dart';
import 'package:respawnd1/core/models/rescue/animal_record.dart';
import 'package:respawnd1/core/utils/facebook_post_composer.dart';

AnimalRecord _animal(String id, Map<String, dynamic> data) => AnimalRecord.fromMap(id, {
      'name': 'Mochi',
      'species': 'Cat',
      'breed': 'Puspin',
      'sex': 'Female',
      'age': '2 years',
      'size': 'Small',
      'description': 'Calm and sweet.',
      'adoptionStatus': 'adoptable',
      'vaccinated': true,
      'spayedNeutered': true,
      'keyCharacteristics': ['Playful'],
      ...data,
    });

void main() {
  group('composeAnimalBlock', () {
    test('includes only the chosen details, and the link', () {
      final text = composeAnimalBlock(
        _animal('abc', {}),
        {ShareField.status, ShareField.speciesBreed, ShareField.age, ShareField.health},
        withLink: true,
      );
      expect(
        text,
        '🐾 Mochi — Available for adoption\n'
        'Cat · Puspin · 2 years\n'
        '✅ Vaccinated, Spayed/Neutered\n'
        '🔗 Full profile: ${AppLinks.animalUrl('abc')}',
      );
    });

    test('name only when nothing is chosen', () {
      expect(composeAnimalBlock(_animal('abc', {}), {}, withLink: false), '🐾 Mochi');
    });

    test('no link for an animal without a public profile', () {
      for (final hidden in [
        {'archived': true},
        {'publicProfileHidden': true},
        {'adoptionStatus': 'deceased'},
      ]) {
        expect(composeAnimalBlock(_animal('abc', hidden), {}, withLink: true), isNot(contains('Full profile')));
      }
    });
  });

  test('composeFacebookPost joins intro, animals and closing', () {
    final post = composeFacebookPost(
      animals: [_animal('a', {}), _animal('b', {'name': 'Bantay', 'species': 'Dog'})],
      fields: {},
      withLinks: false,
      intro: 'Meet them!',
      closing: '  ',
    );
    expect(post, 'Meet them!\n\n🐾 Mochi\n\n🐾 Bantay');
  });

  group('AppLinks.animalIdFromLink', () {
    test('reads the web page, the app scheme and Flutter route forms', () {
      expect(AppLinks.animalIdFromLink(AppLinks.animalUrl('Ab_9-x')), 'Ab_9-x');
      expect(AppLinks.animalIdFromLink('respawnd://open/animal/abc'), 'abc');
      expect(AppLinks.animalIdFromLink('/animal/abc'), 'abc');
      expect(AppLinks.animalIdFromLink('/open/animal/abc?x=1'), 'abc');
    });

    test('ignores everything else', () {
      expect(AppLinks.animalIdFromLink(null), isNull);
      expect(AppLinks.animalIdFromLink('/'), isNull);
      expect(AppLinks.animalIdFromLink('/animal'), isNull);
      expect(AppLinks.animalIdFromLink('/tag/abc'), isNull);
      expect(AppLinks.animalIdFromLink('/animal/a%2Fb'), isNull);
    });
  });

  group('photo captions', () {
    test('parse skips malformed and blank entries', () {
      expect(
        parsePhotoCaptions([
          {'url': 'u1', 'caption': ' Sunny '},
          {'url': 'u2', 'caption': '  '},
          {'url': 3, 'caption': 'x'},
          'junk',
        ]),
        {'u1': 'Sunny'},
      );
      expect(parsePhotoCaptions(null), isEmpty);
    });

    test('stored form follows photo order and drops removed photos', () {
      expect(
        photoCaptionsField(['u2', 'u1'], {'u1': 'One', 'u2': 'Two', 'gone': 'x'}),
        [
          {'url': 'u2', 'caption': 'Two'},
          {'url': 'u1', 'caption': 'One'},
        ],
      );
    });

    test('AnimalRecord reads them', () {
      final a = _animal('a', {
        'photoUrls': ['https://x/1.jpg'],
        'photoCaptions': [
          {'url': 'https://x/1.jpg', 'caption': 'First day'},
        ],
      });
      expect(a.photoCaptions, {'https://x/1.jpg': 'First day'});
    });
  });
}
