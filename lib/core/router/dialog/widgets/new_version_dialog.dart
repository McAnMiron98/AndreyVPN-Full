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
    final tempDir = Directory.systemTemp.createTempSync('andreyvpn_update_');
    final scriptPath = '${tempDir.path}\\andreyvpn_update_visible.ps1';
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

$LogDir = Join-Path $env:LOCALAPPDATA "AndreyVPN"
$LogPath = Join-Path $LogDir "AndreyVPN-update.log"
$WorkDir = Join-Path $env:TEMP ("AndreyVPN_Update_" + [guid]::NewGuid().ToString())
$ZipPath = Join-Path $WorkDir "AndreyVPN-update.zip"
$ExtractDir = Join-Path $WorkDir "extract"

function Write-UpdateLog($Message) {
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$stamp] $Message"
  Write-Host $line
  Add-Content -Path $LogPath -Value $line
}

try {
  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

  Write-UpdateLog "=== AndreyVPN updater started ==="
  Write-UpdateLog "AppDir=$AppDir"
  Write-UpdateLog "ExePath=$ExePath"
  Write-UpdateLog "ZipUrl=$ZipUrl"
  Write-UpdateLog "AppPid=$AppPid"

  Write-UpdateLog "Downloading update zip..."
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
  Write-UpdateLog "Download completed: $ZipPath"

  Write-UpdateLog "Waiting for AndreyVPN to close..."
  try {
    Wait-Process -Id $AppPid -Timeout 120 -ErrorAction SilentlyContinue
  } catch {
    Write-UpdateLog "Wait-Process warning: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds 3

  Write-UpdateLog "Extracting update zip..."
  Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

  $SourceDir = $ExtractDir

  if (-not (Test-Path (Join-Path $SourceDir "AndreyVPN.exe"))) {
    $InnerZip = Get-ChildItem -Path $ExtractDir -Recurse -File | Where-Object {
      $_.Name.ToLower().EndsWith(".zip") -and $_.Name.ToLower().Contains("windows") -and $_.Name.ToLower().Contains("portable")
    } | Select-Object -First 1

    if ($InnerZip) {
      Write-UpdateLog "Found nested portable zip: $($InnerZip.FullName)"
      $NestedExtractDir = Join-Path $WorkDir "nested_extract"
      New-Item -ItemType Directory -Force -Path $NestedExtractDir | Out-Null
      Expand-Archive -Path $InnerZip.FullName -DestinationPath $NestedExtractDir -Force
      $SourceDir = $NestedExtractDir
    }
  }

  if (-not (Test-Path (Join-Path $SourceDir "AndreyVPN.exe"))) {
    $CandidateDirs = Get-ChildItem -Path $SourceDir -Recurse -Directory | Where-Object {
      Test-Path (Join-Path $_.FullName "AndreyVPN.exe")
    }
    if ($CandidateDirs.Count -gt 0) {
      $SourceDir = $CandidateDirs[0].FullName
      Write-UpdateLog "Using nested source dir: $SourceDir"
    }
  }

  if (-not (Test-Path (Join-Path $SourceDir "AndreyVPN.exe"))) {
    Write-UpdateLog "AndreyVPN.exe was not found. Extracted tree:"
    Get-ChildItem -Path $ExtractDir -Recurse | ForEach-Object { Write-UpdateLog $_.FullName }
    throw "AndreyVPN.exe was not found inside downloaded update archive."
  }

  Write-UpdateLog "SourceDir=$SourceDir"
  Write-UpdateLog "Replacing files with robocopy..."
  $robocopyArgs = @($SourceDir, $AppDir, "/E", "/COPY:DAT", "/R:10", "/W:1", "/NP")
  & robocopy @robocopyArgs
  $code = $LASTEXITCODE
  Write-UpdateLog "Robocopy exit code: $code"
  if ($code -ge 8) {
    throw "Robocopy failed with exit code $code"
  }

  $UpdatedExe = Join-Path $AppDir "AndreyVPN.exe"
  if (-not (Test-Path $UpdatedExe)) {
    throw "Updated AndreyVPN.exe not found at $UpdatedExe"
  }

  Write-UpdateLog "Starting updated AndreyVPN..."
  Start-Process -FilePath $UpdatedExe -WorkingDirectory $AppDir
  Write-UpdateLog "=== Update completed successfully ==="
  Write-Host ""
  Write-Host "Update completed. You can close this window."
} catch {
  Write-UpdateLog "UPDATE FAILED: $($_.Exception.Message)"
  try {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("AndreyVPN update failed.`n`nLog: $LogPath", "AndreyVPN Update", "OK", "Error") | Out-Null
  } catch {}
  Write-Host ""
  Write-Host "Update failed. Log: $LogPath"
  Write-Host "Press Enter to close this window."
  Read-Host | Out-Null
} finally {
  Write-UpdateLog "WorkDir kept for diagnostics: $WorkDir"
}
''';

    await File(scriptPath).writeAsString(script);

    final localAppData = Platform.environment['LOCALAPPDATA'] ?? tempDir.path;
    final logDir = Directory('$localAppData\\AndreyVPN');
    await logDir.create(recursive: true);
    final launcherLogPath = '${logDir.path}\\AndreyVPN-updater-launcher.log';
    final launcherScriptPath = '${tempDir.path}\\andreyvpn_update_launcher.cmd';

    Future<void> launcherLog(String message) async {
      final now = DateTime.now().toIso8601String();
      await File(launcherLogPath).writeAsString('[$now] $message\r\n', mode: FileMode.append, flush: true);
    }

    await launcherLog('Preparing updater launch');
    await launcherLog('AppDir=$appDir');
    await launcherLog('ExePath=$exePath');
    await launcherLog('ZipUrl=${newVersion.url}');
    await launcherLog('ScriptPath=$scriptPath');

    final launcherScript = '''@echo off
setlocal
set LOGDIR=%LOCALAPPDATA%\\AndreyVPN
if not exist "%LOGDIR%" mkdir "%LOGDIR%"
set LOG=%LOGDIR%\\AndreyVPN-updater-launcher.log
echo [%date% %time%] CMD launcher started>>"%LOG%"
echo [%date% %time%] Running PowerShell updater>>"%LOG%"
title AndreyVPN Updater
powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "${scriptPath}" -AppDir "${appDir}" -ExePath "${exePath}" -ZipUrl "${newVersion.url}" -AppPid ${currentPid}
echo [%date% %time%] PowerShell finished with code %ERRORLEVEL%>>"%LOG%"
echo.
echo AndreyVPN updater finished. If the application did not restart, check:
echo %LOGDIR%\\AndreyVPN-update.log
echo %LOGDIR%\\AndreyVPN-updater-launcher.log
echo.
pause
''';
    await File(launcherScriptPath).writeAsString(launcherScript);
    await launcherLog('LauncherScriptPath=$launcherScriptPath');

    try {
      final process = await Process.start(
        launcherScriptPath,
        const [],
        mode: ProcessStartMode.detached,
        runInShell: true,
        workingDirectory: tempDir.path,
      );
      await launcherLog('updater launcher started with pid=${process.pid}');
      await Future<void>.delayed(const Duration(seconds: 2));
      await launcherLog('Closing AndreyVPN so updater can replace files');
      exit(0);
    } catch (error, stackTrace) {
      await launcherLog('FAILED to launch updater: $error');
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
