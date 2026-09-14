import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/cached_media_thumbnail.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';

/// Favorites screen with tabs for Live TV, Movies, and Series favorites.
///
/// Long-press any item to toggle its favorite status.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({
    super.key,
    required this.channels,
    required this.catalogRepository,
    required this.isConfigured,
    required this.channelFavoritesService,
    required this.vodFavoritesService,
    required this.seriesFavoritesService,
    required this.onChannelSelect,
    required this.onVodSelect,
    required this.onSeriesSelect,
  });

  final List<Channel> channels;
  final CatalogRepository catalogRepository;
  final bool isConfigured;
  final FavoritesService channelFavoritesService;
  final FavoritesService vodFavoritesService;
  final FavoritesService seriesFavoritesService;
  final void Function(Channel) onChannelSelect;
  final void Function(VodItem) onVodSelect;
  final void Function(Series) onSeriesSelect;

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Set<int> _favoriteChannelIds = {};
  List<VodItem> _favoriteVodItems = const [];
  List<Series> _favoriteSeriesList = const [];
  bool _loadedOnce = false;

  static const _tabs = [
    Tab(text: 'Live TV'),
    Tab(text: 'Movies'),
    Tab(text: 'Series'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    unawaited(_loadFavorites());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final channelIds = await widget.channelFavoritesService.all();
    final vodIds = await widget.vodFavoritesService.all();
    final seriesIds = await widget.seriesFavoritesService.all();
    final vodItems = await widget.catalogRepository.activeItemsByIds<VodItem>(
      kind: kCatalogKindVod,
      ids: vodIds,
    );
    final seriesList = await widget.catalogRepository.activeItemsByIds<Series>(
      kind: kCatalogKindSeries,
      ids: seriesIds,
    );
    if (mounted) {
      setState(() {
        _favoriteChannelIds = channelIds;
        _favoriteVodItems = vodItems;
        _favoriteSeriesList = seriesList;
        _loadedOnce = true;
      });
    }
  }

  List<Channel> get _favoriteChannels =>
      widget.channels.where((c) => _favoriteChannelIds.contains(c.id)).toList();

  bool get _hasAnyFavorites =>
      _favoriteChannels.isNotEmpty ||
      _favoriteVodItems.isNotEmpty ||
      _favoriteSeriesList.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (!widget.isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    if (!_loadedOnce) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasAnyFavorites) {
      return Scaffold(
        body: Center(
          child: Text(
            'No favorites yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: _tabs,
          ),
          Expanded(
            child: DpadTabBarView(
              controller: _tabController,
              children: [
                _buildLiveTvTab(),
                _buildMoviesTab(),
                _buildSeriesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTvTab() {
    final favorites = _favoriteChannels;
    if (favorites.isEmpty) {
      return const Center(child: Text('No favorite channels'));
    }
    return ListView.builder(
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final channel = favorites[index];
        return DpadInkWell(
          onTap: () => widget.onChannelSelect(channel),
          onLongTap: () async {
            await widget.channelFavoritesService.toggle(channel.id);
            await _loadFavorites();
          },
          child: ListTile(
            leading: channel.logoUrl != null && channel.logoUrl!.isNotEmpty
                ? ClipOval(
                    child: CachedMediaThumbnail(
                      url: channel.logoUrl!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                      oversample: 2,
                      fallback: const CircleAvatar(child: Icon(Icons.tv)),
                    ),
                  )
                : const CircleAvatar(child: Icon(Icons.tv)),
            title: Text(channel.name),
            trailing: Icon(
              Icons.star,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        );
      },
    );
  }

  Widget _buildMoviesTab() {
    final favorites = _favoriteVodItems;
    if (favorites.isEmpty) {
      return const Center(child: Text('No favorite movies'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.6,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index];
        return DpadInkWell(
          onTap: () => widget.onVodSelect(item),
          onLongTap: () async {
            await widget.vodFavoritesService.toggle(item.id);
            await _loadFavorites();
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: item.logoUrl != null && item.logoUrl!.isNotEmpty
                          ? CachedMediaThumbnail(
                              url: item.logoUrl!,
                              fit: BoxFit.cover,
                              fallback: const Icon(Icons.movie, size: 48),
                            )
                          : const Icon(Icons.movie, size: 48),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        item.name,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(
                    Icons.star,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSeriesTab() {
    final favorites = _favoriteSeriesList;
    if (favorites.isEmpty) {
      return const Center(child: Text('No favorite series'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 0.6,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index];
        return DpadInkWell(
          onTap: () => widget.onSeriesSelect(item),
          onLongTap: () async {
            await widget.seriesFavoritesService.toggle(item.id);
            await _loadFavorites();
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: item.coverUrl != null && item.coverUrl!.isNotEmpty
                          ? CachedMediaThumbnail(
                              url: item.coverUrl!,
                              fit: BoxFit.cover,
                              fallback: const Icon(Icons.tv, size: 48),
                            )
                          : const Icon(Icons.tv, size: 48),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        item.name,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 4,
                  left: 4,
                  child: Icon(
                    Icons.star,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
