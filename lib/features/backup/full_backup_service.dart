import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dartx/dartx_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

final fullBackupServiceProvider = Provider<FullBackupService>((ref) => FullBackupService(ref));

class FullBackupService with AppLogger {
  FullBackupService(this._ref);

  final Ref _ref;

  Future<bool> exportFullBackup() async {
    final t = _ref.read(translationsProvider).requireValue;
    try {
      final bytes = await _createArchiveBytes();
      final fileName = 'andreyvpn-full-backup-${DateTime.now().toIso8601String().replaceAll(':', '-')}.zip';
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Export AndreyVPN backup',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: bytes,
      );
      if (outputFile == null) return false;
      if (PlatformUtils.isDesktop) {
        final file = File(outputFile.extension == '.zip' ? outputFile : '$outputFile.zip');
        if (!await file.parent.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes, flush: true);
      }
      _ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.file.success);
      return true;
    } catch (e, st) {
      loggy.warning('error exporting full backup', e, st);
      _ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.file.failure);
      return false;
    }
  }

  Future<bool> importFullBackup() async {
    final t = _ref.read(translationsProvider).requireValue;
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import AndreyVPN backup',
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (result == null) return false;
      final path = result.files.single.path;
      if (path == null) return false;
      final file = File(path);
      if (!await file.exists()) return false;
      await _restoreArchive(await file.readAsBytes());
      _ref
          .read(inAppNotificationControllerProvider)
          .showSuccessToast('Импорт завершён. Перезапусти AndreyVPN, чтобы все данные точно применились.');
      return true;
    } catch (e, st) {
      loggy.warning('error importing full backup', e, st);
      _ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.import.failure);
      return false;
    }
  }

  Future<List<int>> _createArchiveBytes() async {
    final dirs = await _resolveBackupDirectories();
    final archive = Archive();
    archive.addFile(
      ArchiveFile.string(
        'andreyvpn-backup.json',
        const JsonEncoder.withIndent('  ').convert({
          'app': 'AndreyVPN',
          'backupVersion': 1,
          'createdAt': DateTime.now().toIso8601String(),
          'content': dirs.map((key, value) => MapEntry(key, value.path)),
        }),
      ),
    );

    final addedPaths = <String>{};
    for (final entry in dirs.entries) {
      final dir = entry.value;
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (_shouldSkip(entity)) continue;
        final realPath = entity.absolute.path;
        if (!addedPaths.add(realPath)) continue;
        final relativePath = p.relative(realPath, from: dir.absolute.path).replaceAll('\\', '/');
        final archivePath = '${entry.key}/$relativePath';
        archive.addFile(ArchiveFile(archivePath, await entity.length(), await entity.readAsBytes()));
      }
    }

    return ZipEncoder().encode(archive) ?? <int>[];
  }

  Future<void> _restoreArchive(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final dirs = await _resolveBackupDirectories();

    for (final file in archive.files) {
      if (!file.isFile) continue;
      final parts = p.posix.split(file.name);
      if (parts.length < 2 || parts.first == 'andreyvpn-backup.json') continue;
      final targetDir = dirs[parts.first];
      if (targetDir == null) continue;
      final relativePath = p.joinAll(parts.skip(1).toList());
      final outFile = File(p.join(targetDir.path, relativePath));
      final normalizedRoot = p.normalize(targetDir.absolute.path);
      final normalizedOut = p.normalize(outFile.absolute.path);
      if (!p.isWithin(normalizedRoot, normalizedOut) && normalizedRoot != normalizedOut) continue;
      if (!await outFile.parent.exists()) await outFile.parent.create(recursive: true);
      await outFile.writeAsBytes(file.content as List<int>, flush: true);
    }
  }

  Future<Map<String, Directory>> _resolveBackupDirectories() async {
    final appDirs = await _ref.read(appDirectoriesProvider.future);
    final dbDir = await AppDirectories.getDatabaseDirectory();
    final dirs = <String, Directory>{
      'base': appDirs.baseDir,
      'working': appDirs.workingDir,
      'database': dbDir,
    };
    return dirs;
  }

  bool _shouldSkip(File file) {
    final name = p.basename(file.path).toLowerCase();
    final path = file.path.toLowerCase();
    if (name == 'access_test.txt') return true;
    if (name.endsWith('.lock') || name.endsWith('-journal') || name.endsWith('-wal') || name.endsWith('-shm')) return true;
    if (path.contains('${p.separator}cache${p.separator}')) return true;
    if (path.contains('${p.separator}logs${p.separator}')) return true;
    return false;
  }
}
