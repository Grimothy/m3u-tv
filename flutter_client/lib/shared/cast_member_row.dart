import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/gradient_border_effect.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Horizontally scrolling row of cast member cards. Used on the VOD movie
/// detail and Series detail screens to display the rich cast emitted by
/// m3u-editor's `cast_list` payload. Returns [SizedBox.shrink] when
/// [members] is null or empty so callers can drop it inline without a
/// null check.
///
/// Each card is 144×~140: a 72×72 circular avatar wrapped in a subtle
/// primary→secondary gradient ring (decorative even when unfocused),
/// with a transparent→black bottom-fade overlay inside the ring so the
/// `Icons.person` fallback blends with the surface. Name (bold, 1 line)
/// and character (muted, 1 line) sit below in a billing-block layout —
/// 144px of width fits ~21 characters so names like "Christoph Waltz"
/// and "Jesse Pinkman" don't truncate.
///
/// D-pad traversal is native: left/right moves focus between cards; the
/// row stops at its edges so focus doesn't escape into the surrounding
/// column. Focused cards get the canonical project-wide
/// [GradientBorderEffect] glow (drawn separately from the decorative
/// ring). Tapping does nothing in v1 — cast is informational.
///
/// **Compact mode** (`compact = true`) shrinks the visible member count
/// to [compactVisibleCount] and appends an "all cast" tile — the m3u-tv
/// favicon in the same 72×72 avatar circle, with a `_` glyph in the
/// lower-right corner — which fires [onShowAll] on tap. Used on the
/// narrow breakpoint of the VOD / Series detail screens, where three
/// cast cards plus the overflow tile is all the row can fit without
/// truncating names. The tile only renders when both `compact` is true,
/// [onShowAll] is non-null, and the cast list is longer than
/// [compactVisibleCount]; with ≤ 3 members there's nothing to expand to.
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

  /// Optional accessibility label for the row (e.g. "Cast"). Spoken by
  /// screen readers when focus enters the row; localized at the call
  /// site so the row itself stays locale-agnostic.
  final String? semanticLabel;

  /// Narrow-breakpoint layout. Caps the visible cards and appends the
  /// "all cast" overflow tile (see [onShowAll]).
  final bool compact;

  /// Tap handler for the overflow tile. Only invoked when `compact` is
  /// true and [members] has more entries than
  /// [CastMemberRow.compactVisibleCount]. Typically
  /// opens a bottom sheet listing the full cast (matches the season
  /// picker shape — same DpadRegion, Scrollbar, ListView).
  final VoidCallback? onShowAll;

  /// Accessibility label spoken for the overflow tile ("Show all
  /// cast"). Localized at the call site.
  final String? allCastSemanticLabel;

  static const double _cardWidth = 144;
  static const double _avatarSize = 72;
  static const double _cardHeight = 140;
  static const int _maxMembers = 15;

  /// Number of cast cards shown in compact mode before the overflow tile.
  /// Three cards + one tile fits inside a 720-wide narrow layout with
  /// the standard page padding without truncating names.
  static const int compactVisibleCount = 3;

  @override
  Widget build(BuildContext context) {
    final visible = members;
    if (visible == null || visible.isEmpty) {
      return const SizedBox.shrink();
    }
    final compactLimit = compact ? compactVisibleCount : _maxMembers;
    final shown = visible.length > compactLimit
        ? visible.sublist(0, compactLimit)
        : visible;
    final showOverflowTile =
        compact && onShowAll != null && visible.length > compactVisibleCount;

    final row = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            SizedBox(
              width: _cardWidth,
              height: _cardHeight,
              child: _CastMemberCard(member: shown[i]),
            ),
          ],
          if (showOverflowTile) ...[
            const SizedBox(width: 12),
            SizedBox(
              width: _cardWidth,
              height: _cardHeight,
              child: _ShowAllCastCard(
                onTap: onShowAll!,
                nameLabel: allCastSemanticLabel ?? 'Show all',
                semanticLabel: allCastSemanticLabel,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: semanticLabel,
      container: true,
      child: DpadRegion(
        memoryKey: 'cast-member-row',
        horizontalEdge: DpadEdgeBehavior.stop,
        child: row,
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

/// "All cast" overflow tile used in compact mode. Avatar circle shows
/// the m3u-tv favicon (no photo) with a `_` glyph anchored to the
/// lower-right corner of the circle. Name slot reads "Show all cast"
/// (localized at the call site via [CastMemberRow.allCastSemanticLabel]
/// is the screen-reader label; the visible text below is set by the
/// tile's own [nameLabel]).
class _ShowAllCastCard extends StatelessWidget {
  const _ShowAllCastCard({
    required this.onTap,
    required this.nameLabel,
    this.semanticLabel,
  });

  final VoidCallback onTap;
  final String nameLabel;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: semanticLabel,
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
            // Same avatar size as a regular cast card.
            SizedBox(
              width: CastMemberRow._avatarSize,
              height: CastMemberRow._avatarSize,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipOval(
                      child: ColoredBox(
                        color: scheme.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Image.asset(
                            'assets/icons/favicon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: _UnderscoreBadge(
                      color: scheme.primary,
                      onColor: scheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                nameLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '…',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small circular badge holding a single `_` glyph. Anchored to the
/// lower-right of the favicon avatar circle in [CastMemberRow]. Reads
/// as "more items" — the underscore is the project's standard "tap to
/// expand" affordance (also used in the inline season picker row).
class _UnderscoreBadge extends StatelessWidget {
  const _UnderscoreBadge({required this.color, required this.onColor});

  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black87, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        '_',
        style: TextStyle(
          color: onColor,
          fontSize: 14,
          fontWeight: FontWeight.w900,
          height: 1,
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
