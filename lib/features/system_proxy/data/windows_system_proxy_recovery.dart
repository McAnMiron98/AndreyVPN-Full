import 'dart:io';

import 'package:andreyvpn/core/directories/directories_provider.dart';
import 'package:andreyvpn/utils/utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WindowsSystemProxyRecovery with InfraLogger {
  WindowsSystemProxyRecovery({required this.sharedPreferences});

  static const _internetSettingsKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _proxyEnableName = 'ProxyEnable';
  static const _proxyServerName = 'ProxyServer';
  static const _defaultMixedPort = 12334;

  final SharedPreferences sharedPreferences;

  Future<void> cleanupStaleProxyOnStartup() async {
    if (!Platform.isWindows) return;

    Future<void> diag(String message) async {
      try {
        final logsDir = await AppDirectories.getLogsDirectory();
        final logFile = File('${logsDir.path}\\andreyvpn_system_proxy_recovery.log');
        await logFile.writeAsString(
          '[${DateTime.now().toIso8601String()}] $message\r\n',
          mode: FileMode.append,
          flush: true,
        );
      } catch (_) {
        // Diagnostics must never block application startup.
      }
    }

    try {
      final mixedPort = sharedPreferences.getInt('mixed-port') ?? _defaultMixedPort;
      await diag('startup check started; mixedPort=$mixedPort');

      final proxyEnable = await _queryProxyEnable();
      final proxyServer = await _queryProxyServer();
      await diag('current proxy settings: ProxyEnable=$proxyEnable; ProxyServer=${proxyServer ?? '<empty>'}');

      if (proxyEnable != true) {
        await diag('no cleanup needed: system proxy is not enabled');
        return;
      }

      if (!_looksLikeAndreyVpnProxy(proxyServer, mixedPort)) {
        await diag('no cleanup needed: enabled proxy does not point to AndreyVPN mixed port');
        return;
      }

      await diag('stale AndreyVPN system proxy detected; disabling ProxyEnable');
      await _setProxyEnabled(false);
      await _notifyInternetSettingsChanged();
      await diag('stale system proxy cleanup completed');
      loggy.info('stale AndreyVPN system proxy disabled on startup');
    } catch (error, stackTrace) {
      await diag('startup proxy recovery failed: $error');
      loggy.warning('startup proxy recovery failed', error, stackTrace);
    }
  }

  bool _looksLikeAndreyVpnProxy(String? proxyServer, int mixedPort) {
    if (proxyServer == null || proxyServer.trim().isEmpty) return false;
    final normalized = proxyServer.toLowerCase().replaceAll(' ', '');
    final markers = <String>[
      '127.0.0.1:$mixedPort',
      'localhost:$mixedPort',
      'http=127.0.0.1:$mixedPort',
      'https=127.0.0.1:$mixedPort',
      'socks=127.0.0.1:$mixedPort',
      'http=localhost:$mixedPort',
      'https=localhost:$mixedPort',
      'socks=localhost:$mixedPort',
    ];
    return markers.any(normalized.contains);
  }

  Future<bool?> _queryProxyEnable() async {
    final output = await _regQuery(_proxyEnableName);
    if (output == null) return null;
    final match = RegExp(r'ProxyEnable\s+REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch(output);
    if (match == null) return null;
    final value = int.tryParse(match.group(1)!, radix: 16);
    return value == 1;
  }

  Future<String?> _queryProxyServer() async {
    final output = await _regQuery(_proxyServerName);
    if (output == null) return null;
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+(.+)', multiLine: true).firstMatch(output);
    return match?.group(1)?.trim();
  }

  Future<String?> _regQuery(String valueName) async {
    final result = await Process.run(
      'reg',
      ['query', _internetSettingsKey, '/v', valueName],
      runInShell: false,
    ).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) return null;
    return '${result.stdout}\n${result.stderr}';
  }

  Future<void> _setProxyEnabled(bool enabled) async {
    final result = await Process.run(
      'reg',
      [
        'add',
        _internetSettingsKey,
        '/v',
        _proxyEnableName,
        '/t',
        'REG_DWORD',
        '/d',
        enabled ? '1' : '0',
        '/f',
      ],
      runInShell: false,
    ).timeout(const Duration(seconds: 5));
    if (result.exitCode != 0) {
      throw ProcessException('reg', ['add', _internetSettingsKey, '/v', _proxyEnableName], '${result.stderr}', result.exitCode);
    }
  }

  Future<void> _notifyInternetSettingsChanged() async {
    // Refresh WinINet/Windows proxy cache for apps that read system proxy settings.
    final command = r'''
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class WinInetRefresh {
  [DllImport("wininet.dll", SetLastError = true)]
  public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
}
"@
[WinInetRefresh]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
[WinInetRefresh]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
''';
    try {
      await Process.run(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command],
        runInShell: false,
      ).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Registry cleanup is the critical part. WinINet refresh is best effort.
    }
  }
}
