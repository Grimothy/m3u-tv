import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Width below which the picker collapses into a bottom-sheet drawer. Matches
/// the rest of the Series Details screen's compact / wide split
/// (`_kSeriesCompactBreakpoint` in `series_details_screen.dart`).
const double _kPickerBreakpoint = 700;

/// Form-factor-aware season selector for the Series Details screen.
///
/// - On wide screens (>= [_kPickerBreakpoint]) renders the inline horizontally
///   scrolling card row (matches PR #261's `SeasonCardRow` visual).
/// - On narrow screens (< [_kPickerBreakpoint]) renders a pill that opens a
///   bottom-sheet drawer with the same poster+title list, slide-up animation.
///
/// Long-pressing either surface triggers the "mark season watched" prompt,
/// matching the upstream `_SeasonPicker.onMarkSeason` affordance.
class SeasonPicker extends StatelessWidget {
  const SeasonPicker({
    super.key,
    required this.seasons,
    required this.selectedSeason,
    required this.canMarkWatched,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.onSeasonSelected,
    required this.onMarkSeason,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;
  final int Function(int seasonNumber) episodeCountFor;
  final String? fallbackPosterUrl;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<bool> onMarkSeason;

  @override
  Widget build(BuildContext context) {
    if (seasons.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kPickerBreakpoint;
        return wide
            ? _SeasonInlineRow(
                seasons: seasons,
                selectedSeason: selectedSeason,
                canMarkWatched: canMarkWatched,
                episodeCountFor: episodeCountFor,
                fallbackPosterUrl: fallbackPosterUrl,
                onSeasonSelected: onSeasonSelected,
                onMarkSeason: onMarkSeason,
              )
            : _SeasonDrawerPicker(
                seasons: seasons,
                selectedSeason: selectedSeason,
                canMarkWatched: canMarkWatched,
                episodeCountFor: episodeCountFor,
                fallbackPosterUrl: fallbackPosterUrl,
                onSeasonSelected: onSeasonSelected,
                onMarkSeason: onMarkSeason,
              );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Wide / TV / desktop: inline horizontal card row.
// ---------------------------------------------------------------------------

class _SeasonInlineRow extends StatelessWidget {
  const _SeasonInlineRow({
    required this.seasons,
    required this.selectedSeason,
    required this.canMarkWatched,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.onSeasonSelected,
    required this.onMarkSeason,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;
  final int Function(int seasonNumber) episodeCountFor;
  final String? fallbackPosterUrl;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<bool> onMarkSeason;

  static const double _cardWidth = 132;
  static const double _cardAspectRatio = 2 / 3;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _cardHeight(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: seasons.length,
        separatorBuilder: (context, index) =>
            const SizedBox(width: MediaBrowsingMetrics.itemGap),
        itemBuilder: (context, i) {
          final season = seasons[i];
          final selected = season.number == selectedSeason;
          final poster = _seasonCover(season);
          return _SeasonCard(
            key: ValueKey('season-card-${season.number}'),
            season: season,
            posterUrl: poster,
            fallbackPosterUrl: fallbackPosterUrl,
            episodeCount: episodeCountFor(season.number),
            selected: selected,
            onTap: () => onSeasonSelected(season.number),
            onLongPress: canMarkWatched && selected
                ? () => unawaited(_confirmMarkSeason(context, season.number))
                : null,
          );
        },
      ),
    );
  }

  double _cardHeight() {
    // 2:3 poster (inset by 2*cardPadding) + label area + 2*cardPadding.
    const cardPadding = MediaBrowsingMetrics.chipGap;
    return (_cardWidth - 2 * cardPadding) / _cardAspectRatio + 52 + 2 * cardPadding;
  }

  String? _seasonCover(Season season) {
    final url = season.coverUrl?.trim();
    return (url == null || url.isEmpty) ? null : url;
  }

  Future<void> _confirmMarkSeason(
    BuildContext context,
    int seasonNumber,
  ) async {
    final l = AppLocalizations.of(context);
    final title = l.homeSeason(seasonNumber);
    final message = l.seriesMarkSeasonPrompt(seasonNumber);
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _confirmMarkWatched(
      context,
      title: title,
      message: message,
    );
    if (ok != null) {
      onMarkSeason(ok);
    } else {
      messenger.hideCurrentSnackBar();
    }
  }
}

class _SeasonCard extends StatelessWidget {
  const _SeasonCard({
    super.key,
    required this.season,
    required this.posterUrl,
    required this.fallbackPosterUrl,
    required this.episodeCount,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Season season;
  final String? posterUrl;
  final String? fallbackPosterUrl;
  final int episodeCount;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final name = season.name.trim().isNotEmpty
        ? season.name.trim()
        : l.homeSeason(season.number);
    return SizedBox(
      width: _SeasonInlineRow._cardWidth,
      child: DpadInkWell(
        borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
        onTap: onTap,
        onLongTap: onLongPress,
        child: Container(
          padding: const EdgeInsets.all(MediaBrowsingMetrics.chipGap),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(MediaBrowsingMetrics.cardRadius),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(
                  MediaBrowsingMetrics.posterRadius,
                ),
                child: AspectRatio(
                  aspectRatio: _SeasonInlineRow._cardAspectRatio,
                  child: posterUrl != null || fallbackPosterUrl != null
                      ? Image.network(
                          posterUrl ?? fallbackPosterUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, error, stack) =>
                              _placeholder(context),
                          loadingBuilder: (_, child, progress) =>
                              progress == null ? child : _placeholder(context),
                        )
                      : _placeholder(context),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? theme.colorScheme.primary : null,
                ),
              ),
              if (episodeCount > 0)
                Text(
                  l.seriesEpisodeCount(episodeCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.tv,
        size: 28,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Narrow / mobile: bottom-sheet drawer driven by a pill anchor.
// ---------------------------------------------------------------------------

class _SeasonDrawerPicker extends StatefulWidget {
  const _SeasonDrawerPicker({
    required this.seasons,
    required this.selectedSeason,
    required this.canMarkWatched,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.onSeasonSelected,
    required this.onMarkSeason,
  });

  final List<Season> seasons;
  final int? selectedSeason;
  final bool canMarkWatched;
  final int Function(int seasonNumber) episodeCountFor;
  final String? fallbackPosterUrl;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<bool> onMarkSeason;

  @override
  State<_SeasonDrawerPicker> createState() => _SeasonDrawerPickerState();
}

class _SeasonDrawerPickerState extends State<_SeasonDrawerPicker>
    with SingleTickerProviderStateMixin {
  static const Duration _rotateDuration = Duration(milliseconds: 150);

  late final AnimationController _rotate;

  @override
  void initState() {
    super.initState();
    _rotate = AnimationController(vsync: this, duration: _rotateDuration);
  }

  @override
  void dispose() {
    _rotate.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final l = AppLocalizations.of(context);
    unawaited(_rotate.forward());
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxHeight: _maxSheetHeight(context),
      ),
      builder: (sheetContext) => _SeasonSheet(
        title: l.seriesSeasonsSheetTitle,
        seasons: widget.seasons,
        selectedSeason: widget.selectedSeason,
        episodeCountFor: widget.episodeCountFor,
        fallbackPosterUrl: widget.fallbackPosterUrl,
        focusSeason: widget.selectedSeason ?? widget.seasons.first.number,
      ),
    );
    if (!mounted) return;
    unawaited(_rotate.reverse());
    if (picked != null) widget.onSeasonSelected(picked);
  }

  Future<void> _longPress() async {
    if (!widget.canMarkWatched) return;
    final n = widget.selectedSeason;
    if (n == null) return;
    final l = AppLocalizations.of(context);
    final ok = await _confirmMarkWatched(
      context,
      title: l.homeSeason(n),
      message: l.seriesMarkSeasonPrompt(n),
    );
    if (ok != null) widget.onMarkSeason(ok);
  }

  double _maxSheetHeight(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    return [screenHeight * 0.5, 480.0].reduce((a, b) => a < b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final label = widget.selectedSeason != null
        ? l.homeSeason(widget.selectedSeason!)
        : l.seriesSeasons;
    final count = widget.selectedSeason != null
        ? widget.episodeCountFor(widget.selectedSeason!)
        : 0;
    return AppBar(
      // Sized so the pill matches the play/start-over button height next to it.
      toolbarHeight: 48,
      backgroundColor: Colors.transparent,
      elevation: 0,
      title: DpadInkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: _open,
        onLongTap: widget.canMarkWatched && widget.selectedSeason != null
            ? _longPress
            : null,
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 8),
                _CountBadge(count: count),
              ],
              const SizedBox(width: 4),
              RotationTransition(
                turns: Tween<double>(begin: 0, end: 0.5).animate(
                  CurvedAnimation(parent: _rotate, curve: Curves.easeInOut),
                ),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$count',
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SeasonSheet extends StatelessWidget {
  const _SeasonSheet({
    required this.title,
    required this.seasons,
    required this.selectedSeason,
    required this.episodeCountFor,
    required this.fallbackPosterUrl,
    required this.focusSeason,
  });

  final String title;
  final List<Season> seasons;
  final int? selectedSeason;
  final int Function(int seasonNumber) episodeCountFor;
  final String? fallbackPosterUrl;
  final int focusSeason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(context).close,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          // List
          Flexible(
            child: DpadRegion(
              verticalEdge: DpadEdgeBehavior.stop,
              horizontalEdge: DpadEdgeBehavior.stop,
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: seasons.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final season = seasons[i];
                  final selected = season.number == selectedSeason;
                  return _SeasonRow(
                    key: ValueKey('season-row-${season.number}'),
                    season: season,
                    selected: selected,
                    episodeCount: episodeCountFor(season.number),
                    fallbackPosterUrl: fallbackPosterUrl,
                    autofocus: season.number == focusSeason,
                    onTap: () => Navigator.of(context).pop(season.number),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeasonRow extends StatelessWidget {
  const _SeasonRow({
    super.key,
    required this.season,
    required this.selected,
    required this.episodeCount,
    required this.fallbackPosterUrl,
    required this.autofocus,
    required this.onTap,
  });

  final Season season;
  final bool selected;
  final int episodeCount;
  final String? fallbackPosterUrl;
  final bool autofocus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final poster = season.coverUrl?.trim();
    final posterUrl = (poster == null || poster.isEmpty) ? null : poster;
    return DpadInkWell(
      autofocus: autofocus,
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.25),
                    theme.colorScheme.tertiary.withValues(alpha: 0.20),
                  ],
                ),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              )
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 80,
                child: posterUrl != null || fallbackPosterUrl != null
                    ? Image.network(
                        posterUrl ?? fallbackPosterUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stack) =>
                            _rowPlaceholder(context),
                        loadingBuilder: (_, child, progress) =>
                            progress == null ? child : _rowPlaceholder(context),
                      )
                    : _rowPlaceholder(context),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    season.name.trim().isNotEmpty
                        ? season.name.trim()
                        : l.homeSeason(season.number),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (episodeCount > 0) ...[
                    const SizedBox(height: 2),
                    Text(
                      l.seriesEpisodeCount(episodeCount),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  Icons.check,
                  color: theme.colorScheme.primary,
                  size: 22,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _rowPlaceholder(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.tv,
        size: 24,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers.
// ---------------------------------------------------------------------------

/// Confirmation modal for the "mark season watched / unwatched" long-press.
/// Returns the chosen watched state, or null when dismissed.
Future<bool?> _confirmMarkWatched(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) {
      final l = AppLocalizations.of(context);
      return AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.seriesMarkUnwatched),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.seriesMarkWatched),
          ),
        ],
      );
    },
  );
}
