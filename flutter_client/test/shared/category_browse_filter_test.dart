import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/category_browse_filter.dart';

class _Item {
  const _Item(
    this.id,
    this.name,
    this.categoryId, [
    this.categoryIds = const [],
  ]);

  final int id;
  final String name;
  final String? categoryId;
  final List<String> categoryIds;
}

CategoryBrowseFilter<_Item> _newFilter() => CategoryBrowseFilter<_Item>(
  primaryCategoryId: (item) => item.categoryId,
  extraCategoryIds: (item) => item.categoryIds,
  name: (item) => item.name,
  id: (item) => item.id,
);

const _favoritesCategoryId = '__FAVORITES__';

void main() {
  group('CategoryBrowseFilter', () {
    test('buckets items by primary and overlapping category ids', () {
      final filter = _newFilter();
      final items = <_Item>[
        const _Item(1, 'Alpha', '10', ['10', '900']),
        const _Item(2, 'Bravo', '10'),
        const _Item(3, 'Charlie', '20', ['20', '900']),
      ];

      List<_Item> membersOf(String category) => filter.members(
        list: items,
        selectedCategory: category,
        query: '',
        favoriteIds: const {},
        favoritesCategoryId: _favoritesCategoryId,
      );

      expect(membersOf('10').map((i) => i.id), [1, 2]);
      expect(membersOf('20').map((i) => i.id), [3]);
      // Dynamic category drawn from the overlapping ids, catalog order kept.
      expect(membersOf('900').map((i) => i.id), [1, 3]);
      expect(membersOf('999'), isEmpty);
    });

    test('collapses a duplicate id on a single item', () {
      final filter = _newFilter();
      final items = <_Item>[
        const _Item(1, 'Alpha', '10', ['10', '900', '900']),
      ];

      final members = filter.members(
        list: items,
        selectedCategory: '900',
        query: '',
        favoriteIds: const {},
        favoritesCategoryId: _favoritesCategoryId,
      );

      expect(members, hasLength(1));
      expect(filter.categoryCounts(items)['900'], 1);
    });

    test(
      'categoryCounts reports member list lengths and omits synthetic tabs',
      () {
        final filter = _newFilter();
        final items = <_Item>[
          const _Item(1, 'Alpha', '10', ['10', '900']),
          const _Item(2, 'Bravo', '10'),
          const _Item(3, 'Charlie', '20', ['20', '900']),
          const _Item(4, 'Delta', null),
        ];

        expect(filter.categoryCounts(items), {'10': 2, '20': 1, '900': 2});
      },
    );

    test('members returns the same instance while inputs are unchanged', () {
      final filter = _newFilter();
      final items = <_Item>[
        const _Item(1, 'Alpha', '10'),
        const _Item(2, 'Bravo', '10'),
      ];

      final first = filter.members(
        list: items,
        selectedCategory: '10',
        query: 'a',
        favoriteIds: const {},
        favoritesCategoryId: _favoritesCategoryId,
      );
      final second = filter.members(
        list: items,
        selectedCategory: '10',
        query: 'a ',
        favoriteIds: const {},
        favoritesCategoryId: _favoritesCategoryId,
      );

      expect(identical(first, second), isTrue);
    });

    test('recomputes when the category, query, or favorites set changes', () {
      final filter = _newFilter();
      final items = <_Item>[
        const _Item(1, 'Alpha', '10'),
        const _Item(2, 'Bravo', '20'),
      ];

      final byTen = filter.members(
        list: items,
        selectedCategory: '10',
        query: '',
        favoriteIds: const {},
        favoritesCategoryId: _favoritesCategoryId,
      );
      final byTwenty = filter.members(
        list: items,
        selectedCategory: '20',
        query: '',
        favoriteIds: const {},
        favoritesCategoryId: _favoritesCategoryId,
      );
      expect(byTen.single.id, 1);
      expect(byTwenty.single.id, 2);
      expect(identical(byTen, byTwenty), isFalse);

      final favorites = {2};
      final favResult = filter.members(
        list: items,
        selectedCategory: _favoritesCategoryId,
        query: '',
        favoriteIds: favorites,
        favoritesCategoryId: _favoritesCategoryId,
      );
      expect(favResult.single.id, 2);
    });

    test('rebuilds the index when a new catalog instance arrives', () {
      final filter = _newFilter();
      final first = <_Item>[const _Item(1, 'Alpha', '10')];
      final second = <_Item>[
        const _Item(1, 'Alpha', '10'),
        const _Item(2, 'Bravo', '10'),
      ];

      expect(filter.categoryCounts(first)['10'], 1);
      expect(filter.categoryCounts(second)['10'], 2);
      expect(
        filter
            .members(
              list: second,
              selectedCategory: '10',
              query: '',
              favoriteIds: const {},
              favoritesCategoryId: _favoritesCategoryId,
            )
            .map((i) => i.id),
        [1, 2],
      );
    });

    test(
      'null/empty selected category returns the whole catalog, then query',
      () {
        final filter = _newFilter();
        final items = <_Item>[
          const _Item(1, 'Big Buck Bunny', '10'),
          const _Item(2, 'Sintel', '20'),
        ];

        expect(
          filter.members(
            list: items,
            selectedCategory: null,
            query: '',
            favoriteIds: const {},
            favoritesCategoryId: _favoritesCategoryId,
          ),
          hasLength(2),
        );
        expect(
          filter
              .members(
                list: items,
                selectedCategory: '',
                query: 'sintel',
                favoriteIds: const {},
                favoritesCategoryId: _favoritesCategoryId,
              )
              .single
              .id,
          2,
        );
      },
    );
  });
}
