import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/settings/notifier/full_backup_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class BackupPage extends HookConsumerWidget {
  const BackupPage({super.key});

  String _normalizeWindowsPath(String path) {
    if (path.startsWith(r'\\?\')) {
      return path.substring(4);
    }
    return path;
  }

  String _escapePowerShellSingleQuoted(String value) {
    return value.replaceAll("'", "''");
  }

  Future<void> _restartApplication() async {
    final executable = Platform.isWindows ? _normalizeWindowsPath(Platform.resolvedExecutable) : Platform.resolvedExecutable;
    final workingDirectory = File(executable).parent.path;

    if (Platform.isWindows) {
      // Start the new instance after the current process has time to exit.
      // Use PowerShell Start-Process instead of cmd/start to avoid malformed
      // UNC-like paths such as \\?\C:\... and to avoid a visible console window.
      final psExecutable = _escapePowerShellSingleQuoted(executable);
      final psWorkingDirectory = _escapePowerShellSingleQuoted(workingDirectory);
      final command = "Start-Sleep -Milliseconds 900; Start-Process -FilePath '$psExecutable' -WorkingDirectory '$psWorkingDirectory'";

      await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-Command',
          command,
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: workingDirectory,
      );
    } else {
      await Process.start(
        executable,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: workingDirectory,
      );
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
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
