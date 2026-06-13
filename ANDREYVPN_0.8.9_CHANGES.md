# AndreyVPN 0.8.9 — Import Root Files Fix

## Changes

- Updated app version to `0.8.9+49`.
- Replaced `extractArchiveToDisk` in full backup import with a manual safe ZIP extractor.
- Fixed restore of root backup files such as `db.sqlite` and `shared_preferences.json`.
- Fixed restore of direct files inside `data`, including `clash.db` and `current-config.json`.
- Added import diagnostics for expected source and target files before and after restore.
- Kept existing export and import diagnostic logging.

## Not changed

- No VPN core logic changes.
- No rollback/safe restore redesign yet.
- No automatic pre-import backup yet.
- No upstream branding cleanup.

## Risk

Medium. This version changes real backup restore behavior for user data files.
