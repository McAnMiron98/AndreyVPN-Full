import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/app_info/app_info_provider.dart';
import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:andreyvpn/core/notification/in_app_notification_controller.dart';
import 'package:andreyvpn/utils/custom_loggers.dart';
import 'package:andreyvpn/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

final fullBackupNotifierProvider = Provider<FullBackupNotifier>((ref) {
  return FullBackupNotifier(ref);
});

class FullBackupNotifier with AppLogger {
  FullBackupNotifier(this.ref);

  final Ref ref;

  static Future<void> processPendingRestoreIfNeeded() async {
    final diagnostics = StringBuffer();

    void diag(String message) {
      final line = '[${DateTime.now().toIso8601String()}] $message';
      diagnostics.writeln(line);
    }

    File? diagnosticFile;

    try {
      diag('AndreyVPN pending restore startup check started');

      final baseDir = await AppDirectories.getDatabaseDirectory();
      final pendingFile = File(p.join(baseDir.path, 'andreyvpn_pending_restore.json'));
      final pendingRoot = Directory(p.join(baseDir.path, 'andreyvpn_pending_restore'));
      final logsDir = await AppDirectories.getLogsDirectory();
      diagnosticFile = File(p.join(logsDir.path, 'andreyvpn_pending_restore_diagnostic.log'));

      diag('baseDir: ${baseDir.path}');
      diag('pendingFile: ${pendingFile.path}');
      diag('pendingRoot: ${pendingRoot.path}');

      if (!await pendingFile.exists()) {
        diag('pending restore manifest missing, nothing to restore');
        await RotatingFileLog.write(diagnosticFile, diagnostics.toString(), detailed: true);
        return;
      }

      if (!await pendingRoot.exists()) {
        diag('pending restore directory missing, deleting manifest');
        await pendingFile.delete();
        await RotatingFileLog.write(diagnosticFile, diagnostics.toString(), detailed: true);
        return;
      }

      diag('pending restore manifest content: ${await pendingFile.readAsString()}');

      final baseBackup = Directory(p.join(pendingRoot.path, 'base'));
      final workingBackup = Directory(p.join(pendingRoot.path, 'working'));
      final databaseBackup = Directory(p.join(pendingRoot.path, 'database'));

      await _logExpectedRestoreStateStatic(baseBackup, diagnostics, label: 'pending/source/base before startup restore');
      await _logExpectedRestoreStateStatic(baseDir, diagnostics, label: 'target/base before startup restore');

      if (await baseBackup.exists()) {
        final count = await _copyDirectoryIfExistsStatic(
          baseBackup,
          baseDir,
          diagnostics: diagnostics,
          label: 'startup_restore/base',
        );
        diag('startup base restored files: $count');
      } else {
        diag('startup base backup missing');
      }

      if (await workingBackup.exists()) {
        final count = await _copyDirectoryIfExistsStatic(
          workingBackup,
          baseDir,
          diagnostics: diagnostics,
          label: 'startup_restore/working',
        );
        diag('startup working restored files: $count');
      } else {
        diag('startup working backup missing');
      }

      final databaseDir = await AppDirectories.getDatabaseDirectory();
      if (await databaseBackup.exists()) {
        final count = await _copyDirectoryIfExistsStatic(
          databaseBackup,
          databaseDir,
          diagnostics: diagnostics,
          label: 'startup_restore/database',
        );
        diag('startup database restored files: $count');
      } else {
        diag('startup database backup missing');
      }

      await _logExpectedRestoreStateStatic(baseDir, diagnostics, label: 'target/base after startup restore');

      await pendingFile.delete();
      diag('pending restore manifest deleted');

      await pendingRoot.delete(recursive: true);
      diag('pending restore directory deleted');

      await RotatingFileLog.write(diagnosticFile, diagnostics.toString(), detailed: true);
    } catch (e, st) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] ERROR: $e');
      diagnostics.writeln(st);
      if (diagnosticFile != null) {
        try {
          await RotatingFileLog.write(diagnosticFile, diagnostics.toString(), detailed: true);
        } catch (_) {}
      }
    }
  }

  static Future<int> _copyDirectoryIfExistsStatic(
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
      if (_shouldSkipStatic(name)) {
        diag('${label ?? source.path}: skipped: ${entity.path}');
        continue;
      }

      final newPath = p.join(destination.path, name);
      if (entity is Directory) {
        copied += await _copyDirectoryIfExistsStatic(
          entity,
          Directory(newPath),
          diagnostics: diagnostics,
          label: label == null ? name : '$label/$name',
        );
      } else if (entity is File) {
        await _copyFileWithOverwriteStatic(
          entity,
          File(newPath),
          diagnostics: diagnostics,
          label: label ?? source.path,
        );
        copied++;
      } else {
        diag('${label ?? source.path}: ignored non-file entity: ${entity.path}');
      }
    }

    return copied;
  }

  static Future<void> _copyFileWithOverwriteStatic(
    File source,
    File destination, {
    StringBuffer? diagnostics,
    String? label,
  }) async {
    void diag(String message) {
      diagnostics?.writeln('[${DateTime.now().toIso8601String()}] $message');
    }

    await destination.parent.create(recursive: true);

    if (await destination.exists()) {
      final oldSize = await destination.length();
      diag('${label ?? source.path}: overwriting existing file: ${destination.path} (old size bytes: $oldSize)');
      await destination.delete();
    } else {
      diag('${label ?? source.path}: target file does not exist, creating: ${destination.path}');
    }

    await source.copy(destination.path);
    final newSize = await destination.length();
    diag('${label ?? source.path}: copied file: ${source.path} -> ${destination.path} (new size bytes: $newSize)');
  }

  static Future<void> _logExpectedRestoreStateStatic(
    Directory root,
    StringBuffer diagnostics, {
    required String label,
  }) async {
    final expectedFiles = <String>[
      'db.sqlite',
      'shared_preferences.json',
      p.join('data', 'clash.db'),
      p.join('data', 'current-config.json'),
    ];

    diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label root: ${root.path}');
    for (final relativePath in expectedFiles) {
      final file = File(p.join(root.path, relativePath));
      if (await file.exists()) {
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: $relativePath exists, size bytes: ${await file.length()}');
      } else {
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: $relativePath missing');
      }
    }

    final appSettingsDir = Directory(p.join(root.path, 'data', 'AppSettings.db'));
    if (await appSettingsDir.exists()) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: data/AppSettings.db exists, files: ${await _countFilesStatic(appSettingsDir)}');
    } else {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: data/AppSettings.db missing');
    }
  }

  static Future<int> _countFilesStatic(Directory directory) async {
    if (!await directory.exists()) return 0;

    var count = 0;
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) count++;
    }
    return count;
  }

  static bool _shouldSkipStatic(String name) {
    return name == 'access_test.txt' ||
        name == 'app.log' ||
        name == 'box.log' ||
        name == 'goroutine-start.log' ||
        name == 'andreyvpn_pending_restore' ||
        name == 'logs' ||
        name == 'andreyvpn_pending_restore.json' ||
        name == 'andreyvpn_pending_restore_diagnostic.log' ||
        name == 'pending_restore.json' ||
        name == 'andreyvpn_backup_diagnostic.log' ||
        name == 'andreyvpn_import_diagnostic.log' ||
        name.endsWith('_diagnostic.log') ||
        name.endsWith('_import_diagnostic.log') ||
        name.endsWith('-journal') ||
        name.endsWith('-shm') ||
        name.endsWith('-wal') ||
        name == 'Cache' ||
        name == 'cache';
  }


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
        'appVersion': ref.read(appInfoProvider).requireValue.presentVersion,
        'type': 'full_backup',
        'format': 2,
        'diagnostic': true,
        'createdAt': DateTime.now().toIso8601String(),
        'items': <String>[],
        'fileCount': 0,
        'backupSizeBytes': 0,
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
      final archivePath = p.join(tempRoot.path, _defaultBackupFileName());
      final archiveFile = File(archivePath);

      final stagingFileCount = await _countFiles(stagingDir);
      manifest['fileCount'] = stagingFileCount + 1; // manifest
      await File(manifestPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      diag('manifest written: $manifestPath');
      diag('staging total files before zip: ${await _countFiles(stagingDir)}');

      diag('creating zip: $archivePath');
      var zipEntryCount = await _createZipFromDirectory(stagingDir, archiveFile, diagnostics);
      var archiveSize = await archiveFile.length();

      manifest['fileCount'] = zipEntryCount;
      manifest['backupSizeBytes'] = archiveSize;
      await File(manifestPath).writeAsString(
        const JsonEncoder.withIndent('  ').convert(manifest),
      );
      diag('manifest updated with file count and first-pass zip size');

      zipEntryCount = await _createZipFromDirectory(stagingDir, archiveFile, diagnostics);
      archiveSize = await archiveFile.length();
      diag('zip created, size bytes: $archiveSize');
      diag('zip entries written: $zipEntryCount');
      final backupBytes = await archiveFile.readAsBytes();
      final decodedArchive = ZipDecoder().decodeBytes(backupBytes);
      diag('zip entries decoded after creation: ${decodedArchive.files.length}');
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

      await _cleanupExternalLevelDbDataFolder(outputZipPath, diagnostics);

      final outputDiagnosticPath = await _diagnosticPathForBackup(outputZipPath);
      await RotatingFileLog.write(File(outputDiagnosticPath), diagnostics.toString(), detailed: true);
      diag('diagnostic log written to logs folder: $outputDiagnosticPath');

      await tempRoot.delete(recursive: true);
      notification.showSuccessToast(
        RotatingFileLog.detailedEnabled
            ? 'Полный бэкап экспортирован. Диагностика сохранена в папке логов'
            : 'Полный бэкап экспортирован',
      );
      return true;
    } catch (e, st) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] ERROR: $e');
      diagnostics.writeln(st);
      loggy.warning('error exporting full backup', e, st);
      notification.showErrorToast('Не удалось экспортировать полный бэкап');
      return false;
    }
  }
  Future<void> _cleanupExternalLevelDbDataFolder(String outputZipPath, StringBuffer diagnostics) async {
    void diag(String message) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] $message');
    }

    try {
      if (!PlatformUtils.isWindows) return;

      final outputDir = File(outputZipPath).parent;
      final possibleDataDir = Directory(p.join(outputDir.path, 'data'));
      final possibleAppSettingsDir = Directory(p.join(possibleDataDir.path, 'AppSettings.db'));

      if (!await possibleDataDir.exists() || !await possibleAppSettingsDir.exists()) {
        diag('external cleanup: no sibling data/AppSettings.db folder found near backup');
        return;
      }

      // Never touch Flutter runtime data folders.
      final protectedRuntimeFiles = <String>[
        'flutter_assets',
        'app.so',
        'icudtl.dat',
      ];
      for (final name in protectedRuntimeFiles) {
        if (await File(p.join(possibleDataDir.path, name)).exists() ||
            await Directory(p.join(possibleDataDir.path, name)).exists()) {
          diag('external cleanup: skipped because sibling data folder looks like Flutter runtime data: ${possibleDataDir.path}');
          return;
        }
      }

      // Only remove the AppSettings.db folder if the sibling data folder contains no other real items.
      final dataItems = await possibleDataDir.list(followLinks: false).toList();
      final hasOnlyAppSettings = dataItems.every((entity) => p.basename(entity.path) == 'AppSettings.db');
      if (!hasOnlyAppSettings) {
        diag('external cleanup: skipped because sibling data folder contains other files: ${possibleDataDir.path}');
        return;
      }

      await possibleAppSettingsDir.delete(recursive: true);
      diag('external cleanup: deleted temporary sibling AppSettings.db folder: ${possibleAppSettingsDir.path}');

      final remainingItems = await possibleDataDir.list(followLinks: false).toList();
      if (remainingItems.isEmpty) {
        await possibleDataDir.delete();
        diag('external cleanup: deleted empty temporary sibling data folder: ${possibleDataDir.path}');
      }
    } catch (e, st) {
      diag('external cleanup error: $e');
      diagnostics.writeln(st);
    }
  }


  Future<bool> importFullBackup() async {
    final notification = ref.read(inAppNotificationControllerProvider);
    final diagnostics = StringBuffer();
    String? outputDiagnosticPath;
    Directory? tempRoot;

    void diag(String message) {
      final line = '[${DateTime.now().toIso8601String()}] $message';
      diagnostics.writeln(line);
      loggy.info(line);
    }

    Future<void> writeImportDiagnostics() async {
      if (outputDiagnosticPath == null) return;
      try {
        final diagnosticFile = File(outputDiagnosticPath!);
        await diagnosticFile.parent.create(recursive: true);
        await RotatingFileLog.write(diagnosticFile, diagnostics.toString(), detailed: true);
      } catch (e, st) {
        loggy.warning('error writing import diagnostic log', e, st);
      }
    }

    try {
      diag('AndreyVPN full backup import started');
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
      if (result == null || result.files.single.path == null) {
        diag('import cancelled by user');
        return false;
      }

      final backupFile = File(result.files.single.path!);
      outputDiagnosticPath = await _diagnosticPathForImport(backupFile.path);
      diag('selected backup zip: ${backupFile.path}');
      diag('import diagnostic path: $outputDiagnosticPath');

      if (!await backupFile.exists()) {
        diag('selected backup zip does not exist');
        await writeImportDiagnostics();
        return false;
      }
      diag('selected backup zip size bytes: ${await backupFile.length()}');

      final dirs = await ref.read(appDirectoriesProvider.future);
      final databaseDir = await AppDirectories.getDatabaseDirectory();
      tempRoot = Directory(p.join(dirs.tempDir.path, 'andreyvpn_restore_${const Uuid().v4()}'));
      await tempRoot.create(recursive: true);

      diag('baseDir target: ${dirs.baseDir.path}');
      diag('workingDir target: ${dirs.workingDir.path}');
      diag('databaseDir target: ${databaseDir.path}');
      diag('tempRoot: ${tempRoot.path}');

      final bytes = await backupFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      diag('zip entries decoded before extract: ${archive.files.length}');
      for (final file in archive.files) {
        diag('zip entry: ${file.name} (${file.size} bytes)');
      }

      final extractedCount = await _extractArchiveToDirectory(archive, tempRoot, diagnostics);
      diag('archive extracted to tempRoot with manual extractor');
      diag('extracted files count: ${await _countFiles(tempRoot)}');
      diag('manual extracted files count: $extractedCount');

      final manifest = File(p.join(tempRoot.path, 'andreyvpn_backup_manifest.json'));
      if (!await manifest.exists()) {
        throw const FormatException('Invalid AndreyVPN backup: manifest not found');
      }
      diag('manifest found: ${manifest.path}');
      diag('manifest content: ${await manifest.readAsString()}');

      final baseBackup = Directory(p.join(tempRoot.path, 'base'));
      final workingBackup = Directory(p.join(tempRoot.path, 'working'));
      final databaseBackup = Directory(p.join(tempRoot.path, 'database'));

      await _logExpectedRestoreState(baseBackup, diagnostics, label: 'source/base expected files before deferred restore');
      await _logExpectedRestoreState(dirs.baseDir, diagnostics, label: 'target/base expected files before deferred restore');

      final pendingRoot = Directory(p.join(dirs.baseDir.path, 'andreyvpn_pending_restore'));
      final pendingFile = File(p.join(dirs.baseDir.path, 'andreyvpn_pending_restore.json'));

      if (await pendingRoot.exists()) {
        diag('removing previous pending restore directory: ${pendingRoot.path}');
        await pendingRoot.delete(recursive: true);
      }
      await pendingRoot.create(recursive: true);

      final stagedCount = await _copyDirectoryIfExists(
        tempRoot,
        pendingRoot,
        diagnostics: diagnostics,
        label: 'stage/pending_restore',
      );
      diag('pending restore staged files: $stagedCount');

      final pendingManifest = <String, dynamic>{
        'app': 'AndreyVPN',
        'appVersion': ref.read(appInfoProvider).requireValue.presentVersion,
        'type': 'pending_restore',
        'format': 1,
        'createdAt': DateTime.now().toIso8601String(),
        'sourceBackupPath': backupFile.path,
        'stagedRoot': pendingRoot.path,
        'baseTarget': dirs.baseDir.path,
        'workingTarget': dirs.workingDir.path,
        'databaseTarget': databaseDir.path,
        'items': <String>[
          if (await baseBackup.exists()) 'base',
          if (await workingBackup.exists()) 'working',
          if (await databaseBackup.exists()) 'database',
        ],
        'stagedFileCount': stagedCount,
      };

      await pendingFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert(pendingManifest),
        flush: true,
      );
      diag('pending restore manifest written: ${pendingFile.path}');
      diag('pending restore will be applied on next application start before live databases are opened');

      await tempRoot.delete(recursive: true);
      tempRoot = null;
      diag('tempRoot deleted');
      await writeImportDiagnostics();
      notification.showSuccessToast('Бэкап подготовлен к восстановлению. Закройте и снова запустите приложение');
      return true;
    } catch (e, st) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] ERROR: $e');
      diagnostics.writeln(st);
      loggy.warning('error importing full backup', e, st);
      if (tempRoot != null && await tempRoot.exists()) {
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] tempRoot kept for diagnostics: ${tempRoot.path}');
      }
      await writeImportDiagnostics();
      notification.showErrorToast(
        RotatingFileLog.detailedEnabled
            ? 'Не удалось импортировать полный бэкап. Диагностика сохранена в папке логов'
            : 'Не удалось импортировать полный бэкап',
      );
      return false;
    }
  }


  Future<int> _extractArchiveToDirectory(
    Archive archive,
    Directory destination,
    StringBuffer diagnostics,
  ) async {
    await destination.create(recursive: true);
    var extracted = 0;

    for (final entry in archive.files) {
      final rawName = entry.name.replaceAll('\\', '/');
      final normalizedName = p.posix.normalize(rawName);

      if (normalizedName == '.' ||
          normalizedName.startsWith('../') ||
          p.posix.isAbsolute(normalizedName)) {
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] extract skipped unsafe entry: ${entry.name}');
        continue;
      }

      final destinationPath = p.joinAll([
        destination.path,
        ...normalizedName.split('/').where((part) => part.isNotEmpty),
      ]);

      if (entry.isFile) {
        final outFile = File(destinationPath);
        await outFile.parent.create(recursive: true);
        final content = entry.content as List<int>;
        await outFile.writeAsBytes(content, flush: true);
        extracted++;
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] extract file: ${entry.name} -> $destinationPath (${content.length} bytes)');
      } else {
        await Directory(destinationPath).create(recursive: true);
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] extract directory: ${entry.name} -> $destinationPath');
      }
    }

    return extracted;
  }

  Future<void> _logExpectedRestoreState(
    Directory root,
    StringBuffer diagnostics, {
    required String label,
  }) async {
    final expectedFiles = <String>[
      'db.sqlite',
      'shared_preferences.json',
      p.join('data', 'clash.db'),
      p.join('data', 'current-config.json'),
    ];

    diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label root: ${root.path}');
    for (final relativePath in expectedFiles) {
      final file = File(p.join(root.path, relativePath));
      if (await file.exists()) {
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: $relativePath exists, size bytes: ${await file.length()}');
      } else {
        diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: $relativePath missing');
      }
    }

    final appSettingsDir = Directory(p.join(root.path, 'data', 'AppSettings.db'));
    if (await appSettingsDir.exists()) {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: data/AppSettings.db exists, files: ${await _countFiles(appSettingsDir)}');
    } else {
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] $label: data/AppSettings.db missing');
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
        await _copyFileWithOverwrite(
          entity,
          File(newPath),
          diagnostics: diagnostics,
          label: label ?? source.path,
        );
        copied++;
      } else {
        diag('${label ?? source.path}: ignored non-file entity: ${entity.path}');
      }
    }

    return copied;
  }


  Future<void> _copyFileWithOverwrite(
    File source,
    File destination, {
    StringBuffer? diagnostics,
    String? label,
  }) async {
    void diag(String message) {
      diagnostics?.writeln('[${DateTime.now().toIso8601String()}] $message');
    }

    await destination.parent.create(recursive: true);

    if (await destination.exists()) {
      final oldSize = await destination.length();
      diag('${label ?? source.path}: overwriting existing file: ${destination.path} (old size bytes: $oldSize)');
      await destination.delete();
    } else {
      diag('${label ?? source.path}: target file does not exist, creating: ${destination.path}');
    }

    await source.copy(destination.path);
    final newSize = await destination.length();
    diag('${label ?? source.path}: copied file: ${source.path} -> ${destination.path} (new size bytes: $newSize)');
  }


  Future<int> _createZipFromDirectory(
    Directory source,
    File destination,
    StringBuffer diagnostics,
  ) async {
    if (!await source.exists()) {
      throw StateError('Backup staging directory does not exist: ${source.path}');
    }

    final files = await _listFilesRecursive(source);
    diagnostics.writeln('[${DateTime.now().toIso8601String()}] zip source files discovered: ${files.length}');

    final archive = Archive();
    for (final file in files) {
      final relativePath = p.relative(file.path, from: source.path).replaceAll('\\', '/');
      final bytes = await file.readAsBytes();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      diagnostics.writeln('[${DateTime.now().toIso8601String()}] zip add file: $relativePath (${bytes.length} bytes)');
    }

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) {
      throw StateError('ZIP encoder returned null');
    }

    await destination.parent.create(recursive: true);
    await destination.writeAsBytes(zipBytes, flush: true);
    return files.length;
  }

  Future<List<File>> _listFilesRecursive(Directory directory) async {
    final files = <File>[];
    await for (final entity in directory.list(recursive: true, followLinks: false)) {
      if (entity is File) files.add(entity);
    }
    files.sort((a, b) => a.path.compareTo(b.path));
    return files;
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
        name == 'app.log' ||
        name == 'box.log' ||
        name == 'goroutine-start.log' ||
        name == 'andreyvpn_pending_restore' ||
        name == 'logs' ||
        name == 'andreyvpn_pending_restore.json' ||
        name == 'andreyvpn_pending_restore_diagnostic.log' ||
        name == 'pending_restore.json' ||
        name == 'andreyvpn_backup_diagnostic.log' ||
        name == 'andreyvpn_import_diagnostic.log' ||
        name.endsWith('_diagnostic.log') ||
        name.endsWith('_import_diagnostic.log') ||
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

  Future<String> _diagnosticPathForBackup(String backupPath) async {
    final logsDir = await AppDirectories.getLogsDirectory();
    final nameWithoutExtension = p.basenameWithoutExtension(backupPath);
    return p.join(logsDir.path, '${nameWithoutExtension}_backup_diagnostic.log');
  }

  Future<String> _diagnosticPathForImport(String backupPath) async {
    final logsDir = await AppDirectories.getLogsDirectory();
    final nameWithoutExtension = p.basenameWithoutExtension(backupPath);
    return p.join(logsDir.path, '${nameWithoutExtension}_import_diagnostic.log');
  }

}
