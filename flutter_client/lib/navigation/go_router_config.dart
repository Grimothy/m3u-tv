import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:m3u_tv/app/app_shell.dart' show AppShell, DeviceType;
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/app/system_ui_policy.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_detail_screen.dart';
import 'package:m3u_tv/features/aiostreams/aiostreams_search_screen.dart';
import 'package:m3u_tv/features/continue_watching/continue_watching_screen.dart';
import 'package:m3u_tv/features/requests/request_detail_screen.dart';
import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/features/vod/vod_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/navigation/content_actions.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart'
    show kCatalogKindSeries, kCatalogKindVod;
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_background.dart';

Widget _withGradient(Widget screen) => DecoratedBox(
  decoration: kAppGradientBg,
  child: SafeArea(bottom: false, child: screen),
);

CustomTransitionPage<void> _slidePage(Widget screen) =>
    CustomTransitionPage<void>(
      child: ColoredBox(
        color: const Color(0xFF09090b),
        child: SafeArea(bottom: false, child: screen),
      ),
      transitionsBuilder: (context, animation, _, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
        child: child,
      ),
    );

/// Opens a Related-row tap's own detail screen, reusing the same
/// `onVodSelect`/`onSeriesSelect` callbacks every other VOD/series entry
/// point (grids, Continue Watching) already navigates through - a related
/// item is guaranteed to already exist in the user's library, so it only
/// needs resolving to the matching [VodItem]/[Series] by id. The lookup hits
/// the SQLite catalog (fire-and-forget from the tap) rather than an
/// in-memory list, so this is the one entry point in the app with a brief
/// (sub-frame, same-process) gap between tap and navigation.
Future<void> _openRelated(ContentActions actions, RelatedItem related) async {
  final targetId = int.tryParse(related.id);
  if (targetId == null) {
    debugPrint('_openRelated: unparseable id "${related.id}"');
    return;
  }
  if (related.isSeries) {
    final series = await actions.appState.catalogRepository
        .activeItemById<Series>(kind: kCatalogKindSeries, id: targetId);
    if (series != null) {
      actions.onSeriesSelect(series);
    } else {
      debugPrint('_openRelated: series #$targetId not found in library');
    }
  } else {
    final vod = await actions.appState.catalogRepository
        .activeItemById<VodItem>(kind: kCatalogKindVod, id: targetId);
    if (vod != null) {
      actions.onVodSelect(vod);
    } else {
      debugPrint('_openRelated: VOD #$targetId not found in library');
    }
  }
}

/// Resolves a VOD detail route's `:vodId` against the SQLite catalog when the
/// caller didn't already have the [VodItem] in hand (`state.extra` null - a
/// deep link, push notification, or restored route). Every in-app tap already
/// carries the object via `extra` and never hits this path.
class _AsyncVodDetails extends StatelessWidget {
  const _AsyncVodDetails({required this.vodId, required this.actions});

  final int vodId;
  final ContentActions actions;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<VodItem?>(
      future: actions.appState.catalogRepository.activeItemById<VodItem>(
        kind: kCatalogKindVod,
        id: vodId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final item = snapshot.data;
        if (item == null) {
          return Scaffold(
            body: SafeArea(
              bottom: false,
              child: Center(child: Text('VOD #$vodId not found')),
            ),
          );
        }
        return ListenableBuilder(
          listenable: actions.appState,
          builder: (ctx, _) => VodDetailsScreen(
            item: item,
            xtreamService: actions.xtreamService,
            onPlay: actions.onOpenPlayer,
            progressList: actions.progressList,
            onSidebarActivate: actions.onSidebarActivate,
            onOpenRelated: (related) => _openRelated(actions, related),
          ),
        );
      },
    );
  }
}

/// Series counterpart to [_AsyncVodDetails].
class _AsyncSeriesDetails extends StatelessWidget {
  const _AsyncSeriesDetails({required this.seriesId, required this.actions});

  final int seriesId;
  final ContentActions actions;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Series?>(
      future: actions.appState.catalogRepository.activeItemById<Series>(
        kind: kCatalogKindSeries,
        id: seriesId,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final series = snapshot.data;
        if (series == null) {
          return Scaffold(
            body: SafeArea(
              bottom: false,
              child: Center(child: Text('Series #$seriesId not found')),
            ),
          );
        }
        return ListenableBuilder(
          listenable: actions.appState,
          builder: (ctx, _) => SeriesDetailsScreen(
            seriesId: series.id,
            seriesName: series.name,
            coverUrl: series.coverUrl,
            xtreamService: actions.xtreamService,
            viewerId: actions.appState.activeViewer?.ulid,
            onPlay: actions.onOpenPlayer,
            progressList: actions.progressList,
            onMarkEpisodeWatched: actions.onMarkEpisodeWatched,
            onSidebarActivate: actions.onSidebarActivate,
            onOpenRelated: (related) => _openRelated(actions, related),
          ),
        );
      },
    );
  }
}

GoRouter createGoRouter({
  required AppStateController appState,
  required bool nativeTelevisionHint,
  PlaybackOrchestrator Function()? playbackOrchestratorBuilder,
  Widget Function(PlayerArgs args)? playerRouteBuilder,
  SystemUiPolicy? systemUiPolicy,
  DeviceType? deviceTypeOverride,
  String initialLocation = RouteNames.home,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          final deviceType =
              deviceTypeOverride ??
              resolveDeviceType(
                context,
                nativeTelevisionHint: nativeTelevisionHint,
              );
          return AppShell(
            navigationShell: navigationShell,
            deviceType: deviceType,
            appState: appState,
            playbackOrchestratorBuilder: playbackOrchestratorBuilder,
            playerRouteBuilder: playerRouteBuilder,
            systemUiPolicy: systemUiPolicy,
          );
        },
        branches: [
          // Branch 0: Home
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.home,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.home)),
                ),
                routes: [
                  GoRoute(
                    path: 'continue-watching',
                    pageBuilder: (context, state) {
                      final actions = ContentActions.of(context);
                      return _slidePage(
                        ListenableBuilder(
                          listenable: actions.appState,
                          builder: (ctx, _) => ContinueWatchingScreen(
                            progressList: actions.appState.progressList,
                            catalogRepository:
                                actions.appState.catalogRepository,
                            onProgressSelect: actions.onProgressSelect,
                            onSidebarActivate: actions.onSidebarActivate,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 1: Search
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.search,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.search)),
                ),
              ),
            ],
          ),
          // Branch 2: Live TV
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.liveTv,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.liveTv)),
                ),
              ),
            ],
          ),
          // Branch 3: VOD with nested details
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.vod,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.vod)),
                ),
                routes: [
                  GoRoute(
                    path: 'details/:vodId',
                    pageBuilder: (context, state) {
                      final vodId = int.parse(state.pathParameters['vodId']!);
                      final actions = ContentActions.of(context);
                      final item = state.extra as VodItem?;
                      if (item != null) {
                        return _slidePage(
                          ListenableBuilder(
                            listenable: actions.appState,
                            builder: (ctx, _) => VodDetailsScreen(
                              item: item,
                              xtreamService: actions.xtreamService,
                              onPlay: actions.onOpenPlayer,
                              progressList: actions.progressList,
                              onSidebarActivate: actions.onSidebarActivate,
                              onOpenRelated: (related) =>
                                  _openRelated(actions, related),
                            ),
                          ),
                        );
                      }
                      // No object in hand (deep link / push notification /
                      // restored route) - resolve it from the catalog.
                      return _slidePage(
                        _AsyncVodDetails(vodId: vodId, actions: actions),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 4: Series with nested details
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.series,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.series)),
                ),
                routes: [
                  GoRoute(
                    path: 'details/:seriesId',
                    pageBuilder: (context, state) {
                      final seriesId = int.parse(
                        state.pathParameters['seriesId']!,
                      );
                      final actions = ContentActions.of(context);
                      final series = state.extra as Series?;
                      if (series != null) {
                        return _slidePage(
                          ListenableBuilder(
                            listenable: actions.appState,
                            builder: (ctx, _) => SeriesDetailsScreen(
                              seriesId: series.id,
                              seriesName: series.name,
                              coverUrl: series.coverUrl,
                              xtreamService: actions.xtreamService,
                              viewerId: actions.appState.activeViewer?.ulid,
                              onPlay: actions.onOpenPlayer,
                              progressList: actions.progressList,
                              onMarkEpisodeWatched:
                                  actions.onMarkEpisodeWatched,
                              onSidebarActivate: actions.onSidebarActivate,
                              onOpenRelated: (related) =>
                                  _openRelated(actions, related),
                            ),
                          ),
                        );
                      }
                      // No object in hand (deep link / push notification /
                      // restored route) - resolve it from the catalog.
                      return _slidePage(
                        _AsyncSeriesDetails(
                          seriesId: seriesId,
                          actions: actions,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 5: AIOStreams with nested item detail
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.aiostreams,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.aiostreams),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'search',
                    pageBuilder: (context, state) {
                      final actions = ContentActions.of(context);
                      return _slidePage(
                        AIOStreamsSearchScreen(
                          integrations: actions.appState.aiostreamsIntegrations,
                          apiService: actions.appState.aiostreamsApiService,
                          favoritesService:
                              actions.appState.aioFavoritesService,
                          onItemSelect: (item, integrationId) {
                            context.go(
                              RouteNames.aiostreamsDetailsFor(
                                integrationId,
                                item.type,
                                item.id,
                              ),
                              extra: item,
                            );
                          },
                          onSidebarActivate: actions.onSidebarActivate,
                        ),
                      );
                    },
                  ),
                  GoRoute(
                    path: 'details/:integrationId/:type/:id',
                    pageBuilder: (context, state) {
                      final integrationId = int.parse(
                        state.pathParameters['integrationId']!,
                      );
                      final type = state.pathParameters['type']!;
                      final id = state.pathParameters['id']!;
                      final actions = ContentActions.of(context);
                      final item =
                          state.extra as AIOStreamsItem? ??
                          AIOStreamsItem(id: id, type: type, name: id);
                      return _slidePage(
                        AIOStreamsDetailScreen(
                          item: item,
                          integrationId: integrationId,
                          apiService: actions.appState.aiostreamsApiService,
                          appStateController: actions.appState,
                          onPlay: actions.onOpenPlayer,
                          onSidebarActivate: actions.onSidebarActivate,
                          // push (not go) - a related item lands on the same
                          // route pattern this screen is already on, and go()
                          // to a same-pattern location updates this State in
                          // place rather than creating a fresh one, so the
                          // (late final) meta fetch never re-runs and the
                          // pushed-detail sidebar-depth tracking every other
                          // detail screen relies on never fires. push() gives
                          // it a real, freshly-initialized instance and a
                          // normal one-level pop on back, matching how
                          // VOD/Series related items navigate.
                          onOpenRelated: (related) => context.push(
                            RouteNames.aiostreamsDetailsFor(
                              integrationId,
                              related.type,
                              related.id,
                            ),
                            extra: AIOStreamsItem(
                              id: related.id,
                              type: related.type,
                              name: related.title,
                              poster: related.posterUrl,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 6: DVR with nested show-detail (Shows is now a tab on
          // DvrRecordingsScreen, not a top-level sidebar destination, so
          // /dvr/shows/:normalizedTitle lives under this branch).
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.dvr,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(_tabScreen(context, RouteNames.dvr)),
                ),
                routes: [
                  GoRoute(
                    path: RouteNames.showsDetailsPath,
                    pageBuilder: (context, state) {
                      final normalizedTitle =
                          state.pathParameters['normalizedTitle'] ?? '';
                      final extra = state.extra;
                      final show = extra is EpgShow ? extra : null;
                      if (show == null) {
                        return NoTransitionPage(
                          child: Scaffold(
                            body: SafeArea(
                              bottom: false,
                              child: Center(
                                child: Text(
                                  AppLocalizations.of(context).showNotFound(
                                    normalizedTitle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                      final actions = ContentActions.of(context);
                      return _slidePage(
                        ShowDetailScreen(
                          show: show,
                          onRecordSeries: actions.onRecordSeries,
                          onDeleteSeriesRule: actions.onDeleteSeriesRule,
                          onScheduleEpisode: actions.onScheduleEpisode,
                          onScheduleEpisodes: actions.onScheduleEpisodes,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 7: Requests with nested result details
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.requests,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.requests),
                  ),
                ),
                routes: [
                  GoRoute(
                    path: 'details/:integrationId/:type/:externalId',
                    pageBuilder: (context, state) {
                      final result = state.extra! as ContentRequestSearchResult;
                      final actions = ContentActions.of(context);
                      final requestOwner = actions.appState.mediaRequestOwner;
                      return _slidePage(
                        ListenableBuilder(
                          listenable: actions.appState,
                          builder: (ctx, _) => RequestDetailScreen(
                            result: result,
                            isOwnerCurrent:
                                actions.appState.mediaRequestOwner ==
                                requestOwner,
                            onSubmit:
                                ({
                                  required type,
                                  required integrationId,
                                  required externalId,
                                  seasons,
                                }) => actions.appState.submitContentRequest(
                                  type: type,
                                  integrationId: integrationId,
                                  externalId: externalId,
                                  seasons: seasons,
                                  requestOwner: requestOwner,
                                ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          // Branch 8: Notifications
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.notifications,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.notifications),
                  ),
                ),
              ),
            ],
          ),
          // Branch 9: Settings
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: RouteNames.settings,
                pageBuilder: (context, state) => NoTransitionPage(
                  child: _withGradient(
                    _tabScreen(context, RouteNames.settings),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Widget _tabScreen(BuildContext context, String routeName) =>
    ContentActions.of(context).buildTabScreen(routeName);
