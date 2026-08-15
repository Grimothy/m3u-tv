import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// #217 made the Live TV search field `activateOnSelect: true` — on TV it
/// renders as a non-editing button facade until activated, so there is no
/// `TextField` in the tree to type into. Activate first, then type.
Future<void> enterQuery(WidgetTester tester, String query) async {
  final field = find.byType(InlineMediaSearchField);
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(field);
    await tester.pumpAndSettle();
  }
  await tester.enterText(field, query);
}

void main() {
  group('LiveTvScreen', () {
    late List<Channel> testChannels;
    late List<Category> testCategories;

    setUp(() {
      testChannels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          epgChannelId: 'bbc.one',
          categoryId: '10',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
          epgChannelId: 'cnn',
          categoryId: '11',
        ),
        const Channel(
          id: 3,
          name: 'ESPN',
          streamUrl: 'http://example.com/3.m3u8',
          categoryId: '12',
        ),
      ];
      testCategories = [
        const Category(id: '10', name: 'News'),
        const Category(id: '11', name: 'Entertainment'),
        const Category(id: '12', name: 'Sports'),
      ];
    });

    testWidgets('renders channel list with names', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsOneWidget);
      expect(find.text('ESPN'), findsOneWidget);
    });

    testWidgets('renders All Channels and Favorites category tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Channels'), findsOneWidget);
      expect(find.text('★ Favorites'), findsOneWidget);
    });

    testWidgets('renders category tabs from service categories', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      // At least the first category should be visible
      expect(find.text('News'), findsAtLeast(1));
    });

    testWidgets('tapping category tab filters channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      // Tap on News category
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();

      // Only BBC One should be visible (categoryId: '10')
      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets(
      'mobile layout shows a Filter button instead of category chips, '
      'and selecting a category filters the channel list',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            useSidebarLayout: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filter'), findsOneWidget);
        expect(find.text('News'), findsNothing);

        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('News'));
        await tester.pumpAndSettle();

        expect(find.text('BBC One'), findsOneWidget);
      },
    );

    testWidgets('tapping All Channels shows all channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      // Tap a category first
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();

      // Tap All Channels
      await tester.tap(find.text('All Channels'));
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsOneWidget);
      expect(find.text('ESPN'), findsOneWidget);
    });

    testWidgets('shows empty state when no channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: const [], categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiveTvScreen), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          isLoading: true,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
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

    testWidgets('Favorites category shows only favorited channels', (
      tester,
    ) async {
      final favoritesService = FavoritesService();
      await favoritesService.add(1); // BBC One

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Favorites category
      await tester.tap(find.text('★ Favorites'));
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets('category bar exposes scrollbar and arrow affordances', (
      tester,
    ) async {
      final manyCategories = List<Category>.generate(
        16,
        (index) => Category(id: '$index', name: 'Category $index'),
      );

      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: manyCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters channels case-insensitively', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'cnn');
      await tester.pumpAndSettle();

      expect(find.text('CNN'), findsOneWidget);
      expect(find.text('BBC One'), findsNothing);
      expect(find.text('ESPN'), findsNothing);
    });

    testWidgets('inline search composes with favorites filter', (tester) async {
      final favoritesService = FavoritesService();
      await favoritesService.add(1);
      await favoritesService.add(2);

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('★ Favorites'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bbc');
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsNothing);
      expect(find.text('ESPN'), findsNothing);
    });

    testWidgets('tapping channel triggers onChannelSelect callback', (
      tester,
    ) async {
      Channel? selectedChannel;
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          onChannelSelect: (channel) => selectedChannel = channel,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BBC One'));
      await tester.pumpAndSettle();

      expect(selectedChannel, isNotNull);
      expect(selectedChannel!.id, 1);
    });

    testWidgets(
      'tapping a channel reports the current filtered list as context',
      (tester) async {
        final favoritesService = FavoritesService();
        await favoritesService.add(1);
        List<Channel>? reportedContext;

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            favoritesService: favoritesService,
            onChannelContextChanged: (channels) => reportedContext = channels,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('★ Favorites'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('BBC One'));
        await tester.pumpAndSettle();

        expect(reportedContext, isNotNull);
        expect(reportedContext!.map((c) => c.id), [1]);
      },
    );

    testWidgets(
      'shows EPG schedule action and calls back with program context',
      (
        tester,
      ) async {
        Channel? scheduledChannel;
        EpgProgram? scheduledProgram;
        final epgService =
            EpgService(clock: () => DateTime.utc(2026, 6, 25, 20))
              ..loadPrograms([
                EpgProgram(
                  channelId: 'bbc.one',
                  title: 'Late Show',
                  description: 'Fixture episode',
                  start: DateTime.utc(2026, 6, 25, 20),
                  end: DateTime.utc(2026, 6, 25, 21),
                ),
              ]);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            epgService: epgService,
            onScheduleProgram: (channel, program) {
              scheduledChannel = channel;
              scheduledProgram = program;
            },
          ),
        );
        await tester.pumpAndSettle();

        await tester.longPress(find.text('BBC One'));
        await tester.pumpAndSettle();

        expect(find.text('Record'), findsOneWidget);
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();

        expect(scheduledChannel?.id, 1);
        expect(scheduledProgram?.title, 'Late Show');
      },
    );

    testWidgets(
      'shows a recording indicator for a channel with an in-progress recording',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            dvrRecordings: const [
              DvrRecording(
                uuid: 'rec-1',
                title: 'Late Show',
                status: DvrRecordingStatus.recording,
                channelId: 1,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('recording-dot')), findsOneWidget);
      },
    );

    testWidgets(
      'bootstrap layout mapping loads list, grid and timeline correctly',
      (tester) async {
        for (final layout in LiveTvLayout.values) {
          final service = ViewSettingsService(memory: <String, Object?>{});
          await service.setLiveTvLayout(layout);

          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              categories: testCategories,
              viewSettingsService: service,
            ),
          );
          await tester.pumpAndSettle();

          switch (layout) {
            case LiveTvLayout.list:
              expect(
                find.byKey(const ValueKey('timeline-previous-day')),
                findsNothing,
              );
            case LiveTvLayout.grid:
              expect(find.byType(ScrollbarGridView), findsOneWidget);
            case LiveTvLayout.timeline:
              expect(
                find.byKey(const ValueKey('timeline-previous-day')),
                findsOneWidget,
              );
          }
        }
      },
    );

    testWidgets(
      'D-pad Right from the Channels column enters the program grid',
      (tester) async {
        final favoritesService = FavoritesService();
        await favoritesService.setLastViewMode('epgGrid');
        final now = DateTime.now();
        final program = EpgProgram(
          channelId: 'bbc.one',
          title: 'Evening News',
          description: 'x',
          start: now.subtract(const Duration(minutes: 15)),
          end: now.add(const Duration(minutes: 15)),
        );
        final epgService = EpgService()..loadPrograms([program]);
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            favoritesService: favoritesService,
            epgService: epgService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        final programBlockKey = ValueKey(
          'timeline-program-${program.channelId}-'
          '${program.start.toIso8601String()}',
        );
        final focusWidgets = tester
            .widgetList<Focus>(
              find.descendant(
                of: find.byKey(programBlockKey),
                matching: find.byType(Focus),
              ),
            )
            .where((focus) => focus.focusNode != null);
        expect(focusWidgets.any((focus) => focus.focusNode!.hasFocus), isTrue);
      },
    );

    testWidgets(
      'migrates legacy favorites-service layout into a fresh view settings service',
      (tester) async {
        final favoritesService = FavoritesService();
        await favoritesService.setLastViewMode('epgGrid');
        final service = ViewSettingsService(memory: <String, Object?>{});

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            favoritesService: favoritesService,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
        expect(await service.liveTvLayout(), LiveTvLayout.timeline);
      },
    );

    testWidgets(
      'replacement view settings service is picked up while screen is mounted',
      (tester) async {
        final firstService = ViewSettingsService(memory: <String, Object?>{});
        await firstService.setLiveTvLayout(LiveTvLayout.list);
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: firstService,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsNothing,
        );

        final secondService = ViewSettingsService(memory: <String, Object?>{});
        await secondService.setLiveTvLayout(LiveTvLayout.timeline);
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: secondService,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retained screen updates view mode when view settings change while mounted',
      (tester) async {
        final service = ViewSettingsService(memory: <String, Object?>{});
        await service.setLiveTvLayout(LiveTvLayout.list);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // List view renders channel rows; timeline day controls are absent.
        expect(find.text('BBC One'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsNothing,
        );

        await service.setLiveTvLayout(LiveTvLayout.timeline);
        await tester.pumpAndSettle();

        // Timeline view renders day controls instead of list rows.
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retained screen updates EPG start view when settings change while mounted',
      (tester) async {
        final service = ViewSettingsService(memory: <String, Object?>{});
        await service.setLiveTvLayout(LiveTvLayout.timeline);
        await service.setEpgStartView(EpgStartView.currentTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        final currentOffset = _timelineHorizontalOffset(tester);

        await service.setEpgStartView(EpgStartView.primeTime);
        await tester.pumpAndSettle();

        final primeOffset = _timelineHorizontalOffset(tester);
        expect(primeOffset, isNot(currentOffset));
      },
    );
    testWidgets('stale reload from replaced service is ignored', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'live_tv_view_settings',
        );
        addTearDown(() => dir.delete(recursive: true));

        final firstFile = File('${dir.path}/service_a.json');
        final secondFile = File('${dir.path}/service_b.json');

        final slowStoreA = _SlowPersistentJsonStore(
          file: firstFile,
          readDelay: const Duration(milliseconds: 100),
        );
        final serviceA = ViewSettingsService(store: slowStoreA);
        await serviceA.setLiveTvLayout(LiveTvLayout.list);
        await serviceA.setEpgStartView(EpgStartView.currentTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: serviceA,
          ),
        );
        await tester.pumpAndSettle();

        final storeB = PersistentJsonStore(file: secondFile);
        final serviceB = ViewSettingsService(store: storeB);
        await serviceB.setLiveTvLayout(LiveTvLayout.timeline);
        await serviceB.setEpgStartView(EpgStartView.primeTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: serviceB,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
        final primeOffset = _timelineHorizontalOffset(tester);

        // Let service A's delayed read finish after B has already won.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
        expect(_timelineHorizontalOffset(tester), primeOffset);
      });
    });

    testWidgets('stale reload after rapid view settings updates is ignored', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'live_tv_view_settings',
        );
        addTearDown(() => dir.delete(recursive: true));

        final slowStore = _SlowPersistentJsonStore(
          file: File('${dir.path}/store.json'),
        );
        final service = ViewSettingsService(store: slowStore);
        await service.setLiveTvLayout(LiveTvLayout.list);
        await service.setEpgStartView(EpgStartView.currentTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // Queue two rapid changes while reads are held; only the latest wins.
        slowStore.holdReads();
        final firstLayout = service.setLiveTvLayout(LiveTvLayout.grid);
        final secondLayout = service.setLiveTvLayout(LiveTvLayout.timeline);
        final firstEpg = service.setEpgStartView(EpgStartView.primeTime);
        await Future.wait([firstLayout, secondLayout, firstEpg]);
        slowStore.releaseReads();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
      });
    });
  });

  group('LiveTvScreen show search', () {
    late List<Channel> channels;
    late List<Category> categories;
    late DateTime futureTime;

    setUp(() {
      futureTime = DateTime.now().toUtc().add(const Duration(hours: 1));
      channels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          categoryId: '10',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
          categoryId: '11',
        ),
        const Channel(
          id: 3,
          name: 'ESPN',
          streamUrl: 'http://example.com/3.m3u8',
          categoryId: '12',
        ),
      ];
      categories = [
        const Category(id: '10', name: 'News'),
        const Category(id: '11', name: 'Entertainment'),
        const Category(id: '12', name: 'Sports'),
      ];
    });

    final railTitle = find.text('Upcoming');

    Future<List<EpgShow>> Function(String) staticResults(
      List<EpgShow> results,
    ) {
      return (query) async => results;
    }

    testWidgets('null onSearchShows renders no Upcoming rail', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: channels, categories: categories),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'bbc');
      await tester.pumpAndSettle();

      expect(railTitle, findsNothing);
    });

    testWidgets('Upcoming section groups airings by show and channel', (
      tester,
    ) async {
      // The Upcoming section renders one row per (show.normalizedTitle,
      // episode.channelId). Two airings of the same show on the same
      // channel collapse into one row with both airing times shown.
      // Use a unique show name that doesn't collide with any fixture
      // category name to keep the finder unambiguous.
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'worldreport',
              displayTitle: 'World Report',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'World News',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Breaking News',
                  startTime: futureTime.add(const Duration(hours: 1)),
                  endTime: futureTime.add(const Duration(hours: 2)),
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'ne');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(railTitle, findsOneWidget);
      // One row for World Report, not two — the show display title
      // renders once even though there are two episodes.
      expect(find.text('World Report'), findsOneWidget);
    });

    testWidgets(
      'channel-name filter narrows immediately while show search is in flight',
      (tester) async {
        final pending = Completer<List<EpgShow>>();
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (query) => pending.future,
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'cn');
        // Pump just past the 350ms debounce but stop before the in-flight
        // future ever completes — the channel list must already be filtered.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(find.text('BBC One'), findsNothing);
        expect(find.text('CNN'), findsOneWidget);
        expect(find.text('ESPN'), findsNothing);

        // Finish the search; the rail renders once the future resolves.
        pending.complete(const <EpgShow>[]);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('clearing the query drops the rail', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults(const [
            EpgShow(
              normalizedTitle: 'x',
              displayTitle: 'Hit',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: [],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'hi');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(railTitle, findsOneWidget);

      await enterQuery(tester, '');
      await tester.pumpAndSettle();
      expect(railTitle, findsNothing);

      // Under 2 chars must also hide the rail — the service's 2-char
      // short-circuit means no network call should be triggered and no
      // results should linger.
      await enterQuery(tester, 'h');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(railTitle, findsNothing);
    });

    testWidgets(
      'stale slow result does not overwrite a fresher fast result',
      (tester) async {
        final slow = Completer<List<EpgShow>>();
        final fast = Completer<List<EpgShow>>();
        var useSlow = true;
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (query) => useSlow ? slow.future : fast.future,
          ),
        );
        await tester.pumpAndSettle();

        // First query: slow.
        await enterQuery(tester, 'ab');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        useSlow = false;

        // Second query (overrides the first): fast. The generation counter
        // must cause the slow result to be ignored when it eventually lands.
        await enterQuery(tester, 'abc');
        await tester.pump(const Duration(milliseconds: 400));
        fast.complete([
          EpgShow(
            normalizedTitle: 'abc',
            displayTitle: 'Fresh',
            channelCount: 1,
            channels: [],
            episodeCount: 0,
            recentEpisodes: [
              EpgShowEpisode(
                channelId: 1,
                channelName: 'Channel',
                title: 'Fresh Episode',
                startTime: futureTime,
                endTime: futureTime.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Fresh'), findsOneWidget);

        // Now resolve the original slow Promise — it must NOT overwrite.
        slow.complete([
          EpgShow(
            normalizedTitle: 'ab',
            displayTitle: 'Stale',
            channelCount: 1,
            channels: [],
            episodeCount: 0,
            recentEpisodes: [
              EpgShowEpisode(
                channelId: 2,
                channelName: 'Channel',
                title: 'Stale Episode',
                startTime: futureTime,
                endTime: futureTime.add(const Duration(hours: 1)),
              ),
            ],
          ),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('Stale'), findsNothing);
        expect(find.text('Fresh'), findsOneWidget);
      },
    );

    testWidgets(
      'throwing onSearchShows renders search-failed, not no-matches',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (query) async => throw StateError('boom'),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'bbc');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Error state — distinct from "no matches".
        expect(find.text('Search failed'), findsOneWidget);
        expect(find.text('No shows match your search'), findsNothing);

        // Channel list still rendered.
        expect(find.text('BBC One'), findsOneWidget);
      },
    );

    testWidgets('blank episode title is filtered out', (tester) async {
      // Build two shows. "Bad Show" has only a blank-title episode, so it
      // contributes zero non-blank episodes to the rail and its row must
      // not render. "Good Show" has one valid episode and renders once.
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'good',
              displayTitle: 'Good Show',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Good Episode',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
            EpgShow(
              normalizedTitle: 'bad',
              displayTitle: 'Bad Show',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 2,
                  channelName: 'BBC Two',
                  title: '',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'good');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Good Show'), findsOneWidget);
      expect(find.text('Bad Show'), findsNothing);
    });

    testWidgets(
      'Upcoming section renders day-relative .toLocal() time on the row',
      (
        tester,
      ) async {
        // Derive the airing instant from now (UTC + 30 days) so the test
        // doesn't rot with the calendar. _formatUpcomingTime renders
        // 30-days-out airings as `MMMd jm` of the local instant, which
        // is what the trailing times Text now carries. Asserting the
        // formatted string proves both the .toLocal() conversion (the
        // formatted string depends on the device's wall clock) and that
        // the day-relative branch of the formatter is reached.
        final utc = DateTime.now().toUtc().add(const Duration(days: 30));
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [
              EpgShow(
                normalizedTitle: 'local-time',
                displayTitle: 'Local Time Check',
                channelCount: 1,
                channels: const [
                  EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                ],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Episode Slot',
                    startTime: utc,
                    endTime: utc.add(const Duration(hours: 1)),
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'loc');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.text('Local Time Check'), findsOneWidget);
        expect(find.text('BBC One'), findsOneWidget);
        expect(
          find.textContaining(
            DateFormat.MMMd('en').add_jm().format(utc.toLocal()),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'synchronously shows loading on first qualifying keystroke',
      (tester) async {
        final pending = Completer<List<EpgShow>>();
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (query) => pending.future,
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'bb');
        // Pump exactly one frame — the debounce hasn't fired yet (350ms),
        // but the rail should already render "Searching shows…" instead
        // of "No shows match your search". Without the R2.1 fix the rail
        // would flash the empty-matches label for a frame before flipping
        // to loading.
        await tester.pump();
        expect(find.text('Searching shows…'), findsOneWidget);
        expect(find.text('No shows match your search'), findsNothing);

        pending.complete(const <EpgShow>[]);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('Upcoming section drops past airings', (tester) async {
      // Two shows: Past Show has only past airings (filtered out entirely,
      // so its row never renders); Future Show has only future airings
      // (one row renders). The time filter is applied per-airing before
      // grouping, so a show with mixed past + future airings would still
      // render — covered by an explicit mixed-case test elsewhere.
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'past',
              displayTitle: 'Past Show',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'Channel',
                  title: 'Past Episode',
                  startTime: futureTime.subtract(const Duration(hours: 2)),
                  endTime: futureTime.subtract(const Duration(hours: 1)),
                ),
              ],
            ),
            EpgShow(
              normalizedTitle: 'future',
              displayTitle: 'Future Show',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 2,
                  channelName: 'Channel',
                  title: 'Future Episode',
                  startTime: futureTime.add(const Duration(hours: 1)),
                  endTime: futureTime.add(const Duration(hours: 2)),
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'sh');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Future Show'), findsOneWidget);
      expect(find.text('Past Show'), findsNothing);
    });

    testWidgets('Upcoming section caps at 4 groups', (tester) async {
      // Default test surface (800x600) only renders ~5-6 cards in the
      // horizontal ListView; size up so all rows are findable without
      // scrolling mid-test.
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // 6 distinct shows on the same channel — each is its own group
      // (different normalizedTitle). The cap at 4 must keep the first 4
      // ordered by earliest airing.
      final shows = <EpgShow>[];
      for (var i = 0; i < 6; i++) {
        shows.add(
          EpgShow(
            normalizedTitle: 'show-$i',
            displayTitle: 'Show $i',
            channelCount: 1,
            channels: const [],
            episodeCount: 0,
            recentEpisodes: [
              EpgShowEpisode(
                channelId: 1,
                channelName: 'Channel',
                title: 'Episode $i',
                startTime: futureTime.add(Duration(hours: i)),
                endTime: futureTime.add(Duration(hours: i + 1)),
              ),
            ],
          ),
        );
      }
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults(shows),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'show');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // First 4 (soonest) render; the last 2 do not.
      for (var i = 0; i < 4; i++) {
        expect(find.text('Show $i'), findsOneWidget);
      }
      expect(find.text('Show 4'), findsNothing);
      expect(find.text('Show 5'), findsNothing);
    });

    testWidgets('Movies & Series rail filters local VOD and Series by query', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          vodItems: const [
            VodItem(
              id: 1,
              name: 'The Matrix',
              streamUrl: 'http://example.com/m.m3u8',
              containerExtension: 'mp4',
            ),
            VodItem(
              id: 2,
              name: 'Inception',
              streamUrl: 'http://example.com/i.m3u8',
              containerExtension: 'mp4',
            ),
          ],
          seriesList: const [Series(id: 10, name: 'Breaking Bad')],
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'mat');
      // No debounce on the local filter — should be visible on the same
      // frame the keystroke lands, without waiting for the 350ms debounce
      // the network-driven Upcoming rail uses.
      await tester.pump();
      expect(find.text('Movies & Series'), findsOneWidget);
      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('Inception'), findsNothing);
      expect(find.text('Breaking Bad'), findsNothing);
    });

    testWidgets(
      'Movies & Series rail updates same frame as channel list',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            vodItems: const [
              VodItem(
                id: 1,
                name: 'Action Movie',
                streamUrl: 'http://example.com/a.m3u8',
                containerExtension: 'mp4',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'act');
        // Both the channel list and the Movies & Series rail update on
        // the same frame — neither has a debounce. The Movies & Series
        // rail filters vodItems by `name.contains(query)` synchronously
        // alongside the channel-name filter narrowing the channels list.
        await tester.pump();
        expect(find.text('Action Movie'), findsOneWidget);
        // No channel name contains "act" — channel list is empty.
        expect(find.text('BBC One'), findsNothing);
        expect(find.text('CNN'), findsNothing);
        expect(find.text('ESPN'), findsNothing);
      },
    );

    testWidgets('Movies & Series rail suppressed when no local matches', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          vodItems: const [
            VodItem(
              id: 1,
              name: 'Inception',
              streamUrl: 'http://example.com/i.m3u8',
              containerExtension: 'mp4',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'xy');
      await tester.pump();
      // No matches in VOD/Series for "xy" — rail should not render.
      expect(find.text('Movies & Series'), findsNothing);
    });

    testWidgets(
      'tapping Upcoming row invokes onShowSelect with parent show',
      (tester) async {
        EpgShow? tapped;
        final parent = EpgShow(
          normalizedTitle: 'worldreport',
          displayTitle: 'World Report',
          channelCount: 1,
          channels: [],
          episodeCount: 0,
          recentEpisodes: [
            EpgShowEpisode(
              channelId: 1,
              channelName: 'BBC One',
              title: 'News Episode',
              startTime: futureTime,
              endTime: futureTime.add(const Duration(hours: 1)),
            ),
          ],
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [parent],
            onShowSelect: (show) => tapped = show,
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'ne');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(find.text('World Report'));
        await tester.pumpAndSettle();

        // The tap routes the *parent* EpgShow, not the episode — same
        // shape AppShell._openShow expects.
        expect(tapped, isNotNull);
        expect(tapped!.normalizedTitle, 'worldreport');
      },
    );

    testWidgets('tapping VOD item invokes onVodSelect', (tester) async {
      VodItem? tapped;
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          vodItems: const [
            VodItem(
              id: 1,
              name: 'The Matrix',
              streamUrl: 'http://example.com/m.m3u8',
              containerExtension: 'mp4',
            ),
          ],
          onVodSelect: (item) => tapped = item,
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'mat');
      await tester.pump();
      expect(find.text('The Matrix'), findsOneWidget);

      await tester.tap(find.text('The Matrix'));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.id, 1);
    });

    testWidgets('tapping Series item invokes onSeriesSelect', (tester) async {
      Series? tapped;
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          seriesList: const [Series(id: 10, name: 'Breaking Bad')],
          onSeriesSelect: (series) => tapped = series,
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'bre');
      await tester.pump();
      expect(find.text('Breaking Bad'), findsOneWidget);

      await tester.tap(find.text('Breaking Bad'));
      await tester.pumpAndSettle();

      expect(tapped, isNotNull);
      expect(tapped!.id, 10);
    });

    testWidgets('null tap callbacks are no-ops', (tester) async {
      // The M&S rail sits below the 600px viewport fold once the search
      // field, category bar, and Upcoming rail are stacked above it. Bump
      // the viewport so both target widgets are in the render tree.
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final parent = EpgShow(
        normalizedTitle: 'worldreport',
        displayTitle: 'World Report',
        channelCount: 1,
        channels: [],
        episodeCount: 0,
        recentEpisodes: [
          EpgShowEpisode(
            channelId: 1,
            channelName: 'Channel',
            title: 'News Episode',
            startTime: futureTime,
            endTime: futureTime.add(const Duration(hours: 1)),
          ),
        ],
      );
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [parent],
          vodItems: const [
            VodItem(
              id: 1,
              name: 'Money Movie',
              streamUrl: 'http://example.com/m.m3u8',
              containerExtension: 'mp4',
            ),
          ],
          // No onShowSelect, onVodSelect, onSeriesSelect callbacks.
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'ne');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Tapping each rail must not throw — null callbacks are no-ops so
      // unwired LiveTvScreen instances still render and respond.
      // Upcoming row uses the show's displayTitle (the row's title
      // text); tapping anywhere inside the DpadInkWell row triggers the
      // onTap, so target the show title to avoid hitting any other widget.
      await tester.tap(find.text('World Report'));
      await tester.pumpAndSettle();
      // Target the VOD title ('Money Movie'), not the card's subtitle
      // which is rendered from the `homeMovie` ARB key ("Movie") and
      // would match the wrong Text widget.
      await tester.tap(find.text('Money Movie'));
      await tester.pumpAndSettle();
    });

    testWidgets('Upcoming row receives the station logo URL', (
      tester,
    ) async {
      final channelsWithLogos = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          categoryId: '10',
          logoUrl: 'http://example.com/bbc.png',
        ),
      ];
      await tester.pumpWidget(
        _TestApp(
          channels: channelsWithLogos,
          categories: categories,
          onSearchShows: (_) async => [
            EpgShow(
              normalizedTitle: 'local-time',
              displayTitle: 'Local Time Check',
              channelCount: 1,
              channels: const [
                EpgShowChannel(channelId: 1, channelName: 'BBC One'),
              ],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Tonight Show',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'loca');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // The row's leading ResilientMediaImage carries the channel's
      // logoUrl. Walk the widget tree from the show title up to the
      // DpadInkWell row, then find the ResilientMediaImage descendant.
      final row = find.ancestor(
        of: find.text('Local Time Check'),
        matching: find.byType(DpadInkWell),
      );
      final image = tester.widget<ResilientMediaImage>(
        find.descendant(of: row, matching: find.byType(ResilientMediaImage)),
      );
      expect(image.imageUrl, 'http://example.com/bbc.png');
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('Upcoming keeps rows for unmatched channels', (tester) async {
      // Unlike On Now which drops unmatched-channelId entries (no channel
      // to tune), Upcoming must NOT drop them — the row opens show
      // detail, not a channel, so an unmatched channel is still a valid
      // row. Contrast with the On Now `omits airingNow entries whose
      // channelId matches no Channel` test. The row's logo image falls
      // back to the channel-name icon since logoUrl is null.
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [
            EpgShow(
              normalizedTitle: 'orphan',
              displayTitle: 'Orphan Show',
              channelCount: 1,
              channels: const [
                EpgShowChannel(channelId: 999, channelName: 'Ghost Channel'),
              ],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 999,
                  channelName: 'Ghost Channel',
                  title: 'Lost Episode',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'orphan');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Orphan Show'), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Orphan Show'),
        matching: find.byType(DpadInkWell),
      );
      final image = tester.widget<ResilientMediaImage>(
        find.descendant(of: row, matching: find.byType(ResilientMediaImage)),
      );
      expect(image.imageUrl, isNull);
    });

    testWidgets(
      'Upcoming emphasis: airing later today renders time-only label',
      (tester) async {
        final now = DateTime.now();
        final todayLaterLocal = DateTime(now.year, now.month, now.day, 23);
        final caseALocal = todayLaterLocal.isAfter(now)
            ? todayLaterLocal
            : DateTime(
                now.year,
                now.month,
                now.day,
                now.hour,
              ).add(const Duration(hours: 1));
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [
              EpgShow(
                normalizedTitle: 'day-relative',
                displayTitle: 'Day Relative',
                channelCount: 1,
                channels: const [
                  EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                ],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Today Episode',
                    startTime: caseALocal.toUtc(),
                    endTime: caseALocal.toUtc().add(const Duration(hours: 1)),
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await enterQuery(tester, 'day');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(
          find.text(DateFormat.jm('en').format(caseALocal)),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Upcoming emphasis: airing tomorrow renders Tomorrow-prefix label',
      (tester) async {
        final now = DateTime.now();
        final tomorrowLocal = DateTime(
          now.year,
          now.month,
          now.day + 1,
          14,
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [
              EpgShow(
                normalizedTitle: 'day-relative',
                displayTitle: 'Day Relative',
                channelCount: 1,
                channels: const [
                  EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                ],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Tomorrow Episode',
                    startTime: tomorrowLocal.toUtc(),
                    endTime: tomorrowLocal.toUtc().add(
                      const Duration(hours: 1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await enterQuery(tester, 'day');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(
          find.text(
            l10n.liveTvAiringTomorrow(
              DateFormat.jm('en').format(tomorrowLocal),
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Upcoming emphasis: airing in 3 days renders date-prefixed label',
      (tester) async {
        final now = DateTime.now();
        final threeDaysLocal = DateTime(
          now.year,
          now.month,
          now.day + 3,
          14,
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [
              EpgShow(
                normalizedTitle: 'day-relative',
                displayTitle: 'Day Relative',
                channelCount: 1,
                channels: const [
                  EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                ],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Days Out Episode',
                    startTime: threeDaysLocal.toUtc(),
                    endTime: threeDaysLocal.toUtc().add(
                      const Duration(hours: 1),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();
        await enterQuery(tester, 'day');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            DateFormat.MMMd('en').add_jm().format(threeDaysLocal),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Upcoming keeps unmatched-channel entries (guard vs On Now)', (
      tester,
    ) async {
      // Mirrors the Upcoming row test above but framed as the explicit
      // guard against copying On Now's `if (channel == null) continue;`
      // into _buildUpcomingSection — that would silently delete airings
      // from the section.
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [
            EpgShow(
              normalizedTitle: 'orphan-2',
              displayTitle: 'Orphan Show 2',
              channelCount: 1,
              channels: const [
                EpgShowChannel(channelId: 9999, channelName: 'Phantom'),
              ],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 9999,
                  channelName: 'Phantom',
                  title: 'Phantom Episode',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'orphan');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Orphan Show 2'), findsOneWidget);
    });

    testWidgets(
      'Movies & Series rail does not render an emphasis label',
      (tester) async {
        // Existing rails set no emphasisLabel. Adding the field to the
        // shared MediaPreviewItem must not surface an emphasis row on
        // rails that don't opt in.
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            vodItems: const [
              VodItem(
                id: 1,
                name: 'Test Movie',
                streamUrl: 'http://example.com/m.m3u8',
                containerExtension: 'mp4',
              ),
            ],
            onSearchShows: (_) async => const [],
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'test');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        final card = find.ancestor(
          of: find.text('Test Movie'),
          matching: find.byType(MediaPreviewCard),
        );
        final cardTexts = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .where((t) => t.data != null && t.data!.isNotEmpty)
            .toList();
        // Title + subtitle (rating-derived) — both small text, neither at
        // titleMedium fontSize. If an emphasis label slipped in, its
        // fontSize would be titleMedium (>= 14 logical px) — assert no
        // such row exists.
        for (final t in cardTexts) {
          expect(
            t.style?.fontSize != null && t.style!.fontSize! >= 14,
            isFalse,
            reason:
                'No emphasis row expected on Movies & Series rail, '
                'but found text "${t.data}" at fontSize ${t.style?.fontSize}.',
          );
        }
      },
    );

    // ── R5 tests ─────────────────────────────────────────────────────────
    // Round 5: vertical grouped Upcoming + bounded scrolling results area
    // (the R5.1 overflow fix). Tests below cover the grouping invariants
    // (collapse duplicates, multi-network split, ordering, 4-group cap,
    // unmatched-channel tolerance) and the overflow regression itself.

    testWidgets('search results area does not overflow on 1080p @ DPR 1.6', (
      tester,
    ) async {
      // Reproduces the R5.1 bug: without the bounded `ConstrainedBox +
      // SingleChildScrollView` wrapper, all three sections plus chrome
      // (~944 px) overflow the ~675 logical px available on a 1080p panel
      // at `_TvZoom._scale = 1.6`, throwing "A RenderFlex overflowed by
      // 297 pixels on the bottom". With the fix, the results area scrolls
      // internally and the channel list stays usable.
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.6;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [
            EpgShow(
              normalizedTitle: 'on-now-show',
              displayTitle: 'On Now Show',
              channelCount: 1,
              channels: const [
                EpgShowChannel(channelId: 1, channelName: 'BBC One'),
              ],
              episodeCount: 1,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Upcoming Slot',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
              airingNow: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'On Now Slot',
                  startTime: DateTime.now().toUtc().subtract(
                    const Duration(minutes: 30),
                  ),
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
          ],
          vodItems: const [
            VodItem(
              id: 1,
              name: 'Test Movie',
              streamUrl: 'http://example.com/m.m3u8',
              containerExtension: 'mp4',
            ),
          ],
          seriesList: const [Series(id: 10, name: 'Test Series')],
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'te');
      await tester.pumpAndSettle();

      // The R5.1 bug surfaces as a RenderFlex overflowed exception. The
      // fix wraps the three sections in a bounded scrolling region so
      // nothing throws. Take any exception that built up during the
      // pump cycle and assert it is null.
      expect(tester.takeException(), isNull);
    });

    testWidgets('groups 40 same-channel airings into one row with +37 more', (
      tester,
    ) async {
      // 40 future airings of the same show on the same channel must
      // render exactly ONE row — not 40 cards, not 12. The row shows the
      // first 3 airing times plus a "+37 more" affordance that points
      // at the show detail screen (which already lists every airing).
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final episodes = <EpgShowEpisode>[];
      for (var i = 0; i < 40; i++) {
        episodes.add(
          EpgShowEpisode(
            channelId: 1,
            channelName: 'BBC One',
            title: 'Episode $i',
            startTime: futureTime.add(Duration(hours: i)),
            endTime: futureTime.add(Duration(hours: i + 1)),
          ),
        );
      }
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'repeatshow',
              displayTitle: 'Repeat Show',
              channelCount: 1,
              channels: const [],
              episodeCount: 0,
              recentEpisodes: episodes,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'rep');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Show display title renders once.
      expect(find.text('Repeat Show'), findsOneWidget);
      // The "+37 more" affordance wraps the 40-airing count after the
      // first 3 are shown. It is joined into the row's trailing times
      // Text with " · " separators, so the affordance is reached via
      // textContaining rather than exact text.
      expect(find.textContaining('+37 more'), findsOneWidget);
      // Episode titles are deliberately not rendered — only the show
      // title (once) and the airing times (3) + the more-affordance.
      expect(find.text('Episode 0'), findsNothing);
      expect(find.text('Episode 39'), findsNothing);
    });

    testWidgets('same show on two channels renders two rows', (tester) async {
      // Same show (normalizedTitle) on two different channels → two rows,
      // each with its own logo and channel name. Groups are keyed by
      // (normalizedTitle, channelId), not normalizedTitle alone.
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'crossnetshow',
              displayTitle: 'Cross-Net Show',
              channelCount: 2,
              channels: const [
                EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                EpgShowChannel(channelId: 2, channelName: 'CNN'),
              ],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Episode BBC',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
                EpgShowEpisode(
                  channelId: 2,
                  channelName: 'CNN',
                  title: 'Episode CNN',
                  startTime: futureTime.add(const Duration(hours: 1)),
                  endTime: futureTime.add(const Duration(hours: 2)),
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'cro');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Show title renders once per row (so twice total).
      expect(find.text('Cross-Net Show'), findsNWidgets(2));
      // Both channel names appear.
      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsOneWidget);
    });

    testWidgets('groups order by earliest airing across shows', (tester) async {
      // Two shows, each with one airing. The later-airing show is
      // returned first by the search; the rail must reorder so the
      // sooner-airing show renders first.
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'late',
              displayTitle: 'Late Show',
              channelCount: 1,
              channels: const [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Late Episode',
                  startTime: futureTime.add(const Duration(hours: 4)),
                  endTime: futureTime.add(const Duration(hours: 5)),
                ),
              ],
            ),
            EpgShow(
              normalizedTitle: 'soon',
              displayTitle: 'Soon Show',
              channelCount: 1,
              channels: const [],
              episodeCount: 0,
              recentEpisodes: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Soon Episode',
                  startTime: futureTime,
                  endTime: futureTime.add(const Duration(hours: 1)),
                ),
              ],
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'show');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      final soonY = tester.getTopLeft(find.text('Soon Show')).dy;
      final lateY = tester.getTopLeft(find.text('Late Show')).dy;
      expect(soonY, lessThan(lateY));
    });

    testWidgets(
      'On Now and Movies & Series still render as MediaPreviewSection',
      (
        tester,
      ) async {
        // R5.2 only restructures the Upcoming rail. On Now and Movies &
        // Series must remain MediaPreviewSection instances — the shared
        // rail widget, not the new vertical Column. Pinning this guards
        // against a future "let's also rewrite On Now" drift.
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [
              EpgShow(
                normalizedTitle: 'on-now-show',
                displayTitle: 'On Now Show',
                channelCount: 1,
                channels: const [
                  EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                ],
                episodeCount: 1,
                recentEpisodes: const [],
                airingNow: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'On Now Slot',
                    startTime: DateTime.now().toUtc().subtract(
                      const Duration(minutes: 30),
                    ),
                    endTime: DateTime.now().toUtc().add(
                      const Duration(hours: 1),
                    ),
                  ),
                ],
              ),
            ],
            vodItems: const [
              VodItem(
                id: 1,
                name: 'Test Movie',
                streamUrl: 'http://example.com/m.m3u8',
                containerExtension: 'mp4',
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'te');
        await tester.pumpAndSettle();

        // Two MediaPreviewSections: one for On Now, one for Movies & Series.
        // The Upcoming section is a Column, not a MediaPreviewSection.
        expect(find.byType(MediaPreviewSection), findsNWidgets(2));
      },
    );
  });

  group('LiveTvScreen On Now rail', () {
    late List<Channel> channels;
    late List<Category> categories;
    late DateTime endTime;

    setUp(() {
      // Use a relative, future endTime so the rail's case stays valid
      // regardless of when the test is run (round-2 lesson: hardcoded
      // dates rot once wall-clock passes them).
      endTime = DateTime.now().toUtc().add(const Duration(hours: 2));
      channels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          categoryId: '10',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
          categoryId: '11',
        ),
      ];
      categories = [
        const Category(id: '10', name: 'News'),
        const Category(id: '11', name: 'Entertainment'),
      ];
    });

    final onNowRailTitle = find.text('On Now');

    EpgShow showWithAiringNow({
      required String showKey,
      required List<EpgShowEpisode> airingNow,
      String? displayTitle,
    }) {
      return EpgShow(
        normalizedTitle: showKey,
        displayTitle: displayTitle ?? showKey,
        channelCount: airingNow.length,
        channels: [],
        episodeCount: 0,
        recentEpisodes: const [],
        airingNow: airingNow,
      );
    }

    Future<void> enterQueryAndSettle(WidgetTester tester, String query) async {
      await enterQuery(tester, query);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    }

    testWidgets('renders one card per airingNow entry', (tester) async {
      // The On Now rail sits below the search field, category bar, and
      // Upcoming rail — bump the viewport so all rendered cards are in
      // the tree (round-2 lesson: find.text misses off-screen widgets).
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Show displayTitle is the card title (R6: fixed the wrong-field
      // bug). Use a name that doesn't collide with the 'News' category
      // tab in this group's setUp.
      final show = showWithAiringNow(
        showKey: 'tonightnews',
        displayTitle: 'Tonight News',
        airingNow: [
          EpgShowEpisode(
            channelId: 1,
            channelName: 'BBC One',
            title: 'World News',
            subtitle: 'Tonight',
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        ],
      );
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [show],
        ),
      );
      await tester.pumpAndSettle();

      await enterQueryAndSettle(tester, 'ton');

      expect(onNowRailTitle, findsOneWidget);
      // Card title is the SHOW name (R6).
      expect(find.text('Tonight News'), findsOneWidget);
      // Subtitle joins the episode subtitle with the channel.
      expect(find.text('Tonight · BBC One'), findsOneWidget);
      // Episode title no longer renders as a card title.
      expect(find.text('World News'), findsNothing);
    });

    testWidgets(
      'subtitle falls back to channel name when episode has no subtitle',
      (
        tester,
      ) async {
        // Renamed from 'falls back to episode title when subtitle is
        // absent': the show name is now the card title, and an episode
        // without a subtitle produces a channel-only subtitle row.
        tester.view.physicalSize = const Size(4000, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final show = showWithAiringNow(
          showKey: 'tonightnews',
          displayTitle: 'Tonight News',
          airingNow: [
            EpgShowEpisode(
              channelId: 1,
              channelName: 'BBC One',
              title: 'World News',
              // subtitle: null — falls through to channel-only.
              startTime: DateTime.now().toUtc().subtract(
                const Duration(minutes: 30),
              ),
              endTime: endTime,
            ),
          ],
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [show],
          ),
        );
        await tester.pumpAndSettle();

        await enterQueryAndSettle(tester, 'ton');

        // Card title is the SHOW name.
        expect(find.text('Tonight News'), findsOneWidget);
        // Subtitle is the channel alone — no stray " · " separator.
        expect(find.text('BBC One'), findsOneWidget);
        expect(find.text('World News'), findsNothing);
      },
    );

    testWidgets(
      'renders nothing when airing_now is absent from the payload',
      (tester) async {
        // Older m3u-editor (pre-#1414) does not include `airing_now` in
        // the response. `fromXtream` defaults the field to `const []`,
        // so the rail stays suppressed instead of crashing.
        const show = EpgShow(
          normalizedTitle: 'news',
          displayTitle: 'News',
          channelCount: 1,
          channels: [],
          episodeCount: 0,
          recentEpisodes: [],
          // airingNow intentionally omitted — defaults to const [].
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [show],
          ),
        );
        await tester.pumpAndSettle();

        await enterQueryAndSettle(tester, 'ne');

        expect(onNowRailTitle, findsNothing);
      },
    );

    testWidgets(
      'omits airingNow entries whose channelId matches no Channel',
      (tester) async {
        tester.view.physicalSize = const Size(4000, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // channelId 999 doesn't appear in `channels` above — the
        // episode has nowhere to tune to. The rail should skip it
        // rather than render a card that can't do anything. Use a
        // show displayTitle that doesn't collide with the 'News'
        // category tab.
        final show = showWithAiringNow(
          showKey: 'ghostshow',
          displayTitle: 'Ghost Show',
          airingNow: [
            EpgShowEpisode(
              channelId: 1,
              channelName: 'BBC One',
              title: 'On BBC',
              startTime: DateTime.now().toUtc().subtract(
                const Duration(minutes: 30),
              ),
              endTime: endTime,
            ),
            EpgShowEpisode(
              channelId: 999,
              channelName: 'Ghost Channel',
              title: 'On Ghost',
              startTime: DateTime.now().toUtc().subtract(
                const Duration(minutes: 30),
              ),
              endTime: endTime,
            ),
          ],
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [show],
          ),
        );
        await tester.pumpAndSettle();

        await enterQueryAndSettle(tester, 'ghost');

        // Card title is the SHOW name (one card rendered for the
        // matched channel); the dropped episode has no card at all.
        expect(find.text('Ghost Show'), findsOneWidget);
        // Channel 'BBC One' survives as the subtitle; the dropped
        // 'Ghost Channel' rendering never reaches the tree.
        expect(find.text('BBC One'), findsOneWidget);
        expect(find.text('Ghost Channel'), findsNothing);
      },
    );

    testWidgets('tap tunes the matching channel and updates context', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Channel? selected;
      List<Channel>? contextList;
      // Two airings on different channels. The query deliberately
      // matches neither channel name ("Grace and Frankie" doesn't
      // appear in "BBC One" or "CNN"), so the rail can only render
      // both cards if the lookup uses the full channel list — the
      // exact regression guard for the R3 review bug.
      final show = showWithAiringNow(
        showKey: 'Grace and Frankie',
        airingNow: [
          EpgShowEpisode(
            channelId: 1,
            channelName: 'BBC One',
            title: 'Episode on BBC',
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
          EpgShowEpisode(
            channelId: 2,
            channelName: 'CNN',
            title: 'Live Coverage',
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        ],
      );
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [show],
          onChannelSelect: (channel) => selected = channel,
          onChannelContextChanged: (list) => contextList = list,
        ),
      );
      await tester.pumpAndSettle();

      await enterQueryAndSettle(tester, 'Grace and Frankie');

      // R6: card title is the SHOW name, not the episode name. Both
      // cards render the same title (same show on two channels);
      // tap the second one — find by channel subtitle. The fixture
      // episodes have no `subtitle` field set, so the subtitle is
      // just the channel name (no `Live Coverage · CNN` joined form).
      final cnnCard = find.ancestor(
        of: find.text('CNN'),
        matching: find.byType(DpadInkWell),
      );
      await tester.tap(cnnCard);
      await tester.pumpAndSettle();

      expect(selected, isNotNull);
      expect(selected!.id, 2);
      expect(selected!.name, 'CNN');
      // Context list must be the rail's distinct channels (BBC One
      // and CNN, in flatten order), not the search-filtered channel
      // list. The user tapped from the On Now rail, so skip-previous/
      // next should step between other things airing now.
      expect(contextList, isNotNull);
      expect(contextList!.map((c) => c.id), equals([1, 2]));
    });

    testWidgets('On Now renders above Upcoming when both have content', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Upcoming startTime must be strictly in the future (the R5.2 time
      // filter is `startTime.isAfter(now)`). endTime is set in setUp as
      // `now + 2h`; back off 1h so the upcoming airing lands an hour
      // from now, comfortably future across any test-render latency.
      final startTime = endTime.subtract(const Duration(hours: 1));
      final show = EpgShow(
        normalizedTitle: 'news',
        displayTitle: 'News',
        channelCount: 1,
        channels: [],
        episodeCount: 1,
        recentEpisodes: [
          EpgShowEpisode(
            channelId: 1,
            channelName: 'BBC One',
            title: 'Upcoming Slot',
            startTime: startTime,
            endTime: endTime,
          ),
        ],
        airingNow: [
          EpgShowEpisode(
            channelId: 1,
            channelName: 'BBC One',
            title: 'On Now Slot',
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        ],
      );
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [show],
        ),
      );
      await tester.pumpAndSettle();

      await enterQueryAndSettle(tester, 'ne');

      // Both section titles render…
      expect(find.text('On Now'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);
      // …and "On Now" appears higher in the column than "Upcoming".
      final onNowY = tester.getTopLeft(find.text('On Now')).dy;
      final upcomingY = tester.getTopLeft(find.text('Upcoming')).dy;
      expect(onNowY, lessThan(upcomingY));
    });

    testWidgets('section order is stable across a rebuild', (tester) async {
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // R6: card title is the SHOW name, not the episode name — three
      // airings of the same show would now share a title (and the
      // x/y test couldn't disambiguate them). Restructure as three
      // distinct shows with one airing each; the invariant under test
      // (server order preserved across rebuild) is unchanged. Mixed
      // channelIds exercise the lookup against the full channel list
      // (the R3 review fix), and the query deliberately matches
      // neither channel name so neither card can be dropped by the
      // search-name filter.
      EpgShow mkShow(String key, int channelId, String channelName) {
        return EpgShow(
          normalizedTitle: key,
          displayTitle: key,
          channelCount: 1,
          channels: const [],
          episodeCount: 0,
          recentEpisodes: const [],
          airingNow: [
            EpgShowEpisode(
              channelId: channelId,
              channelName: channelName,
              title: '$key episode',
              startTime: DateTime.now().toUtc().subtract(
                const Duration(minutes: 30),
              ),
              endTime: endTime,
            ),
          ],
        );
      }

      final shows = [
        mkShow('Grace and Frankie', 1, 'BBC One'),
        mkShow('King of Queens', 2, 'CNN'),
        mkShow('Downright Delicious', 1, 'BBC One'),
      ];
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => shows,
        ),
      );
      await tester.pumpAndSettle();

      // "ne" matches all three shows (each contains 'n').
      await enterQueryAndSettle(tester, 'ne');

      final orderBefore = [
        tester.getTopLeft(find.text('Grace and Frankie')).dy,
        tester.getTopLeft(find.text('King of Queens')).dy,
        tester.getTopLeft(find.text('Downright Delicious')).dy,
      ];
      // Force one extra frame to exercise the rebuild path.
      await tester.pump();
      final orderAfter = [
        tester.getTopLeft(find.text('Grace and Frankie')).dy,
        tester.getTopLeft(find.text('King of Queens')).dy,
        tester.getTopLeft(find.text('Downright Delicious')).dy,
      ];
      expect(orderAfter, equals(orderBefore));
    });

    testWidgets(
      'renders On Now cards even when query matches no channel name',
      (tester) async {
        tester.view.physicalSize = const Size(4000, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // Regression guard for the R3 review bug: the lookup must use
        // the full channel list, not the search-filtered one. With
        // query='Grace and Frankie' the filtered channel list is empty
        // (neither 'BBC One' nor 'CNN' contains 'grace' or 'frankie')
        // — if the rail uses that for lookups, both cards drop and the
        // rail suppresses. The post-fix rail must render both cards.
        final show = showWithAiringNow(
          showKey: 'Grace and Frankie',
          airingNow: [
            EpgShowEpisode(
              channelId: 1,
              channelName: 'BBC One',
              title: 'Grace on BBC',
              startTime: DateTime.now().toUtc().subtract(
                const Duration(minutes: 30),
              ),
              endTime: endTime,
            ),
            EpgShowEpisode(
              channelId: 2,
              channelName: 'CNN',
              title: 'Grace on CNN',
              startTime: DateTime.now().toUtc().subtract(
                const Duration(minutes: 30),
              ),
              endTime: endTime,
            ),
          ],
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [show],
          ),
        );
        await tester.pumpAndSettle();

        await enterQueryAndSettle(tester, 'Grace and Frankie');

        expect(find.text('On Now'), findsOneWidget);
        // R6: card title is the SHOW name (one widget per card), not
        // the episode name (which no longer renders). The search field
        // also renders the query 'Grace and Frankie' as a Text widget,
        // so we scope to descendants of MediaPreviewCard to count only
        // the two cards.
        final showTitleCount = tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(MediaPreviewCard),
                matching: find.text('Grace and Frankie'),
              ),
            )
            .length;
        expect(showTitleCount, 2);
        // Each card's subtitle carries its channel.
        expect(find.text('BBC One'), findsOneWidget);
        expect(find.text('CNN'), findsOneWidget);
        // The episode titles never render as Text widgets — they're
        // now in the title slot's old position and that slot is the
        // show's displayTitle.
        expect(find.text('Grace on BBC'), findsNothing);
        expect(find.text('Grace on CNN'), findsNothing);
      },
    );

    testWidgets('On Now card receives the station logo URL', (tester) async {
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final channelsWithLogos = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          categoryId: '10',
          logoUrl: 'http://example.com/bbc.png',
        ),
      ];
      await tester.pumpWidget(
        _TestApp(
          channels: channelsWithLogos,
          categories: categories,
          onSearchShows: (_) async => [
            showWithAiringNow(
              showKey: 'news',
              airingNow: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Now Playing',
                  startTime: DateTime.now().toUtc().subtract(
                    const Duration(minutes: 30),
                  ),
                  endTime: endTime,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterQueryAndSettle(tester, 'news');

      // R6: card title is the show's displayTitle (lowercase 'news' from
      // the helper), not the episode's title ('Now Playing'). The card
      // ancestor is found by the show title.
      final card = find.ancestor(
        of: find.text('news'),
        matching: find.byType(MediaPreviewCard),
      );
      final image = tester.widget<ResilientMediaImage>(
        find.descendant(of: card, matching: find.byType(ResilientMediaImage)),
      );
      expect(image.imageUrl, 'http://example.com/bbc.png');
      expect(image.fit, BoxFit.contain);
    });

    testWidgets('On Now emphasis label is rendered at title-scale weight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [
            showWithAiringNow(
              showKey: 'news',
              airingNow: [
                EpgShowEpisode(
                  channelId: 1,
                  channelName: 'BBC One',
                  title: 'Now Playing',
                  startTime: DateTime.now().toUtc().subtract(
                    const Duration(minutes: 30),
                  ),
                  endTime: endTime,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await enterQueryAndSettle(tester, 'news');

      // Find the card containing the show title (R6). Card title is
      // `displayTitle: 'news'` from the helper, not the episode's
      // title ('Now Playing') which no longer renders.
      final card = find.ancestor(
        of: find.text('news'),
        matching: find.byType(MediaPreviewCard),
      );
      // The emphasis label renders as a Text wrapped in FittedBox, with
      // the channel name as the subtitle Text. Both are descendants of
      // the card. Distinguish by fontSize: emphasis > subtitle.
      final cardTexts = tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .where((t) => t.data != null && t.data!.isNotEmpty)
          .toList();
      final emphasisText = cardTexts.firstWhere(
        (t) =>
            t.data == 'Until ${DateFormat.jm('en').format(endTime.toLocal())}',
      );
      final subtitleText = cardTexts.firstWhere((t) => t.data == 'BBC One');

      expect(
        emphasisText.style?.fontWeight,
        FontWeight.w700,
        reason:
            'Emphasis label must be at title-scale weight to be '
            'readable from the couch.',
      );
      expect(
        emphasisText.style!.fontSize! > subtitleText.style!.fontSize!,
        isTrue,
        reason:
            'Emphasis fontSize must exceed subtitle fontSize so the '
            'airing time is the most prominent datum on the card.',
      );
    });

    // ── R6: On Now card title is the SHOW name, subtitle carries the
    // episode name + channel with graceful degradation. Regression guard
    // for the wrong-field bug CJ found in manual testing — see
    // AGENT_HANDOFF.md entries at the end of round 5. The previous code
    // rendered `entry.episode.displayTitle` (a getter `subtitle ?? title`),
    // so a "Midsomer Murders" search whose only airing had `subtitle:
    // "A Picture of Innocence"` rendered the card titled "A Picture of
    // Innocence" — wrong field, looked like drift. None of the existing
    // On Now tests caught it because every fixture left `subtitle: null`.

    Future<void> setupOnNowCard(
      WidgetTester tester,
      EpgShowEpisode episode,
    ) async {
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Construct EpgShow directly so we control displayTitle verbatim.
      // The group's `showWithAiringNow` helper hard-codes `displayTitle:
      // showKey` which would give us 'midsomer-murders' instead of the
      // human-readable 'Midsomer Murders' the spec asks for.
      final show = EpgShow(
        normalizedTitle: 'midsomer-murders',
        displayTitle: 'Midsomer Murders',
        channelCount: 1,
        channels: const [],
        episodeCount: 0,
        recentEpisodes: const [],
        airingNow: [episode],
      );
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: (_) async => [show],
        ),
      );
      await tester.pumpAndSettle();
      await enterQueryAndSettle(tester, 'mid');
    }

    testWidgets(
      'On Now card title is show name + subtitle joins ep · channel',
      (
        tester,
      ) async {
        // Both present — title is the SHOW name, subtitle is
        // "{episode subtitle} · {channel name}". The previous code rendered
        // the episode name as the title (a getter returning subtitle ?? title),
        // so this test fails against the buggy impl and passes against the
        // fixed one — the mutation check relies on this asymmetry.
        await setupOnNowCard(
          tester,
          EpgShowEpisode(
            channelId: 1,
            channelName: 'US: OVATION',
            title: 'Midsomer Murders',
            subtitle: 'A Picture of Innocence',
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        );

        // Title is the show name (displayTitle on EpgShow).
        expect(find.text('Midsomer Murders'), findsOneWidget);
        // Episode name appears in the subtitle, joined with the channel.
        expect(
          find.text('A Picture of Innocence · US: OVATION'),
          findsOneWidget,
        );
        // No stray separator or duplicate rendering of either token.
        expect(find.text('A Picture of Innocence'), findsNothing);
      },
    );

    testWidgets(
      'On Now card subtitle falls back to channel name when episode has no subtitle',
      (tester) async {
        await setupOnNowCard(
          tester,
          EpgShowEpisode(
            channelId: 1,
            channelName: 'US: OVATION',
            title: 'Midsomer Murders',
            // subtitle: null — falls through to channel-only.
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        );

        // Title is the show name (R4 unchanged).
        expect(find.text('Midsomer Murders'), findsOneWidget);
        // Subtitle is the channel alone — no stray " · " separator.
        expect(find.text('US: OVATION'), findsOneWidget);
        expect(find.textContaining(' · '), findsNothing);
      },
    );

    testWidgets(
      'On Now card subtitle falls back to episode subtitle when channel name is null',
      (tester) async {
        await setupOnNowCard(
          tester,
          EpgShowEpisode(
            channelId: 1,
            title: 'Midsomer Murders',
            subtitle: 'A Picture of Innocence',
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        );

        // Title is the show name.
        expect(find.text('Midsomer Murders'), findsOneWidget);
        // Subtitle is the episode subtitle alone — no trailing " · ".
        expect(find.text('A Picture of Innocence'), findsOneWidget);
        expect(find.textContaining(' · '), findsNothing);
      },
    );

    testWidgets(
      'On Now card subtitle is null when both episode subtitle and channel name are absent',
      (tester) async {
        await setupOnNowCard(
          tester,
          EpgShowEpisode(
            channelId: 1,
            title: 'Midsomer Murders',
            // subtitle: null and channelName: null — no subtitle row.
            startTime: DateTime.now().toUtc().subtract(
              const Duration(minutes: 30),
            ),
            endTime: endTime,
          ),
        );

        // Title is the show name.
        expect(find.text('Midsomer Murders'), findsOneWidget);
        // No subtitle Text widget renders — confirmed by walking the
        // card's Text descendants and asserting none has empty data
        // (the phantom-row regression: an empty-string subtitle would
        // render an 11px empty Text below the title).
        final card = find.ancestor(
          of: find.text('Midsomer Murders'),
          matching: find.byType(MediaPreviewCard),
        );
        final cardTexts = tester
            .widgetList<Text>(
              find.descendant(of: card, matching: find.byType(Text)),
            )
            .where((t) => t.data != null && t.data!.isEmpty)
            .toList();
        expect(cardTexts, isEmpty);
      },
    );
  });
}

class _SlowPersistentJsonStore extends PersistentJsonStore {
  _SlowPersistentJsonStore({
    required super.file,
    this.readDelay = Duration.zero,
  });

  final Duration readDelay;
  final _pending = <Completer<void>>[];
  var _hold = false;

  void holdReads() => _hold = true;

  void releaseReads() {
    _hold = false;
    for (final completer in _pending) {
      completer.complete();
    }
    _pending.clear();
  }

  @override
  Future<Object?> read(String key) async {
    if (_hold) {
      final completer = Completer<void>();
      _pending.add(completer);
      await completer.future;
    }
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return super.read(key);
  }
}

Scrollable _timelineHorizontalOffsetRow(WidgetTester tester) {
  return tester.widget<Scrollable>(
    find
        .descendant(
          of: find.byType(TimelineEpgView),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          ),
        )
        .first,
  );
}

double _timelineHorizontalOffset(WidgetTester tester) {
  return _timelineHorizontalOffsetRow(tester).controller!.offset;
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.channels,
    required this.categories,
    this.isLoading = false,
    this.isConfigured = true,
    this.favoritesService,
    this.viewSettingsService,
    this.epgService,
    this.onChannelSelect,
    this.onChannelContextChanged,
    this.onScheduleProgram,
    this.dvrRecordings = const [],
    this.useSidebarLayout = true,
    this.onSearchShows,
    this.onShowSelect,
    this.onVodSelect,
    this.onSeriesSelect,
    this.vodItems = const [],
    this.seriesList = const [],
  });

  final List<Channel> channels;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final FavoritesService? favoritesService;
  final ViewSettingsService? viewSettingsService;
  final EpgService? epgService;
  final void Function(Channel)? onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(Channel, EpgProgram)? onScheduleProgram;
  final List<DvrRecording> dvrRecordings;
  final bool useSidebarLayout;
  final Future<List<EpgShow>> Function(String query)? onSearchShows;
  final void Function(EpgShow)? onShowSelect;
  final void Function(VodItem)? onVodSelect;
  final void Function(Series)? onSeriesSelect;
  final List<VodItem> vodItems;
  final List<Series> seriesList;

  @override
  Widget build(BuildContext context) {
    final epg = epgService ?? EpgService();
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        isLoadingContentProvider.overrideWith((_) => isLoading),
        liveChannelsProvider.overrideWith((_) => channels),
        liveCategoriesProvider.overrideWith((_) => categories),
        vodItemsProvider.overrideWith((_) => vodItems),
        seriesListProvider.overrideWith((_) => seriesList),
        epgServiceProvider.overrideWith((_) => epg),
        dvrRecordingsProvider.overrideWith((_) => dvrRecordings),
        recordingChannelIdsProvider.overrideWith(
          (_) => dvrRecordings
              .where((recording) => recording.isInProgress)
              .map((recording) => recording.channelId)
              .whereType<int>()
              .toSet(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData.dark(useMaterial3: true),
        home: LiveTvScreen(
          favoritesService: favoritesService ?? FavoritesService(),
          viewSettingsService: viewSettingsService,
          onChannelSelect: onChannelSelect ?? (_) {},
          useSidebarLayout: useSidebarLayout,
          onChannelContextChanged: onChannelContextChanged,
          onScheduleProgram: onScheduleProgram,
          onSearchShows: onSearchShows,
          onShowSelect: onShowSelect,
          onVodSelect: onVodSelect,
          onSeriesSelect: onSeriesSelect,
        ),
      ),
    );
  }
}
