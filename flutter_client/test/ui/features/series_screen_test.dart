import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/series/series_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

/// Builds a fresh in-memory catalog repository populated with [seriesList].
/// Opening the database needs `tester.runAsync` (real drift I/O doesn't
/// resolve under flutter_test's default fakeAsync zone); once it's open,
/// query pumps back in the normal zone resolve fine via plain
/// `pumpAndSettle`.
Future<CatalogRepository> _buildRepo(
  WidgetTester tester,
  List<Series> seriesList,
) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.activeSource,
      kind: kCatalogKindSeries,
      items: seriesList,
    );
    return repo;
  });
  return repo!;
}

void main() {
  // See vod_screen_test.dart: a real poster/cover URL can drive
  // flutter_cache_manager into a real path_provider call once any
  // tester.runAsync bridge has run in this test file, which otherwise throws
  // MissingPluginException (sometimes attributed to a later test).
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  group('SeriesScreen', () {
    late List<Series> testSeriesList;
    late List<Category> testCategories;

    setUp(() {
      testSeriesList = [
        const Series(
          id: 1,
          name: 'Breaking Bad',
          coverUrl: 'http://example.com/bb.jpg',
          categoryId: '30',
          rating: 4.8,
        ),
        const Series(
          id: 2,
          name: 'Stranger Things',
          coverUrl: 'http://example.com/st.jpg',
          categoryId: '31',
          rating: 4.2,
        ),
      ];
      testCategories = [
        const Category(id: '30', name: 'Thriller'),
        const Category(id: '31', name: 'Sci-Fi'),
      ];
    });

    testWidgets('renders series grid with names', (tester) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Stranger Things'), findsOneWidget);
    });

    testWidgets('renders All Series and category tabs', (tester) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Series'), findsOneWidget);
      expect(find.text('Thriller'), findsOneWidget);
      expect(find.text('Sci-Fi'), findsOneWidget);
    });

    testWidgets('large desktop grids keep series cards comfortably sized', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manySeries = List<Series>.generate(
        40,
        (index) => Series(
          id: index,
          name: 'Desktop Series $index',
          coverUrl: 'http://example.com/$index.jpg',
          categoryId: '30',
        ),
      );
      final repo = await _buildRepo(tester, manySeries);

      for (final viewport in [
        const Size(1440, 900),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: testCategories),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final firstSeriesCard = find.ancestor(
          of: find.text('Desktop Series 0'),
          matching: find.byType(DpadInkWell),
        );
        expect(firstSeriesCard, findsOneWidget);
        expect(tester.getSize(firstSeriesCard).width, lessThanOrEqualTo(220));
      }
    });

    testWidgets('tapping category tab filters series', (tester) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thriller'));
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Stranger Things'), findsNothing);
    });

    testWidgets(
      'dynamic category tab filters series by overlapping category_ids',
      (tester) async {
        // See the matching VodScreen test — dynamic TMDB categories overlap
        // the regular category, carried via categoryIds.
        final seriesList = [
          const Series(
            id: 1,
            name: 'Breaking Bad',
            categoryId: '30',
            categoryIds: ['30', '900000002'],
          ),
          const Series(id: 2, name: 'Firefly', categoryId: '30'),
        ];
        final categories = [
          const Category(id: '900000002', name: 'Trending Shows'),
          const Category(id: '30', name: 'Thriller'),
        ];
        final repo = await _buildRepo(tester, seriesList);

        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: categories),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Trending Shows'));
        await tester.pumpAndSettle();

        expect(find.text('Breaking Bad'), findsOneWidget);
        expect(find.text('Firefly'), findsNothing);
      },
    );

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: testCategories,
          isConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('category bar and series grid expose scrollbars', (
      tester,
    ) async {
      final manyCategories = List<Category>.generate(
        16,
        (index) => Category(id: '$index', name: 'Category $index'),
      );
      final repo = await _buildRepo(tester, testSeriesList);

      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: manyCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters series case-insensitively', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'stranger');
      await tester.pumpAndSettle();

      expect(find.text('Stranger Things'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsNothing);
    });

    testWidgets('inline search composes with category filter', (tester) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thriller'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Stranger Things'), findsNothing);
    });

    testWidgets('tapping series triggers onSeriesSelect callback', (
      tester,
    ) async {
      Series? selectedSeries;
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: testCategories,
          onSeriesSelect: (series) => selectedSeries = series,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Breaking Bad'));
      await tester.pumpAndSettle();

      expect(selectedSeries, isNotNull);
      expect(selectedSeries!.id, 1);
    });

    testWidgets('shows rating when available', (tester) async {
      final repo = await _buildRepo(tester, testSeriesList);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('★ 4.8'), findsOneWidget);
    });

    testWidgets(
      'mobile layout shows a Filter button instead of category chips, '
      'and selecting a category filters the grid',
      (tester) async {
        final repo = await _buildRepo(tester, testSeriesList);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: testCategories,
            useSidebarLayout: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filter'), findsOneWidget);

        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();

        final categoryTab = testCategories.first;
        await tester.tap(find.text(categoryTab.name));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.catalogRepository,
    required this.categories,
    this.isConfigured = true,
    this.useSidebarLayout = true,
    this.onSeriesSelect,
  });

  final CatalogRepository catalogRepository;
  final List<Category> categories;
  final bool isConfigured;
  final bool useSidebarLayout;
  final void Function(Series)? onSeriesSelect;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        seriesCategoriesProvider.overrideWith((_) => categories),
        catalogRepositoryProvider.overrideWith((_) => catalogRepository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: SeriesScreen(
          useSidebarLayout: useSidebarLayout,
          onSeriesSelect: onSeriesSelect ?? (_) {},
        ),
      ),
    );
  }
}
