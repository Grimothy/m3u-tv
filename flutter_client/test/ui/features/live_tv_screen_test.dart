import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
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

    testWidgets('Upcoming rail renders one card per future airing', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'news',
              displayTitle: 'News',
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
                  channelName: 'CNN',
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
      expect(find.text('World News'), findsOneWidget);
      expect(find.text('Breaking News'), findsOneWidget);
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
        expect(find.text('Fresh Episode'), findsOneWidget);

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
        expect(find.text('Stale Episode'), findsNothing);
        expect(find.text('Fresh Episode'), findsOneWidget);
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

      expect(find.text('Good Episode'), findsOneWidget);
      // The blank-title episode must not render an empty card; the rail
      // contains exactly one item, found as a MediaPreviewSection ancestor.
      final rail = find.ancestor(
        of: find.text('Good Episode'),
        matching: find.byType(MediaPreviewSection),
      );
      expect(rail, findsOneWidget);
    });

    testWidgets(
      'Upcoming rail subtitle uses episode startTime via .toLocal()',
      (
        tester,
      ) async {
        // Derive the airing instant from now (UTC + 30 days) so the test
        // doesn't rot with the calendar. The .toLocal() invocation is
        // exercised by the widget building without throwing on a UTC
        // input; we also check that the subtitle Text widget carries the
        // channel name (the formatted local time is asserted via the
        // surrounding text rather than a hardcoded wall-clock string).
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

        expect(find.text('Episode Slot'), findsOneWidget);
        expect(find.textContaining('BBC One'), findsOneWidget);
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

    testWidgets('Upcoming rail drops past airings', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults([
            EpgShow(
              normalizedTitle: 'show',
              displayTitle: 'Show',
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
                EpgShowEpisode(
                  channelId: 1,
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

      expect(find.text('Future Episode'), findsOneWidget);
      expect(find.text('Past Episode'), findsNothing);
    });

    testWidgets('Upcoming rail caps at 12 airings soonest first', (
      tester,
    ) async {
      // Default test surface (800x600) only renders ~5-6 cards in the
      // horizontal ListView; size up so all 12 are findable without
      // scrolling the rail mid-test.
      tester.view.physicalSize = const Size(4000, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final episodes = <EpgShowEpisode>[];
      for (var i = 0; i < 15; i++) {
        episodes.add(
          EpgShowEpisode(
            channelId: 1,
            channelName: 'Channel',
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
              normalizedTitle: 'show',
              displayTitle: 'Show',
              channelCount: 1,
              channels: [],
              episodeCount: 0,
              recentEpisodes: episodes,
            ),
          ]),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'sh');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // Episodes 0-11 are visible (soonest first), 12-14 are not.
      for (var i = 0; i < 12; i++) {
        expect(find.text('Episode $i'), findsOneWidget);
      }
      for (var i = 12; i < 15; i++) {
        expect(find.text('Episode $i'), findsNothing);
      }
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
      'tapping Upcoming card invokes onShowSelect with parent show',
      (tester) async {
        EpgShow? tapped;
        final parent = EpgShow(
          normalizedTitle: 'news',
          displayTitle: 'News',
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

        await tester.tap(find.text('News Episode'));
        await tester.pumpAndSettle();

        // The tap routes the *parent* EpgShow, not the episode — same
        // shape AppShell._openShow expects.
        expect(tapped, isNotNull);
        expect(tapped!.normalizedTitle, 'news');
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
        normalizedTitle: 'news',
        displayTitle: 'News',
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
      await tester.tap(find.text('News Episode'));
      await tester.pumpAndSettle();
      // Target the VOD title ('Money Movie'), not the card's subtitle
      // which is rendered from the `homeMovie` ARB key ("Movie") and
      // would match the wrong Text widget.
      await tester.tap(find.text('Money Movie'));
      await tester.pumpAndSettle();
    });
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
