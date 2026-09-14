import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// The editor's `get_recently_watched&include_up_next=1` payload: one finished
/// episode plus a synthetic "up next" row for the following episode (no
/// progress of its own).
const _recentlyWatched = <Map<String, Object?>>[
  <String, Object?>{
    'content_type': 'episode',
    'stream_id': 10,
    'series_id': 5,
    'season_number': 1,
    'episode_number': 3,
    'position_seconds': 1400,
    'duration_seconds': 1500,
    'completed': true,
    'title': 'Murderbot',
    'series_name': 'Murderbot',
    'episode_title': 'Episode 3',
    'last_watched_at': '2026-09-03 10:00:00',
  },
  <String, Object?>{
    'id': null,
    'content_type': 'episode',
    'stream_id': 11,
    'series_id': 5,
    'season_number': 1,
    'episode_number': 4,
    'position_seconds': 0,
    'completed': false,
    'up_next': true,
    'title': 'Murderbot',
    'series_name': 'Murderbot',
    'episode_title': 'Episode 4',
    'last_watched_at': '2026-09-03 10:00:00',
  },
];

Future<AppStateController> _connected(
  _FakeXtreamTransport transport,
  Map<String, Object?> memory,
) async {
  final controller = _controller(memory: memory, transport: transport);
  final ok = await controller.connectXtream(
    const UserCredentials(
      server: 'https://fixture.example',
      username: 'fixture-user',
      password: 'fixture-password',
    ),
  );
  expect(ok, isTrue);
  await pumpEventQueue();
  return controller;
}

void main() {
  test(
    'keeps the up-next flag even when a stale local resume entry shadows it',
    () async {
      final memory = <String, Object?>{};
      final controller = await _connected(_FakeXtreamTransport(), memory);
      addTearDown(controller.dispose);
      final viewer = controller.activeViewer!;

      // Simulate a stale local resume entry for the up-next episode, as an
      // older build would have persisted from a prior refresh.
      await controller.resumeService.save(
        Progress(
          viewerId: viewer.ulid,
          contentType: ContentType.episode,
          streamId: 11,
          positionSeconds: 0,
          seriesId: 5,
          seasonNumber: 1,
          episodeNumber: 4,
          title: 'Murderbot',
          seriesName: 'Murderbot',
          episodeTitle: 'Episode 4',
        ),
      );

      // Reload for the same viewer - the path that used to drop the flag
      // (local entry shadows the remote synthetic row in the merge).
      await controller.switchViewer(viewer);
      await pumpEventQueue();

      final upNext = controller.progressList.firstWhere(
        (p) => p.streamId == 11,
        orElse: () => throw StateError('up-next row missing from progressList'),
      );
      expect(upNext.upNext, isTrue);

      // A second reload must not make it vanish either.
      await controller.switchViewer(viewer);
      await pumpEventQueue();
      expect(
        controller.progressList.any((p) => p.streamId == 11 && p.upNext),
        isTrue,
      );
    },
  );

  test('never writes synthetic up-next rows to the resume store', () async {
    final memory = <String, Object?>{};
    final controller = await _connected(_FakeXtreamTransport(), memory);
    addTearDown(controller.dispose);
    final viewer = controller.activeViewer!;

    expect(
      controller.progressList.any((p) => p.streamId == 11 && p.upNext),
      isTrue,
    );

    final cached = await controller.resumeService.all(viewer.ulid);
    expect(
      cached.any((p) => p.streamId == 10),
      isTrue,
      reason: 'the real finished-episode row is still cached',
    );
    expect(
      cached.any((p) => p.streamId == 11),
      isFalse,
      reason: 'synthetic up-next rows must not be persisted locally',
    );
  });
}

AppStateController _controller({
  required Map<String, Object?> memory,
  required _FakeXtreamTransport transport,
}) {
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: memory),
    vodFavoritesService: FavoritesService(memory: memory, namespace: 'vod'),
    seriesFavoritesService: FavoritesService(
      memory: memory,
      namespace: 'series',
    ),
    aioFavoritesService: AIOStreamsFavoritesService(),
    resumeService: ResumeService(memory: memory),
    viewerService: ViewerService(memory: memory),
  );
}

class _FakeXtreamTransport {
  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    switch (action) {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.12.53'},
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_favorites':
      case 'sync_favorites':
        return const <Object?>[];
      case 'get_recently_watched':
        return _recentlyWatched;
      case 'get_viewers':
        return <Map<String, Object?>>[
          <String, Object?>{
            'id': 1,
            'ulid': 'viewer-admin',
            'name': 'Admin',
            'is_admin': true,
          },
        ];
      case 'get_epg_batch':
        return <String, Object?>{};
      case 'update_progress':
        return <String, Object?>{};
      default:
        throw StateError('No fixture for $action');
    }
  }
}
