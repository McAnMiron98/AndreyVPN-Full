# AndreyVPN 0.9.5 — Updater Logs Cleanup

## Changes

- Updated app version to 0.9.5+66.
- Redirected updater launcher diagnostics to `andreyvpn_data/logs`.
- Added `--logDir` argument support for the external Windows updater.
- Redirected external updater diagnostics to `andreyvpn_data/logs`.
- Added cleanup for legacy updater logs from `%LOCALAPPDATA%\AndreyVPN`.
- Added `andreyvpn_updater_cleanup.log` diagnostics.
- No VPN core logic changes.

## Verification plan

1. Build with GitHub Actions.
2. Start AndreyVPN and check VPN connection.
3. Trigger/open update dialog if possible.
4. Check that updater logs are created in `andreyvpn_data/logs`.
5. Check that `%LOCALAPPDATA%\AndreyVPN` is not recreated or is cleaned if only updater logs existed.
