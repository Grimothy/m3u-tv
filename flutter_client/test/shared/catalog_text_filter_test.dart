// ignore_for_file: cascade_invocations

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/catalog_text_filter.dart';

class _Item {
  const _Item(this.name);
  final String name;
}

void main() {
  group('CatalogTextFilter', () {
    CatalogTextFilter<_Item> newFilter() => CatalogTextFilter((i) => i.name);

    test('filterWhole matches case-insensitively on a substring', () {
      final filter = newFilter();
      final items = <_Item>[
        const _Item('The Matrix'),
        const _Item('Matrix Reloaded'),
        const _Item('Sintel'),
      ];

      expect(
        filter.filterWhole(items, ' mAtRiX ').map((i) => i.name),
        ['The Matrix', 'Matrix Reloaded'],
      );
    });

    test('filterWhole returns an empty list for a blank query', () {
      final filter = newFilter();
      final items = <_Item>[const _Item('Sintel')];

      expect(filter.filterWhole(items, '   '), isEmpty);
    });

    test('filterWhole returns the same instance for repeat calls', () {
      final filter = newFilter();
      final items = <_Item>[
        const _Item('Sintel'),
        const _Item('Big Buck Bunny'),
      ];

      final first = filter.filterWhole(items, 'si');
      final second = filter.filterWhole(items, 'SI');
      expect(identical(first, second), isTrue);
    });

    test('filterWhole recomputes when the catalog instance changes', () {
      final filter = newFilter();
      final first = <_Item>[const _Item('Sintel')];
      final second = <_Item>[const _Item('Sintel'), const _Item('Sinbad')];

      final fromFirst = filter.filterWhole(first, 'sin');
      final fromSecond = filter.filterWhole(second, 'sin');
      expect(fromFirst, hasLength(1));
      expect(fromSecond, hasLength(2));
    });

    test('matches works for an item outside the last reindexed list', () {
      final filter = newFilter();
      filter.reindex(<_Item>[const _Item('Sintel')]);

      // Not folded, so it falls back to folding on the spot.
      const outsider = _Item('Tears of Steel');
      expect(filter.matches(outsider, 'steel'), isTrue);
      expect(filter.matches(outsider, 'matrix'), isFalse);
    });

    test('matches treats a blank query as matching everything', () {
      final filter = newFilter();
      filter.reindex(<_Item>[const _Item('Sintel')]);

      expect(filter.matches(const _Item('Sintel'), ''), isTrue);
    });
  });
}
