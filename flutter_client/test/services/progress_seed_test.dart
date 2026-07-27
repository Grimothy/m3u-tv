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

void main() {
  group('AppStateController seeds the server from local progress when empty', () {
    test(
      'pushes local-only progress via update_progress when the server has none for this viewer',
      () async {
        final transport = _FakeXtreamTransport();
        final sharedMemory = <String, Object?>{};
        final controller = _controller(
          memory: sharedMemory,
          transport: transport,
        );
        addTearDown(controller.dispose);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();

        final viewer = controller.activeViewer!;
        await controller.resumeService.save(
          Progress(
            viewerId: viewer.ulid,
            contentType: ContentType.vod,
            streamId: 555,
            positionSeconds: 1234,
            durationSeconds: 5400,
          ),
        );

        transport.requests.clear();

        // Re-trigger a progress load for the same viewer.
        await controller.switchViewer(viewer);
        await pumpEventQueue();

        final request = transport.requests.singleWhere(
          (r) => r.action == 'update_progress',
        );
        expect(request.body['viewer_id'], viewer.ulid);
        expect(request.body['content_type'], 'vod');
        expect(request.body['stream_id'], '555');
        expect(request.body['position_seconds'], '1234');

        expect(
          controller.progressList.any((p) => p.streamId == 555),
          isTrue,
        );
      },
    );

    test(
      'also seeds local-only AIOStreams progress (not just Xtream vod/live/episode)',
      () async {
        final transport = _FakeXtreamTransport();
        final sharedMemory = <String, Object?>{};
        final controller = _controller(
          memory: sharedMemory,
          transport: transport,
        );
        addTearDown(controller.dispose);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();

        final viewer = controller.activeViewer!;
        await controller.resumeService.save(
          Progress(
            viewerId: viewer.ulid,
            contentType: ContentType.aiostreams,
            streamId: 0,
            positionSeconds: 300,
            durationSeconds: 8520,
            aioItemId: 'tt0111161',
            aioIntegrationId: 7,
            title: 'The Shawshank Redemption',
          ),
        );
        transport.requests.clear();

        await controller.switchViewer(viewer);
        await pumpEventQueue();

        final request = transport.requests.singleWhere(
          (r) => r.action == 'update_progress',
        );
        expect(request.body['content_type'], 'aiostreams');
        expect(request.body['aio_item_id'], 'tt0111161');
        expect(request.body['aio_integration_id'], '7');
        expect(request.body['position_seconds'], '300');
      },
    );

    test(
      'does not push anything once the server already has progress for this viewer',
      () async {
        final transport = _FakeXtreamTransport()..seedRemoteProgress = true;
        final controller = _controller(transport: transport);
        addTearDown(controller.dispose);

        expect(
          await controller.connectXtream(
            const UserCredentials(
              server: 'https://fixture.example',
              username: 'fixture-user',
              password: 'fixture-password',
            ),
          ),
          isTrue,
        );
        await pumpEventQueue();

        final viewer = controller.activeViewer!;
        await controller.resumeService.save(
          Progress(
            viewerId: viewer.ulid,
            contentType: ContentType.vod,
            streamId: 999,
            positionSeconds: 10,
            durationSeconds: 100,
          ),
        );
        transport.requests.clear();

        await controller.switchViewer(viewer);
        await pumpEventQueue();

        expect(
          transport.requests.where((r) => r.action == 'update_progress'),
          isEmpty,
        );
      },
    );
  });
}

AppStateController _controller({
  Map<String, Object?>? memory,
  required _FakeXtreamTransport transport,
}) {
  final sharedMemory = memory ?? <String, Object?>{};
  return AppStateController(
    xtreamService: XtreamService(
      transport: transport.call,
      cache: CacheService(memory: <String, Object?>{}),
    ),
    secureStorage: InMemorySecureStorage(),
    cacheService: CacheService(memory: <String, Object?>{}),
    favoritesService: FavoritesService(memory: sharedMemory),
    vodFavoritesService: FavoritesService(
      memory: sharedMemory,
      namespace: 'vod',
    ),
    seriesFavoritesService: FavoritesService(
      memory: sharedMemory,
      namespace: 'series',
    ),
    aioFavoritesService: AIOStreamsFavoritesService(),
    resumeService: ResumeService(memory: sharedMemory),
    viewerService: ViewerService(memory: sharedMemory),
  );
}

class _RecordedRequest {
  _RecordedRequest(this.action, this.body);
  final String action;
  final Map<String, Object?> body;
}

class _FakeXtreamTransport {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  bool seedRemoteProgress = false;

  Future<Object?> call(XtreamRequest request) async {
    final action = request.action ?? 'auth';
    if (request.method == 'POST') {
      requests.add(_RecordedRequest(action, request.body));
    }
    switch (action) {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'm3u_editor': <String, Object?>{'version': '0.10.0'},
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_favorites':
        return const <Object?>[];
      case 'get_recently_watched':
        if (seedRemoteProgress) {
          return <Map<String, Object?>>[
            <String, Object?>{
              'content_type': 'vod',
              'stream_id': 999,
              'position_seconds': 10,
              'duration_seconds': 100,
            },
          ];
        }
        return const <Object?>[];
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
      case 'toggle_favorite':
        return <String, Object?>{'favorited': request.body['favorited']};
      case 'sync_favorites':
        return const <Object?>[];
      default:
        throw StateError('No fixture for $action');
    }
  }
}
