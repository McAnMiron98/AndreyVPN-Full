# AndreyVPN 0.8.12 — Backup Cleanup + Restart Prompt

## Changes

- Updated app version to 0.8.12+52.
- Excluded pending restore service files from full backup export.
- Excluded internal diagnostic logs from backup ZIP contents.
- External export/import diagnostic logs are still saved next to the selected ZIP.
- Added restart prompt after successful full backup import staging.
- Added two user actions after import: `Перезапустить` and `Позже`.
- Restart action launches a new AndreyVPN instance and closes the current one so deferred restore can be applied.

## Files changed

- pubspec.yaml
- appcast.xml
- .github/workflows/build-windows-andrey.yml
- lib/features/settings/notifier/full_backup_notifier.dart
- lib/features/settings/overview/backup_page.dart
- ANDREYVPN_0.8.12_CHANGES.md

## Risk

Low to medium. Backup/restore data logic is unchanged; this release cleans backup contents and adds restart UX after import.
