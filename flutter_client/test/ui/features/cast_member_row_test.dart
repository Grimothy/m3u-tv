import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

CastMember _m({
  required String name,
  String? character,
  String? photo,
  int? id,
}) => CastMember(name: name, character: character, photo: photo, id: id);

Widget _harness({
  List<CastMember>? members,
  String? semanticLabel,
  bool compact = false,
  VoidCallback? onShowAll,
  String? allCastSemanticLabel,
}) {
  return MaterialApp(
    home: Scaffold(
      body: CastMemberRow(
        members: members,
        semanticLabel: semanticLabel,
        compact: compact,
        onShowAll: onShowAll,
        allCastSemanticLabel: allCastSemanticLabel,
      ),
    ),
  );
}

void main() {
  group('CastMemberRow', () {
    testWidgets('renders nothing for null members', (tester) async {
      await tester.pumpWidget(_harness());
      expect(find.byType(CastMemberRow), findsOneWidget);
      // No _CastMemberCard inside.
      expect(find.text('Leonardo DiCaprio'), findsNothing);
    });

    testWidgets('renders nothing for empty list', (tester) async {
      await tester.pumpWidget(_harness(members: const <CastMember>[]));
      expect(find.byType(CastMemberRow), findsOneWidget);
      expect(find.text('Leonardo DiCaprio'), findsNothing);
    });

    testWidgets('renders one card per member', (tester) async {
      await tester.pumpWidget(
        _harness(
          members: [
            _m(name: 'Leonardo DiCaprio', character: 'Cobb'),
            _m(name: 'Joseph Gordon-Levitt', character: 'Arthur'),
            _m(name: 'Tom Hardy', character: 'Eames'),
          ],
        ),
      );

      expect(find.text('Leonardo DiCaprio'), findsOneWidget);
      expect(find.text('Joseph Gordon-Levitt'), findsOneWidget);
      expect(find.text('Tom Hardy'), findsOneWidget);
      expect(find.text('Cobb'), findsOneWidget);
      expect(find.text('Arthur'), findsOneWidget);
      expect(find.text('Eames'), findsOneWidget);
    });

    testWidgets('omits character text when null', (tester) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Solo Actor')],
        ),
      );
      expect(find.text('Solo Actor'), findsOneWidget);
      // No empty character row.
      expect(find.text(''), findsNothing);
    });

    testWidgets('omits character text when empty string', (tester) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Solo Actor', character: '')],
        ),
      );
      expect(find.text('Solo Actor'), findsOneWidget);
    });

    testWidgets('caps rendered cards at 15', (tester) async {
      // 20 members → only 15 cards render.
      final members = [
        for (var i = 0; i < 20; i++) _m(name: 'Actor $i', character: 'Role $i'),
      ];
      await tester.pumpWidget(_harness(members: members));

      // First 15 should render, last 5 should not.
      expect(find.text('Actor 0'), findsOneWidget);
      expect(find.text('Actor 14'), findsOneWidget);
      expect(find.text('Actor 15'), findsNothing);
      expect(find.text('Actor 19'), findsNothing);
    });

    testWidgets('image source is ResilientMediaImage with member photo', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Actor', photo: 'https://example.com/photo.jpg')],
        ),
      );

      // ResilientMediaImage should be in the tree (one per card).
      expect(find.byType(ResilientMediaImage), findsOneWidget);
      final img = tester.widget<ResilientMediaImage>(
        find.byType(ResilientMediaImage),
      );
      expect(img.imageUrl, 'https://example.com/photo.jpg');
      expect(img.fallbackIcon, Icons.person);
    });

    testWidgets('passes semanticLabel through to the row Semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Actor')],
          semanticLabel: 'Cast',
        ),
      );

      // Find the row's Semantics widget by its label.
      // (Skip asserting `container` — not on SemanticsProperties in this Flutter version.)
      final semanticsFinder = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Cast',
      );
      expect(semanticsFinder, findsOneWidget);
    });

    testWidgets('card semantics include "as Character" when present', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Bryan Cranston', character: 'Walter White')],
        ),
      );

      final cardSemantics = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Bryan Cranston as Walter White',
      );
      expect(cardSemantics, findsOneWidget);
    });

    testWidgets('card semantics show only name when character absent', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          members: [_m(name: 'Bryan Cranston')],
        ),
      );

      final cardSemantics = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Bryan Cranston',
      );
      expect(cardSemantics, findsOneWidget);
    });

    testWidgets(
      'name renders bold (billing-block style) so long names stand out',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            members: [_m(name: 'Christoph Waltz', character: 'Blofeld')],
          ),
        );

        // "Christoph Waltz" is 15 chars; the 144px card width (~22 chars at
        // bodySmall/12sp) leaves room without ellipsis.
        expect(find.text('Christoph Waltz'), findsOneWidget);
        final style = tester.widget<Text>(find.text('Christoph Waltz')).style;
        expect(style?.fontWeight, FontWeight.w700);
      },
    );

    testWidgets(
      'character renders muted and below name (labelSmall color, not bold)',
      (tester) async {
        await tester.pumpWidget(
          _harness(
            members: [_m(name: 'Bryan Cranston', character: 'Walter White')],
          ),
        );

        final characterStyle =
            tester.widget<Text>(find.text('Walter White')).style;
        expect(characterStyle?.fontWeight, isNot(FontWeight.w700));
        // labelSmall uses a smaller font than bodySmall - distinct typography
        // from the name above it so the eye reads name > role.
        expect(
          characterStyle?.fontSize,
          lessThan(
            tester
                .widget<Text>(find.text('Bryan Cranston'))
                .style!
                .fontSize!,
          ),
        );
      },
    );

    group('compact mode', () {
      testWidgets(
        'renders only 3 cast cards + the overflow tile when more than 3',
        (tester) async {
          final members = [
            for (var i = 0; i < 8; i++) _m(name: 'Actor $i', character: 'Role $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () {},
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          // First 3 render, others don't.
          expect(find.text('Actor 0'), findsOneWidget);
          expect(find.text('Actor 2'), findsOneWidget);
          expect(find.text('Actor 3'), findsNothing);
          expect(find.text('Actor 7'), findsNothing);
          // The overflow tile's name label.
          expect(find.text('Show all cast'), findsOneWidget);
          // Underscore glyph on the badge.
          expect(find.text('_'), findsOneWidget);
        },
      );

      testWidgets(
        'hides overflow tile when 3 or fewer members (nothing to expand to)',
        (tester) async {
          await tester.pumpWidget(
            _harness(
              members: [_m(name: 'Only One'), _m(name: 'Only Two')],
              compact: true,
              onShowAll: () {},
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          expect(find.text('Only One'), findsOneWidget);
          expect(find.text('Only Two'), findsOneWidget);
          expect(find.text('Show all cast'), findsNothing);
          expect(find.text('_'), findsNothing);
        },
      );

      testWidgets(
        'hides overflow tile when onShowAll is null even if members overflow',
        (tester) async {
          // Callers pass null when they don't want a sheet (e.g. compact
          // disabled, or wide layout). No tile should appear regardless.
          final members = [
            for (var i = 0; i < 8; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(_harness(members: members, compact: true));

          expect(find.text('Actor 7'), findsNothing);
          expect(find.text('_'), findsNothing);
        },
      );

      testWidgets(
        'overflow tile fires onShowAll callback on tap',
        (tester) async {
          var tapCount = 0;
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () => tapCount++,
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          await tester.tap(find.text('Show all cast'));
          await tester.pump();
          expect(tapCount, 1);
        },
      );

      testWidgets(
        'overflow tile sets Semantics button=true for screen readers',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i'),
          ];
          await tester.pumpWidget(
            _harness(
              members: members,
              compact: true,
              onShowAll: () {},
              allCastSemanticLabel: 'Show all cast',
            ),
          );

          final buttonFinder = find.byWidgetPredicate(
            (w) =>
                w is Semantics &&
                w.properties.label == 'Show all cast' &&
                w.properties.button == true,
          );
          expect(buttonFinder, findsOneWidget);
        },
      );

      testWidgets(
        'wide layout shows full cast up to 15 without overflow tile',
        (tester) async {
          final members = [
            for (var i = 0; i < 5; i++) _m(name: 'Actor $i', character: 'Role $i'),
          ];
          await tester.pumpWidget(_harness(members: members));

          // All 5 render.
          expect(find.text('Actor 4'), findsOneWidget);
          expect(find.text('Show all cast'), findsNothing);
          expect(find.text('_'), findsNothing);
        },
      );
    });
  });
}
