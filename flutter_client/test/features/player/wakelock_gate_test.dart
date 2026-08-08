import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/features/player/wakelock_gate.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

class _FakeWakelockController implements WakelockController {
  final List<String> events = <String>[];
  bool enableThrows = false;
  bool disableThrows = false;

  @override
  Future<void> enable() async {
    if (enableThrows) {
      throw StateError('boom');
    }
    events.add('enable');
  }

  @override
  Future<void> disable() async {
    if (disableThrows) {
      throw StateError('boom');
    }
    events.add('disable');
  }
}

void main() {
  group('WakelockGate', () {
    late _FakeWakelockController controller;
    late WakelockGate gate;

    setUp(() {
      controller = _FakeWakelockController();
      gate = WakelockGate(controller);
    });

    // 1. Transition into playing enables wakelock
    test('playing enables wakelock', () async {
      expect(gate.isActive, false);

      await gate.onPlaybackStatus(PlaybackStatus.playing);

      expect(gate.isActive, true);
      expect(controller.events, <String>['enable']);
    });

    // 2. Transition out of playing disables wakelock (paused)
    test('paused disables wakelock', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.paused);

      expect(gate.isActive, false);
      expect(controller.events, <String>['disable']);
    });

    // 3. completed disables wakelock
    test('completed disables wakelock', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.completed);

      expect(gate.isActive, false);
      expect(controller.events, <String>['disable']);
    });

    // 4. stopped disables wakelock
    test('stopped disables wakelock', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.stopped);

      expect(gate.isActive, false);
      expect(controller.events, <String>['disable']);
    });

    // 5. Buffering is a no-op when playing
    test('buffering is a no-op when playing', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.buffering);

      expect(gate.isActive, true);
      expect(controller.events, isEmpty);
    });

    // 6. Buffering is a no-op when paused
    test('buffering is a no-op when paused', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      await gate.onPlaybackStatus(PlaybackStatus.paused);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.buffering);

      expect(gate.isActive, false);
      expect(controller.events, isEmpty);
    });

    // 7. buffering → playing while buffering from paused keeps wakelock off
    test('buffering from paused then playing re-enables once', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      await gate.onPlaybackStatus(PlaybackStatus.paused);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.buffering);
      await gate.onPlaybackStatus(PlaybackStatus.playing);

      expect(gate.isActive, true);
      expect(controller.events, <String>['enable']);
    });

    // 8. Same status repeated is a no-op
    test('same status repeated is a no-op', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.playing);
      await gate.onPlaybackStatus(PlaybackStatus.playing);

      expect(gate.isActive, true);
      expect(controller.events, isEmpty);
    });

    // 9. release() with isActive=true disables exactly once
    test('release while active disables once', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.events.clear();

      await gate.release();
      await gate.release();

      expect(gate.isActive, false);
      expect(controller.events, <String>['disable']);
    });

    // 10. release() with isActive=false is a no-op
    test('release while inactive is a no-op', () async {
      await gate.release();

      expect(gate.isActive, false);
      expect(controller.events, isEmpty);
    });

    // 11. Controller exception during enable() is swallowed
    test('controller exception during enable is swallowed', () async {
      controller.enableThrows = true;

      await gate.onPlaybackStatus(PlaybackStatus.playing);

      expect(gate.isActive, true);
      expect(controller.events, isEmpty);
    });

    // 12. Controller exception during disable() is swallowed
    test('controller exception during disable is swallowed', () async {
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      controller.disableThrows = true;
      controller.events.clear();

      await gate.onPlaybackStatus(PlaybackStatus.paused);

      expect(gate.isActive, false);
      expect(controller.events, isEmpty);
    });

    // 13. Full lifecycle smoke test
    test('full lifecycle smoke test', () async {
      // playing → enable
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      expect(gate.isActive, true);

      // buffering → no-op (still enabled)
      await gate.onPlaybackStatus(PlaybackStatus.buffering);
      expect(gate.isActive, true);

      // playing → no-op
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      expect(gate.isActive, true);

      // paused → disable
      await gate.onPlaybackStatus(PlaybackStatus.paused);
      expect(gate.isActive, false);

      // playing → enable (second time)
      await gate.onPlaybackStatus(PlaybackStatus.playing);
      expect(gate.isActive, true);

      // completed → disable
      await gate.onPlaybackStatus(PlaybackStatus.completed);
      expect(gate.isActive, false);

      // stop (from inactive) → no-op
      await gate.onPlaybackStatus(PlaybackStatus.stopped);
      expect(gate.isActive, false);

      // release() after stop → no-op
      await gate.release();
      expect(gate.isActive, false);

      expect(controller.events, <String>[
        'enable',
        'disable',
        'enable',
        'disable',
      ]);
      expect(
        controller.events.where((e) => e == 'enable').length,
        2,
      );
      expect(
        controller.events.where((e) => e == 'disable').length,
        2,
      );
    });
  });
}
