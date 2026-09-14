import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/favorites/favorites_screen.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';

void main() {
  group('FavoritesScreen', () {
    late List<Channel> testChannels;
    late List<VodItem> testVodItems;
    late List<Series> testSeriesList;
    late CatalogDatabase db;
    late CatalogRepository repo;

    setUp(() async {
      db = CatalogDatabase.memory();
      repo = CatalogRepository(db);
      testChannels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
        ),
      ];
      testVodItems = [
        const VodItem(
          id: 10,
          name: 'The Matrix',
          streamUrl: 'http://example.com/10.mp4',
          containerExtension: 'mp4',
        ),
      ];
      testSeriesList = [
        const Series(id: 20, name: 'Breaking Bad'),
      ];
      await repo.replaceItems(
        sourceKey: CatalogRepository.activeSource,
        kind: kCatalogKindVod,
        items: testVodItems,
      );
      await repo.replaceItems(
        sourceKey: CatalogRepository.activeSource,
        kind: kCatalogKindSeries,
        items: testSeriesList,
      );
    });

    tearDown(() => db.close());

    testWidgets('renders favorites screen with tabs', (tester) async {
      final channelService = FavoritesService();
      await channelService.add(1);

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          catalogRepository: repo,
          channelFavoritesService: channelService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live TV'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
    });

    testWidgets('shows favorited live channels in Live TV tab', (tester) async {
      final channelService = FavoritesService();
      await channelService.add(1); // BBC One

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          catalogRepository: repo,
          channelFavoritesService: channelService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets('shows favorited VOD items in Movies tab', (tester) async {
      final vodService = FavoritesService(namespace: 'vod');
      await vodService.add(10);

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          catalogRepository: repo,
          vodFavoritesService: vodService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();

      expect(find.text('The Matrix'), findsOneWidget);
    });

    testWidgets('shows favorited series in Series tab', (tester) async {
      final seriesService = FavoritesService(namespace: 'series');
      await seriesService.add(20);

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          catalogRepository: repo,
          seriesFavoritesService: seriesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('shows empty state when no favorites', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          catalogRepository: repo,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No favorites yet'), findsOneWidget);
    });

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          catalogRepository: repo,
          isConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.channels,
    required this.catalogRepository,
    this.channelFavoritesService,
    this.vodFavoritesService,
    this.seriesFavoritesService,
    this.isConfigured = true,
  });

  final List<Channel> channels;
  final CatalogRepository catalogRepository;
  final FavoritesService? channelFavoritesService;
  final FavoritesService? vodFavoritesService;
  final FavoritesService? seriesFavoritesService;
  final bool isConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: FavoritesScreen(
        channels: channels,
        catalogRepository: catalogRepository,
        isConfigured: isConfigured,
        channelFavoritesService: channelFavoritesService ?? FavoritesService(),
        vodFavoritesService:
            vodFavoritesService ?? FavoritesService(namespace: 'vod'),
        seriesFavoritesService:
            seriesFavoritesService ?? FavoritesService(namespace: 'series'),
        onChannelSelect: (_) {},
        onVodSelect: (_) {},
        onSeriesSelect: (_) {},
      ),
    );
  }
}
