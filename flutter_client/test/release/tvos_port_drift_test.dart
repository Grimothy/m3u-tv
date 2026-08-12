import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Each `packages/*_tvos` directory is a manual `flutter-tvos plugin port` of
/// an upstream Darwin/iOS plugin implementation. Pub has no idea these forks
/// exist, so bumping the upstream package (flutter_secure_storage_darwin,
/// sqflite_darwin, wakelock_plus, ...) never triggers a corresponding update
/// to the tvOS fork - the two silently drift apart.
///
/// This test compares the source version recorded in each fork's
/// PORTING_REPORT.md against the version currently resolved in pubspec.lock,
/// so drift fails CI instead of going unnoticed.
void main() {
  final packagesDir = Directory('packages');
  final lockfile = File('pubspec.lock').readAsStringSync();

  final sourceLineRegex = RegExp(
    r'^Source: `([\w.]+)` ([^\s]+) ',
    multiLine: true,
  );

  String? resolvedVersionFor(String packageName) {
    final blockRegex = RegExp(
      '^  ${RegExp.escape(packageName)}:\\n((?:    .*\\n?)*)',
      multiLine: true,
    );
    final block = blockRegex.firstMatch(lockfile)?.group(1);
    if (block == null) return null;
    return RegExp('version: "([^"]+)"').firstMatch(block)?.group(1);
  }

  final portDirs = packagesDir
      .listSync()
      .whereType<Directory>()
      .where(
        (dir) => File('${dir.path}/PORTING_REPORT.md').existsSync(),
      )
      .toList();

  test('at least one ported tvOS package is present to check', () {
    expect(
      portDirs,
      isNotEmpty,
      reason:
          'No packages/*/PORTING_REPORT.md found - if all tvOS ports were '
          'removed, delete this test too.',
    );
  });

  for (final dir in portDirs) {
    final forkName = dir.path.split(Platform.pathSeparator).last;

    test(
      '$forkName is ported from the currently resolved upstream version',
      () {
        final report = File('${dir.path}/PORTING_REPORT.md').readAsStringSync();
        final match = sourceLineRegex.firstMatch(report);
        expect(
          match,
          isNotNull,
          reason:
              '${dir.path}/PORTING_REPORT.md is missing a "Source: `pkg` '
              'version" line - was it hand-edited?',
        );

        final upstreamName = match!.group(1)!;
        final portedVersion = match.group(2)!;
        final resolvedVersion = resolvedVersionFor(upstreamName);

        expect(
          resolvedVersion,
          isNotNull,
          reason:
              "$upstreamName is not in pubspec.lock - has $forkName's "
              'upstream source package been removed or renamed?',
        );

        expect(
          portedVersion,
          resolvedVersion,
          reason:
              '$forkName was ported from $upstreamName $portedVersion, but '
              'pubspec.lock now resolves $upstreamName to $resolvedVersion. '
              'Re-run `flutter-tvos plugin port` for $upstreamName and merge '
              'the changes into packages/$forkName, then update its '
              'PORTING_REPORT.md.',
        );
      },
    );
  }
}
