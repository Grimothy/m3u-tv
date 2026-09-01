import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';

const _wideScreenSize = Size(1280, 800);
const _narrowScreenSize = Size(420, 800);

class _StubSeriesService extends XtreamService {
  _StubSeriesService(this.info);

  final SeriesInfo info;

  @override
  Future<SeriesInfo> getSeriesInfo(int seriesId, {int? seasonNumber}) async =>
      info;
}

SeriesInfo _info({List<CastMember>? richCast, String? plot}) => SeriesInfo(
  series: Series(
    id: 1,
    name: 'Test Series',
    plot: plot ?? 'A test series plot for testing.',
    tmdbId: 1396,
    richCast: richCast,
  ),
  seasons: [const Season(number: 1, name: 'Season 1', episodeCount: 8)],
  episodesBySeason: const {
    1: <Episode>[],
  },
);

Widget _harness({required SeriesInfo info, Size screenSize = _wideScreenSize}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Dpad(
      child: MediaQuery(
        data: MediaQueryData(size: screenSize),
        child: Scaffold(
          body: SeriesDetailsScreen(
            seriesId: 1,
            seriesName: 'Test Series',
            xtreamService: _StubSeriesService(info),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('SeriesDetailsScreen — rich cast', () {
    testWidgets(
      'wide layout: renders CastMemberRow when series.richCast is populated',
      (tester) async {
        tester.view.physicalSize = _wideScreenSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _harness(
            info: _info(
              richCast: const [
                CastMember(
                  id: 1,
                  name: 'Bryan Cranston',
                  character: 'Walter White',
                ),
                CastMember(
                  id: 2,
                  name: 'Aaron Paul',
                  character: 'Jesse Pinkman',
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsOneWidget);
        expect(find.text('Bryan Cranston'), findsOneWidget);
        expect(find.text('Walter White'), findsOneWidget);
        expect(find.text('Aaron Paul'), findsOneWidget);
        expect(find.text('Jesse Pinkman'), findsOneWidget);
      },
    );

    testWidgets(
      'wide layout: hides CastMemberRow when series.richCast is null',
      (tester) async {
        tester.view.physicalSize = _wideScreenSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(_harness(info: _info()));
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsNothing);
        // Plot still renders.
        expect(
          find.text('A test series plot for testing.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'narrow layout: renders CastMemberRow when series.richCast is populated',
      (tester) async {
        tester.view.physicalSize = _narrowScreenSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _harness(
            info: _info(
              richCast: const [
                CastMember(name: 'Bryan Cranston', character: 'Walter White'),
              ],
            ),
            screenSize: _narrowScreenSize,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsOneWidget);
        expect(find.text('Bryan Cranston'), findsOneWidget);
      },
    );

    testWidgets(
      'narrow layout: hides CastMemberRow when series.richCast is null',
      (tester) async {
        tester.view.physicalSize = _narrowScreenSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          _harness(info: _info(), screenSize: _narrowScreenSize),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsNothing);
      },
    );
  });
}
