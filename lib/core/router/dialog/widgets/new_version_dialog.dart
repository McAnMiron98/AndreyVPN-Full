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

$LogDir = Join-Path $env:LOCALAPPDATA "AndreyVPN"
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
$LogPath = Join-Path $LogDir "AndreyVPN-update.log"
$WorkDir = Join-Path $env:TEMP ("AndreyVPN_Update_" + [guid]::NewGuid().ToString())
$ZipPath = Join-Path $WorkDir "AndreyVPN-update.zip"
$ExtractDir = Join-Path $WorkDir "extract"

function Write-UpdateLog($Message) {
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  Add-Content -Path $LogPath -Value "[$stamp] $Message"
}

function Find-PortableSourceDir($RootDir) {
  $directExe = Join-Path $RootDir "AndreyVPN.exe"
  if (Test-Path $directExe) { return $RootDir }

  $innerZip = Get-ChildItem -Path $RootDir -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
    $name = $_.Name.ToLowerInvariant()
    $name.EndsWith(".zip") -and $name.Contains("windows") -and $name.Contains("portable")
  } | Select-Object -First 1

  if ($innerZip) {
    Write-UpdateLog "Found nested portable zip: $($innerZip.FullName)"
    $nestedExtractDir = Join-Path $WorkDir "nested_extract"
    New-Item -ItemType Directory -Force -Path $nestedExtractDir | Out-Null
    Expand-Archive -Path $innerZip.FullName -DestinationPath $nestedExtractDir -Force
    return Find-PortableSourceDir $nestedExtractDir
  }

  $exe = Get-ChildItem -Path $RootDir -Recurse -File -Filter "AndreyVPN.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($exe) { return $exe.DirectoryName }

  return $null
}

try {
  "" | Set-Content -Path $LogPath
  Write-UpdateLog "Starting AndreyVPN update"
  Write-UpdateLog "AppDir=$AppDir"
  Write-UpdateLog "ExePath=$ExePath"
  Write-UpdateLog "ZipUrl=$ZipUrl"
  Write-UpdateLog "AppPid=$AppPid"

  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null

  Write-UpdateLog "Downloading update zip"
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing -Headers @{ "User-Agent" = "AndreyVPN-Updater" }
  Write-UpdateLog "Downloaded: $((Get-Item $ZipPath).Length) bytes"

  Write-UpdateLog "Waiting for AndreyVPN process to close"
  try { Wait-Process -Id $AppPid -Timeout 90 -ErrorAction SilentlyContinue } catch { Write-UpdateLog "Wait warning: $($_.Exception.Message)" }
  Start-Sleep -Seconds 2

  # Some helper processes can keep files locked. Stop only known AndreyVPN/Hiddify helper processes.
  Write-UpdateLog "Stopping helper processes if still running"
  Get-Process -Name "AndreyVPN","HiddifyCli" -ErrorAction SilentlyContinue | ForEach-Object {
    try {
      Write-UpdateLog "Stopping process: $($_.ProcessName) PID=$($_.Id)"
      Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    } catch { Write-UpdateLog "Stop warning: $($_.Exception.Message)" }
  }
  Start-Sleep -Seconds 1

  Write-UpdateLog "Extracting update zip"
  Expand-Archive -Path $ZipPath -DestinationPath $ExtractDir -Force

  $SourceDir = Find-PortableSourceDir $ExtractDir
  if (-not $SourceDir) {
    Write-UpdateLog "Extracted files dump:"
    Get-ChildItem -Path $ExtractDir -Recurse -ErrorAction SilentlyContinue | ForEach-Object { Write-UpdateLog $_.FullName }
    throw "AndreyVPN.exe was not found inside downloaded update archive."
  }

  Write-UpdateLog "Portable source detected: $SourceDir"
  Write-UpdateLog "Copying files to application directory"
  Copy-Item -Path (Join-Path $SourceDir "*") -Destination $AppDir -Recurse -Force

  $UpdatedExePath = Join-Path $AppDir "AndreyVPN.exe"
  if (-not (Test-Path $UpdatedExePath)) { throw "Updated AndreyVPN.exe was not found at $UpdatedExePath" }

  Write-UpdateLog "Starting updated AndreyVPN: $UpdatedExePath"
  Start-Process -FilePath $UpdatedExePath -WorkingDirectory $AppDir
  Write-UpdateLog "Update completed successfully"
} catch {
  Write-UpdateLog "Update failed: $($_.Exception.Message)"
  $msg = "AndreyVPN update failed.`n`nLog file:`n$LogPath`n`nError:`n$($_.Exception.Message)"
  Add-Type -AssemblyName PresentationFramework -ErrorAction SilentlyContinue
  try { [System.Windows.MessageBox]::Show($msg, "AndreyVPN Update", "OK", "Error") | Out-Null } catch { Write-Host $msg }
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
