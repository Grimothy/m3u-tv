import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindVod;
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/shared/catalog_window.dart';
import 'package:m3u_tv/shared/catalog_window_grid.dart';
import 'package:m3u_tv/shared/category_browse_filter.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';

/// VOD (Movies) screen with category filtering and poster grid.
///
/// Mirrors the RN HomeScreen Movies row and MovieDetailsScreen behavior:
/// - All Movies + category tabs
/// - Grid layout with poster thumbnails and ratings
/// - Category filtering
class VodScreen extends ConsumerStatefulWidget {
  const VodScreen({
    super.key,
    required this.onVodSelect,
    required this.useSidebarLayout,
    this.favoritesService,
    this.onSidebarActivate,
    this.onEntryFocusScopeReady,
  });

  final void Function(VodItem) onVodSelect;

  /// TV/desktop (`true`): search+category render as a vertical strip beside
  /// the grid. Mobile (`false`): stacked at the top with a Filter button.
  final bool useSidebarLayout;
  final FavoritesService? favoritesService;
  final VoidCallback? onSidebarActivate;

  /// TV/desktop only: forwarded to [MediaCategoryNav.onEntryFocusScopeReady]
  /// so AppShell can always re-enter this screen's strip first when the
  /// sidebar deactivates.
  final ValueChanged<FocusScopeNode>? onEntryFocusScopeReady;

  @override
  ConsumerState<VodScreen> createState() => _VodScreenState();
}

class _VodScreenState extends ConsumerState<VodScreen> {
  static const double _minPosterCardWidth = 120;
  static const double _maxPosterCardWidth = 220;
  static const _kFavoritesCategoryId = '__FAVORITES__';

  static const _searchDebounce = Duration(milliseconds: 200);

  String? _selectedCategory;
  String _query = '';
  // Lags [_query] by up to one debounce; drives the actual filtering so fast
  // typing over a large catalog does not re-scan it on every keystroke.
  String _appliedQuery = '';
  Timer? _debounce;
  Set<int> _favoriteIds = {};
  final CategoryBrowseFilter<VodItem> _filter = CategoryBrowseFilter<VodItem>(
    primaryCategoryId: (item) => item.categoryId,
    extraCategoryIds: (item) => item.categoryIds,
    name: (item) => item.name,
    id: (item) => item.id,
  );
  final FocusScopeNode _gridFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();

  // Windowed grid backed by the SQLite catalog, used for every tab except
  // favorites (favorites is a membership filter over locally-known ids, not
  // something worth pushing into a repository query for what is normally a
  // small set). `_repo` is null in widget tests that don't override
  // `catalogRepositoryProvider` - those keep rendering the legacy in-memory
  // grid below, unchanged.
  CatalogRepository? _repo;
  CatalogWindow<VodItem>? _window;
  List<VodItem>? _observedVodItems;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
    _repo = _readCatalogRepository();
    final repo = _repo;
    if (repo != null) {
      _window = CatalogWindow<VodItem>(
        fetchPage: (offset, limit) async => const <VodItem>[],
        fetchCount: () async => 0,
      );
      _observedVodItems = ref.read(vodItemsProvider);
      _reconfigureWindow();
    }
  }

  CatalogRepository? _readCatalogRepository() {
    try {
      return ref.read(catalogRepositoryProvider);
    } on Object {
      return null;
    }
  }

  void _reconfigureWindow() {
    final repo = _repo;
    final window = _window;
    if (repo == null || window == null) return;
    final category = _selectedCategory;
    final categoryId = (category == null || category.isEmpty) ? null : category;
    final search = _appliedQuery.trim().isEmpty ? null : _appliedQuery.trim();
    unawaited(
      window.configure(
        fetchPage: (offset, limit) => repo.pageActiveItems<VodItem>(
          kind: kCatalogKindVod,
          categoryId: categoryId,
          search: search,
          offset: offset,
          limit: limit,
        ),
        fetchCount: () => repo.countActiveItems(
          kind: kCatalogKindVod,
          categoryId: categoryId,
          search: search,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gridFocusNode.dispose();
    _window?.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    setState(() => _query = value);
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _appliedQuery = '';
      _reconfigureWindow();
      return;
    }
    // Apply the first character of a fresh query immediately; only throttle
    // subsequent keystrokes while a filtered result is already on screen.
    if (_appliedQuery.isEmpty) {
      _appliedQuery = value;
      _reconfigureWindow();
      return;
    }
    _debounce = Timer(_searchDebounce, () {
      if (mounted && value != _appliedQuery) {
        setState(() => _appliedQuery = value);
        _reconfigureWindow();
      }
    });
  }

  void _onCategorySelected(String id) {
    setState(() => _selectedCategory = id);
    if (id != _kFavoritesCategoryId) _reconfigureWindow();
  }

  Future<void> _loadFavorites() async {
    final service = widget.favoritesService;
    if (service == null) return;
    final ids = await service.all();
    if (mounted) setState(() => _favoriteIds = ids);
  }

  List<VodItem> _filteredItems(List<VodItem> vodItems) => _filter.members(
    list: vodItems,
    selectedCategory: _selectedCategory,
    query: _appliedQuery,
    favoriteIds: _favoriteIds,
    favoritesCategoryId: _kFavoritesCategoryId,
  );

  List<CategoryTabData> _tabs(List<Category> categories) {
    final l = AppLocalizations.of(context);
    return [
      CategoryTabData(id: '', name: l.vodAllMovies),
      if (_favoriteIds.isNotEmpty)
        CategoryTabData(id: _kFavoritesCategoryId, name: l.liveTvFavorites),
      ...categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];
  }

  Map<String, int> _categoryCounts(List<VodItem> vodItems) => {
    '': vodItems.length,
    if (_favoriteIds.isNotEmpty) _kFavoritesCategoryId: _favoriteIds.length,
    ..._filter.categoryCounts(vodItems),
  };

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
    final isLoading = ref.watch(isLoadingContentProvider);
    final vodItems = ref.watch(vodItemsProvider);
    final categories = ref.watch(vodCategoriesProvider);

    if (isBootstrapping) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!isConfigured) {
      return Scaffold(
        body: Center(
          child: Text(
            'Please connect to your service in Settings',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    // The window's query only tracks category/search (set via
    // _reconfigureWindow); a fresh catalog load/replace instead swaps the
    // rows underneath the same repository instance, which the window can't
    // see on its own. Re-run the current query when the provider hands back
    // a new list instance (AppStateController always reassigns wholesale, so
    // identity is a reliable "the catalog changed" signal - see
    // CategoryBrowseFilter's `_ensureIndex` for the same pattern).
    if (_window != null && !identical(vodItems, _observedVodItems)) {
      _observedVodItems = vodItems;
      unawaited(_window!.load());
    }

    final useWindow =
        _repo != null && _selectedCategory != _kFavoritesCategoryId;
    final filtered = useWindow ? const <VodItem>[] : _filteredItems(vodItems);
    final l = AppLocalizations.of(context);
    final nav = MediaCategoryNav(
      key: _navKey,
      useSidebarLayout: widget.useSidebarLayout,
      query: _query,
      onQueryChanged: _onQueryChanged,
      searchHint: l.vodSearchHint,
      tabs: _tabs(categories),
      selectedId: _selectedCategory ?? '',
      onSelected: _onCategorySelected,
      filterButtonLabel: l.mediaCategoryFilterButton,
      filterScreenTitle: l.mediaCategoryFilterScreenTitle,
      categoryCounts: _categoryCounts(vodItems),
      onSidebarActivate: widget.onSidebarActivate,
      gridFocusScopeNode: _gridFocusNode,
      memoryKeyPrefix: 'vod',
      onEntryFocusScopeReady: widget.onEntryFocusScopeReady,
    );
    final content = Expanded(
      // Only show the spinner when there is nothing to display yet. During a
      // background refresh the already-populated grid stays visible.
      child: isLoading && vodItems.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : useWindow
          ? _buildWindowedContent(_window!)
          : filtered.isEmpty
          ? Center(
              child: Text(
                'No movies available',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            )
          : _buildGrid(filtered),
    );

    return Scaffold(
      body: widget.useSidebarLayout
          ? Row(children: [nav, content])
          : Column(children: [nav, content]),
    );
  }

  Widget _buildGrid(List<VodItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth =
            constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2;
        final columnCount = _posterColumnCount(
          availableWidth,
          FontSizeScope.scaleOf(context),
        );

        return FocusScope(
          node: _gridFocusNode,
          child: DpadRegion(
            memoryKey: 'vod/grid',
            horizontalEdge: DpadEdgeBehavior.stop,
            onEdge: (direction) {
              if (direction != TraversalDirection.left) return;
              if (widget.useSidebarLayout) {
                _navKey.currentState?.requestFocus();
              } else {
                widget.onSidebarActivate?.call();
              }
            },
            child: ScrollbarGridView(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columnCount,
                childAspectRatio: 0.6,
                mainAxisSpacing: MediaBrowsingMetrics.itemGap,
                crossAxisSpacing: MediaBrowsingMetrics.itemGap,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) =>
                  _vodCard(items[index], autofocus: index == 0),
            ),
          ),
        );
      },
    );
  }

  Widget _vodCard(VodItem item, {required bool autofocus}) => MediaPreviewCard(
    posterStyle: true,
    keepAlive: false,
    autofocus: autofocus,
    item: MediaPreviewItem(
      title: item.name,
      imageUrl: item.logoUrl,
      subtitle: item.year,
      ratingLabel: item.rating == null ? null : '★ ${item.rating}',
      fallbackIcon: Icons.movie,
      isFavorite: _favoriteIds.contains(item.id),
      onTap: () => widget.onVodSelect(item),
      onLongTap: widget.favoritesService == null
          ? null
          : () async {
              await widget.favoritesService!.toggle(item.id);
              await _loadFavorites();
            },
    ),
  );

  /// Windowed counterpart to [_buildGrid]: same layout/focus wiring, but the
  /// grid is driven by [window] (paged from SQLite) instead of an in-memory
  /// list, and only [CatalogWindowGrid.lookAheadRows] worth of items are ever
  /// materialized into [VodItem]s/widgets at once, regardless of catalog size.
  Widget _buildWindowedContent(CatalogWindow<VodItem> window) {
    return AnimatedBuilder(
      animation: window,
      builder: (context, _) {
        if (!window.hasLoadedOnce && window.error == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // A database that never opens must not strand the user on a spinner
        // forever - fall back to the legacy in-memory grid, which still works
        // off the provider's full list regardless of the repository's state.
        if (window.error != null && !window.hasLoadedOnce) {
          return _buildGrid(_filteredItems(ref.read(vodItemsProvider)));
        }
        if (window.totalCount == 0) {
          return Center(
            child: Text(
              'No movies available',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth =
                constraints.maxWidth - MediaBrowsingMetrics.contentPadding * 2;
            final columnCount = _posterColumnCount(
              availableWidth,
              FontSizeScope.scaleOf(context),
            );
            return FocusScope(
              node: _gridFocusNode,
              child: DpadRegion(
                memoryKey: 'vod/grid',
                horizontalEdge: DpadEdgeBehavior.stop,
                onEdge: (direction) {
                  if (direction != TraversalDirection.left) return;
                  if (widget.useSidebarLayout) {
                    _navKey.currentState?.requestFocus();
                  } else {
                    widget.onSidebarActivate?.call();
                  }
                },
                child: CatalogWindowGrid<VodItem>(
                  window: window,
                  crossAxisCount: columnCount,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columnCount,
                    childAspectRatio: 0.6,
                    mainAxisSpacing: MediaBrowsingMetrics.itemGap,
                    crossAxisSpacing: MediaBrowsingMetrics.itemGap,
                  ),
                  itemBuilder: (context, index, item) =>
                      _vodCard(item, autofocus: index == 0),
                  placeholderBuilder: (context, index) =>
                      const CatalogGridPlaceholder(),
                ),
              ),
            );
          },
        );
      },
    );
  }

  int _posterColumnCount(double availableWidth, double scale) {
    final maxCardWidth = _maxPosterCardWidth * scale;
    final minCardWidth = _minPosterCardWidth * scale;
    final minimumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (maxCardWidth + MediaBrowsingMetrics.itemGap))
            .ceil();
    final maximumColumns =
        ((availableWidth + MediaBrowsingMetrics.itemGap) /
                (minCardWidth + MediaBrowsingMetrics.itemGap))
            .floor();
    return minimumColumns.clamp(1, maximumColumns.clamp(1, 100));
  }
}
