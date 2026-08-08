import 'package:m3u_tv/features/player/wakelock_controller.dart';
import 'package:m3u_tv/playback/player_adapter.dart' show PlaybackStatus;

/// Pure transition logic that turns a stream of [PlaybackStatus] events into
/// enable/disable calls on a [WakelockController]. Lifted out of the
/// player widget so the lifecycle can be unit-tested without spinning up a
/// widget tree, and so the wakelock policy lives in exactly one place.
///
/// Rules:
///   - Transition *into* [PlaybackStatus.playing]: enable.
///   - Transition *out of* playing (paused / completed / stopped / idle):
///     disable.
///   - Buffering does NOT toggle the wakelock — it's part of active playback
///     and the screen must stay on. (The previous playing/paused state is
///     preserved across buffering events.)
///   - [release] is the unconditional teardown path called on dispose.
///     Safe to call multiple times; a no-op if already released.
///
/// All platform calls are best-effort: a [WakelockController] that throws
/// must not crash playback, so failures are swallowed silently.
class WakelockGate {
  WakelockGate(this._wakelock);

  final WakelockController _wakelock;
  bool _isActive = false;

  bool get isActive => _isActive;

  /// Drive the gate with a PlaybackStatus. Returns the future from the
  /// underlying enable/disable call (if any); callers may `unawaited` it
  /// because the controller swallows its own errors.
  Future<void> onPlaybackStatus(PlaybackStatus status) {
    // Buffering is an intermediate state — preserve the previous wakelock
    // decision. The screen must stay on across buffering events regardless
    // of whether we were playing or paused before them.
    if (status == PlaybackStatus.buffering) return Future<void>.value();
    final shouldBeActive = status == PlaybackStatus.playing;
    if (shouldBeActive == _isActive) return Future<void>.value();
    _isActive = shouldBeActive;
    return _invoke(shouldBeActive);
  }

  /// Tear the wakelock down unconditionally. Idempotent.
  Future<void> release() {
    if (!_isActive) return Future<void>.value();
    _isActive = false;
    return _invoke(false);
  }

  Future<void> _invoke(bool enable) async {
    try {
      if (enable) {
        await _wakelock.enable();
      } else {
        await _wakelock.disable();
      }
    } on Object {
      // Best-effort: a wakelock platform failure must never break playback.
    }
  }
}
