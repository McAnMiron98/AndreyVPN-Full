import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:andreyvpn/core/preferences/general_preferences.dart';
import 'package:andreyvpn/core/router/dialog/dialog_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LogsPage extends HookConsumerWidget {
  const LogsPage({super.key});

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
          } catch (_) {
            // Best-effort cleanup: locked files are skipped.
          }
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Логи'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Text(
              r'Диагностические логи AndreyVPN хранятся в папке andreyvpn_data\logs.',
            ),
          ),
          const Gap(8),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.tune_rounded),
            title: const Text('Подробная диагностика'),
            subtitle: const Text('Записывать расширенные технические логи. Обычно не требуется'),
            value: ref.watch(Preferences.detailedDiagnostics),
            onChanged: (value) async {
              RotatingFileLog.detailedEnabled = value;
              await ref.read(Preferences.detailedDiagnostics.notifier).update(value);
            },
          ),
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
