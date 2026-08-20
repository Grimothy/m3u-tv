import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/media_image_cache_manager.dart';

/// Full-bleed backdrop image for detail screens, disk-cached via
/// [MediaImageCacheManager] (the same cache posters use) so revisiting a
/// title doesn't refetch its backdrop from network every time.
class CachedBackdropImage extends StatelessWidget {
  const CachedBackdropImage(this.url, {this.fit = BoxFit.cover, super.key});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) => Image(
    image: CachedNetworkImageProvider(
      url,
      cacheManager: MediaImageCacheManager(),
    ),
    fit: fit,
    gaplessPlayback: true,
  );
}
