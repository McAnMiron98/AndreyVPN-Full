import 'dart:io';

import 'package:andreyvpn/core/app_info/app_info_provider.dart';
import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/core/logger/rotating_file_log.dart';
import 'package:andreyvpn/utils/utils.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_start_notifier.g.dart';

@Riverpod(keepAlive: true)
class AutoStartNotifier extends _$AutoStartNotifier with InfraLogger {
  static const _windowsTaskName = 'AndreyVPN';

  @override
  Future<bool> build() async {
    if (!PlatformUtils.isDesktop) return false;
    final appInfo = ref.watch(appInfoProvider).requireValue;
    launchAtStartup.setup(
      appName: appInfo.name,
      appPath: Platform.resolvedExecutable,
      packageName: 'AndreyVPN',
    );
    final isEnabled = await _isEnabled();
    loggy.info('auto start is [${isEnabled ? "Enabled" : "Disabled"}]');
    return isEnabled;
  }

  Future<bool> updateStatus() async {
    loggy.debug('update auto start status');
    final isEnabled = await _isEnabled();
    state = AsyncValue.data(isEnabled);
    return isEnabled;
  }

  Future<void> enable() async {
    loggy.debug('enabling auto start');
    if (Platform.isWindows) {
      await _enableWindowsScheduledTask();
    } else {
      await launchAtStartup.enable();
    }
    state = const AsyncValue.data(true);
  }

  Future<void> disable() async {
    loggy.debug('disabling auto start');
    if (Platform.isWindows) {
      await _disableWindowsScheduledTask();
    } else {
      await launchAtStartup.disable();
    }
    state = const AsyncValue.data(false);
  }

  Future<bool> _isEnabled() async {
    if (Platform.isWindows) {
      final taskEnabled = await _isWindowsScheduledTaskEnabled();
      if (taskEnabled) {
        await _ensureWindowsScheduledTaskIsCurrent();
        return true;
      }

      try {
        final legacyEnabled = await launchAtStartup.isEnabled();
        if (legacyEnabled) {
          await _logWindowsAutoStart('legacy launch_at_startup entry found; attempting migration to scheduled task');
          try {
            await _enableWindowsScheduledTask();
            return true;
          } catch (error) {
            await _logWindowsAutoStart('legacy migration failed: $error');
            return false;
          }
        }
      } catch (_) {
        return false;
      }
      return false;
    }
    return launchAtStartup.isEnabled();
  }

  Future<bool> _isWindowsScheduledTaskEnabled() async {
    final result = await Process.run(
      'schtasks',
      ['/Query', '/TN', _windowsTaskName],
      runInShell: false,
    ).timeout(const Duration(seconds: 5), onTimeout: () => ProcessResult(0, -1, '', 'timeout'));
    await _logWindowsAutoStart('query task exit=${result.exitCode}; stderr=${_singleLine(result.stderr)}');
    return result.exitCode == 0;
  }

  Future<void> _ensureWindowsScheduledTaskIsCurrent() async {
    try {
      final result = await Process.run(
        'schtasks',
        ['/Query', '/TN', _windowsTaskName, '/XML'],
        runInShell: false,
      ).timeout(const Duration(seconds: 5), onTimeout: () => ProcessResult(0, -1, '', 'timeout'));
      final hasAutoStartArgument =
          result.exitCode == 0 && result.stdout.toString().contains('--autostart');
      if (hasAutoStartArgument) return;

      await _logWindowsAutoStart('scheduled task is missing --autostart; updating task action');
      await _enableWindowsScheduledTask();
    } catch (error) {
      await _logWindowsAutoStart('scheduled task action update failed: $error');
    }
  }

  Future<void> _enableWindowsScheduledTask() async {
    final executable = Platform.resolvedExecutable;
    await _logWindowsAutoStart('enable requested; executable=$executable');

    // Avoid duplicate startup entries: the old Run/startup shortcut entry is no
    // longer reliable for elevated AndreyVPN launches, so remove it if present.
    try {
      await launchAtStartup.disable();
      await _logWindowsAutoStart('legacy launch_at_startup entry disabled');
    } catch (error) {
      await _logWindowsAutoStart('legacy launch_at_startup disable skipped/failed: $error');
    }

    final result = await Process.run(
      'schtasks',
      [
        '/Create',
        '/TN',
        _windowsTaskName,
        '/SC',
        'ONLOGON',
        '/RL',
        'HIGHEST',
        '/F',
        '/TR',
        '"$executable" --autostart',
      ],
      runInShell: false,
    ).timeout(const Duration(seconds: 10), onTimeout: () => ProcessResult(0, -1, '', 'timeout'));

    await _logWindowsAutoStart(
      'create task exit=${result.exitCode}; stdout=${_singleLine(result.stdout)}; stderr=${_singleLine(result.stderr)}',
    );
    if (result.exitCode != 0) {
      throw ProcessException('schtasks', ['/Create', '/TN', _windowsTaskName], '${result.stderr}', result.exitCode);
    }
  }

  Future<void> _disableWindowsScheduledTask() async {
    await _logWindowsAutoStart('disable requested');

    final result = await Process.run(
      'schtasks',
      ['/Delete', '/TN', _windowsTaskName, '/F'],
      runInShell: false,
    ).timeout(const Duration(seconds: 10), onTimeout: () => ProcessResult(0, -1, '', 'timeout'));
    await _logWindowsAutoStart(
      'delete task exit=${result.exitCode}; stdout=${_singleLine(result.stdout)}; stderr=${_singleLine(result.stderr)}',
    );

    try {
      await launchAtStartup.disable();
      await _logWindowsAutoStart('legacy launch_at_startup entry disabled');
    } catch (error) {
      await _logWindowsAutoStart('legacy launch_at_startup disable skipped/failed: $error');
    }

    // schtasks returns non-zero when the task does not exist. That is already a
    // disabled state, so do not fail the settings toggle in this case.
  }

  Future<void> _logWindowsAutoStart(String message) async {
    try {
      final logsDir = await AppDirectories.getLogsDirectory();
      final logFile = File('${logsDir.path}\\andreyvpn_autostart.log');
      await RotatingFileLog.append(
        logFile,
        '[${DateTime.now().toIso8601String()}] $message\r\n',
        detailed: true,
      );
    } catch (_) {
      // Auto-start diagnostics must never block application startup/settings.
    }
  }

  String _singleLine(Object? value) => value.toString().replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
}
