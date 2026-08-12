import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'desktop notification dependency is wired into Linux, Windows and macOS',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lockfile = File('pubspec.lock').readAsStringSync();
      final linuxCmake = File('linux/CMakeLists.txt').readAsStringSync();
      final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
      final macosRegistrant = File(
        'macos/Flutter/GeneratedPluginRegistrant.swift',
      ).readAsStringSync();

      expect(
        pubspec,
        matches(RegExp(r'flutter_local_notifications: \^\d+\.\d+\.\d+')),
      );
      expect(lockfile, contains('flutter_local_notifications_linux:'));
      expect(lockfile, contains('flutter_local_notifications_windows:'));
      expect(linuxCmake, contains('generated_plugin_registrant.cc'));
      expect(linuxCmake, contains('include(flutter/generated_plugins.cmake)'));
      expect(
        windowsCmake,
        contains('include(flutter/generated_plugins.cmake)'),
      );
      expect(macosRegistrant, contains('import flutter_local_notifications'));
      expect(
        macosRegistrant,
        contains('FlutterLocalNotificationsPlugin.register('),
      );
    },
  );
}
