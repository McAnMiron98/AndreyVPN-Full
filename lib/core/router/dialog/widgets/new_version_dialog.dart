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
    final tempDir = Directory.systemTemp.createTempSync('andreyvpn_update_');
    final scriptPath = '${tempDir.path}\\andreyvpn_update.ps1';
    final currentPid = pid;

    final script = r'''
param(
  [Parameter(Mandatory=$true)][string]$AppDir,
  [Parameter(Mandatory=$true)][string]$ExePath,
  [Parameter(Mandatory=$true)][string]$ZipUrl,
  [Parameter(Mandatory=$true)][int]$AppPid
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
$WorkDir = Join-Path $env:TEMP ("AndreyVPN_Update_" + [guid]::NewGuid().ToString())
$ZipPath = Join-Path $WorkDir "AndreyVPN-update.zip"
$ExtractDir = Join-Path $WorkDir "extract"
$LogPath = Join-Path $env:TEMP "AndreyVPN-update.log"

function Write-UpdateLog($Message) {
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $LogPath -Value "[$stamp] $Message"
}

try {
  Write-UpdateLog "Starting AndreyVPN update"
  Write-UpdateLog "AppDir=$AppDir"
  Write-UpdateLog "ExePath=$ExePath"
  Write-UpdateLog "ZipUrl=$ZipUrl"

  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

  Write-UpdateLog "Downloading update zip"
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing

  Write-UpdateLog "Waiting for AndreyVPN to close"
  try {
    Wait-Process -Id $AppPid -Timeout 60 -ErrorAction SilentlyContinue
  } catch {
    Write-UpdateLog "Wait-Process finished with warning: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds 2

  Write-UpdateLog "Extracting update zip"
  Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

  $SourceDir = $ExtractDir
  $NestedDirs = Get-ChildItem -Path $ExtractDir -Directory
  if ($NestedDirs.Count -eq 1 -and (Test-Path (Join-Path $NestedDirs[0].FullName "AndreyVPN.exe"))) {
    $SourceDir = $NestedDirs[0].FullName
  }

  if (-not (Test-Path (Join-Path $SourceDir "AndreyVPN.exe"))) {
    throw "AndreyVPN.exe was not found inside downloaded update archive."
  }

  Write-UpdateLog "Copying files from $SourceDir to $AppDir"
  Copy-Item -Path (Join-Path $SourceDir "*") -Destination $AppDir -Recurse -Force

  Write-UpdateLog "Starting updated AndreyVPN"
  Start-Process -FilePath $ExePath -WorkingDirectory $AppDir

  Write-UpdateLog "Update completed successfully"
} catch {
  Write-UpdateLog "Update failed: $($_.Exception.Message)"
  [System.Windows.MessageBox]::Show("AndreyVPN update failed. Log: $LogPath", "AndreyVPN Update", "OK", "Error") | Out-Null
} finally {
  try { Remove-Item -Path $WorkDir -Recurse -Force -ErrorAction SilentlyContinue } catch {}
}
''';

    await File(scriptPath).writeAsString(script);
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptPath,
        '-AppDir',
        appDir,
        '-ExePath',
        exePath,
        '-ZipUrl',
        newVersion.url,
        '-AppPid',
        currentPid.toString(),
      ],
      mode: ProcessStartMode.detached,
      runInShell: false,
    );

    exit(0);
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
