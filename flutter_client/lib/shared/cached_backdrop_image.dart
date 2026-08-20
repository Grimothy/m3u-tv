import 'package:cached_network_image/cached_network_image.dart'
    show CachedNetworkImageProvider;
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/media_image_cache_manager.dart';

/// Full-bleed backdrop image for detail screens, disk-cached via
/// [MediaImageCacheManager] (the same cache posters use) so revisiting a
/// title doesn't refetch its backdrop from network every time.
///
/// Always used inside a `Stack(fit: StackFit.expand)`, which gives this
/// widget tight layout constraints — [LayoutBuilder] reads those to decode
/// the image at its actual on-screen pixel size instead of the source
/// resolution (backdrops are frequently 1920x1080+ while these render as a
/// 200-220dp strip), which is a meaningful decode-cost and memory saving.
class CachedBackdropImage extends StatelessWidget {
  const CachedBackdropImage(this.url, {this.fit = BoxFit.cover, super.key});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final provider = CachedNetworkImageProvider(
          url,
          cacheManager: MediaImageCacheManager(),
        );
        final cacheWidth = constraints.hasBoundedWidth
            ? (constraints.maxWidth * devicePixelRatio).round()
            : null;
        final cacheHeight = constraints.hasBoundedHeight
            ? (constraints.maxHeight * devicePixelRatio).round()
            : null;
        return Image(
          image: cacheWidth == null && cacheHeight == null
              ? provider
              : ResizeImage(
                  provider,
                  width: cacheWidth,
                  height: cacheHeight,
                ),
          fit: fit,
          gaplessPlayback: true,
        );
      },
    );
  }
}
