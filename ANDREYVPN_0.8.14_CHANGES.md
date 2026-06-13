# AndreyVPN 0.8.14 — Restart Path Fix

## Changes

- Updated app version to 0.8.14+54.
- Fixed restart action after successful backup import.
- Normalized Windows executable path before restarting.
- Replaced cmd/start restart command with PowerShell Start-Process.
- Added hidden PowerShell launch mode to avoid visible console window during restart.
- No backup data format changes.
- No VPN core logic changes.

## Changed files

- pubspec.yaml
- appcast.xml
- .github/workflows/build-windows-andrey.yml
- lib/features/settings/overview/backup_page.dart

## Risk

Low–medium.
