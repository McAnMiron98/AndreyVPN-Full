# AndreyVPN 0.8.15 — Restart Helper BAT

## Changes

- Updated app version to `0.8.15+55`.
- Reworked the restart action shown after successful backup import.
- Added a temporary BAT restart helper launched through hidden WScript.
- The helper waits briefly, launches the current `AndreyVPN.exe`, and then removes itself.
- Added restart diagnostics to `andreyvpn_restart_diagnostic.log`.
- No backup data format changes.
- No import/export data logic changes.
- No VPN core logic changes.

## Risk

Low to medium. Only the post-import restart helper was changed.

## Test plan

1. Create a backup.
2. Delete a test profile.
3. Import the backup.
4. Click `Перезапустить`.
5. Confirm the app closes and opens again automatically.
6. Confirm the deleted profile is restored.
7. If restart fails, send `andreyvpn_restart_diagnostic.log` from `%APPDATA%\AndreyVPN\AndreyVPN`.
