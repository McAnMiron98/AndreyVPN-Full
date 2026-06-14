import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'directories_provider.g.dart';

@Riverpod(keepAlive: true)
class AppDirectories extends _$AppDirectories with InfraLogger {
  final _methodChannel = const MethodChannel("com.hiddify.app/platform");

  @override
  Future<Directories> build() async {
    final Directories dirs;
    if (kIsWeb) {
      return (baseDir: Directory("."), workingDir: Directory("."), tempDir: Directory("."));
    }
    if (PlatformUtils.isIOS) {
      final paths = await _methodChannel.invokeMethod<Map>("get_paths");
      loggy.debug("paths: $paths");
      dirs = (
        baseDir: Directory(paths?["base"]! as String),
        workingDir: Directory(paths?["working"]! as String),
        tempDir: Directory(paths?["temp"]! as String),
      );
    } else if (PlatformUtils.isWindows) {
      final portableDir = getPortableDirectory();
      final tempDir = await getTemporaryDirectory();
      final hasPortableAccess = await checkDirectoryAccess(portableDir);
      if (hasPortableAccess) {
        dirs = (baseDir: portableDir, workingDir: portableDir, tempDir: tempDir);
      } else {
        final baseDir = await getApplicationSupportDirectory();
        dirs = (baseDir: baseDir, workingDir: baseDir, tempDir: tempDir);
      }
      await _writePathDiagnostic(
        selectedDir: dirs.baseDir,
        portableDir: portableDir,
        usedPortable: hasPortableAccess,
        reason: hasPortableAccess ? 'portable directory is writable' : 'portable directory is not writable, fallback to application support',
      );
    } else {
      final baseDir = await getApplicationSupportDirectory();
      final workingDir = Platform.isAndroid ? await getExternalStorageDirectory() : baseDir;
      final tempDir = await getTemporaryDirectory();
      dirs = (baseDir: baseDir, workingDir: workingDir!, tempDir: tempDir);
    }

    if (!dirs.baseDir.existsSync()) {
      await dirs.baseDir.create(recursive: true);
    }
    if (!dirs.workingDir.existsSync()) {
      await dirs.workingDir.create(recursive: true);
    }

    return dirs;
  }

  static Future<Directory> getDatabaseDirectory() async {
    if (kIsWeb) {
      return Directory(".");
    }
    if (PlatformUtils.isIOS || PlatformUtils.isMacOS) {
      return await getLibraryDirectory();
    } else if (PlatformUtils.isWindows) {
      final portableDir = getPortableDirectory();
      if (await checkDirectoryAccess(portableDir)) {
        await _writePathDiagnostic(
          selectedDir: portableDir,
          portableDir: portableDir,
          usedPortable: true,
          reason: 'database directory uses portable directory',
        );
          return portableDir;
      }
      final fallbackDir = await getApplicationSupportDirectory();
      await _writePathDiagnostic(
        selectedDir: fallbackDir,
        portableDir: portableDir,
        usedPortable: false,
        reason: 'database directory fallback: portable directory is not writable',
      );
      return fallbackDir;
    } else if (PlatformUtils.isLinux) {
      return await getApplicationSupportDirectory();
    }
    return await getApplicationDocumentsDirectory();
  }

  static Directory getPortableDirectory() {
    final exeDir = File(Platform.resolvedExecutable).parent;
    return Directory(p.join(exeDir.path, 'andreyvpn_data'));
  }

  static Future<Directory> getLogsDirectory() async {
    final logsDir = Directory(p.join(getPortableDirectory().path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    if (PlatformUtils.isWindows) {
      await _moveLegacyUpdaterLogs(logsDir);
    }
    return logsDir;
  }

  static Future<void> _moveLegacyUpdaterLogs(Directory logsDir) async {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null || localAppData.isEmpty) return;

      final legacyDir = Directory(p.join(localAppData, 'AndreyVPN'));
      if (!await legacyDir.exists()) return;

      final cleanupLog = File(p.join(logsDir.path, 'andreyvpn_updater_cleanup.log'));
      Future<void> log(String message) async {
        await cleanupLog.writeAsString(
          '[${DateTime.now().toIso8601String()}] $message\n',
          mode: FileMode.append,
          flush: true,
        );
      }

      await log('legacy updater log directory found: ${legacyDir.path}');

      const legacyLogNames = [
        'AndreyVPN-update.log',
        'AndreyVPN-updater-launcher.log',
      ];

      for (final name in legacyLogNames) {
        final legacyFile = File(p.join(legacyDir.path, name));
        if (!await legacyFile.exists()) continue;

        final targetFile = File(p.join(logsDir.path, name));
        if (await targetFile.exists()) {
          await targetFile.writeAsString(
            '\n--- moved from legacy AppData at ${DateTime.now().toIso8601String()} ---\n',
            mode: FileMode.append,
            flush: true,
          );
          await targetFile.writeAsString(
            await legacyFile.readAsString(),
            mode: FileMode.append,
            flush: true,
          );
        } else {
          await legacyFile.copy(targetFile.path);
        }
        await legacyFile.delete();
        await log('moved legacy updater log: ${legacyFile.path} -> ${targetFile.path}');
      }

      final remaining = await legacyDir.list(followLinks: false).toList();
      if (remaining.isEmpty) {
        await legacyDir.delete();
        await log('deleted empty legacy updater log directory: ${legacyDir.path}');
      } else {
        await log('legacy updater log directory kept because it is not empty: ${legacyDir.path}');
      }
    } catch (_) {
      // Updater log cleanup must never block application startup.
    }
  }

  static Future<void> _writePathDiagnostic({
    required Directory selectedDir,
    required Directory portableDir,
    required bool usedPortable,
    required String reason,
  }) async {
    try {
      final diagnosticDir = PlatformUtils.isWindows ? await getLogsDirectory() : (usedPortable ? portableDir : selectedDir);
      if (!await diagnosticDir.exists()) {
        await diagnosticDir.create(recursive: true);
      }
      final file = File(p.join(diagnosticDir.path, 'andreyvpn_path_diagnostic.log'));
      final lines = <String>[
        '[${DateTime.now().toIso8601String()}] AndreyVPN path diagnostics',
        'resolvedExecutable: ${Platform.resolvedExecutable}',
        'executableDir: ${File(Platform.resolvedExecutable).parent.path}',
        'portableDir: ${portableDir.path}',
        'selectedDir: ${selectedDir.path}',
        'usedPortable: $usedPortable',
        'reason: $reason',
        'Environment.isPortable: ${Environment.isPortable}',
        '',
      ];
      await file.writeAsString(lines.join('\n'), mode: FileMode.append, flush: true);
    } catch (_) {
      // Path diagnostics must never block application startup.
    }
  }


  static Future<bool> checkDirectoryAccess(Directory dir) async {
    final testFile = File(p.join(dir.path, 'access_test.txt'));

    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      await testFile.writeAsString('Testing write permission...');
      await testFile.readAsString();
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }
}
