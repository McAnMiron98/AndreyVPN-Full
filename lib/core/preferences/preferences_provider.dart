import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'preferences_provider.g.dart';

@Riverpod(keepAlive: true)
Future<SharedPreferences> sharedPreferences(Ref ref) async {
  final logger = Loggy("preferences");
  SharedPreferences? sharedPreferences;

  logger.debug("initializing preferences");
  try {
    if (PlatformUtils.isWindows && Environment.isPortable) SharedPreferences.setPrefix('portable.');
    sharedPreferences = await SharedPreferences.getInstance();
    if (PlatformUtils.isWindows) {
      await _mirrorPreferencesToPortable(sharedPreferences);
      await _cleanupLegacyAppDataArtifacts();
      unawaited(_delayedPortablePreferencesCleanup(sharedPreferences));
    }
  } catch (e) {
    logger.error("error initializing preferences", e);
    if (!Platform.isWindows && !Platform.isLinux) {
      rethrow;
    }
    // https://github.com/flutter/flutter/issues/89211
    final directory = PlatformUtils.isWindows
        ? await AppDirectories.getDatabaseDirectory()
        : await getApplicationSupportDirectory();
    final file = File(p.join(directory.path, 'shared_preferences.json'));
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  sharedPreferences ??= await SharedPreferences.getInstance();
  if (PlatformUtils.isWindows) {
    await _mirrorPreferencesToPortable(sharedPreferences);
    await _cleanupLegacyAppDataArtifacts();
    unawaited(_delayedPortablePreferencesCleanup(sharedPreferences));
  }
  return sharedPreferences;
}

Future<void> _delayedPortablePreferencesCleanup(SharedPreferences preferences) async {
  // Some shared_preferences_windows writes can happen shortly after initialization.
  // Keep this small delayed cleanup so portable builds do not leave files in AppData.
  for (final delay in <Duration>[
    const Duration(milliseconds: 500),
    const Duration(seconds: 2),
    const Duration(seconds: 5),
  ]) {
    await Future<void>.delayed(delay);
    await _mirrorPreferencesToPortable(preferences);
    await _cleanupLegacyAppDataArtifacts();
  }
}

Future<void> _mirrorPreferencesToPortable(SharedPreferences preferences) async {
  try {
    if (!PlatformUtils.isWindows) return;
    final portableDir = AppDirectories.getPortableDirectory();
    if (!await portableDir.exists()) {
      await portableDir.create(recursive: true);
    }

    final values = <String, Object?>{};
    for (final key in preferences.getKeys()) {
      values[key] = preferences.get(key);
    }

    final file = File(p.join(portableDir.path, 'shared_preferences.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(values),
      flush: true,
    );
  } catch (_) {
    // Preferences mirroring must never block startup.
  }
}

Future<void> _cleanupLegacyAppDataArtifacts() async {
  try {
    if (!PlatformUtils.isWindows) return;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return;

    final legacyDir = Directory(p.join(appData, 'AndreyVPN', 'AndreyVPN'));
    if (!await legacyDir.exists()) return;

    for (final name in <String>[
      'shared_preferences.json',
      'andreyvpn_restart_diagnostic.log',
    ]) {
      final file = File(p.join(legacyDir.path, name));
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  } catch (_) {
    // Legacy cleanup must never block startup.
  }
}
