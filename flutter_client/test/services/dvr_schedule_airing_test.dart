import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_favorites_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/cache_service.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/resume_service.dart';
import 'package:m3u_tv/services/reverb_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/tv_notification_service.dart';
import 'package:m3u_tv/services/tv_notification_store.dart';
import 'package:m3u_tv/services/viewer_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

const _credentials = UserCredentials(
  server: 'https://fixture.invalid',
  username: 'airing-test',
  password: 'airing-pass',
);

final _airingStart = DateTime.utc(2026, 8, 20, 18, 30);
final _airingEnd = DateTime.utc(2026, 8, 20, 19, 45);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'scheduleDvrAiring posts channel/title/window to schedule_dvr and '
    'returns the refreshed matching recording',
    () async {
      final transport = _AiringTransport();
      final controller = _controller(transport);
      addTearDown(controller.dispose);

      expect(await controller.connectXtream(_credentials), isTrue);

      final recording = await controller.scheduleDvrAiring(
        channelId: 101,
        title: 'Evening News',
        startTime: _airingStart,
        endTime: _airingEnd,
      );

      expect(transport.scheduleBodies, hasLength(1));
      final body = transport.scheduleBodies.single;
      expect(body['channel_id'], '101');
      expect(body['title'], 'Evening News');
      expect(body['start_time'], _airingStart.toIso8601String());
      expect(body['end_time'], _airingEnd.toIso8601String());

      expect(recording, isNotNull);
      expect(recording!.channelId, 101);
      expect(recording.title, 'Evening News');
      // The refreshed list is what the controller now serves.
      expect(controller.dvrRecordings.single.title, 'Evening News');
    },
  );

  test('scheduleDvrAiring propagates schedule_dvr failure', () async {
    final transport = _AiringTransport()..failSchedule = true;
    final controller = _controller(transport);
    addTearDown(controller.dispose);

    expect(await controller.connectXtream(_credentials), isTrue);

    await expectLater(
      controller.scheduleDvrAiring(
        channelId: 101,
        title: 'Evening News',
        startTime: _airingStart,
        endTime: _airingEnd,
      ),
      throwsA(isA<XtreamDvrScheduleException>()),
    );
  });
}

AppStateController _controller(_AiringTransport transport) {
  final memory = <String, Object?>{};
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
    tvNotificationService: _NotificationService(),
    tvNotificationStore: TvNotificationStore(memory: memory),
    reverbService: _NoopReverbService(),
  );
}

class _AiringTransport {
  bool failSchedule = false;
  final List<Map<String, Object?>> scheduleBodies = <Map<String, Object?>>[];

  Future<Object?> call(XtreamRequest request) async {
    switch (request.action ?? 'auth') {
      case 'auth':
        return <String, Object?>{
          'user_info': <String, Object?>{'auth': 1, 'status': 'Active'},
          'server_info': <String, Object?>{'timezone': 'UTC'},
          'm3u_editor': <String, Object?>{
            'version': '0.10.0',
            'features': <String>['dvr'],
          },
        };
      case 'get_live_categories':
      case 'get_vod_categories':
      case 'get_series_categories':
      case 'get_live_streams':
      case 'get_vod_streams':
      case 'get_series':
      case 'get_viewers':
      case 'list_dvr_series_rules':
        return const <Object?>[];
      case 'get_dvr_recordings':
        return <Map<String, Object?>>[
          <String, Object?>{
            'uuid': 'rec-airing',
            'title': 'Evening News',
            'status': 'scheduled',
            'channel_id': 101,
            'scheduled_start': _airingStart.toIso8601String(),
            'scheduled_end': _airingEnd.toIso8601String(),
          },
        ];
      case 'get_dvr_storage':
        return <String, Object?>{
          'used_bytes': 0,
          'quota_bytes': null,
          'percent_used': null,
          'recording_count': 1,
          'scope': 'account',
        };
      case 'schedule_dvr':
        scheduleBodies.add(Map<String, Object?>.from(request.body));
        if (failSchedule) {
          return <String, Object?>{'success': false, 'error': 'slot taken'};
        }
        return <String, Object?>{'success': true, 'rule_id': 1};
      default:
        throw StateError('No fixture for ${request.action}');
    }
  }
}

class _NotificationService extends TvNotificationService {
  @override
  Future<(TvPlaylistSession, List<TvNotificationItem>)> fetchUnread(
    UserCredentials creds, {
    List<String>? channels,
  }) async => const (
    TvPlaylistSession(
      notifiableId: 1,
      notifiableType: 'playlist',
      isAdmin: false,
      channelName: '',
      reverb: ReverbConfig(host: '', port: 0, scheme: 'wss', appKey: ''),
    ),
    <TvNotificationItem>[],
  );
}

class _NoopReverbService extends ReverbService {
  @override
  Future<void> disconnect() async {}
}
