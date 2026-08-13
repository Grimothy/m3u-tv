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
        Config(
          _key,
          maxNrOfCacheObjects: 300,
          stalePeriod: const Duration(days: 30),
        ),
      );

  static const _key = 'm3uMediaImages';
  static final MediaImageCacheManager _instance = MediaImageCacheManager._();
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
