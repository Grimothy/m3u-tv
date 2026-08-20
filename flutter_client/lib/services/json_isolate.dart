import 'dart:convert';
import 'dart:isolate';

/// Below this size, `Isolate.run`'s spawn/copy overhead costs more than the
/// decode itself would ever block a frame for, so we just decode inline.
const int _offloadThresholdBytes = 32 * 1024;

/// Decodes [text] as JSON, hopping off the calling isolate when the payload
/// is large enough that a synchronous decode could visibly steal a frame
/// (catalog dumps with thousands of channels/VOD/series entries).
Future<Object?> decodeJsonOffMainIsolate(String text) {
  if (text.length < _offloadThresholdBytes) {
    return Future.value(jsonDecode(text));
  }
  return Isolate.run(() => jsonDecode(text));
}

/// Encodes [data] as JSON, hopping off the calling isolate for large maps
/// for the same reason as [decodeJsonOffMainIsolate].
Future<String> encodeJsonOffMainIsolate(Map<String, Object?> data) {
  if (data.length < 64) {
    return Future.value(jsonEncode(data));
  }
  return Isolate.run(() => jsonEncode(data));
}
