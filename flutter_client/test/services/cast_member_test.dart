import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('CastMember.fromXtream', () {
    test('parses a full cast entry with id, character, photo', () {
      final result = CastMember.fromXtream(<String, Object?>{
        'id': 12345,
        'name': 'Idris Elba',
        'character': 'John Luther',
        'photo': 'https://image.tmdb.org/t/p/w185/abc.jpg',
      });
      expect(result, isNotNull);
      expect(result!.id, 12345);
      expect(result.name, 'Idris Elba');
      expect(result.character, 'John Luther');
      expect(result.photo, 'https://image.tmdb.org/t/p/w185/abc.jpg');
    });

    test('parses an entry with only a name (no id/character/photo)', () {
      final result = CastMember.fromXtream(<String, Object?>{'name': 'Bryan Cranston'});
      expect(result, isNotNull);
      expect(result!.name, 'Bryan Cranston');
      expect(result.id, isNull);
      expect(result.character, isNull);
      expect(result.photo, isNull);
    });

    test('trims whitespace from the name', () {
      final result = CastMember.fromXtream(<String, Object?>{'name': '  Anna Paquin  '});
      expect(result!.name, 'Anna Paquin');
    });

    test('drops entries whose name is empty after trimming', () {
      expect(CastMember.fromXtream(<String, Object?>{'name': ''}), isNull);
      expect(CastMember.fromXtream(<String, Object?>{'name': '   '}), isNull);
      expect(CastMember.fromXtream(<String, Object?>{}), isNull);
    });

    test('returns null for non-Map input', () {
      expect(CastMember.fromXtream(null), isNull);
      expect(CastMember.fromXtream('Bryan Cranston'), isNull);
      expect(CastMember.fromXtream(123), isNull);
      expect(CastMember.fromXtream(<Object?>['Bryan Cranston']), isNull);
    });
  });
}
