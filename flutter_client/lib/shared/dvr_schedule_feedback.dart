import 'package:flutter/material.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';

/// Runs [schedule] and shows the shared success/failure SnackBar for a
/// single DVR airing. Shared between the live-tv context menu
/// (`AppShell._scheduleDvr`) and the Shows-search episode row
/// (`ShowDetailScreen._scheduleEpisode`) so both surfaces report the same
/// way. Returns the scheduled result, or null if scheduling failed or the
/// context was unmounted by the time the call completed.
Future<T?> scheduleDvrWithFeedback<T>(
  BuildContext context, {
  required Future<T> Function() schedule,
  required String title,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);
  try {
    final result = await schedule();
    if (!context.mounted) return null;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.appRecordingScheduled(title))),
    );
    return result;
  } on Object catch (error) {
    if (!context.mounted) return null;
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.appRecordingFailed(error.toString()))),
    );
    return null;
  }
}
