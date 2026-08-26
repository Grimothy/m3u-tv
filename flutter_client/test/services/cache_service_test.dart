import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/persistent_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<PersistentJsonStore> newStore(String prefix) async {
    final directory = await Directory.systemTemp.createTemp(prefix);
    addTearDown(() => directory.delete(recursive: true));
    return PersistentJsonStore(file: File('${directory.path}/app_state.json'));
  }

  test(
    'series metadata survives a persist + cold hydrate round trip',
    () async {
      final store = await newStore('m3u-tv-series-cache-roundtrip-');
      final source = CacheService(store: store);
      final original = <Series>[
        const Series(
          id: 42,
          name: 'The Example',
          coverUrl: 'https://img/cover.jpg',
          backdropUrl: 'https://img/backdrop.jpg',
          categoryId: '7',
          plot: 'A plot.',
          rating: 4.3,
          tmdbId: 99123,
        ),
      ];
      await source.set<List<Series>>('seriesStreams', original);

      // A fresh CacheService with no memory forces hydration from the store.
      final hydrated = CacheService(store: store);
      final entry = await hydrated.get<List<Series>>('seriesStreams');
      final series = entry!.data.single;

      expect(series.id, 42);
      expect(series.name, 'The Example');
      expect(series.coverUrl, 'https://img/cover.jpg');
      expect(series.backdropUrl, 'https://img/backdrop.jpg');
      expect(series.categoryId, '7');
      expect(series.plot, 'A plot.');
      expect(series.rating, 4.3);
      expect(series.tmdbId, 99123);
    },
  );

  test('legacy rating_5based cache entries still hydrate a rating', () async {
    final store = await newStore('m3u-tv-series-cache-legacy-');
    await store.write('m3ue_cache_seriesStreams', <String, Object?>{
      'timestamp': DateTime.now().toIso8601String(),
      'data': <Object?>[
        <String, Object?>{
          'series_id': 1,
          'name': 'Legacy Series',
          'rating_5based': 3.5,
        },
      ],
    });

    final cache = CacheService(store: store);
    final entry = await cache.get<List<Series>>('seriesStreams');
    final series = entry!.data.single;

    expect(series.rating, 3.5);
    expect(series.backdropUrl, isNull);
    expect(series.tmdbId, isNull);
  });
}
