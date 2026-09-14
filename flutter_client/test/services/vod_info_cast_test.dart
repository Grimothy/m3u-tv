import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  Map<String, Object?> vodPayload(Object? castList) => <String, Object?>{
    'info': <String, Object?>{
      'tmdb_id': 27205,
      'name': 'Inception',
    },
    'movie_data': <String, Object?>{
      'stream_id': 101,
      'name': 'Inception',
      if (castList != const _Omitted()) 'cast_list': castList,
    },
  };

  test('VodInfo.richCast is parsed when cast_list is a list of maps', () {
    final vod = VodInfo.fromXtream(
      vodPayload(<Object?>[
        <String, Object?>{
          'id': 1,
          'name': 'Leonardo DiCaprio',
          'character': 'Cobb',
        },
        <String, Object?>{
          'id': 2,
          'name': 'Joseph Gordon-Levitt',
          'character': 'Arthur',
        },
      ]),
    );

    expect(vod.richCast, isNotNull);
    expect(vod.richCast!.length, 2);
    expect(vod.richCast![0].name, 'Leonardo DiCaprio');
    expect(vod.richCast![0].character, 'Cobb');
    expect(vod.richCast![1].name, 'Joseph Gordon-Levitt');
  });

  test('VodInfo.richCast is null when cast_list is missing entirely', () {
    final vod = VodInfo.fromXtream(vodPayload(const _Omitted()));
    expect(vod.richCast, isNull);
  });

  test('VodInfo.richCast is null when cast_list is an empty list', () {
    final vod = VodInfo.fromXtream(vodPayload(<Object?>[]));
    expect(vod.richCast, isNull);
  });

  test(
    'VodInfo.richCast is null when cast_list is the legacy comma-joined string',
    () {
      final vod = VodInfo.fromXtream(
        vodPayload('Leonardo DiCaprio, Joseph Gordon-Levitt'),
      );
      expect(vod.richCast, isNull);
    },
  );

  test(
    'VodInfo.richCast preserves the legacy string `cast` field (no regression)',
    () {
      final payload = <String, Object?>{
        'info': <String, Object?>{'name': 'Inception'},
        'movie_data': <String, Object?>{
          'stream_id': 101,
          'name': 'Inception',
          'cast': 'Leonardo DiCaprio, Joseph Gordon-Levitt',
        },
      };
      final vod = VodInfo.fromXtream(payload);
      expect(vod.cast, 'Leonardo DiCaprio, Joseph Gordon-Levitt');
      expect(vod.richCast, isNull);
    },
  );

  test(
    'VodInfo.richCast is null when cast_list contains only malformed entries',
    () {
      final vod = VodInfo.fromXtream(
        vodPayload(<Object?>[
          <String, Object?>{'name': ''},
          <String, Object?>{'name': '   '},
          <String, Object?>{},
        ]),
      );
      expect(vod.richCast, isNull);
    },
  );
}

class _Omitted {
  const _Omitted();
}
