import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache for media poster/thumbnail images.
///
/// Holds up to 300 files for 30 days. At ~100 KB average per poster this
/// stays well under 30 MB on device while covering a full library of recently
/// browsed content.
class MediaImageCacheManager extends CacheManager with ImageCacheManager {
  factory MediaImageCacheManager() => _instance;

  MediaImageCacheManager._()
    : super(
        Platform.operatingSystem == 'tvos'
            ? Config(
                _key,
                maxNrOfCacheObjects: 300,
                stalePeriod: const Duration(days: 30),
                repo: _tvosRepo(),
              )
            : Config(
                _key,
                maxNrOfCacheObjects: 300,
                stalePeriod: const Duration(days: 30),
              ),
      );

  static const _key = 'm3uMediaImages';
  static final MediaImageCacheManager _instance = MediaImageCacheManager._();

  /// flutter_cache_manager picks its cache-info repo by
  /// `Platform.isIOS/isAndroid/isMacOS`, none of which are true on tvOS
  /// (`Platform.operatingSystem == 'tvos'`), so it falls back to
  /// `JsonCacheInfoRepository`, which lazily resolves its storage directory
  /// via `getApplicationSupportDirectory()`. That directory cannot be created
  /// on a physical Apple TV (see path_provider_tvos's PathProviderPlugin.swift),
  /// so every cache write threw and images silently failed to load on device
  /// - the simulator permits the write, which is why this doesn't reproduce
  /// there. [tvosCacheDirectory] must be set (from `main.dart`, before any
  /// image widget builds) to a writable directory such as
  /// `getApplicationCacheDirectory()`'s result.
  static JsonCacheInfoRepository _tvosRepo() {
    final repo = JsonCacheInfoRepository(databaseName: _key);
    if (tvosCacheDirectory != null) {
      repo.directory = tvosCacheDirectory;
    }
    return repo;
  }

  static Directory? tvosCacheDirectory;
}

/// Empties the media image cache, skipping under `flutter test` (which sets
/// the `FLUTTER_TEST` environment variable). Constructing
/// [MediaImageCacheManager] there hits `path_provider`'s platform channel,
/// which test suites don't mock; `TestWidgetsFlutterBinding.ensureInitialized()`
/// alone isn't a reliable signal since some tests call it for unrelated
/// reasons, so this checks the environment variable directly instead.
Future<void> emptyMediaImageCacheIfAvailable() async {
  if (Platform.environment['FLUTTER_TEST'] == 'true') return;
  await MediaImageCacheManager().emptyCache();
}
