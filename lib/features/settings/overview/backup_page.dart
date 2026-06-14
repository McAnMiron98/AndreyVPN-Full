import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/settings/notifier/full_backup_notifier.dart';
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
      logFile.parent.createSync(recursive: true);
      logFile.writeAsStringSync('[${DateTime.now().toIso8601String()}] $message\n', mode: FileMode.append, flush: true);
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
    _appendRestartLog('exiting current process');
    exit(0);
  }



  Future<Directory> _logsDirectory() async {
    return AppDirectories.getLogsDirectory();
  }

  Future<void> _openLogsFolder(BuildContext context) async {
    try {
      final logsDir = await _logsDirectory();
      if (Platform.isWindows) {
        await Process.start('explorer.exe', [logsDir.path], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [logsDir.path], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [logsDir.path], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось открыть папку логов: $e')),
        );
      }
    }
  }

  Future<void> _clearLogsFolder(BuildContext context) async {
    try {
      final logsDir = await _logsDirectory();
      var deleted = 0;
      if (await logsDir.exists()) {
        await for (final entity in logsDir.list(followLinks: false)) {
          try {
            await entity.delete(recursive: true);
            deleted++;
          } catch (_) {}
        }
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Логи очищены. Удалено элементов: $deleted')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось очистить логи: $e')),
        );
      }
    }
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
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: const Text('Открыть папку логов'),
            subtitle: const Text(r'Открыть andreyvpn_data\logs'),
            onTap: () async => _openLogsFolder(context),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_rounded),
            title: const Text('Очистить логи'),
            subtitle: const Text('Удалить только содержимое папки logs'),
            onTap: () async {
              final shouldClear = await ref.read(dialogNotifierProvider.notifier).showConfirmation(
                    title: 'Очистить логи',
                    message: 'Будет удалено только содержимое папки логов. Профили, настройки и бэкапы не изменятся.',
                  );
              if (shouldClear && context.mounted) {
                await _clearLogsFolder(context);
              }
            },
          ),
        ],
      ),
    );
  }
}
