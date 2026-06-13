# AndreyVPN 0.8.17 — Portable Path Cleanup

## Summary
- Updated app version to 0.8.17+57.
- Moved restart diagnostics to the portable `andreyvpn_data` directory.
- Added cleanup for legacy AppData artifacts: `shared_preferences.json` and `andreyvpn_restart_diagnostic.log`.
- Added portable mirror for shared preferences into `andreyvpn_data/shared_preferences.json`.
- Added safe cleanup for temporary sibling `data/AppSettings.db` folders created near exported backup ZIP files.
- Kept backup/import format unchanged.
- No VPN core logic changes.

## Notes
This release continues the portable data storage transition started in 0.8.16.
