import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/vod/vod_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

/// Builds a fresh in-memory catalog repository populated with [vodItems].
/// Drift's real I/O does not resolve under flutter_test's default fakeAsync
/// zone, so this - and every subsequent pump that touches the repository -
/// runs via `tester.runAsync`.
Future<CatalogRepository> _buildRepo(
  WidgetTester tester,
  List<VodItem> vodItems,
) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.activeSource,
      kind: kCatalogKindVod,
      items: vodItems,
    );
    return repo;
  });
  return repo!;
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

void main() {
  // Rendering a real poster URL kicks off flutter_cache_manager's disk-cache
  // lookup via path_provider. That's inert under plain fakeAsync (nothing
  // ever runs it for real), but tester.runAsync (needed above for drift)
  // runs in a real zone, so the plugin channel call actually fires and
  // throws MissingPluginException - sometimes attributed to a *later* test
  // since the leaked async chain outlives the test that started it. Give it
  // a real, writable answer instead of leaving the channel unmocked.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  group('VodScreen', () {
    late List<VodItem> testVodItems;
    late List<Category> testCategories;

    setUp(() {
      testVodItems = [
        const VodItem(
          id: 1,
          name: 'Big Buck Bunny',
          streamUrl: 'http://example.com/1.mp4',
          containerExtension: 'mp4',
          logoUrl: 'http://example.com/bunny.jpg',
          categoryId: '20',
          rating: 4.5,
        ),
        const VodItem(
          id: 2,
          name: 'Sintel',
          streamUrl: 'http://example.com/2.mp4',
          containerExtension: 'mp4',
          logoUrl: 'http://example.com/sintel.jpg',
          categoryId: '21',
          rating: 4,
        ),
        const VodItem(
          id: 3,
          name: 'Tears of Steel',
          streamUrl: 'http://example.com/3.mkv',
          containerExtension: 'mkv',
          categoryId: '20',
        ),
      ];
      testCategories = [
        const Category(id: '20', name: 'Action'),
        const Category(id: '21', name: 'Drama'),
      ];
    });

    testWidgets('renders movie grid with names', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsOneWidget);
    });

    testWidgets('narrow phone layout does not overflow movie cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('★ 4.5'), findsOneWidget);
    });

    testWidgets('large desktop grids keep movie cards comfortably sized', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manyMovies = List<VodItem>.generate(
        40,
        (index) => VodItem(
          id: index,
          name: 'Desktop Movie $index',
          streamUrl: 'http://example.com/$index.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
        ),
      );
      final repo = await _buildRepo(tester, manyMovies);

      for (final viewport in [
        const Size(1440, 900),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: testCategories),
        );
        await _settle(tester);

        expect(tester.takeException(), isNull);
        final firstMovieCard = find.ancestor(
          of: find.text('Desktop Movie 0'),
          matching: find.byType(DpadInkWell),
        );
        expect(firstMovieCard, findsOneWidget);
        expect(tester.getSize(firstMovieCard).width, lessThanOrEqualTo(220));
      }
    });

    testWidgets('renders All Movies and category tabs', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(find.text('All Movies'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
    });

    testWidgets('tapping category tab filters movies', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.text('Action'));
      await _settle(tester);

      // Only Action movies should be visible
      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsOneWidget);
      expect(find.text('Sintel'), findsNothing);
    });

    testWidgets(
      'dynamic category tab filters movies by overlapping category_ids',
      (tester) async {
        // m3u-editor's dynamic TMDB categories overlap the regular groups:
        // a member keeps its primary categoryId and additionally carries the
        // dynamic category id in categoryIds.
        final items = [
          const VodItem(
            id: 1,
            name: 'Big Buck Bunny',
            streamUrl: 'http://example.com/1.mp4',
            containerExtension: 'mp4',
            categoryId: '20',
            categoryIds: ['20', '900000001'],
          ),
          const VodItem(
            id: 2,
            name: 'Sintel',
            streamUrl: 'http://example.com/2.mp4',
            containerExtension: 'mp4',
            categoryId: '20',
          ),
        ];
        final categories = [
          const Category(id: '900000001', name: 'Trending Now'),
          const Category(id: '20', name: 'Action'),
        ];
        final repo = await _buildRepo(tester, items);

        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: categories),
        );
        await _settle(tester);

        await tester.tap(find.text('Trending Now'));
        await _settle(tester);

        expect(find.text('Big Buck Bunny'), findsOneWidget);
        expect(find.text('Sintel'), findsNothing);
      },
    );

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: testCategories,
          isConfigured: false,
        ),
      );
      await _settle(tester);

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('category bar and movie grid expose scrollbars', (
      tester,
    ) async {
      final manyCategories = List<Category>.generate(
        16,
        (index) => Category(id: '$index', name: 'Category $index'),
      );
      final repo = await _buildRepo(tester, testVodItems);

      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: manyCategories),
      );
      await _settle(tester);

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters movies case-insensitively', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'sintel');
      await _settle(tester);

      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Tears of Steel'), findsNothing);
    });

    testWidgets('replacing a query is debounced; old results stay until the '
        'pause', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);

      // First query applies immediately (no debounce-length empty flash).
      await tester.enterText(find.byType(TextField), 'sintel');
      await _settle(tester);
      expect(find.text('Sintel'), findsOneWidget);

      // Replacing it: the grid keeps showing the previous match for the
      // debounce window, then switches once typing settles.
      await tester.enterText(find.byType(TextField), 'steel');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await _settle(tester);
      expect(find.text('Sintel'), findsNothing);
      expect(find.text('Tears of Steel'), findsOneWidget);
    });

    testWidgets('inline search composes with category filter', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.text('Action'));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'steel');
      await _settle(tester);

      expect(find.text('Tears of Steel'), findsOneWidget);
      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Sintel'), findsNothing);
    });

    testWidgets('tapping movie triggers onVodSelect callback', (tester) async {
      VodItem? selectedItem;
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: testCategories,
          onVodSelect: (item) => selectedItem = item,
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Big Buck Bunny'));
      await _settle(tester);

      expect(selectedItem, isNotNull);
      expect(selectedItem!.id, 1);
    });

    testWidgets('shows rating when available', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(find.text('★ 4.5'), findsOneWidget);
    });

    testWidgets(
      'mobile layout shows a Filter button instead of category chips, '
      'and selecting a category filters the grid',
      (tester) async {
        final repo = await _buildRepo(tester, testVodItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: testCategories,
            useSidebarLayout: false,
          ),
        );
        await _settle(tester);

        expect(find.text('Filter'), findsOneWidget);
        expect(find.text('Action'), findsNothing);

        await tester.tap(find.text('Filter'));
        await _settle(tester);

        expect(find.text('Action'), findsOneWidget);
        await tester.tap(find.text('Action'));
        await _settle(tester);

        expect(find.text('Big Buck Bunny'), findsOneWidget);
        expect(find.text('Sintel'), findsNothing);
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
    this.onVodSelect,
  });

  final CatalogRepository catalogRepository;
  final List<Category> categories;
  final bool isConfigured;
  final bool useSidebarLayout;
  final void Function(VodItem)? onVodSelect;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        vodCategoriesProvider.overrideWith((_) => categories),
        catalogRepositoryProvider.overrideWith((_) => catalogRepository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: VodScreen(
          useSidebarLayout: useSidebarLayout,
          onVodSelect: onVodSelect ?? (_) {},
        ),
      ),
    );
  }
}
