# AndreyVPN 0.8.18 — Shared Preferences Stabilization

## Changes

- Updated app version to 0.8.18+58.
- Stabilized Windows shared preferences behavior for portable builds.
- Seeds the legacy shared_preferences.json from portable andreyvpn_data before SharedPreferences initialization.
- Mirrors SharedPreferences back to andreyvpn_data/shared_preferences.json after initialization.
- Stops deleting legacy shared_preferences.json because shared_preferences_windows still reads it.
- Added andreyvpn_preferences_diagnostic.log for preferences path diagnostics.
- Keeps restart diagnostics cleanup for old AppData leftovers.
- No backup data format changes.
- No VPN core logic changes.

## Notes

This is an intermediate safe step. The app still allows shared_preferences_windows to use its default AppData file, but the file is now seeded from the portable copy and no longer deleted after startup. This prevents the intro/analytics screen from appearing on every launch.
