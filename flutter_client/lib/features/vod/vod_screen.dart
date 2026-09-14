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
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/catalog_window.dart';
import 'package:m3u_tv/shared/catalog_window_grid.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';

/// VOD (Movies) screen with category filtering and poster grid.
///
/// Mirrors the RN HomeScreen Movies row and MovieDetailsScreen behavior:
/// - All Movies + category tabs
/// - Grid layout with poster thumbnails and ratings
/// - Category filtering
///
/// Every tab except Favorites is a [CatalogWindowGrid] paged straight from
/// the SQLite catalog (`CatalogRepository`) - the screen never holds the
/// full VOD catalog in memory. Favorites is a bounded id-list lookup instead
/// (typically a handful of items), not worth a windowed query.
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
  VodSortOption _sortOption = VodSortOption.defaultOrder;

  /// Cached copy of [ViewSettingsService.rememberVodSort] so we only read it
  /// when opening the sort dialog (not per sort change). Refreshed every
  /// time the dialog opens so flipping the Settings toggle in another tab
  /// is honored on next open.
  bool _rememberVodSort = false;
  List<VodItem> _favoriteItems = const [];
  bool _favoritesLoadedOnce = false;

  Map<String, int> _categoryCounts = const {};
  List<Category>? _countsFetchedForCategories;
  int _countsFetchedForFavoritesCount = -1;

  final FocusScopeNode _gridFocusNode = FocusScopeNode();
  final GlobalKey<MediaCategoryNavState> _navKey =
      GlobalKey<MediaCategoryNavState>();

  late final CatalogRepository _repo = ref.read(catalogRepositoryProvider);
  late final CatalogWindow<VodItem> _window = CatalogWindow<VodItem>(
    fetchPage: (offset, limit) async => const <VodItem>[],
    fetchCount: () async => 0,
  );

  @override
  void initState() {
    super.initState();
    unawaited(_loadFavorites());
    unawaited(_loadSortPreference());
    _reconfigureWindow();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _gridFocusNode.dispose();
    _window.dispose();
    super.dispose();
  }

  void _reconfigureWindow() {
    final category = _selectedCategory;
    final categoryId = (category == null || category.isEmpty) ? null : category;
    final search = _appliedQuery.trim().isEmpty ? null : _appliedQuery.trim();
    unawaited(
      _window.configure(
        fetchPage: (offset, limit) => _repo.pageActiveItems<VodItem>(
          kind: kCatalogKindVod,
          categoryId: categoryId,
          search: search,
          sortByRatingDesc: _sortOption == VodSortOption.ratingDesc,
          offset: offset,
          limit: limit,
        ),
        fetchCount: () => _repo.countActiveItems(
          kind: kCatalogKindVod,
          categoryId: categoryId,
          search: search,
        ),
      ),
    );
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
    if (service == null) {
      if (mounted) setState(() => _favoritesLoadedOnce = true);
      return;
    }
    final ids = await service.all();
    final items = ids.isEmpty
        ? const <VodItem>[]
        : await _repo.activeItemsByIds<VodItem>(
            kind: kCatalogKindVod,
            ids: ids,
          );
    if (mounted) {
      setState(() {
        _favoriteIds = ids;
        _favoriteItems = items;
        _favoritesLoadedOnce = true;
      });
    }
  }

  /// Restores the persisted VOD sort only when the user has opted in via
  /// Settings -> View -> Filter Persistence. Otherwise we leave
  /// [VodSortOption.defaultOrder] in place - matching the no-key-set case
  /// for users who have never opened the dialog or don't want their choice
  /// to survive a relaunch. Reconfigures the window when a non-default sort
  /// is restored so the already-in-flight default-order load gets replaced.
  Future<void> _loadSortPreference() async {
    final service = ref.read(viewSettingsServiceProvider);
    final remember = await service.rememberVodSort();
    if (!mounted) return;
    setState(() => _rememberVodSort = remember);
    if (!remember) return;
    final option = await service.vodSortOption();
    if (!mounted) return;
    setState(() => _sortOption = option);
    _reconfigureWindow();
  }

  /// Applies [_sortOption] to the (already category/query-filtered)
  /// favorites list. The windowed catalog tabs sort in SQL via
  /// [CatalogRepository.pageActiveItems]; favorites is a small,
  /// fully-materialized list, so sorting it client-side is simplest.
  List<VodItem> _sortedFavorites(List<VodItem> items) {
    if (_sortOption != VodSortOption.ratingDesc) return items;
    // Unrated items sink below every rated one - keeps the grid visually
    // anchored on the best-rated movies and treats missing data as "less
    // informative" rather than "zero stars".
    return items.toList(growable: false)
      ..sort((a, b) => (b.rating ?? -1).compareTo(a.rating ?? -1));
  }

  /// Refreshes tab-count labels (total / favorites / per-category) when the
  /// category list changes (a fresh catalog load) or the favorites count
  /// changes. Cheap: one unfiltered count plus one query per category,
  /// versus scanning the whole catalog in Dart.
  void _ensureCounts(List<Category> categories) {
    if (identical(categories, _countsFetchedForCategories) &&
        _favoriteIds.length == _countsFetchedForFavoritesCount) {
      return;
    }
    _countsFetchedForCategories = categories;
    _countsFetchedForFavoritesCount = _favoriteIds.length;
    final favoritesSnapshotCount = _favoriteIds.length;
    unawaited(_computeCounts(categories, favoritesSnapshotCount));
  }

  Future<void> _computeCounts(
    List<Category> categories,
    int favoritesCount,
  ) async {
    final total = await _repo.countActiveItems(kind: kCatalogKindVod);
    final perCategory = await _repo.activeCategoryCounts(
      kind: kCatalogKindVod,
      categoryIds: categories.map((c) => c.id).toList(growable: false),
    );
    if (!mounted) return;
    setState(() {
      _categoryCounts = {
        '': total,
        if (favoritesCount > 0) _kFavoritesCategoryId: favoritesCount,
        ...perCategory,
      };
    });
  }

  List<CategoryTabData> _tabs(List<Category> categories) {
    final l = AppLocalizations.of(context);
    return [
      CategoryTabData(id: '', name: l.vodAllMovies),
      if (_favoriteIds.isNotEmpty)
        CategoryTabData(id: _kFavoritesCategoryId, name: l.liveTvFavorites),
      ...categories.map((c) => CategoryTabData(id: c.id, name: c.name)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isBootstrapping = ref.watch(isBootstrappingProvider);
    final isConfigured = ref.watch(isConfiguredProvider);
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

    _ensureCounts(categories);
    final isFavoritesTab = _selectedCategory == _kFavoritesCategoryId;
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
      categoryCounts: _categoryCounts,
      onSidebarActivate: widget.onSidebarActivate,
      gridFocusScopeNode: _gridFocusNode,
      memoryKeyPrefix: 'vod',
      onEntryFocusScopeReady: widget.onEntryFocusScopeReady,
      onCategoryLongPress: () => _showSortMenu(context),
    );
    final content = Expanded(
      child: isFavoritesTab
          ? _buildFavoritesContent()
          : _buildWindowedContent(_window),
    );

    return Scaffold(
      body: widget.useSidebarLayout
          ? Row(children: [nav, content])
          : Column(children: [nav, content]),
    );
  }

  Widget _buildFavoritesContent() {
    if (!_favoritesLoadedOnce) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_favoriteItems.isEmpty) {
      return Center(
        child: Text(
          'No movies available',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }
    return _buildGrid(_sortedFavorites(_favoriteItems));
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

  /// Windowed grid: same layout/focus wiring as [_buildGrid], but driven by
  /// [window] (paged from SQLite) instead of an in-memory list, and only
  /// [CatalogWindowGrid.lookAheadRows] worth of items are ever materialized
  /// into [VodItem]s/widgets at once, regardless of catalog size.
  Widget _buildWindowedContent(CatalogWindow<VodItem> window) {
    return AnimatedBuilder(
      animation: window,
      builder: (context, _) {
        if (!window.hasLoadedOnce && window.error == null) {
          return const Center(child: CircularProgressIndicator());
        }
        // A database that never opens must not strand the user on a spinner
        // forever.
        if (window.error != null && !window.hasLoadedOnce) {
          return Center(
            child: Text(
              'Unable to load movies',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          );
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

  /// Opens the "Sort Movies By" modal. Refreshes the cached
  /// [ViewSettingsService.rememberVodSort] value up front so the
  /// post-dialog persistence decision uses the latest setting, then applies
  /// the user's selection (or no-op on dismiss). On selecting a new
  /// option: always updates the local [_sortOption]; only writes back to
  /// the service when persistence is currently on - exactly per the
  /// plan's "read once at dialog open" discipline.
  Future<void> _showSortMenu(BuildContext context) async {
    final service = ref.read(viewSettingsServiceProvider);
    final remember = await service.rememberVodSort();
    if (!mounted) return;
    setState(() => _rememberVodSort = remember);
    if (!context.mounted) return;

    final selected = await showDialog<VodSortOption>(
      context: context,
      builder: (dialogContext) {
        final l = AppLocalizations.of(dialogContext);
        return SimpleDialog(
          title: Row(
            children: [
              const Icon(Icons.sort, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(l.vodSortDialogTitle)),
            ],
          ),
          children: [
            DpadRegion(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _VodSortOption(
                    icon: Icons.list_alt,
                    label: l.vodSortDefault,
                    isActive: _sortOption == VodSortOption.defaultOrder,
                    autofocus: _sortOption == VodSortOption.defaultOrder,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(VodSortOption.defaultOrder),
                  ),
                  _VodSortOption(
                    icon: Icons.star_rate,
                    label: l.vodSortRating,
                    isActive: _sortOption == VodSortOption.ratingDesc,
                    autofocus: _sortOption == VodSortOption.ratingDesc,
                    onTap: () => Navigator.of(
                      dialogContext,
                    ).pop(VodSortOption.ratingDesc),
                  ),
                  _VodSortOption(
                    icon: Icons.close,
                    label: l.cancel,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() => _sortOption = selected);
    _reconfigureWindow();
    if (!_rememberVodSort) return;
    unawaited(
      ref.read(viewSettingsServiceProvider).setVodSortOption(selected),
    );
  }
}

class _VodSortOption extends StatelessWidget {
  const _VodSortOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  /// First option in the dialog gets autofocus; subsequent ones don't, so
  /// d-pad down naturally walks through the list.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                  color: isActive ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
            if (isActive) Icon(Icons.check, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
