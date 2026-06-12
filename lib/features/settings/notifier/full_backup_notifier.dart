import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

final fullBackupNotifierProvider = Provider<FullBackupNotifier>((ref) {
  return FullBackupNotifier(ref);
});

class FullBackupNotifier with AppLogger {
  FullBackupNotifier(this.ref);

  final Ref ref;

  Future<bool> exportFullBackup() async {
    final notification = ref.read(inAppNotificationControllerProvider);

    try {
      final dirs = await ref.read(appDirectoriesProvider.future);
      final databaseDir = await AppDirectories.getDatabaseDirectory();
      final tempRoot = Directory(p.join(dirs.tempDir.path, 'andreyvpn_backup_${const Uuid().v4()}'));
      final stagingDir = Directory(p.join(tempRoot.path, 'backup'));

      await stagingDir.create(recursive: true);

      final manifest = <String, dynamic>{
        'app': 'AndreyVPN',
        'type': 'full_backup',
        'format': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'items': <String>[],
      };

      await _copyDirectoryIfExists(dirs.baseDir, Directory(p.join(stagingDir.path, 'base')));
      (manifest['items'] as List<String>).add('base');

      if (!_samePath(dirs.workingDir.path, dirs.baseDir.path)) {
        await _copyDirectoryIfExists(dirs.workingDir, Directory(p.join(stagingDir.path, 'working')));
        (manifest['items'] as List<String>).add('working');
      }

      if (!_samePath(databaseDir.path, dirs.baseDir.path) && !_samePath(databaseDir.path, dirs.workingDir.path)) {
        await _copyDirectoryIfExists(databaseDir, Directory(p.join(stagingDir.path, 'database')));
        (manifest['items'] as List<String>).add('database');
      }

      await File(p.join(stagingDir.path, 'andreyvpn_backup_manifest.json')).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );

      final archivePath = p.join(tempRoot.path, _defaultBackupFileName());
      final encoder = ZipFileEncoder();
      encoder.create(archivePath);
      encoder.addDirectory(stagingDir, includeDirName: false);
      encoder.close();

      final backupBytes = await File(archivePath).readAsBytes();
      final outputFile = await FilePicker.platform.saveFile(
        fileName: _defaultBackupFileName(),
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: PlatformUtils.isDesktop ? null : backupBytes,
      );

      if (outputFile == null) {
        await tempRoot.delete(recursive: true);
        return false;
      }

      if (PlatformUtils.isDesktop) {
        final file = File(_ensureZipExtension(outputFile));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(backupBytes, flush: true);
      }

      await tempRoot.delete(recursive: true);
      notification.showSuccessToast('Полный бэкап экспортирован');
      return true;
    } catch (e, st) {
      loggy.warning('error exporting full backup', e, st);
      notification.showErrorToast('Не удалось экспортировать полный бэкап');
      return false;
    }
  }

  Future<bool> importFullBackup() async {
    final notification = ref.read(inAppNotificationControllerProvider);

    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
      if (result == null || result.files.single.path == null) return false;

      final backupFile = File(result.files.single.path!);
      if (!await backupFile.exists()) return false;

      final dirs = await ref.read(appDirectoriesProvider.future);
      final databaseDir = await AppDirectories.getDatabaseDirectory();
      final tempRoot = Directory(p.join(dirs.tempDir.path, 'andreyvpn_restore_${const Uuid().v4()}'));
      await tempRoot.create(recursive: true);

      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      extractArchiveToDisk(archive, tempRoot.path);

      final manifest = File(p.join(tempRoot.path, 'andreyvpn_backup_manifest.json'));
      if (!await manifest.exists()) {
        throw const FormatException('Invalid AndreyVPN backup: manifest not found');
      }

      final baseBackup = Directory(p.join(tempRoot.path, 'base'));
      final workingBackup = Directory(p.join(tempRoot.path, 'working'));
      final databaseBackup = Directory(p.join(tempRoot.path, 'database'));

      if (await baseBackup.exists()) {
        await _copyDirectoryIfExists(baseBackup, dirs.baseDir);
      }
      if (await workingBackup.exists()) {
        await _copyDirectoryIfExists(workingBackup, dirs.workingDir);
      }
      if (await databaseBackup.exists()) {
        await _copyDirectoryIfExists(databaseBackup, databaseDir);
      }

      await tempRoot.delete(recursive: true);
      notification.showSuccessToast('Полный бэкап импортирован. Перезапустите приложение');
      return true;
    } catch (e, st) {
      loggy.warning('error importing full backup', e, st);
      notification.showErrorToast('Не удалось импортировать полный бэкап');
      return false;
    }
  }

  Future<void> _copyDirectoryIfExists(Directory source, Directory destination) async {
    if (!await source.exists()) return;
    if (!await destination.exists()) await destination.create(recursive: true);

    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      if (_shouldSkip(name)) continue;

      final newPath = p.join(destination.path, name);
      if (entity is Directory) {
        await _copyDirectoryIfExists(entity, Directory(newPath));
      } else if (entity is File) {
        await File(newPath).parent.create(recursive: true);
        await entity.copy(newPath);
      }
    }
  }

  bool _shouldSkip(String name) {
    return name == 'access_test.txt' ||
        name.endsWith('-journal') ||
        name.endsWith('-shm') ||
        name.endsWith('-wal') ||
        name == 'Cache' ||
        name == 'cache';
  }

  bool _samePath(String a, String b) => p.normalize(p.absolute(a)) == p.normalize(p.absolute(b));

  String _defaultBackupFileName() {
    final now = DateTime.now();
    final stamp = [
      now.year.toString().padLeft(4, '0'),
      now.month.toString().padLeft(2, '0'),
      now.day.toString().padLeft(2, '0'),
      '_',
      now.hour.toString().padLeft(2, '0'),
      now.minute.toString().padLeft(2, '0'),
    ].join();
    return 'AndreyVPN_full_backup_$stamp.zip';
  }

  String _ensureZipExtension(String path) {
    if (p.extension(path).toLowerCase() == '.zip') return path;
    return '$path.zip';
  }
}
