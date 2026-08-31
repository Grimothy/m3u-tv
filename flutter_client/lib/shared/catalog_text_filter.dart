/// Case-insensitive substring name matching over a large catalog, with the
/// lowercased form of every name computed once instead of on every keystroke.
///
/// Some providers ship catalogs of hundreds of thousands of entries. Filtering
/// them with `item.name.toLowerCase().contains(query)` allocates a lowercased
/// string per item per keystroke; the browse and search screens do this across
/// up to three catalogs at once. This helper folds each name a single time per
/// catalog identity (a new list instance means the catalog reloaded) and keeps
/// the folds in an identity map so an already-narrowed subset can still be
/// matched.
class CatalogTextFilter<T> {
  CatalogTextFilter(this.name);

  final String Function(T item) name;

  List<T>? _indexedList;
  final Map<T, String> _fold = Map<T, String>.identity();

  List<T>? _wholeResult;
  List<T>? _wholeResultForList;
  String? _wholeResultForQuery;

  /// Rebuilds the fold map when [list] is a different instance than last time.
  /// Cheap to call every build.
  void reindex(List<T> list) {
    if (identical(list, _indexedList)) return;
    _indexedList = list;
    _fold
      ..clear()
      ..addEntries(
        list.map((item) => MapEntry(item, name(item).toLowerCase())),
      );
    _wholeResult = null;
  }

  /// Whether [item]'s name contains [normalizedQuery] (already trimmed and
  /// lowercased). An empty query matches everything. Falls back to folding on
  /// the spot for an item that was not in the last [reindex]ed list.
  bool matches(T item, String normalizedQuery) {
    if (normalizedQuery.isEmpty) return true;
    final folded = _fold[item] ?? name(item).toLowerCase();
    return folded.contains(normalizedQuery);
  }

  /// Filters the whole [list] to names containing [rawQuery]. Returns an empty
  /// list for a blank query (search semantics), and the same result instance
  /// on repeated calls with an unchanged catalog and query.
  List<T> filterWhole(List<T> list, String rawQuery) {
    reindex(list);
    final normalizedQuery = rawQuery.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const [];

    final cached = _wholeResult;
    if (cached != null &&
        identical(list, _wholeResultForList) &&
        normalizedQuery == _wholeResultForQuery) {
      return cached;
    }

    final result = [
      for (final item in list)
        if (matches(item, normalizedQuery)) item,
    ];
    _wholeResult = result;
    _wholeResultForList = list;
    _wholeResultForQuery = normalizedQuery;
    return result;
  }
}
