import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/settings/notifier/full_backup_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class BackupPage extends HookConsumerWidget {
  const BackupPage({super.key});

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
                await ref.read(fullBackupNotifierProvider).importFullBackup();
              }
            },
          ),
        ],
      ),
    );
  }
}
