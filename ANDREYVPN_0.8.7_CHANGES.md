# AndreyVPN 0.8.7 — Backup Cleanup

## Summary

This release cleans up the full backup export introduced and fixed in previous versions.

## Changes

- Updated app version to `0.8.7+47`.
- Updated appcast release entry to `v0.8.7`.
- Updated Windows GitHub Actions portable artifact name to `AndreyVPN-0.8.7-windows-portable.zip`.
- Excluded runtime log files from full backup export:
  - `app.log`
  - `box.log`
  - `goroutine-start.log`
- Kept required user data in the backup:
  - `db.sqlite`
  - `shared_preferences.json`
  - `configs/`
  - `data/AppSettings.db/`
  - `data/clash.db`
  - `data/current-config.json`
- Added backup manifest metadata:
  - app version
  - backup format version
  - created date
  - file count
  - backup size in bytes
- Kept diagnostic logging for one more release to verify cleanup behavior.

## Not changed

- No VPN core logic changes.
- No import/restore redesign yet.
- No profile or routing logic changes.
- No Hiddify internal cleanup in this release.

## Risk

Low. Only the exported backup file set and manifest metadata were changed.
