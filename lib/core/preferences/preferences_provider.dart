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
    if (PlatformUtils.isWindows) {
      await _preparePortablePreferencesBeforeInitialization();
    }
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

  if (sharedPreferences == null) {
    if (PlatformUtils.isWindows) {
      await _preparePortablePreferencesBeforeInitialization();
    }
    sharedPreferences = await SharedPreferences.getInstance();
  }
  if (PlatformUtils.isWindows) {
    await _mirrorPreferencesToPortable(sharedPreferences);
    await _cleanupLegacyAppDataArtifacts();
    unawaited(_delayedPortablePreferencesCleanup(sharedPreferences));
  }
  return sharedPreferences;
}

Future<void> _preparePortablePreferencesBeforeInitialization() async {
  try {
    if (!PlatformUtils.isWindows) return;

    final portableDir = AppDirectories.getPortableDirectory();
    if (!await portableDir.exists()) {
      await portableDir.create(recursive: true);
    }

    final portableFile = File(p.join(portableDir.path, 'shared_preferences.json'));
    final legacyFile = await _legacyPreferencesFile();

    await _writePreferencesDiagnostic(
      'prepare start; portable exists=${await portableFile.exists()}; legacy exists=${legacyFile != null && await legacyFile.exists()}',
    );

    if (legacyFile == null) return;

    if (!await legacyFile.parent.exists()) {
      await legacyFile.parent.create(recursive: true);
    }

    if (await portableFile.exists()) {
      // shared_preferences_windows still reads from AppData. Seed that file from
      // the portable copy before SharedPreferences.getInstance() is called so
      // the intro/analytics flags are available immediately on startup.
      await portableFile.copy(legacyFile.path);
      await _writePreferencesDiagnostic('seeded legacy preferences from portable: ${legacyFile.path}');
      return;
    }

    if (await legacyFile.exists()) {
      await legacyFile.copy(portableFile.path);
      await _writePreferencesDiagnostic('created portable preferences from existing legacy file: ${portableFile.path}');
    }
  } catch (e) {
    await _writePreferencesDiagnostic('prepare error: $e');
    // Preferences preparation must never block startup.
  }
}

Future<File?> _legacyPreferencesFile() async {
  final appData = Platform.environment['APPDATA'];
  if (appData == null || appData.isEmpty) return null;
  return File(p.join(appData, 'AndreyVPN', 'AndreyVPN', 'shared_preferences.json'));
}

Future<void> _writePreferencesDiagnostic(String message) async {
  try {
    if (!PlatformUtils.isWindows) return;
    final portableDir = AppDirectories.getPortableDirectory();
    if (!await portableDir.exists()) {
      await portableDir.create(recursive: true);
    }
    final file = File(p.join(portableDir.path, 'andreyvpn_preferences_diagnostic.log'));
    await file.writeAsString(
      '[${DateTime.now().toIso8601String()}] $message\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {
    // Preference diagnostics must never block startup.
  }
}

Future<void> _delayedPortablePreferencesCleanup(SharedPreferences preferences) async {
  // Some shared_preferences_windows writes can happen shortly after initialization.
  // Keep this small delayed sync so portable copy stays up to date.
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
