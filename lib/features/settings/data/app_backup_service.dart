import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/profile/data/profile_data_providers.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

class AppBackupService with AppLogger {
  AppBackupService(this.ref);

  final WidgetRef ref;

  static const int _version = 1;

  Future<Map<String, dynamic>> _createBackupMap({bool includePrivate = true}) async {
    final db = ref.read(dbProvider);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final profilePathResolver = ref.read(profilePathResolverProvider);

    final profiles = await db.select(db.profileEntries).get();
    final appProxy = await db.select(db.appProxyEntries).get();
    final options = ref.read(ConfigOptions.singboxConfigOptions).toJson();

    final profileBackups = <Map<String, dynamic>>[];
    for (final profile in profiles) {
      String? rawConfig;
      final file = profilePathResolver.file(profile.id);
      if (await file.exists()) {
        rawConfig = await file.readAsString();
      }

      profileBackups.add({
        'entry': _profileEntryToJson(profile),
        'rawConfig': rawConfig,
      });
    }

    final prefsMap = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      final value = prefs.get(key);
      if (value is String || value is bool || value is int || value is double || value is List<String>) {
        prefsMap[key] = value;
      }
    }

    return {
      'backupType': 'andreyvpn_full_backup',
      'backupVersion': _version,
      'app': 'AndreyVPN',
      'createdAt': DateTime.now().toIso8601String(),
      'includePrivate': includePrivate,
      'configOptions': options,
      'sharedPreferences': prefsMap,
      'profiles': profileBackups,
      'appProxyEntries': appProxy.map((e) => {'mode': e.mode.name, 'pkgName': e.pkgName, 'flags': e.flags}).toList(),
    };
  }


  Map<String, dynamic> _profileEntryToJson(ProfileEntry profile) {
    return {
      'id': profile.id,
      'type': profile.type.name,
      'active': profile.active,
      'name': profile.name,
      'url': profile.url,
      'lastUpdate': profile.lastUpdate.toIso8601String(),
      'updateInterval': profile.updateInterval?.inSeconds,
      'upload': profile.upload,
      'download': profile.download,
      'total': profile.total,
      'expire': profile.expire?.toIso8601String(),
      'webPageUrl': profile.webPageUrl,
      'supportUrl': profile.supportUrl,
      'populatedHeaders': profile.populatedHeaders == null ? null : jsonDecode(profile.populatedHeaders!),
      'profileOverride': profile.profileOverride,
      'userOverride': profile.userOverride == null ? null : jsonDecode(profile.userOverride!),
    };
  }

  Future<bool> exportFullBackupToFile() async {
    try {
      final backup = await _createBackupMap(includePrivate: true);
      const encoder = JsonEncoder.withIndent('  ');
      final bytes = utf8.encode(encoder.convert(backup));
      final date = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;

      final outputFile = await FilePicker.platform.saveFile(
        fileName: 'AndreyVPN-full-backup-$date.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (outputFile == null) return false;

      if (PlatformUtils.isDesktop) {
        final file = File(outputFile);
        if (p.extension(file.path).toLowerCase() != '.json') return false;
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }

      ref.read(inAppNotificationControllerProvider).showSuccessToast('Полный экспорт AndreyVPN сохранён');
      return true;
    } catch (e, st) {
      loggy.warning('error exporting full app backup', e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast('Ошибка полного экспорта AndreyVPN');
      return false;
    }
  }

  Future<bool> exportFullBackupToClipboard() async {
    try {
      final backup = await _createBackupMap(includePrivate: true);
      const encoder = JsonEncoder.withIndent('  ');
      await Clipboard.setData(ClipboardData(text: encoder.convert(backup)));
      ref.read(inAppNotificationControllerProvider).showSuccessToast('Полный экспорт AndreyVPN скопирован');
      return true;
    } catch (e, st) {
      loggy.warning('error exporting full app backup to clipboard', e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast('Ошибка копирования полного экспорта');
      return false;
    }
  }

  Future<bool> importFullBackupFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (result == null) return false;
      final path = result.files.single.path;
      final bytes = result.files.single.bytes ?? (path == null ? null : await File(path).readAsBytes());
      if (bytes == null) return false;
      await _importBackupJson(utf8.decode(bytes));
      ref.read(inAppNotificationControllerProvider).showSuccessToast('Полный импорт AndreyVPN завершён');
      return true;
    } catch (e, st) {
      loggy.warning('error importing full app backup from file', e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast('Ошибка полного импорта AndreyVPN');
      return false;
    }
  }

  Future<bool> importFullBackupFromClipboard() async {
    try {
      final input = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text);
      if (input == null || input.trim().isEmpty) return false;
      await _importBackupJson(input);
      ref.read(inAppNotificationControllerProvider).showSuccessToast('Полный импорт AndreyVPN завершён');
      return true;
    } catch (e, st) {
      loggy.warning('error importing full app backup from clipboard', e, st);
      ref.read(inAppNotificationControllerProvider).showErrorToast('Ошибка полного импорта из буфера');
      return false;
    }
  }

  Future<void> _importBackupJson(String input) async {
    final decoded = jsonDecode(input);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid backup format');
    }
    if (decoded['backupType'] != 'andreyvpn_full_backup') {
      throw const FormatException('This is not an AndreyVPN full backup');
    }

    final db = ref.read(dbProvider);
    final prefs = await ref.read(sharedPreferencesProvider.future);
    final profilePathResolver = ref.read(profilePathResolverProvider);

    final preferences = decoded['sharedPreferences'];
    if (preferences is Map) {
      for (final entry in preferences.entries) {
        final key = entry.key.toString();
        final value = entry.value;
        if (value is String) await prefs.setString(key, value);
        if (value is bool) await prefs.setBool(key, value);
        if (value is int) await prefs.setInt(key, value);
        if (value is double) await prefs.setDouble(key, value);
        if (value is List) await prefs.setStringList(key, value.map((e) => e.toString()).toList());
      }
    }

    final profiles = decoded['profiles'];
    if (profiles is List) {
      await db.transaction(() async {
        for (final item in profiles.whereType<Map>()) {
          final entryJson = item['entry'];
          if (entryJson is! Map) continue;
          final map = entryJson.cast<String, dynamic>();
          final id = map['id']?.toString();
          final name = map['name']?.toString();
          final type = map['type']?.toString();
          if (id == null || id.isEmpty || name == null || name.isEmpty || type == null || type.isEmpty) continue;

          final rawConfig = item['rawConfig'];
          if (rawConfig is String) {
            final file = profilePathResolver.file(id);
            if (!await file.parent.exists()) await file.parent.create(recursive: true);
            await file.writeAsString(rawConfig);
          }

          final companion = ProfileEntriesCompanion(
            id: Value(id),
            type: Value(ProfileType.values.byName(type)),
            active: Value(map['active'] == true),
            name: Value(name),
            url: Value(map['url'] as String?),
            lastUpdate: Value(DateTime.tryParse(map['lastUpdate']?.toString() ?? '') ?? DateTime.now()),
            updateInterval: Value(map['updateInterval'] == null ? null : Duration(seconds: map['updateInterval'] as int)),
            upload: Value(map['upload'] as int?),
            download: Value(map['download'] as int?),
            total: Value(map['total'] as int?),
            expire: Value(map['expire'] == null ? null : DateTime.tryParse(map['expire'].toString())),
            webPageUrl: Value(map['webPageUrl'] as String?),
            supportUrl: Value(map['supportUrl'] as String?),
            populatedHeaders: Value(map['populatedHeaders'] == null ? null : jsonEncode(map['populatedHeaders'])),
            profileOverride: Value(map['profileOverride'] as String?),
            userOverride: Value(map['userOverride'] == null ? null : jsonEncode(map['userOverride'])),
          );
          await db.into(db.profileEntries).insertOnConflictUpdate(companion);
        }
      });
    }

    final appProxyEntries = decoded['appProxyEntries'];
    if (appProxyEntries is List) {
      await db.transaction(() async {
        await db.delete(db.appProxyEntries).go();
        for (final item in appProxyEntries.whereType<Map>()) {
          final mode = item['mode']?.toString();
          final pkgName = item['pkgName']?.toString();
          final flags = item['flags'];
          if (mode == null || pkgName == null) continue;
          await db.into(db.appProxyEntries).insertOnConflictUpdate(
                AppProxyEntriesCompanion(
                  mode: Value(AppProxyMode.values.byName(mode)),
                  pkgName: Value(pkgName),
                  flags: Value(flags is int ? flags : 0),
                ),
              );
        }
      });
    }
  }
}
