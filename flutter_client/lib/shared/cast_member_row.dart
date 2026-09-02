import 'dart:math' as math;

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Cast row used on the VOD movie detail and Series detail screens to
/// display the rich cast emitted by m3u-editor's `cast_list` payload.
/// Returns [SizedBox.shrink] when [members] is null or empty so callers
/// can drop it inline without a null check.
///
/// **Wide layout** (`compact = false`, the default): a horizontal scroll
/// row of 144×~140 cards. Each card is a 72×72 circular avatar with
/// name (bold, 1 line) and character (muted, 1 line) in a billing-block
/// layout — 144px fits ~21 characters so names like "Christoph Waltz"
/// and "Jesse Pinkman" don't truncate. When more members exist than
/// cards fit the available width (and [onShowAll] is set), the last
/// visible slot becomes a "+N / show all" tile that fires [onShowAll]
/// — callers wire it to the same picker modal the season picker uses.
/// Without [onShowAll] the row falls back to a plain horizontal scroll
/// capped at [_maxMembers] (15). D-pad traversal is native: left/right
/// moves focus between cards; the row stops at its edges so focus
/// doesn't escape into the surrounding column. Focused cards get the
/// canonical project-wide [GradientBorderEffect] glow. Member cards
/// have no tap action — cast is informational on wide layouts.
///
/// **Compact mode** (`compact = true`, phone breakpoint): a pill-shaped
/// picker button mirroring the season picker's chrome — the localized
/// "Cast" label, a down-chevron, and a count badge showing how many cast
/// members are in [members]. Tapping the button fires [onShowAll],
/// which callers wire to the same bottom-drawer picker used by the
/// season picker. The picker button is hidden when [onShowAll] is null,
/// allowing narrow callers (e.g. a search results card) to opt out of
/// the cast UI entirely.
class CastMemberRow extends StatelessWidget {
  const CastMemberRow({
    super.key,
    required this.members,
    this.semanticLabel,
    this.compact = false,
    this.onShowAll,
    this.allCastSemanticLabel,
  });

  final List<CastMember>? members;

  /// Accessibility label for the row in wide layout, and the visible
  /// button label in compact layout. Localized at the call site (the
  /// VOD/Series detail screens pass `AppLocalizations.of(context)
  /// .vodCast` / `.seriesCast`). The row itself stays
  /// locale-agnostic.
  final String? semanticLabel;

  /// Phone-breakpoint layout. Renders a single picker button instead of
  /// the wide horizontal scroll row. See class doc.
  final bool compact;

  /// Tap handler for the compact picker chip and the wide layout's
  /// "+N / show all" overflow tile. Typically opens the full cast in
  /// the same modal shape the season picker uses (bottom sheet on the
  /// narrow breakpoint, centered dialog on the wide one). When null,
  /// the compact widget renders nothing and the wide row falls back to
  /// a plain scroll without an overflow tile.
  final VoidCallback? onShowAll;

  /// Accessibility / visible label for the sheet when the picker is
  /// tapped (e.g. "Show all cast"). Localized at the call site.
  final String? allCastSemanticLabel;

  static const double _cardWidth = 144;
  static const double _avatarSize = 72;
  static const double _cardHeight = 140;
  static const double _cardGap = 12;
  static const int _maxMembers = 15;

  @override
  Widget build(BuildContext context) {
    final visible = members;
    if (visible == null || visible.isEmpty) {
      return const SizedBox.shrink();
    }

    if (compact) {
      // Compact callers without a sheet set onShowAll=null → render
      // nothing. Avoids a tap target that would no-op.
      if (onShowAll == null) return const SizedBox.shrink();
      return _CastPickerButton(
        label: semanticLabel ?? 'Cast',
        badgeCount: visible.length,
        onTap: onShowAll!,
      );
    }

    return Semantics(
      label: semanticLabel,
      container: true,
      child: DpadRegion(
        memoryKey: 'cast-member-row',
        horizontalEdge: DpadEdgeBehavior.stop,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final capped = visible.length > _maxMembers
                ? visible.sublist(0, _maxMembers)
                : visible;
            // Card slots that fit the available width without scrolling
            // (n × 144 + (n−1) × 12 ≤ maxWidth). Unbounded width (e.g.
            // an ancestor horizontal scroller) fits everything.
            final maxWidth = constraints.maxWidth;
            final fit = maxWidth.isFinite
                ? math.max(
                    1,
                    (maxWidth + _cardGap) ~/ (_cardWidth + _cardGap),
                  )
                : capped.length;
            // With onShowAll wired, members beyond what fits collapse
            // into a trailing "+N / show all" tile instead of scrolling
            // off-screen. Without it, keep the plain capped scroll row.
            final overflows = onShowAll != null && visible.length > fit;
            final shown = overflows
                ? capped.sublist(0, math.min(fit - 1, capped.length))
                : capped;
            final hiddenCount = visible.length - shown.length;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              child: Row(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    if (i > 0) const SizedBox(width: _cardGap),
                    SizedBox(
                      width: _cardWidth,
                      height: _cardHeight,
                      child: _CastMemberCard(member: shown[i]),
                    ),
                  ],
                  if (overflows) ...[
                    if (shown.isNotEmpty) const SizedBox(width: _cardGap),
                    SizedBox(
                      width: _cardWidth,
                      height: _cardHeight,
                      child: _ShowAllCastCard(
                        hiddenCount: hiddenCount,
                        label: allCastSemanticLabel ?? 'Show all',
                        onTap: onShowAll!,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Pill-shaped picker button matching the season picker's chrome:
/// `label` text, a count badge, a down-chevron, focused via
/// [GradientBorderEffect]. Tap fires [onTap]. Renders nothing different
/// when [badgeCount] is 0 or 1 — the season picker shows the badge for
/// any positive count.
class _CastPickerButton extends StatelessWidget {
  const _CastPickerButton({
    required this.label,
    required this.badgeCount,
    required this.onTap,
  });

  final String label;
  final int badgeCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppButton(
      label: label,
      icon: Icons.arrow_drop_down,
      badgeCount: badgeCount > 0 ? badgeCount : null,
      // Muted, not the default error red — this is a count, not an
      // unwatched / new alert (matches how the season picker styles its
      // episode-count badge).
      badgeColor: scheme.surfaceContainerHighest,
      badgeTextColor: scheme.onSurfaceVariant,
      onPressed: onTap,
    );
  }
}

/// Trailing wide-layout tile shown when more members exist than fit
/// the row: a "+N" circle where the avatar sits and the localized
/// "Show all" label in the name slot. Tap opens the full cast in the
/// caller's picker modal.
class _ShowAllCastCard extends StatelessWidget {
  const _ShowAllCastCard({
    required this.hiddenCount,
    required this.label,
    required this.onTap,
  });

  final int hiddenCount;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Semantics(
      label: label,
      button: true,
      child: DpadInkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        effects: const [
          GradientBorderEffect(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ],
        child: Column(
          children: [
            SizedBox(
              width: CastMemberRow._avatarSize,
              height: CastMemberRow._avatarSize,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.surfaceContainerHighest,
                ),
                child: Center(
                  child: Text(
                    '+$hiddenCount',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CastMemberCard extends StatelessWidget {
  const _CastMemberCard({required this.member});

  final CastMember member;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = member.name;
    final character = member.character;

    return Semantics(
      label: character != null && character.isNotEmpty
          ? '$name as $character'
          : name,
      child: DpadInkWell(
        // No tap action — cast is informational in v1.
        borderRadius: const BorderRadius.all(Radius.circular(8)),
        effects: const [
          GradientBorderEffect(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ],
        child: Column(
          children: [
            // Decorative gradient ring + circular avatar + bottom-fade.
            _GradientRingAvatar(
              size: CastMemberRow._avatarSize,
              child: _AvatarWithFade(
                imageUrl: member.photo,
                size: CastMemberRow._avatarSize,
                surface: scheme.surface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                name,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (character != null && character.isNotEmpty) ...[
              const SizedBox(height: 2),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  character,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Circular clip around the avatar child. No decorative ring — focus is
/// handled by [GradientBorderEffect] at the card level.
class _GradientRingAvatar extends StatelessWidget {
  const _GradientRingAvatar({
    required this.child,
    required this.size,
  });

  final Widget child;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(child: child),
    );
  }
}

/// Circular clip containing the [ResilientMediaImage] headshot. No
/// decorative overlay — a bottom→top surface fade was tried here and
/// produced a visible dark half-circle on every avatar in dark theme.
class _AvatarWithFade extends StatelessWidget {
  const _AvatarWithFade({
    required this.imageUrl,
    required this.size,
    required this.surface,
  });

  final String? imageUrl;
  final double size;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: ResilientMediaImage(
          imageUrl: imageUrl,
          fallbackIcon: Icons.person,
          backgroundColor: surface,
        ),
      ),
    );
  }
}
