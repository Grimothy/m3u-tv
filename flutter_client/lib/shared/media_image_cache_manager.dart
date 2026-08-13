import 'package:flutter/services.dart' show ServicesBinding;
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

/// Empties the media image cache, skipping if Flutter's platform bindings
/// aren't initialized (plain `flutter test` VM unit tests never call
/// `runApp()`/`ensureInitialized()`). Constructing [MediaImageCacheManager]
/// without a binding trips an unhandled platform-channel error deep inside
/// `flutter_cache_manager`'s file system setup, so this check must happen
/// before the singleton is ever touched.
Future<void> emptyMediaImageCacheIfAvailable() async {
  try {
    ServicesBinding.instance;
  } on Object {
    return;
  }
  await MediaImageCacheManager().emptyCache();
}
