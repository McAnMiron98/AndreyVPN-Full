# AndreyVPN 0.8.20 — Portable Preferences Build Fix

## Summary
- Updated app version to 0.8.20+60.
- Fixed Windows build failure introduced in 0.8.19 portable SharedPreferences backend.
- Removed shared_preferences_platform_interface APIs that are not available in the pinned project dependency version.
- Fixed nullable Object assignment in portable preferences store.
- Kept portable preferences format fix from 0.8.19.
- No backup data format changes.
- No VPN core logic changes.

## Risk
Low–medium.
