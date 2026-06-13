# AndreyVPN 0.8.16 — Portable Data Storage

## Changed
- Updated app version to `0.8.16+56`.
- Changed Windows user data storage to a portable folder next to `AndreyVPN.exe`:
  - `<AndreyVPN.exe folder>/andreyvpn_data`
- Replaced the old portable folder name `hiddify_portable_data` with `andreyvpn_data`.
- Windows directories now prefer `andreyvpn_data` whenever it is writable.
- Added `andreyvpn_path_diagnostic.log` to record resolved executable path, selected data path, portable path and fallback reason.
- Backup/import/pending restore now use the selected portable data directory through `AppDirectories`.

## Not changed
- No automatic migration from `%APPDATA%\AndreyVPN\AndreyVPN`.
- No VPN core logic changes.
- No backup archive format change.
- No Hiddify cleanup.

## Notes
- Existing users should restore data from a previously created backup after switching to this version.
- If the executable directory is not writable, the app falls back to the system application support directory and logs the reason.
