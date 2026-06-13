# AndreyVPN 0.8.11 — Deferred Restore

## Changes

- Updated app version to 0.8.11+51.
- Added deferred full backup restore workflow.
- Full backup import now stages selected backup data into `andreyvpn_pending_restore`.
- Added `andreyvpn_pending_restore.json` marker for restore on next application start.
- Added startup pending-restore processing before normal application bootstrap.
- Added pending restore diagnostic log: `andreyvpn_pending_restore_diagnostic.log`.
- Avoided replacing `db.sqlite` while the application is running.
- Kept import/export diagnostics enabled.

## Not changed

- No VPN core logic changes.
- No routing logic changes.
- No Hiddify cleanup/renaming.
- No automatic rollback redesign yet.
