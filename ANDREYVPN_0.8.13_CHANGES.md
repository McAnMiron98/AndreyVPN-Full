# AndreyVPN 0.8.13 — Restart Button Fix

## Version
AndreyVPN 0.8.13+53

## Git tag
v0.8.13

## Release title
AndreyVPN 0.8.13 — Restart Button Fix

## Summary
- Updated app version to 0.8.13+53
- Fixed the Restart button shown after successful backup import
- Restart now launches a new AndreyVPN process after a short delay, then closes the current process
- This avoids the single-instance guard preventing the new process from opening
- No backup data format changes
- No VPN core logic changes

## Changed files
- pubspec.yaml
- appcast.xml
- .github/workflows/build-windows-andrey.yml
- lib/features/settings/overview/backup_page.dart
- ANDREYVPN_0.8.13_CHANGES.md

## Risk
Low–medium.

Only the restart action after backup import was changed. Backup/export/import data logic and VPN core logic were not changed.

## Test plan
1. Create a new full backup.
2. Delete a test profile.
3. Import the backup.
4. In the restart prompt, click Restart.
5. Confirm AndreyVPN closes and opens again automatically.
6. Confirm the deleted profile is restored after restart.
7. If restart still fails, report whether the app only closes or shows any error.
