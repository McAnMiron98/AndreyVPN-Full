import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:andreyvpn/core/preferences/preferences_provider.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:andreyvpn/features/settings/notifier/full_backup_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

class BackupPage extends HookConsumerWidget {
  const BackupPage({super.key});

  String _normalizeWindowsPath(String path) {
    if (path.startsWith(r'\\?\')) {
      return path.substring(4);
    }
    return path;
  }

  File _restartDiagnosticFile() {
    if (Platform.isWindows) {
      final logsDir = Directory(p.join(AppDirectories.getPortableDirectory().path, 'logs'));
      return File(p.join(logsDir.path, 'andreyvpn_restart_diagnostic.log'));
    }
    return File(p.join(Directory.systemTemp.path, 'andreyvpn_restart_diagnostic.log'));
  }

  void _appendRestartLog(String message) {
    try {
      final logFile = _restartDiagnosticFile();
      unawaited(
        RotatingFileLog.append(
          logFile,
          '[${DateTime.now().toIso8601String()}] $message\n',
          detailed: true,
        ).catchError((_) {}),
      );
    } catch (_) {
      // Restart logging must never block the restart flow.
    }
  }

  String _escapeBat(String value) {
    return value.replaceAll('%', '%%');
  }

  String _escapeVbs(String value) {
    return value.replaceAll('"', '""');
  }

  Future<void> _restartApplication() async {
    final executable = Platform.isWindows ? _normalizeWindowsPath(Platform.resolvedExecutable) : Platform.resolvedExecutable;
    final workingDirectory = File(executable).parent.path;

    _appendRestartLog('restart requested');
    _appendRestartLog('resolved executable: $executable');
    _appendRestartLog('working directory: $workingDirectory');

    if (Platform.isWindows) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final helperBat = File('${Directory.systemTemp.path}${Platform.pathSeparator}andreyvpn_restart_$timestamp.bat');
      final helperVbs = File('${Directory.systemTemp.path}${Platform.pathSeparator}andreyvpn_restart_$timestamp.vbs');
      final escapedExecutable = _escapeBat(executable);
      final escapedWorkingDirectory = _escapeBat(workingDirectory);
      final escapedLogPath = _escapeBat(_restartDiagnosticFile().path);

      final batContent = '@echo off\r\n'
          'setlocal\r\n'
          'echo [%DATE% %TIME%] restart helper started >> "$escapedLogPath"\r\n'
          'timeout /t 2 /nobreak >nul\r\n'
          'cd /d "$escapedWorkingDirectory"\r\n'
          'echo [%DATE% %TIME%] launching: $escapedExecutable >> "$escapedLogPath"\r\n'
          'start "" "$escapedExecutable"\r\n'
          'echo [%DATE% %TIME%] launch command sent >> "$escapedLogPath"\r\n'
          '(del "%~f0") >nul 2>nul\r\n';
      helperBat.writeAsStringSync(batContent, flush: true);

      final vbsContent = 'Set WshShell = CreateObject("WScript.Shell")\r\n'
          'WshShell.Run """${_escapeVbs(helperBat.path)}""", 0, False\r\n'
          'Set fso = CreateObject("Scripting.FileSystemObject")\r\n'
          'WScript.Sleep 500\r\n'
          'On Error Resume Next\r\n'
          'fso.DeleteFile "${_escapeVbs(helperVbs.path)}", True\r\n';
      helperVbs.writeAsStringSync(vbsContent, flush: true);

      _appendRestartLog('restart helper bat created: ${helperBat.path}');
      _appendRestartLog('restart helper vbs created: ${helperVbs.path}');

      await Process.start(
        'wscript.exe',
        [helperVbs.path],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: Directory.systemTemp.path,
      );
      _appendRestartLog('restart helper launched via wscript');
    } else {
      await Process.start(
        executable,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: workingDirectory,
      );
      _appendRestartLog('non-windows restart process launched');
    }

    await Future<void>.delayed(const Duration(milliseconds: 300));
    await flushPortablePreferences();
    _appendRestartLog('exiting current process');
    exit(0);
  }



  Future<void> _showRestartPrompt(BuildContext context) async {
    final shouldRestart = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Импорт завершён'),
        content: const Text(
          'Для успешного применения восстановленных данных необходимо перезапустить приложение.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Позже'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Перезапустить'),
          ),
        ],
      ),
    );

    if (shouldRestart == true) {
      await _restartApplication();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Бэкап'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              'Полный бэкап сохраняет настройки приложения, профили и рабочие данные AndreyVPN в ZIP-файл.',
            ),
          ),
          const Gap(8),
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: const Text('Экспорт полного бэкапа'),
            subtitle: const Text('Сохранить данные приложения в ZIP-файл'),
            onTap: () async {
              await ref.read(fullBackupNotifierProvider).exportFullBackup();
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded),
            title: const Text('Импорт полного бэкапа'),
            subtitle: const Text('Восстановить данные приложения из ZIP-файла'),
            onTap: () async {
              final shouldImport = await ref.read(dialogNotifierProvider.notifier).showConfirmation(
                    title: 'Импорт полного бэкапа',
                    message:
                        'Текущие данные приложения будут заменены данными из бэкапа. После импорта перезапустите приложение.',
                  );
              if (shouldImport) {
                final imported = await ref.read(fullBackupNotifierProvider).importFullBackup();
                if (imported && context.mounted) {
                  await _showRestartPrompt(context);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
