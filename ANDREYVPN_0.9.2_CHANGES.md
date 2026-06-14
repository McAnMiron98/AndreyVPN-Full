# AndreyVPN 0.9.2 — Full Project Audit Cleanup

## Summary

- Updated app version to 0.9.2+63.
- Removed unused legacy GitHub workflows that were not part of the current Windows release pipeline.
- Removed obsolete helper scripts and release-note templates from the old upstream project setup.
- Removed old per-version internal change notes from 0.2–0.8.x, keeping the current 0.9.x history.
- Removed legacy AppData cleanup code that was no longer needed after portable preferences stabilization.
- Kept Windows portable storage, backup/import, restart, and VPN core behavior unchanged.

## Risk

Medium-low. This release mainly removes obsolete project files and no longer needed cleanup code. VPN core logic is not changed.
