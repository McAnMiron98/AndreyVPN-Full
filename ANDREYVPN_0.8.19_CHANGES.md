# AndreyVPN 0.8.19 — Portable Preferences Format Fix

## Changes
- Updated app version to 0.8.19+59.
- Replaced Windows SharedPreferences backend with a portable JSON backend.
- Portable preferences now use the correct Flutter key format: `flutter.*`.
- Added automatic conversion from old portable keys to Flutter-format keys.
- Added one-time rescue from legacy AppData preferences if a valid Flutter-format file exists there.
- Stopped using `%APPDATA%\AndreyVPN\AndreyVPN` as the preferences source.
- Added diagnostics for portable preferences reads/writes and key validation.
- Legacy AppData preferences are cleaned only after portable backend is installed.

## Risk
Medium. This changes Windows preferences storage behavior, but does not change VPN core logic.
