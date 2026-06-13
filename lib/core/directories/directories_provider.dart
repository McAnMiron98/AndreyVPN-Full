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
      await _cleanupLegacyAppDataArtifacts();
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
        await _cleanupLegacyAppDataArtifacts();
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

  static Future<void> _writePathDiagnostic({
    required Directory selectedDir,
    required Directory portableDir,
    required bool usedPortable,
    required String reason,
  }) async {
    try {
      final diagnosticDir = usedPortable ? portableDir : selectedDir;
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


  static Future<void> _cleanupLegacyAppDataArtifacts() async {
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
