import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Debounced EPG show-search state machine shared by `LiveTvScreen` and
/// `SearchScreen`. Owns the 350ms debounce and the generation counter that
/// guards against an out-of-order network response clobbering a later
/// query's result, plus the "just became active" edge used to bump
/// [searchSessionId] (consumed by `ShowSearchResultsView` to reset its tab
/// index back to "All") only on the transition into search mode - not on
/// every keystroke of an already-active query, which would otherwise bounce
/// the user off a deliberately-chosen On Now/Upcoming tab mid-typing.
class EpgShowSearchController extends ChangeNotifier {
  Timer? _debounce;
  int _generation = 0;
  bool _wasActive = false;
  bool _disposed = false;

  List<EpgShow> results = const <EpgShow>[];
  bool isLoading = false;
  String? error;
  int searchSessionId = 0;

  /// Call on every keystroke of the search field, passing the host's
  /// current `onSearchShows` callback (may be null to hide the affordance
  /// entirely).
  void onQueryChanged(
    String value,
    Future<List<EpgShow>> Function(String)? search,
  ) {
    final trimmed = value.trim();
    if (trimmed.length < 2) {
      _wasActive = false;
      _debounce?.cancel();
      _generation++;
      if (results.isNotEmpty || isLoading || error != null) {
        results = const <EpgShow>[];
        isLoading = false;
        error = null;
        notifyListeners();
      }
      return;
    }
    if (!_wasActive) {
      searchSessionId++;
    }
    _wasActive = true;
    _debounce?.cancel();
    // Flip to loading synchronously so the results view renders "Searching
    // shows..." the same frame the qualifying query first arrives. Without
    // this, the empty view flashes "No shows match your search" for the
    // 350ms the debounce is waiting before the network call fires.
    isLoading = true;
    results = const <EpgShow>[];
    error = null;
    notifyListeners();
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _runSearch(trimmed, search),
    );
  }

  Future<void> _runSearch(
    String trimmed,
    Future<List<EpgShow>> Function(String)? search,
  ) async {
    if (search == null) {
      if (isLoading) {
        isLoading = false;
        notifyListeners();
      }
      return;
    }
    final generation = ++_generation;
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final searchResults = await search(trimmed);
      if (_disposed || generation != _generation) return;
      results = searchResults;
      isLoading = false;
      notifyListeners();
    } on Object catch (e) {
      if (_disposed || generation != _generation) return;
      error = e.toString();
      isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}
