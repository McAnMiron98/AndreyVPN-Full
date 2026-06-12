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
    final diagnostics = StringBuffer();

    void diag(String message) {
      final line = '[${DateTime.now().toIso8601String()}] $message';
      diagnostics.writeln(line);
      loggy.info(line);
    }

    try {
      diag('AndreyVPN full backup export started');
      final dirs = await ref.read(appDirectoriesProvider.future);
      final databaseDir = await AppDirectories.getDatabaseDirectory();
      final tempRoot = Directory(p.join(dirs.tempDir.path, 'andreyvpn_backup_${const Uuid().v4()}'));
      final stagingDir = Directory(p.join(tempRoot.path, 'backup'));

      diag('baseDir: ${dirs.baseDir.path}');
      diag('workingDir: ${dirs.workingDir.path}');
      diag('tempDir: ${dirs.tempDir.path}');
      diag('databaseDir: ${databaseDir.path}');
      diag('tempRoot: ${tempRoot.path}');
      diag('stagingDir: ${stagingDir.path}');

      await stagingDir.create(recursive: true);

      final manifest = <String, dynamic>{
        'app': 'AndreyVPN',
        'type': 'full_backup',
        'format': 1,
        'diagnostic': true,
        'createdAt': DateTime.now().toIso8601String(),
        'items': <String>[],
      };

      final baseCount = await _copyDirectoryIfExists(
        dirs.baseDir,
        Directory(p.join(stagingDir.path, 'base')),
        diagnostics: diagnostics,
        label: 'base',
      );
      (manifest['items'] as List<String>).add('base');
      diag('base copied files: $baseCount');

      if (!_samePath(dirs.workingDir.path, dirs.baseDir.path)) {
        final workingCount = await _copyDirectoryIfExists(
          dirs.workingDir,
          Directory(p.join(stagingDir.path, 'working')),
          diagnostics: diagnostics,
          label: 'working',
        );
        (manifest['items'] as List<String>).add('working');
        diag('working copied files: $workingCount');
      } else {
        diag('working skipped: same path as base');
      }

      if (!_samePath(databaseDir.path, dirs.baseDir.path) && !_samePath(databaseDir.path, dirs.workingDir.path)) {
        final databaseCount = await _copyDirectoryIfExists(
          databaseDir,
          Directory(p.join(stagingDir.path, 'database')),
          diagnostics: diagnostics,
          label: 'database',
        );
        (manifest['items'] as List<String>).add('database');
        diag('database copied files: $databaseCount');
      } else {
        diag('database skipped: same path as base or working');
      }

      final manifestPath = p.join(stagingDir.path, 'andreyvpn_backup_manifest.json');
      await File(manifestPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      diag('manifest written: $manifestPath');

      final stagingFileCount = await _countFiles(stagingDir);
      diag('staging total files before zip: $stagingFileCount');

      final diagnosticFilePath = p.join(stagingDir.path, 'andreyvpn_backup_diagnostic.log');
      await File(diagnosticFilePath).writeAsString(diagnostics.toString(), flush: true);
      diag('diagnostic log added to staging: $diagnosticFilePath');

      final archivePath = p.join(tempRoot.path, _defaultBackupFileName());
      diag('creating zip: $archivePath');
      final encoder = ZipFileEncoder();
      encoder.create(archivePath);
      encoder.addDirectory(stagingDir, includeDirName: false);
      encoder.close();

      final archiveFile = File(archivePath);
      final archiveSize = await archiveFile.length();
      diag('zip created, size bytes: $archiveSize');
      final backupBytes = await archiveFile.readAsBytes();
      final outputFile = await FilePicker.platform.saveFile(
        fileName: _defaultBackupFileName(),
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: PlatformUtils.isDesktop ? null : backupBytes,
      );

      if (outputFile == null) {
        diag('save cancelled by user');
        await tempRoot.delete(recursive: true);
        return false;
      }

      final outputZipPath = _ensureZipExtension(outputFile);
      diag('selected output zip: $outputZipPath');

      if (PlatformUtils.isDesktop) {
        final file = File(outputZipPath);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(backupBytes, flush: true);
        diag('zip written to selected path, size bytes: ${await file.length()}');
      }

      final outputDiagnosticPath = _diagnosticPathForBackup(outputZipPath);
      await File(outputDiagnosticPath).writeAsString(diagnostics.toString(), flush: true);
      diag('external diagnostic log written: $outputDiagnosticPath');

      await tempRoot.delete(recursive: true);
      notification.showSuccessToast('Полный бэкап экспортирован. Диагностика сохранена рядом с архивом');
      return true;
    } catch (e, st) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] ERROR: $e');
      diagnostics.writeln(st);
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

  Future<int> _copyDirectoryIfExists(
    Directory source,
    Directory destination, {
    StringBuffer? diagnostics,
    String? label,
  }) async {
    void diag(String message) {
      diagnostics?.writeln('[${DateTime.now().toIso8601String()}] $message');
    }

    if (!await source.exists()) {
      diag('${label ?? source.path}: source missing: ${source.path}');
      return 0;
    }

    diag('${label ?? source.path}: source exists: ${source.path}');
    if (!await destination.exists()) await destination.create(recursive: true);

    var copied = 0;
    await for (final entity in source.list(recursive: false, followLinks: false)) {
      final name = p.basename(entity.path);
      if (_shouldSkip(name)) {
        diag('${label ?? source.path}: skipped: ${entity.path}');
        continue;
      }

      final newPath = p.join(destination.path, name);
      if (entity is Directory) {
        copied += await _copyDirectoryIfExists(
          entity,
          Directory(newPath),
          diagnostics: diagnostics,
          label: label == null ? name : '$label/$name',
        );
      } else if (entity is File) {
        await File(newPath).parent.create(recursive: true);
        await entity.copy(newPath);
        copied++;
        diag('${label ?? source.path}: copied file: ${entity.path} -> $newPath');
      } else {
        diag('${label ?? source.path}: ignored non-file entity: ${entity.path}');
      }
    }

    return copied;
  }

  Future<int> _countFiles(Directory directory) async {
    if (!await directory.exists()) return 0;

    var count = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) count++;
    }
    return count;
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

  String _diagnosticPathForBackup(String backupPath) {
    final dir = p.dirname(backupPath);
    final nameWithoutExtension = p.basenameWithoutExtension(backupPath);
    return p.join(dir, '${nameWithoutExtension}_diagnostic.log');
  }
}
