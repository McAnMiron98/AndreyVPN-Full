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

$Form = $null
$StatusLabel = $null

function Init-ProgressWindow {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $script:Form = New-Object System.Windows.Forms.Form
    $script:Form.Text = "AndreyVPN Update"
    $script:Form.Width = 460
    $script:Form.Height = 170
    $script:Form.StartPosition = "CenterScreen"
    $script:Form.FormBorderStyle = "FixedDialog"
    $script:Form.MaximizeBox = $false
    $script:Form.MinimizeBox = $false
    $script:Form.TopMost = $true

    $title = New-Object System.Windows.Forms.Label
    $title.Text = "Обновление AndreyVPN"
    $title.Left = 20
    $title.Top = 18
    $title.Width = 400
    $title.Height = 24
    $title.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $script:Form.Controls.Add($title)

    $script:StatusLabel = New-Object System.Windows.Forms.Label
    $script:StatusLabel.Text = "Подготовка обновления..."
    $script:StatusLabel.Left = 20
    $script:StatusLabel.Top = 54
    $script:StatusLabel.Width = 400
    $script:StatusLabel.Height = 24
    $script:StatusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $script:Form.Controls.Add($script:StatusLabel)

    $progress = New-Object System.Windows.Forms.ProgressBar
    $progress.Left = 20
    $progress.Top = 88
    $progress.Width = 405
    $progress.Height = 22
    $progress.Style = "Marquee"
    $progress.MarqueeAnimationSpeed = 30
    $script:Form.Controls.Add($progress)

    $script:Form.Show()
    [System.Windows.Forms.Application]::DoEvents()
  } catch {}
}

function Set-UpdateStatus($Message) {
  try {
    if ($script:StatusLabel -ne $null) {
      $script:StatusLabel.Text = $Message
      [System.Windows.Forms.Application]::DoEvents()
    }
  } catch {}
}

function Close-ProgressWindow {
  try {
    if ($script:Form -ne $null) {
      $script:Form.Close()
      $script:Form.Dispose()
    }
  } catch {}
}

function Write-UpdateLog($Message) {
  $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "[$stamp] $Message"
  Add-Content -Path $LogPath -Value $line
}

try {
  New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
  Init-ProgressWindow

  Write-UpdateLog "=== AndreyVPN updater started ==="
  Write-UpdateLog "AppDir=$AppDir"
  Write-UpdateLog "ExePath=$ExePath"
  Write-UpdateLog "ZipUrl=$ZipUrl"
  Write-UpdateLog "AppPid=$AppPid"

  Set-UpdateStatus "Скачивание обновления..."
  Write-UpdateLog "Downloading update zip..."
  Invoke-WebRequest -Uri $ZipUrl -OutFile $ZipPath -UseBasicParsing
  Write-UpdateLog "Download completed: $ZipPath"

  Set-UpdateStatus "Ожидание закрытия AndreyVPN..."
  Write-UpdateLog "Waiting for AndreyVPN to close..."
  try {
    Wait-Process -Id $AppPid -Timeout 120 -ErrorAction SilentlyContinue
  } catch {
    Write-UpdateLog "Wait-Process warning: $($_.Exception.Message)"
  }
  Start-Sleep -Seconds 3

  Set-UpdateStatus "Распаковка обновления..."
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

  Set-UpdateStatus "Замена файлов..."
  Write-UpdateLog "SourceDir=$SourceDir"
  Write-UpdateLog "Replacing files with robocopy..."
  $robocopyArgs = @($SourceDir, $AppDir, "/E", "/COPY:DAT", "/R:10", "/W:1", "/NP")
  & robocopy @robocopyArgs | Out-Null
  $code = $LASTEXITCODE
  Write-UpdateLog "Robocopy exit code: $code"
  if ($code -ge 8) {
    throw "Robocopy failed with exit code $code"
  }

  $UpdatedExe = Join-Path $AppDir "AndreyVPN.exe"
  if (-not (Test-Path $UpdatedExe)) {
    throw "Updated AndreyVPN.exe not found at $UpdatedExe"
  }

  Set-UpdateStatus "Запуск обновлённой версии..."
  Write-UpdateLog "Starting updated AndreyVPN..."
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $UpdatedExe
  $psi.WorkingDirectory = $AppDir
  $psi.UseShellExecute = $true
  [System.Diagnostics.Process]::Start($psi) | Out-Null
  Write-UpdateLog "=== Update completed successfully ==="
  Start-Sleep -Seconds 2
} catch {
  Write-UpdateLog "UPDATE FAILED: $($_.Exception.Message)"
  try {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("AndreyVPN update failed.`n`nLog: $LogPath", "AndreyVPN Update", "OK", "Error") | Out-Null
  } catch {}
} finally {
  Write-UpdateLog "WorkDir kept for diagnostics: $WorkDir"
  Close-ProgressWindow
}
''';

    await File(scriptPath).writeAsString(script);

    final localAppData = Platform.environment['LOCALAPPDATA'] ?? tempDir.path;
    final logDir = Directory('$localAppData\\AndreyVPN');
    await logDir.create(recursive: true);
    final launcherLogPath = '${logDir.path}\\AndreyVPN-updater-launcher.log';
    final vbsLauncherPath = '${tempDir.path}\\andreyvpn_update_launcher.vbs';

    Future<void> launcherLog(String message) async {
      final now = DateTime.now().toIso8601String();
      await File(launcherLogPath).writeAsString('[$now] $message\r\n', mode: FileMode.append, flush: true);
    }

    String vbsEscape(String value) => value.replaceAll('"', '""');

    await launcherLog('Preparing updater launch');
    await launcherLog('AppDir=$appDir');
    await launcherLog('ExePath=$exePath');
    await launcherLog('ZipUrl=${newVersion.url}');
    await launcherLog('ScriptPath=$scriptPath');

    final psCommand = 'powershell.exe -NoProfile -STA -ExecutionPolicy Bypass '
        '-File "${vbsEscape(scriptPath)}" '
        '-AppDir "${vbsEscape(appDir)}" '
        '-ExePath "${vbsEscape(exePath)}" '
        '-ZipUrl "${vbsEscape(newVersion.url)}" '
        '-AppPid $currentPid';

    final vbsLauncher = '''
Set shell = CreateObject("WScript.Shell")
shell.Run "$psCommand", 0, False
''';

    await File(vbsLauncherPath).writeAsString(vbsLauncher);
    await launcherLog('VbsLauncherPath=$vbsLauncherPath');

    try {
      final process = await Process.start(
        'wscript.exe',
        [vbsLauncherPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
        workingDirectory: tempDir.path,
      );
      await launcherLog('VBS updater launcher started with pid=${process.pid}');
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
