import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/app_update/model/remote_version_entity.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class NewVersionDialog extends HookConsumerWidget with PresLogger {
  NewVersionDialog(this.currentVersion, this.newVersion, {super.key, this.canIgnore = true});

  final String currentVersion;
  final RemoteVersionEntity newVersion;
  final bool canIgnore;

  Future<void> _startWindowsPortableUpdate(BuildContext context) async {
    if (!Platform.isWindows || !newVersion.url.toLowerCase().endsWith('.zip')) {
      await UriUtils.tryLaunch(Uri.parse(newVersion.url));
      return;
    }

    final exePath = Platform.resolvedExecutable;
    final appDir = File(exePath).parent.path;
    final updaterPath = '$appDir\\AndreyVPNUpdater.exe';

    if (!await File(updaterPath).exists()) {
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Обновление недоступно'),
            content: Text('Не найден AndreyVPNUpdater.exe рядом с приложением.\n\n$updaterPath'),
            actions: [
              TextButton(onPressed: context.pop, child: const Text('OK')),
            ],
          ),
        );
      }
      return;
    }

    final tempDir = Directory.systemTemp.createTempSync('andreyvpn_updater_');
    final tempUpdaterPath = '${tempDir.path}\\AndreyVPNUpdater.exe';
    await File(updaterPath).copy(tempUpdaterPath);

    final localAppData = Platform.environment['LOCALAPPDATA'] ?? tempDir.path;
    final logDir = Directory('$localAppData\\AndreyVPN');
    await logDir.create(recursive: true);
    final launcherLogPath = '${logDir.path}\\AndreyVPN-updater-launcher.log';

    Future<void> launcherLog(String message) async {
      final now = DateTime.now().toIso8601String();
      await File(launcherLogPath).writeAsString('[$now] $message\r\n', mode: FileMode.append, flush: true);
    }

    await launcherLog('Preparing external updater launch');
    await launcherLog('AppDir=$appDir');
    await launcherLog('ExePath=$exePath');
    await launcherLog('ZipUrl=${newVersion.url}');
    await launcherLog('UpdaterPath=$updaterPath');
    await launcherLog('TempUpdaterPath=$tempUpdaterPath');

    try {
      final process = await Process.start(
        tempUpdaterPath,
        [
          '--appDir',
          appDir,
          '--exePath',
          exePath,
          '--zipUrl',
          newVersion.url,
          '--appPid',
          pid.toString(),
        ],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: tempDir.path,
      );
      await launcherLog('external updater started with pid=${process.pid}');
      await Future<void>.delayed(const Duration(seconds: 1));
      await launcherLog('Closing AndreyVPN so external updater can replace files');
      exit(0);
    } catch (error, stackTrace) {
      await launcherLog('FAILED to launch external updater: $error');
      await launcherLog(stackTrace.toString());
      if (context.mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Не удалось запустить обновление'),
            content: Text('Лог: $launcherLogPath\n\nОшибка: $error'),
            actions: [
              TextButton(onPressed: context.pop, child: const Text('OK')),
            ],
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(t.dialogs.newVersion.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.dialogs.newVersion.msg),
          const Gap(8),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: t.dialogs.newVersion.currentVersion, style: theme.textTheme.bodySmall),
                TextSpan(text: currentVersion, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: t.dialogs.newVersion.newVersion, style: theme.textTheme.bodySmall),
                TextSpan(text: newVersion.presentVersion, style: theme.textTheme.labelMedium),
              ],
            ),
          ),
          if (Platform.isWindows && newVersion.url.toLowerCase().endsWith('.zip')) ...[
            const Gap(8),
            Text(
              'AndreyVPN скачает обновление, закроется, заменит файлы и запустится заново.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
      actions: [
        if (canIgnore)
          TextButton(
            onPressed: () async {
              await ref.read(appUpdateNotifierProvider.notifier).ignoreRelease(newVersion);
              if (context.mounted) context.pop();
            },
            child: Text(t.common.ignore),
          ),
        TextButton(onPressed: context.pop, child: Text(t.common.later)),
        TextButton(
          onPressed: () async {
            await _startWindowsPortableUpdate(context);
          },
          child: Text(t.dialogs.newVersion.updateNow),
        ),
      ],
    );
  }
}
