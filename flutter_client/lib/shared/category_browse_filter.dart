import 'package:m3u_tv/shared/catalog_text_filter.dart';

/// Memoized category/search filtering for the VOD and Series browse screens.
///
/// Both screens hold the entire catalog (which for some providers is hundreds
/// of thousands of entries) and used to re-scan all of it on every rebuild -
/// every search keystroke, every favorites `setState`, and every toggle of the
/// loading flag during a background refresh.
///
/// This helper does the O(catalog) work once:
///
/// * [categoryCounts] and the per-category member lists are built a single
///   time per catalog identity (a new list instance means the catalog was
///   reloaded). Switching tabs is then O(members), not O(catalog).
/// * [members] caches its last result and returns it unchanged while the
///   catalog, selected category, normalized query, and favorites set are all
///   identical to the previous call.
///
/// An item belongs to its primary [primaryCategoryId] plus every id in
/// [extraCategoryIds] (m3u-editor's overlapping dynamic TMDB categories).
/// Duplicate ids on a single item are collapsed so a member is never counted
/// or listed twice.
///
/// The name query reuses [CatalogTextFilter] so each name is lowercased once
/// per catalog, not once per keystroke.
class CategoryBrowseFilter<T> {
  CategoryBrowseFilter({
    required this.primaryCategoryId,
    required this.extraCategoryIds,
    required this.name,
    required this.id,
  });

  final String? Function(T item) primaryCategoryId;
  final List<String> Function(T item) extraCategoryIds;
  final String Function(T item) name;
  final int Function(T item) id;

  late final CatalogTextFilter<T> _text = CatalogTextFilter<T>(name);

  List<T>? _indexedList;
  Map<String, List<T>> _byCategory = const {};
  Map<String, int> _categoryCounts = const {};

  List<T>? _filtered;
  List<T>? _filteredForList;
  String? _filteredForCategory;
  String? _filteredForQuery;
  Set<int>? _filteredForFavorites;

  void _ensureIndex(List<T> list) {
    if (identical(list, _indexedList)) return;
    _text.reindex(list);
    final byCategory = <String, List<T>>{};
    for (final item in list) {
      final primary = primaryCategoryId(item);
      final seen = <String>{};
      if (primary != null && seen.add(primary)) {
        (byCategory[primary] ??= <T>[]).add(item);
      }
      for (final extra in extraCategoryIds(item)) {
        if (!seen.add(extra)) continue;
        (byCategory[extra] ??= <T>[]).add(item);
      }
    }
    _indexedList = list;
    _byCategory = byCategory;
    _categoryCounts = {
      for (final entry in byCategory.entries) entry.key: entry.value.length,
    };
    // The catalog changed, so any cached filtered result is stale.
    _filtered = null;
  }

  /// Per-category membership counts, keyed by category id. Does not include the
  /// synthetic "all" or favorites tabs - the caller merges those in.
  Map<String, int> categoryCounts(List<T> list) {
    _ensureIndex(list);
    return _categoryCounts;
  }

  /// The catalog filtered to [selectedCategory] (null/empty means all,
  /// [favoritesCategoryId] means the favorites set) and then to [query].
  ///
  /// Returns the same list instance on repeated calls with unchanged inputs.
  List<T> members({
    required List<T> list,
    required String? selectedCategory,
    required String query,
    required Set<int> favoriteIds,
    required String favoritesCategoryId,
  }) {
    _ensureIndex(list);
    final normalizedQuery = query.trim().toLowerCase();

    final cached = _filtered;
    if (cached != null &&
        identical(list, _filteredForList) &&
        selectedCategory == _filteredForCategory &&
        normalizedQuery == _filteredForQuery &&
        identical(favoriteIds, _filteredForFavorites)) {
      return cached;
    }

    final Iterable<T> categoryFiltered;
    if (selectedCategory == favoritesCategoryId) {
      categoryFiltered = list.where((item) => favoriteIds.contains(id(item)));
    } else if (selectedCategory == null || selectedCategory.isEmpty) {
      categoryFiltered = list;
    } else {
      categoryFiltered = _byCategory[selectedCategory] ?? const [];
    }

    final result =
        (normalizedQuery.isEmpty
                ? categoryFiltered
                : categoryFiltered.where(
                    (item) => _text.matches(item, normalizedQuery),
                  ))
            .toList(growable: false);

    _filtered = result;
    _filteredForList = list;
    _filteredForCategory = selectedCategory;
    _filteredForQuery = normalizedQuery;
    _filteredForFavorites = favoriteIds;
    return result;
  }
}
