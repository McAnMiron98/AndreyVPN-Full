# AndreyVPN 0.9.3 — Diagnostics Center

## Changes

- Updated app version to 0.9.3+64.
- Added unified diagnostics folder: `andreyvpn_data/logs`.
- Moved path diagnostics, preferences diagnostics, restart diagnostics and pending restore diagnostics into the logs folder.
- Moved full backup export/import diagnostics into the logs folder instead of saving them next to ZIP files.
- Added Backup page actions: open logs folder and clear logs.
- Excluded the logs folder from backup ZIP archives.
- No VPN core logic changes.

## Risk

Low to medium. This release reorganizes diagnostic files only and does not change VPN core behavior.
