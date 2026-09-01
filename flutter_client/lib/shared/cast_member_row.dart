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
class CastMemberRow extends StatelessWidget {
  const CastMemberRow({
    super.key,
    required this.members,
    this.semanticLabel,
  });

  final List<CastMember>? members;

  /// Optional accessibility label for the row (e.g. "Cast"). Spoken by
  /// screen readers when focus enters the row; localized at the call
  /// site so the row itself stays locale-agnostic.
  final String? semanticLabel;

  static const double _cardWidth = 144;
  static const double _avatarSize = 72;
  static const double _cardHeight = 140;
  static const int _maxMembers = 15;

  @override
  Widget build(BuildContext context) {
    final visible = members;
    if (visible == null || visible.isEmpty) {
      return const SizedBox.shrink();
    }
    final shown = visible.length > _maxMembers
        ? visible.sublist(0, _maxMembers)
        : visible;

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
              ringWidth: 2,
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

/// Decorative primary→secondary gradient ring painted around a circular
/// child (the avatar). Unfocused; focus is handled by [GradientBorderEffect]
/// at the card level.
class _GradientRingAvatar extends StatelessWidget {
  const _GradientRingAvatar({
    required this.child,
    required this.size,
    required this.ringWidth,
  });

  final Widget child;
  final double size;
  final double ringWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size + ringWidth * 2,
      height: size + ringWidth * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [scheme.primary, scheme.secondary],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(ringWidth),
        child: ClipOval(child: child),
      ),
    );
  }
}

/// Circular clip containing the [ResilientMediaImage] headshot, with a
/// transparent→surface fade across the bottom ~35%. The fade softens
/// the [Icons.person] fallback when no photo loads, and gives loaded
/// headshots a subtle poster-like depth.
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
      child: Stack(
        children: [
          ResilientMediaImage(
            imageUrl: imageUrl,
            fallbackIcon: Icons.person,
            backgroundColor: surface,
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      surface.withValues(alpha: 0.6),
                    ],
                    stops: const [0.65, 1.0],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
