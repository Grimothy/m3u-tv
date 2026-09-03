import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  test('VodInfo.clearLogoUrl is parsed from the info.clearlogo wire key', () {
    final vod = VodInfo.fromXtream(<String, Object?>{
      'info': <String, Object?>{
        'name': 'Inception',
        'clearlogo': 'https://image.tmdb.org/t/p/w500/logo.png',
      },
      'movie_data': <String, Object?>{'stream_id': 101},
    });

    expect(vod.clearLogoUrl, 'https://image.tmdb.org/t/p/w500/logo.png');
  });

  test('VodInfo.clearLogoUrl is null when the key is absent', () {
    final vod = VodInfo.fromXtream(<String, Object?>{
      'info': <String, Object?>{'name': 'Inception'},
      'movie_data': <String, Object?>{'stream_id': 101},
    });

    expect(vod.clearLogoUrl, isNull);
  });

  test('Series.clearLogoUrl is parsed from a get_series row', () {
    final series = Series.fromXtream(<String, Object?>{
      'series_id': 7,
      'name': 'Andor',
      'clearlogo': 'https://image.tmdb.org/t/p/w500/andor-logo.png',
    });

    expect(
      series.clearLogoUrl,
      'https://image.tmdb.org/t/p/w500/andor-logo.png',
    );
  });

  test('Series.clearLogoUrl tolerates a cast_list entry with a null id', () {
    final series = Series.fromXtream(<String, Object?>{
      'series_id': 7,
      'name': 'Andor',
      'cast_list': <Object?>[
        <String, Object?>{
          'id': null,
          'name': 'Diego Luna',
          'character': 'Cassian Andor',
          'photo': null,
        },
      ],
    });

    expect(series.richCast, isNotNull);
    expect(series.richCast!.single.id, isNull);
    expect(series.richCast!.single.name, 'Diego Luna');
  });
}
