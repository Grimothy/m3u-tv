/// Detects whether a native mpv error message describes a failed format
/// probe rather than a genuine codec/network failure.
///
/// mpv never sees the upstream IPTV provider's own HTTP status -- an
/// m3u-proxy hop that gets a 5xx from the provider and gives up simply
/// closes the connection with no usable bytes, which mpv can only report as
/// "no format found"/"unrecognized file format". That shape (a live source
/// that opens and immediately fails to identify a container) is the
/// signature of an upstream/proxy failure, not a client-side bug -- see the
/// `m3u-proxy` 503-retry investigation in
/// `docs/release/platform-release-matrix.md`.
bool looksLikeStreamProbeFailure(String? message) {
  if (message == null) return false;
  final text = message.toLowerCase();
  return text.contains('no format found') ||
      text.contains('invalid data found when processing input') ||
      (text.contains('format') &&
          (text.contains('unrecognized') || text.contains('recognize')));
}
