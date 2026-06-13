import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

part 'preferences_provider.g.dart';

@Riverpod(keepAlive: true)
Future<SharedPreferences> sharedPreferences(Ref ref) async {
  final logger = Loggy("preferences");
  SharedPreferences? sharedPreferences;

  logger.debug("initializing preferences");
  try {
    if (PlatformUtils.isWindows) {
      await _installPortablePreferencesStore();
    }
    sharedPreferences = await SharedPreferences.getInstance();
    if (PlatformUtils.isWindows) {
      await _mirrorPreferencesToPortable(sharedPreferences);
      await _cleanupLegacyAppDataArtifacts();
      unawaited(_delayedPortablePreferencesSync(sharedPreferences));
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
      await _installPortablePreferencesStore();
    }
    sharedPreferences = await SharedPreferences.getInstance();
  }
  if (PlatformUtils.isWindows) {
    await _mirrorPreferencesToPortable(sharedPreferences);
    await _cleanupLegacyAppDataArtifacts();
    unawaited(_delayedPortablePreferencesSync(sharedPreferences));
  }
  return sharedPreferences;
}

Future<void> _installPortablePreferencesStore() async {
  try {
    if (!PlatformUtils.isWindows) return;

    final portableDir = AppDirectories.getPortableDirectory();
    if (!await portableDir.exists()) {
      await portableDir.create(recursive: true);
    }

    final portableFile = File(p.join(portableDir.path, 'shared_preferences.json'));
    final legacyFile = await _legacyPreferencesFile();

    await _writePreferencesDiagnostic(
      'install portable store; portable=${portableFile.path}; portable exists=${await portableFile.exists()}; legacy=${legacyFile?.path}; legacy exists=${legacyFile != null && await legacyFile.exists()}',
    );

    await _normalizePortablePreferencesFile(portableFile, legacyFile);

    SharedPreferencesStorePlatform.instance = _PortableJsonSharedPreferencesStore(portableFile);
    await _writePreferencesDiagnostic('portable preferences store installed: ${portableFile.path}');
  } catch (e) {
    await _writePreferencesDiagnostic('portable store install error: $e');
    // Preferences preparation must never block startup.
  }
}

Future<void> _normalizePortablePreferencesFile(File portableFile, File? legacyFile) async {
  try {
    Map<String, Object?> portableValues = const <String, Object?>{};
    Map<String, Object?> legacyValues = const <String, Object?>{};

    if (await portableFile.exists()) {
      portableValues = await _readJsonMap(portableFile);
    }
    if (legacyFile != null && await legacyFile.exists()) {
      legacyValues = await _readJsonMap(legacyFile);
    }

    final portableHasFlutterKeys = portableValues.keys.any((key) => key.startsWith('flutter.'));
    final legacyHasFlutterKeys = legacyValues.keys.any((key) => key.startsWith('flutter.'));

    Map<String, Object?> normalized;
    String source;

    if (portableHasFlutterKeys) {
      normalized = _normalizePreferenceKeys(portableValues);
      source = 'portable';
    } else if (legacyHasFlutterKeys) {
      // One-time rescue for users coming from 0.8.18 or older: copy the valid
      // Flutter-format file from AppData into portable storage, then stop using AppData.
      normalized = _normalizePreferenceKeys(legacyValues);
      source = 'legacy_rescue';
    } else if (portableValues.isNotEmpty) {
      // Convert the old AndreyVPN portable format:
      // intro_completed -> flutter.intro_completed, enable_analytics -> flutter.enable_analytics, etc.
      normalized = _normalizePreferenceKeys(portableValues);
      source = 'portable_converted';
    } else if (legacyValues.isNotEmpty) {
      normalized = _normalizePreferenceKeys(legacyValues);
      source = 'legacy_converted';
    } else {
      normalized = <String, Object?>{
        'flutter.preferences_version': 1,
        'flutter.region': 'ru',
        'flutter.locale': 'ru',
        'flutter.enable_analytics': false,
        'flutter.intro_completed': true,
      };
      source = 'defaults';
    }

    await _writeJsonMap(portableFile, normalized);
    await _writePreferencesDiagnostic(
      'portable preferences normalized from $source; keys=${normalized.keys.toList()}; flutter.intro_completed=${normalized['flutter.intro_completed']}; flutter.enable_analytics=${normalized['flutter.enable_analytics']}',
    );
  } catch (e) {
    await _writePreferencesDiagnostic('normalize portable preferences error: $e');
  }
}

Map<String, Object?> _normalizePreferenceKeys(Map<String, Object?> values) {
  final normalized = <String, Object?>{};

  for (final entry in values.entries) {
    final rawKey = entry.key;
    if (rawKey.isEmpty) continue;
    final key = rawKey.startsWith('flutter.') ? rawKey : 'flutter.$rawKey';
    normalized[key] = entry.value;
  }

  normalized.putIfAbsent('flutter.preferences_version', () => 1);
  normalized.putIfAbsent('flutter.region', () => 'ru');
  normalized.putIfAbsent('flutter.locale', () => 'ru');
  normalized.putIfAbsent('flutter.enable_analytics', () => false);
  normalized.putIfAbsent('flutter.intro_completed', () => true);

  return normalized;
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

Future<void> _delayedPortablePreferencesSync(SharedPreferences preferences) async {
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
      final rawKey = key.startsWith('flutter.') ? key : 'flutter.$key';
      values[rawKey] = preferences.get(key);
    }

    final normalized = _normalizePreferenceKeys(values);
    final file = File(p.join(portableDir.path, 'shared_preferences.json'));
    await _writeJsonMap(file, normalized);
    await _writePreferencesDiagnostic(
      'mirrored preferences to portable; flutter.intro_completed=${normalized['flutter.intro_completed']}; flutter.enable_analytics=${normalized['flutter.enable_analytics']}; keys=${normalized.keys.length}',
    );
  } catch (e) {
    await _writePreferencesDiagnostic('mirror preferences error: $e');
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
      'shared_preferences.json',
    ]) {
      final file = File(p.join(legacyDir.path, name));
      if (await file.exists()) {
        try {
          await file.delete();
          await _writePreferencesDiagnostic('deleted legacy artifact: ${file.path}');
        } catch (e) {
          await _writePreferencesDiagnostic('failed to delete legacy artifact ${file.path}: $e');
        }
      }
    }

    try {
      final remaining = await legacyDir.list().isEmpty;
      if (remaining) {
        await legacyDir.delete();
        await _writePreferencesDiagnostic('deleted empty legacy directory: ${legacyDir.path}');
      }
    } catch (_) {}
  } catch (e) {
    await _writePreferencesDiagnostic('legacy cleanup error: $e');
  }
}

Future<Map<String, Object?>> _readJsonMap(File file) async {
  if (!await file.exists()) return <String, Object?>{};
  final content = await file.readAsString();
  if (content.trim().isEmpty) return <String, Object?>{};
  final decoded = jsonDecode(content);
  if (decoded is! Map) return <String, Object?>{};
  return decoded.map((key, value) => MapEntry(key.toString(), _normalizeJsonValue(value)));
}

Object? _normalizeJsonValue(Object? value) {
  if (value is List) {
    return value.map((e) => e.toString()).toList();
  }
  return value;
}

Future<void> _writeJsonMap(File file, Map<String, Object?> values) async {
  if (!await file.parent.exists()) {
    await file.parent.create(recursive: true);
  }
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(values),
    flush: true,
  );
}

class _PortableJsonSharedPreferencesStore extends SharedPreferencesStorePlatform {
  _PortableJsonSharedPreferencesStore(this.file);

  final File file;

  Future<Map<String, Object>> _readAllRaw() async {
    final values = _normalizePreferenceKeys(await _readJsonMap(file));
    final result = <String, Object>{};
    for (final entry in values.entries) {
      final value = entry.value;
      if (value is bool || value is int || value is double || value is String || value is List<String>) {
        result[entry.key] = value as Object;
      } else if (value is List) {
        result[entry.key] = value.map((e) => e.toString()).toList();
      }
    }
    return result;
  }

  Future<void> _writeAllRaw(Map<String, Object?> values) async {
    await _writeJsonMap(file, _normalizePreferenceKeys(values));
  }

  @override
  Future<Map<String, Object>> getAll() async {
    final values = await _readAllRaw();
    await _writePreferencesDiagnostic(
      'portable store getAll; file=${file.path}; keys=${values.keys.toList()}; flutter.intro_completed=${values['flutter.intro_completed']}; flutter.enable_analytics=${values['flutter.enable_analytics']}',
    );
    return values;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    final values = await _readAllRaw();
    values[key] = value;
    await _writeAllRaw(values);
    await _writePreferencesDiagnostic('portable store setValue; key=$key; valueType=$valueType; value=$value');
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    final values = await _readAllRaw();
    values.remove(key);
    await _writeAllRaw(values);
    await _writePreferencesDiagnostic('portable store remove; key=$key');
    return true;
  }

  @override
  Future<bool> clear() async {
    await _writeAllRaw(<String, Object?>{});
    await _writePreferencesDiagnostic('portable store clear');
    return true;
  }
}
