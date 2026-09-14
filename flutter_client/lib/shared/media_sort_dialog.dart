import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

/// Shows the "Sort By" modal shared by every sortable media grid (VOD,
/// Series). Returns the newly selected [MediaSortOption], or null if the
/// dialog was dismissed (Cancel, back, tap outside) without one.
Future<MediaSortOption?> showMediaSortDialog(
  BuildContext context, {
  required String title,
  required MediaSortOption current,
}) {
  final l = AppLocalizations.of(context);
  final options = <(IconData, String, MediaSortOption)>[
    (Icons.list_alt, l.mediaSortDefault, MediaSortOption.defaultOrder),
    (Icons.star_rate, l.mediaSortRating, MediaSortOption.ratingDesc),
    (
      Icons.south,
      l.mediaSortReleaseDateNewest,
      MediaSortOption.releaseDateDesc,
    ),
    (
      Icons.north,
      l.mediaSortReleaseDateOldest,
      MediaSortOption.releaseDateAsc,
    ),
  ];
  return showDialog<MediaSortOption>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: Row(
        children: [
          const Icon(Icons.sort, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
      children: [
        DpadRegion(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (icon, label, option) in options)
                _MediaSortOptionRow(
                  icon: icon,
                  label: label,
                  isActive: current == option,
                  autofocus: current == option,
                  onTap: () => Navigator.of(dialogContext).pop(option),
                ),
              _MediaSortOptionRow(
                icon: Icons.close,
                label: l.cancel,
                onTap: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MediaSortOptionRow extends StatelessWidget {
  const _MediaSortOptionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isActive = false,
    this.autofocus = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isActive;

  /// The currently-active option gets autofocus, wherever it sits in the
  /// list, so d-pad down naturally walks from it through the rest.
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DpadInkWell(
      autofocus: autofocus,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 24),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.normal,
                  color: isActive ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
            if (isActive) Icon(Icons.check, color: colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
